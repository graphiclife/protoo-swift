//
//  Peer.swift
//  protoo-swift
//
//  Created by @graphiclife on May 15, 2024.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation
import NIOCore
import NIOFoundationCompat

public final actor Peer {
    private enum State {
        case closed
        case open(WebSocketConnection, Task<Void, Never>)
    }

    public enum Error: Swift.Error {
        case closed
        case invalidData
        case invalidMessage
    }

    // MARK: - Requests, Responses and Notifications

    public struct Request {
        private static func data<T: Encodable>(for value: T) throws -> ByteBuffer {
            var data = ByteBuffer()
            try data.writeJSONEncodable(value)
            return data
        }

        let buffer: ByteBuffer
        private let message: Message
        public let method: String
        public let id: UInt32

        init(buffer: ByteBuffer) throws {
            guard let message = try buffer.getJSONDecodable(Message.self, at: 0, length: buffer.readableBytes) else {
                throw Error.invalidData
            }

            guard case .request(let request) = message.type else {
                throw Error.invalidMessage
            }

            self.buffer = buffer
            self.message = message
            self.method = request.method
            self.id = request.id
        }

        public init(method: String) throws {
            let request = Message.MessageRequest(method: method)
            let message = Message(type: .request(request))
            self.buffer = try Self.data(for: message)
            self.message = message
            self.method = method
            self.id = request.id
        }

        public init<T: Codable>(method: String, data: T) throws {
            let request = Message.MessageRequest(method: method)
            let message = Message(type: .request(request))
            self.buffer = try Self.data(for: DataMessage(message: message, data: data))
            self.message = message
            self.method = method
            self.id = request.id
        }

        public func data<T: Codable>(as dataType: T.Type) throws -> T {
            guard let value = try buffer.getJSONDecodable(DataMessage<T>.self, at: 0, length: buffer.readableBytes) else {
                throw Error.invalidData
            }

            return value.data
        }
    }

    public struct Notification {
        private static func data<T: Encodable>(for value: T) throws -> ByteBuffer {
            var data = ByteBuffer()
            try data.writeJSONEncodable(value)
            return data
        }

        let buffer: ByteBuffer
        private let message: Message
        public let method: String

        init(buffer: ByteBuffer) throws {
            guard let message = try buffer.getJSONDecodable(Message.self, at: 0, length: buffer.readableBytes) else {
                throw Error.invalidData
            }

            guard case .notification(let method) = message.type else {
                throw Error.invalidMessage
            }

            self.buffer = buffer
            self.message = message
            self.method = method
        }

        public init(method: String) throws {
            let message = Message(type: .notification(method: method))
            self.buffer = try Self.data(for: message)
            self.message = message
            self.method = method
        }

        public init<T: Codable>(method: String, data: T) throws {
            let message = Message(type: .notification(method: method))
            self.buffer = try Self.data(for: DataMessage(message: message, data: data))
            self.message = message
            self.method = method
        }

        public func data<T: Codable>(as dataType: T.Type) throws -> T {
            guard let value = try buffer.getJSONDecodable(DataMessage<T>.self, at: 0, length: buffer.readableBytes) else {
                throw Error.invalidData
            }

            return value.data
        }
    }

    public struct Response {
        public static func success(for request: Request) throws -> Self {
            return try .init(message: .init(type: .response(.init(result: .success, id: request.id))))
        }

        public static func success<T: Codable>(for request: Request, data: T) throws -> Self {
            return try .init(message: .init(type: .response(.init(result: .success, id: request.id))), data: data)
        }

        public static func failure(for request: Request, code: Int, reason: String?) throws -> Self {
            return try .init(message: .init(type: .response(.init(result: .error(code: code, reason: reason), id: request.id))))
        }

        static func failure(for requestID: UInt32, code: Int, reason: String?) throws -> Self {
            return try .init(message: .init(type: .response(.init(result: .error(code: code, reason: reason), id: requestID))))
        }

        private static func data<T: Encodable>(for value: T) throws -> ByteBuffer {
            var data = ByteBuffer()
            try data.writeJSONEncodable(value)
            return data
        }

        let buffer: ByteBuffer

        init(buffer: ByteBuffer) {
            self.buffer = buffer
        }

        private init(message: Message) throws {
            self.buffer = try Self.data(for: message)
        }

        private init<T: Codable>(message: Message, data: T) throws {
            self.buffer = try Self.data(for: DataMessage(message: message, data: data))
        }

        public func data<T: Codable>(as dataType: T.Type) throws -> T {
            guard let value = try buffer.getJSONDecodable(DataMessage<T>.self, at: 0, length: buffer.readableBytes) else {
                throw Error.invalidData
            }

            return value.data
        }
    }

    private struct SentRequest {
        let id: UInt32
        let continuation: CheckedContinuation<Response, Swift.Error>
        let deadline: ContinuousClock.Instant
    }

    // MARK: - Builder

    public typealias OpenHandler = @Sendable () -> Void
    public typealias FailedHandler = @Sendable (_ currentAttempt: Int, _ error: Swift.Error) -> Void
    public typealias DisconnectedHandler = @Sendable () -> Void
    public typealias CloseHandler = @Sendable () -> Void
    public typealias RequestHandler = @Sendable (_ request: Request) async throws -> Response
    public typealias NotificationHandler = @Sendable (_ notification: Notification) -> Void

    struct Handlers {
        var open: OpenHandler?
        var failed: FailedHandler?
        var disconnected: DisconnectedHandler?
        var close: CloseHandler?
        var request: RequestHandler?
        var notification: NotificationHandler?
    }

    public class Builder {
        private let transport: WebSocketTransport
        private var handlers = Handlers()

        public init(transport: WebSocketTransport) {
            self.transport = transport
        }

        @discardableResult
        public func onOpen(_ open: @escaping OpenHandler) -> Self {
            handlers.open = open
            return self
        }

        @discardableResult
        public func onFailed(_ failed: @escaping FailedHandler) -> Self {
            handlers.failed = failed
            return self
        }

        @discardableResult
        public func onDisconnected(_ disconnected: @escaping DisconnectedHandler) -> Self {
            handlers.disconnected = disconnected
            return self
        }

        @discardableResult
        public func onClose(_ close: @escaping CloseHandler) -> Self {
            handlers.close = close
            return self
        }

        @discardableResult
        public func onRequest(_ request: @escaping RequestHandler) -> Self {
            handlers.request = request
            return self
        }

        @discardableResult
        public func onNotification(_ notification: @escaping NotificationHandler) -> Self {
            handlers.notification = notification
            return self
        }

        public func build() -> Peer {
            return .init(transport: transport, handlers: handlers)
        }
    }

    // MARK: - Implementation

    private let transport: WebSocketTransport
    private let handlers: Handlers

    private var state: State = .closed
    private var sents: [UInt32: SentRequest] = [:]

    init(transport: WebSocketTransport, handlers: Handlers) {
        self.transport = transport
        self.handlers = handlers
    }

    public func open() async throws {
        guard case .closed = state else {
            return
        }

        let connection = try transport.connect()
        let task = Task {
            for await event in connection.reader.read() {
                await self.handle(event: event)
            }
        }

        state = .open(connection, task)
    }

    public func close() {
        guard case let .open(connection, _) = state else {
            return
        }

        connection.writer.close()
    }

    private func handle(event: WebSocketEvent) async {
        switch event {
        case .close:
            if case let .open(_, task) = state {
                task.cancel()
            }

            handlers.close?()
            state = .closed

        case .open:
            handlers.open?()

        case .message(let message):
            handle(message: message)

        case .disconnect:
            handlers.disconnected?()

        case .fail(let currentAttempt, let error):
            handlers.failed?(currentAttempt, error)
        }
    }

    private func handle(message: WebSocketMessage) {
        switch message {
        case .binary, .ping, .pong:
            break

        case .text(let text):
            guard let message = try? text.getJSONDecodable(Message.self, at: 0, length: text.readableBytes) else {
                return
            }

            switch message.type {
            case .request(let request):
                handle(request: request, buffer: text)

            case .response(let response):
                handle(response: response, buffer: text)

            case .notification:
                if let notificationHandler = handlers.notification, let notification = try? Notification(buffer: text) {
                    notificationHandler(notification)
                }
                break
            }
        }
    }

    private func handle(request: Message.MessageRequest, buffer: ByteBuffer) {
        Task {
            let response: Response?

            do {
                let request = try Request(buffer: buffer)

                if let requestHandler = handlers.request {
                    response = try await requestHandler(request)
                } else {
                    response = try .failure(for: request, code: 404, reason: "not found")
                }
            } catch {
                response = try? .failure(for: request.id, code: 500, reason: error.localizedDescription)
            }
            
            if let response, case .open(let connection, _) = state {
                connection.writer.write(.text(response.buffer))
            }
        }
    }

    private func handle(response: Message.MessageResponse, buffer: ByteBuffer) {
        guard let sent = sents.removeValue(forKey: response.id) else {
            return
        }
        
        sent.continuation.resume(returning: .init(buffer: buffer))
    }

    public func request(_ request: Request) async throws -> Response {
        guard case .open(let connection, _) = state else {
            throw Error.closed
        }

        connection.writer.write(.text(request.buffer))

        return try await withCheckedThrowingContinuation { continuation in
            let clock = ContinuousClock()
            let timeout = 1_500 * (15 + Int(0.1 * Double(sents.count)))
            let deadline = clock.now.advanced(by: .milliseconds(timeout))

            sents[request.id] = .init(id: request.id, continuation: continuation, deadline: deadline)
        }
    }

    public func notify(_ notification: Notification) async throws {
        guard case .open(let connection, _) = state else {
            throw Error.closed
        }

        connection.writer.write(.text(notification.buffer))
    }
}
