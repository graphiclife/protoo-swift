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

public final actor Peer {
    public enum PeerEvent {
        case close
        case disconnected
        case failed
        case notification
        case open
        case request
    }

    public typealias PeerEventHandler = (PeerEvent, Message?) -> Void

    private struct PeerRequest {
        let id: Int
    }

    private let transport: WebSocketTransport

    private var eventHandlers: [PeerEvent: [PeerEventHandler]] = [:]

    public init(transport: WebSocketTransport) async {
        self.transport = transport
    }

    public func on(_ event: PeerEvent, handler: @escaping PeerEventHandler) -> Self {
        if eventHandlers[event] == nil {
            eventHandlers[event] = []
        }

        eventHandlers[event]?.append(handler)
        return self
    }

    public func open() async {
        await transport
            .on(.open, handler: onTransportEvent)
            .on(.close, handler: onTransportEvent)
            .on(.disconnected, handler: onTransportEvent)
            .on(.failed, handler: onTransportEvent)
            .on(.message, handler: onTransportEvent)
            .connect()
    }

    public func close() async {
        await transport.disconnect()
    }

//    public func request(method: String, data: MessageData, responseDecodable: Response.Type) async throws -> Response where Request: Codable, Response: Codable {
//        fatalError("not implemented")
//    }
//
//    public func notify<Request>(method: String, data: Request) async throws {
//
//    }

    //
    //  Transport
    //

    private func onTransportEvent(event: WebSocketTransport.WebSocketEvent, message: WebSocketTransport.WebSocketMessage?) async {
        switch event {
        case .close:
            break

        case .disconnected:
            break

        case .failed:
            break

        case .message:
            break

        case .open:
            break
        }
    }
}
