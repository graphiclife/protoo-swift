//
//  Message.swift
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

public struct Message: Codable {
    public enum MessageError: Error {
        case invalidType
    }

    public enum MessageType {
        case request(method: String)
        case response(result: MessageResult)
        case notification(method: String)
    }

    public enum MessageResult {
        case success
        case error(code: Int, reason: String?)
    }

    private enum CodingKeys: String, CodingKey {
        case errorCode
        case errorReason
        case id
        case method
        case notification
        case ok
        case request
        case response
    }

    let type: MessageType
    let id: Int

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type: MessageType

        if let request = try container.decodeIfPresent(Bool.self, forKey: .request), request {
            type = .request(method: try container.decode(String.self, forKey: .method))
        } else if let response = try container.decodeIfPresent(Bool.self, forKey: .response), response {
            let ok = try container.decode(Bool.self, forKey: .ok)

            if ok {
                type = .response(result: .success)
            } else {
                type = .response(result: .error(code: try container.decode(Int.self, forKey: .errorCode), reason: try container.decodeIfPresent(String.self, forKey: .errorReason)))
            }
        } else if let notification = try container.decodeIfPresent(Bool.self, forKey: .notification), notification {
            type = .notification(method: try container.decode(String.self, forKey: .method))
        } else {
            throw MessageError.invalidType
        }

        self.type = type
        self.id = try container.decode(Int.self, forKey: .id)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch type {
        case .request(let method):
            try container.encode(true, forKey: .request)
            try container.encode(method, forKey: .method)

        case .response(let result):
            switch result {
            case .success:
                try container.encode(true, forKey: .ok)

            case .error(let code, let reason):
                try container.encode(false, forKey: .ok)
                try container.encode(code, forKey: .errorCode)
                try container.encodeIfPresent(reason, forKey: .errorReason)
            }

        case .notification(let method):
            try container.encode(true, forKey: .notification)
            try container.encode(method, forKey: .method)
        }

        try container.encode(id, forKey: .id)
    }
}
