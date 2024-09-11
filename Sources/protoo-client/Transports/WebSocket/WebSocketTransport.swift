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

public struct WebSocketTransport {
    public enum WebSocketTransportError: Error {
        case invalidURI(String)
    }

    private static let defaultHeaders = [
        "Sec-WebSocket-Protocol": "protoo"
    ]

    private let uri: URL
    private let group: MultiThreadedEventLoopGroup
    private let retryOptions: WebSocketRetryOptions

    public init(uri: URL, group: MultiThreadedEventLoopGroup, retryOptions: WebSocketRetryOptions = .default) {
        self.uri = uri
        self.group = group
        self.retryOptions = retryOptions
    }

    func connect() throws -> WebSocketConnection {
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

        return .init(bootstrap: bootstrap, retryOptions: retryOptions)
    }
}
