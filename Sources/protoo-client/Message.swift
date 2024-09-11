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

struct Message: Codable {
    enum MessageError: Error {
        case invalidType
    }

    enum MessageType {
        case request(MessageRequest)
        case response(MessageResponse)
        case notification(method: String)
    }

    struct MessageRequest {
        let method: String
        let id: UInt32

        init(method: String, id: UInt32 = .random(in: 0..<UInt32.max)) {
            self.method = method
            self.id = id
        }
    }

    struct MessageResponse {
        enum MessageResult {
            case success
            case error(code: Int, reason: String?)
        }

        let result: MessageResult
        let id: UInt32

        init(result: MessageResult, id: UInt32) {
            self.result = result
            self.id = id
        }
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

    init(type: MessageType) {
        self.type = type
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type: MessageType

        if let request = try container.decodeIfPresent(Bool.self, forKey: .request), request {
            type = .request(.init(method: try container.decode(String.self, forKey: .method), id: try container.decode(UInt32.self, forKey: .id)))
        } else if let response = try container.decodeIfPresent(Bool.self, forKey: .response), response {
            let ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false

            if ok {
                type = .response(.init(result: .success, id: try container.decode(UInt32.self, forKey: .id)))
            } else {
                type = .response(.init(result: .error(code: try container.decode(Int.self, forKey: .errorCode), reason: try container.decodeIfPresent(String.self, forKey: .errorReason)), id: try container.decode(UInt32.self, forKey: .id)))
            }
        } else if let notification = try container.decodeIfPresent(Bool.self, forKey: .notification), notification {
            type = .notification(method: try container.decode(String.self, forKey: .method))
        } else {
            throw MessageError.invalidType
        }

        self.type = type
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch type {
        case .request(let request):
            try container.encode(true, forKey: .request)
            try container.encode(request.method, forKey: .method)
            try container.encode(request.id, forKey: .id)

        case .response(let response):
            switch response.result {
            case .success:
                try container.encode(true, forKey: .ok)

            case .error(let code, let reason):
                try container.encode(false, forKey: .ok)
                try container.encode(code, forKey: .errorCode)
                try container.encodeIfPresent(reason, forKey: .errorReason)
            }

            try container.encode(true, forKey: .response)
            try container.encode(response.id, forKey: .id)

        case .notification(let method):
            try container.encode(true, forKey: .notification)
            try container.encode(method, forKey: .method)
        }
    }
}

struct DataMessage<DataType: Codable>: Codable {
    let message: Message
    let data: DataType

    private enum CodingKeys: String, CodingKey {
        case data
    }

    init(message: Message, data: DataType) {
        self.message = message
        self.data = data
    }

    init(from decoder: any Decoder) throws {
        self.message = try Message(from: decoder)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.data = try container.decode(DataType.self, forKey: .data)
    }

    func encode(to encoder: any Encoder) throws {
        try message.encode(to: encoder)

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
    }
}
