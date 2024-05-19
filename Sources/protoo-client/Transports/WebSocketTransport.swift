//
//  File.swift
//  
//
//  Created by Måns Severin on 2024-05-19.
//

import Foundation

import NIOCore
import NIOPosix
import NIOHTTP1
import NIOSSL
import NIOWebSocket

public final actor WebSocketTransport {
    public enum WebSocketTransportError: Error {
        case invalidURI(String)
    }

    public enum WebSocketEvent {
        case close
        case disconnected
        case failed
        case message
        case open
    }

    public typealias WebSocketEventHandler = (WebSocketEvent, WebSocketTransport) -> Void

    private static let DEFAULT_RETRY_OPTIONS = [
        "retries"    : 10,
        "factor"     : 2,
        "minTimeout" : 1 * 1000,
        "maxTimeout" : 8 * 1000
    ]

    private enum State {
        case idle
        case connecting(Task<Void, Error>)
        case connected(Channel)
    }

    private let uri: URL
    private let group: MultiThreadedEventLoopGroup

    private var state: State = .idle
    private var eventHandlers: [WebSocketEvent: [WebSocketEventHandler]] = [:]

    public init(uri: URL, group: MultiThreadedEventLoopGroup) {
        self.uri = uri
        self.group = group
    }

    public func connect() {
        guard case .idle = state else {
            return
        }
        
        state = .connecting(.init {

        })
    }

    public func disconnect() {
        
    }

    public func on(_ event: WebSocketEvent, handler: @escaping WebSocketEventHandler) -> Self {
        return self
    }

    private func connect(retriesLeft: Int = 10) async throws {
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
        let bootstrap = WebSocketBootstrap(scheme: scheme, host: host, port: port, path: path, group: group)
        let channel = try await bootstrap.connect()
    }

//    /// This method handles the upgrade result.
//    private func handleUpgradeResult(_ upgradeResult: EventLoopFuture<UpgradeResult>) async throws {
//        switch try await upgradeResult.get() {
//        case .websocket(let websocketChannel):
//            print("Handling websocket connection")
//            try await self.handleWebsocketChannel(websocketChannel)
//            print("Done handling websocket connection")
//        case .failed:
//            // The upgrade to websocket did not succeed. We are just exiting in this case.
//            print("Upgrade declined")
//        }
//    }
//
//    private func handleWebsocketChannel(_ channel: NIOAsyncChannel<WebSocketFrame, WebSocketFrame>) async throws {
//        // We are sending a ping frame and then
//        // start to handle all inbound frames.
//
//        let pingFrame = WebSocketFrame(fin: true, opcode: .ping, data: ByteBuffer(string: "Hello!"))
//        try await channel.executeThenClose { inbound, outbound in
//            try await outbound.write(pingFrame)
//
//            for try await frame in inbound {
//                switch frame.opcode {
//                case .pong:
//                    print("Received pong: \(String(buffer: frame.data))")
//
//                case .text:
//                    print("Received: \(String(buffer: frame.data))")
//
//                case .connectionClose:
//                    // Handle a received close frame. We're just going to close by returning from this method.
//                    print("Received Close instruction from server")
//                    return
//                case .binary, .continuation, .ping:
//                    // We ignore these frames.
//                    break
//                default:
//                    // Unknown frames are errors.
//                    return
//                }
//            }
//        }
//    }
}

struct WebSocketBootstrap {
    enum WebSocketBootstrapError: Error {
        case upgradeFailed
    }

    let scheme: String
    let host: String
    let port: Int
    let path: String
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

                var headers = HTTPHeaders()

                headers.add(name: "Host", value: host)
                headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
                headers.add(name: "Content-Length", value: "0")
                headers.add(name: "Sec-WebSocket-Protocol", value: "protoo")

                let requestHead = HTTPRequestHead(version: .http1_1, method: .GET, uri: path, headers: headers)

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
            let bootstrap = ClientBootstrap(group: group)

            upgradeResult = try await bootstrap.connect(host: host, port: port, channelInitializer: initializer)
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
        return try await (self.underlyingBootstrap as! ClientBootstrap).connect(host: host, port: port, channelInitializer: channelInitializer)
    }
}
