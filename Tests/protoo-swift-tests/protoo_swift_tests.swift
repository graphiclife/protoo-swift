import XCTest
import NIOCore
import NIOPosix

@testable import protoo_client

final class protoo_swift_tests: XCTestCase {
    let uri = URL(string: "ws://meet.graphiclife.com:40150/session/pommes")!

    func testExample() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        let peer = await Peer(transport: WebSocketTransport(uri: uri, group: group))
        
        await peer.open()
        try await Task.sleep(for: .seconds(10))
        await peer.close()
        try await Task.sleep(for: .seconds(300))
    }
}
