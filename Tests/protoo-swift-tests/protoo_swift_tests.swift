import XCTest
import NIOCore
import NIOPosix

@testable import protoo_client

final class protoo_swift_tests: XCTestCase {
    func testExample() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        let ws = WebSocketTransport(uri: URL(string: "ws://meet.graphiclife.com:40150/session/pommes")!, group: group)

        try await ws.run()
    }
}
