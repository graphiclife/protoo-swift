//
//  WebSocketReader.swift
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

class WebSocketReader {
    class Consumer {
        var handler: ((WebSocketEvent) -> Void)?
        var cancelled = false
    }

    private var consumers = [Consumer]()

    func publish(event: WebSocketEvent) {
        if consumers.isEmpty {
            return
        }

        var active = [Consumer]()

        consumers.forEach { consumer in
            if consumer.cancelled {
                return
            }

            consumer.handler?(event)
            active.append(consumer)
        }

        self.consumers = active
    }

    func createConsumer() -> Consumer {
        let consumer = Consumer()
        consumers.append(consumer)
        return consumer
    }

    func read() -> AsyncStream<WebSocketEvent> {
        let consumer = createConsumer()

        return .init { continuation in
            consumer.handler = { event in
                continuation.yield(event)
            }

            continuation.onTermination = { @Sendable _ in
                consumer.handler = nil
                consumer.cancelled = true
            }
        }
    }
}
