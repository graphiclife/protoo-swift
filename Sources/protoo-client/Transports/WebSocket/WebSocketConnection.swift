//
//  WebSocketConnection.swift
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
import NIOWebSocket

struct WebSocketConnection {
    enum WebSocketConnectionError: Error {
        case clientClosed
        case serverClosed

        fileprivate var shouldReconnect: Bool {
            switch self {
            case .clientClosed:
                return false

            case .serverClosed:
                return false
            }
        }
    }

    private let bootstrap: WebSocketBootstrap
    private let retryOptions: WebSocketRetryOptions

    let reader: WebSocketReader
    let writer: WebSocketWriter

    init(bootstrap: WebSocketBootstrap, retryOptions: WebSocketRetryOptions) {
        self.bootstrap = bootstrap
        self.retryOptions = retryOptions
        self.reader = .init()
        self.writer = .init()

        run()
    }

    private func run() {
        Task {
            var attempt = 0

            while attempt < retryOptions.numberOfRetries {
                var reconnectOnError = true

                do {
                    let channel = try await bootstrap.connect()

                    reader.publish(event: .open)
                    attempt = 0
                    
                    try await channel.executeThenClose { (inbound, outbound) in
                        let writerTask = Task {
                            for await frame in writer.stream {
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
                                reader.publish(event: .message(.ping))

                            case .pong:
                                reader.publish(event: .message(.pong))

                            case .binary:
                                reader.publish(event: .message(.binary(frame.data)))

                            case .text:
                                reader.publish(event: .message(.text(frame.data)))

                            case .connectionClose:
                                throw WebSocketConnectionError.serverClosed

                            case .continuation:
                                break

                            default:
                                break
                            }
                        }

                        if writer.isClosed {
                            throw WebSocketConnectionError.clientClosed
                        }

                        reader.publish(event: .disconnect)
                    }
                } catch let error as WebSocketConnectionError {
                    reconnectOnError = error.shouldReconnect
                } catch {
                    reconnectOnError = true
                    reader.publish(event: .fail(attempt, error))
                }

                if reconnectOnError && attempt < retryOptions.numberOfRetries {
                    do {
                        try await Task.sleep(for: .milliseconds(min(retryOptions.minInterval * pow(retryOptions.factor, Double(attempt)), retryOptions.maxInterval)))
                    } catch {
                        reader.publish(event: .close)
                        return
                    }

                    attempt += 1
                } else {
                    reader.publish(event: .close)
                    return
                }
            }
        }
    }
}
