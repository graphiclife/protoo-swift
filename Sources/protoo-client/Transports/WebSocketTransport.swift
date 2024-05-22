//
//  WebSocketTransport.swift
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
import NIOPosix
import NIOHTTP1
import NIOSSL
import NIOWebSocket

fileprivate enum WebSocketTransportInternalError: Error {
    case invalidUnderlyingBootstrap
}

public final actor WebSocketTransport {
    public enum WebSocketTransportError: Error {
        case notConnected
        case invalidURI(String)
        case clientClosed
        case serverClosed

        fileprivate var shouldRetry: Bool {
            switch self {
            case .notConnected:
                return false

            case .invalidURI:
                return false

            case .clientClosed:
                return false

            case .serverClosed:
                return false
            }
        }
    }

    public enum WebSocketEvent: Hashable {
        case close
        case disconnected
        case failed
        case message
        case open
    }

    public enum WebSocketMessage {
        case ping
        case pong
        case text(ByteBuffer)
        case binary(ByteBuffer)
    }

    public struct WebSocketRetryOptions {
        public static var `default`: WebSocketRetryOptions = .init(numberOfRetries: 10, factor: 2.0, minInterval: 1000.0, maxInterval: 8000.0)

        public let numberOfRetries: Int
        public let factor: Double
        public let minInterval: TimeInterval
        public let maxInterval: TimeInterval
    }

    public typealias WebSocketEventHandler = (WebSocketEvent, WebSocketMessage?) async -> Void

    private class WebSocketWriter {
        static func create() -> (WebSocketWriter, AsyncStream<WebSocketFrame>) {
            let writer = WebSocketWriter()
            let stream = AsyncStream<WebSocketFrame> { continuation in
                writer.writer = { frames in
                    for frame in frames {
                        continuation.yield(frame)
                    }
                }

                writer.closer = {
                    continuation.finish()
                }

                continuation.onTermination = { @Sendable _ in
                    writer.writer = nil
                    writer.closer = nil
                }
            }

            return (writer, stream)
        }

        var writer: (([WebSocketFrame]) -> Void)?
        var closer: (() -> Void)?
        var isClosed = false

        func write(_ message: WebSocketMessage) {
            var frames = [WebSocketFrame]()

            switch message {
            case .ping:
                frames.append(.init(fin: true, opcode: .ping, maskKey: .random(), data: .init()))

            case .pong:
                frames.append(.init(fin: true, opcode: .pong, maskKey: .random(), data: .init()))

            case .text(let text):
                frames.append(.init(fin: true, opcode: .text, maskKey: .random(), data: text))

            case .binary(let binary):
                frames.append(.init(fin: true, opcode: .binary, maskKey: .random(), data: binary))
            }

            writer?(frames)
        }

        func close() {
            isClosed = true
            closer?()
        }
    }

    private static let defaultHeaders = [
        "Sec-WebSocket-Protocol": "protoo"
    ]

    private enum State {
        case idle
        case connecting
        case connected(WebSocketWriter)
    }

    private let uri: URL
    private let group: MultiThreadedEventLoopGroup
    private let retryOptions: WebSocketRetryOptions

    private var state: State = .idle
    private var eventHandlers: [WebSocketEvent: [WebSocketEventHandler]] = [:]

    public init(uri: URL, group: MultiThreadedEventLoopGroup, retryOptions: WebSocketRetryOptions = .default) {
        self.uri = uri
        self.group = group
        self.retryOptions = retryOptions
    }

    //
    //  Public API
    //

    @discardableResult
    public func connect() -> Self {
        connect(attempt: 0)
        return self
    }

    @discardableResult
    public func disconnect() -> Self {
        guard case .connected(let writer) = state else {
            return self
        }
        
        writer.close()
        return self
    }

    @discardableResult
    public func on(_ event: WebSocketEvent, handler: @escaping WebSocketEventHandler) -> Self {
        if eventHandlers[event] == nil {
            eventHandlers[event] = []
        }

        eventHandlers[event]?.append(handler)
        return self
    }

    @discardableResult
    public func write(_ message: WebSocketMessage) throws -> Self {
        guard case .connected(let writer) = state else {
            throw WebSocketTransportError.notConnected
        }
        
        writer.write(message)
        return self
    }

    //
    //  Private API
    //

    private func setState(_ state: State) {
        self.state = state
    }

    private func connect(attempt: Int) {
        guard case .idle = state else {
            return
        }

        setState(.connecting)

        Task {
            var reconnectOnError = true

            do {
                guard let components = URLComponents(url: uri, resolvingAgainstBaseURL: true) else {
                    throw WebSocketTransportError.invalidURI("invalid uri")
                }

                guard let host = components.host else {
                    throw WebSocketTransportError.invalidURI("invalid uri: no host")
                }

                guard let scheme = components.scheme else {
                    throw WebSocketTransportError.invalidURI("invalid uri: no scheme")
                }

                guard scheme == "ws" || scheme == "wss" else {
                    throw WebSocketTransportError.invalidURI("invalid uri: scheme is not ws or wss")
                }

                let port = components.port ?? (scheme == "wss" ? 443 : 80)
                let path = components.path

                let bootstrap = WebSocketBootstrap(scheme: scheme, host: host, port: port, path: path, headers: Self.defaultHeaders, group: group)
                let channel = try await bootstrap.connect()
                let (writer, stream) = WebSocketWriter.create()

                setState(.connected(writer))
                await notify(event: .open, message: nil)

                try await channel.executeThenClose { (inbound, outbound) in
                    let writerTask = Task {
                        for await frame in stream {
                            try await outbound.write(frame)
                        }

                        try? await channel.channel.close()
                    }

                    defer {
                        writerTask.cancel()
                    }

                    for try await frame in inbound {
                        switch frame.opcode {
                        case .ping:
                            writer.write(.pong)
                            await notify(event: .message, message: .ping)

                        case .pong:
                            await notify(event: .message, message: .pong)

                        case .text:
                            await notify(event: .message, message: .text(frame.data))

                        case .connectionClose:
                            throw WebSocketTransportError.serverClosed

                        case .binary:
                            await notify(event: .message, message: .binary(frame.data))

                        case .continuation:
                            break

                        default:
                            break
                        }
                    }

                    await notify(event: .disconnected, message: nil)

                    if writer.isClosed {
                        throw WebSocketTransportError.clientClosed
                    }
                }
            } catch let error as WebSocketTransportError {
                reconnectOnError = error.shouldRetry
            } catch {
                reconnectOnError = true
                await notify(event: .failed, message: nil)
            }

            setState(.idle)

            if reconnectOnError && attempt < retryOptions.numberOfRetries {
                do {
                    try await Task.sleep(for: .milliseconds(min(retryOptions.minInterval * pow(retryOptions.factor, Double(attempt)), retryOptions.maxInterval)))
                } catch {
                    await notify(event: .close, message: nil)
                    return
                }

                connect(attempt: attempt + 1)
            } else {
                await notify(event: .close, message: nil)
            }
        }
    }

    private func notify(event: WebSocketEvent, message: WebSocketMessage?) async {
        guard let handlers = eventHandlers[event] else {
            return
        }

        for handler in handlers {
            await handler(event, message)
        }
    }
}

struct WebSocketBootstrap {
    enum WebSocketBootstrapError: Error {
        case upgradeFailed
    }

    let scheme: String
    let host: String
    let port: Int
    let path: String
    let headers: [String: String]
    let group: EventLoopGroup

    private enum UpgradeResult {
        case websocket(NIOAsyncChannel<WebSocketFrame, WebSocketFrame>)
        case failed
    }

    func connect() async throws -> NIOAsyncChannel<WebSocketFrame, WebSocketFrame> {
        let initializer: @Sendable (Channel) -> EventLoopFuture<EventLoopFuture<UpgradeResult>> = { channel in
            channel.eventLoop.makeCompletedFuture {
                let upgrader = NIOTypedWebSocketClientUpgrader<UpgradeResult>(upgradePipelineHandler: { (channel, _) in
                    channel.eventLoop.makeCompletedFuture {
                        return UpgradeResult.websocket(try NIOAsyncChannel<WebSocketFrame, WebSocketFrame>(wrappingChannelSynchronously: channel))
                    }
                })

                var requestHeaders = HTTPHeaders()

                requestHeaders.add(name: "Host", value: host)
                requestHeaders.add(name: "Content-Type", value: "text/plain; charset=utf-8")
                requestHeaders.add(name: "Content-Length", value: "0")

                headers.forEach { requestHeaders.add(name: $0.key, value: $0.value) }

                let requestHead = HTTPRequestHead(version: .http1_1, method: .GET, uri: path, headers: requestHeaders)

                let clientUpgradeConfiguration = NIOTypedHTTPClientUpgradeConfiguration(
                    upgradeRequestHead: requestHead,
                    upgraders: [upgrader],
                    notUpgradingCompletionHandler: { channel in
                        channel.eventLoop.makeCompletedFuture {
                            return UpgradeResult.failed
                        }
                    }
                )

                let negotiationResultFuture = try channel.pipeline.syncOperations.configureUpgradableHTTPClientPipeline(
                    configuration: .init(upgradeConfiguration: clientUpgradeConfiguration)
                )

                return negotiationResultFuture
            }
        }

        let upgradeResult: EventLoopFuture<UpgradeResult>

        if scheme == "wss" {
            let configuration = TLSConfiguration.makeClientConfiguration()
            let sslContext = try NIOSSLContext(configuration: configuration)
            let bootstrap = try NIOClientTCPBootstrap(ClientBootstrap(group: group), tls: NIOSSLClientTLSProvider(context: sslContext, serverHostname: host))

            upgradeResult = try await bootstrap
                .enableTLS()
                .connect(host: host, port: port, channelInitializer: initializer)
        } else {
            upgradeResult = try await ClientBootstrap(group: group).connect(host: host, port: port, channelInitializer: initializer)
        }

        guard case let .websocket(channel) = try await upgradeResult.get() else {
            throw WebSocketBootstrapError.upgradeFailed
        }

        let aggregator = NIOWebSocketFrameAggregator(minNonFinalFragmentSize: 256,
                                                    maxAccumulatedFrameCount: 100,
                                                     maxAccumulatedFrameSize: 10 * 1024 * 1024)

        try await channel.channel.pipeline.addHandler(aggregator).get()

        return channel
    }
}

extension NIOClientTCPBootstrap {
    @available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
    public func connect<Output: Sendable>(
        host: String,
        port: Int,
        channelInitializer: @escaping @Sendable (Channel) -> EventLoopFuture<Output>
    ) async throws -> Output {
        guard let underlyingBootstrap = underlyingBootstrap as? ClientBootstrap else {
            throw WebSocketTransportInternalError.invalidUnderlyingBootstrap
        }

        return try await underlyingBootstrap.connect(host: host, port: port, channelInitializer: channelInitializer)
    }
}
