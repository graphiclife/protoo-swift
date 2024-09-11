import XCTest
import NIOCore
import NIOPosix

@testable import protoo_client

struct Auth: Codable {
    let authorization: String
}

final class protoo_swift_tests: XCTestCase {
    let uri = URL(string: "ws://127.0.0.1:40150/session/test")!

    func testExample() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        let transport = WebSocketTransport(uri: uri, group: group)
        let peer = Peer.Builder(transport: transport)
            .onOpen {
                print("onOpen")
            }
            .onClose {
                print("onClose")
            }
            .onFailed { (attempt, error) in
                print("onFailed \(attempt) \(error)")
            }
            .onDisconnected {
                print("onDisconnected")
            }
            .onRequest { request in
                print("onRequest \(request)")
                return try .success(for: request)
            }
            .onNotification { notification in
                print("onNotification \(notification)")
            }
            .build()

        try await peer.open()
        try await Task.sleep(for: .seconds(2))
        let auth = try await peer.request(.init(method: "auth", data: Auth(authorization: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbnRpdHkiOiJlbnRpdHktNDkxNjE2NCIsImRlc2NyaXB0aW9uIjoiVSBTYXNha2kiLCJpYXQiOjE3MjQ0MjAyNTN9.NzAyWjgHpomcZ1PjTS7kO78fUbE9b6Gc9TKH04Npp3o")))
        print("returned auth", auth)
        let capabilities = try await peer.request(.init(method: "media.capabilities"))
        print("returned capabilities", capabilities)
        try await Task.sleep(for: .seconds(100))
        await peer.close()
        try await Task.sleep(for: .seconds(5))
    }
}
