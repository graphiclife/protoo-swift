//
//  WebSocketBootstrap.swift
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

enum WebSocketBootstrapError: Error {
    case upgradeFailed
    case invalidUnderlyingBootstrap
}

struct WebSocketBootstrap {
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
            var configuration = TLSConfiguration.makeClientConfiguration()

            if let reject = ProcessInfo.processInfo.environment["PROTOO_TLS_REJECT_UNAUTHORIZED"] {
                if reject == "0" || reject.lowercased() == "false" {
                    configuration.certificateVerification = .none
                }
            }

            let sslContext = try NIOSSLContext(configuration: configuration)
            let isSocketAddress = (try? SocketAddress(ipAddress: host, port: 0)) != nil
            let bootstrap = try NIOClientTCPBootstrap(ClientBootstrap(group: group), tls: NIOSSLClientTLSProvider(context: sslContext,
                                                                                                          serverHostname: isSocketAddress ? nil : host))

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
    fileprivate func connect<Output: Sendable>(
        host: String,
        port: Int,
        channelInitializer: @escaping @Sendable (Channel) -> EventLoopFuture<Output>
    ) async throws -> Output {
        guard let underlyingBootstrap = underlyingBootstrap as? ClientBootstrap else {
            throw WebSocketBootstrapError.invalidUnderlyingBootstrap
        }

        return try await underlyingBootstrap.connect(host: host, port: port, channelInitializer: channelInitializer)
    }
}
