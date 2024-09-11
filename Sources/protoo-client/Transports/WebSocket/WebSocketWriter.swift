//
//  WebSocketWriter.swift
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

class WebSocketWriter {
    private var writer: (([WebSocketFrame]) -> Void)?
    private var closer: (() -> Void)?

    lazy var stream: AsyncStream<WebSocketFrame> = .init { continuation in
        self.writer = { frames in
            for frame in frames {
                continuation.yield(frame)
            }
        }

        self.closer = {
            continuation.finish()
        }

        continuation.onTermination = { @Sendable _ in
            self.writer = nil
            self.closer = nil
        }
    }

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
        writer?([.init(fin: true, opcode: .connectionClose, maskKey: .random(), data: .init())])
        isClosed = true
        closer?()
    }
}
