import XCTest
@testable import iosTerminal

final class MoshBootstrapTests: XCTestCase {

    func testServerCommand() {
        let c = MoshBootstrap.serverCommand(exec: "tmux new -A -s main")
        XCTAssertTrue(c.hasPrefix("mosh-server new -s -c 256"), c)
        XCTAssertTrue(c.contains("-l LANG=en_US.UTF-8"))
        XCTAssertTrue(c.contains("-l LC_ALL=en_US.UTF-8"))
        XCTAssertTrue(c.hasSuffix("-- tmux new -A -s main"))
    }

    func testServerCommandWithPort() {
        let c = MoshBootstrap.serverCommand(udpPort: "60005", exec: nil)
        XCTAssertTrue(c.contains("-p 60005"))
        XCTAssertFalse(c.contains("--"))
    }

    func testParseConnectValidIgnoresBanner() {
        let out = "Last login: today\nMOSH CONNECT 60001 g6gXNAErZ7iAcDQ8h7VtUA\nbye\n"
        XCTAssertEqual(MoshBootstrap.parseConnect(out),
                       MoshConnectInfo(port: "60001", key: "g6gXNAErZ7iAcDQ8h7VtUA"))
    }

    func testParseConnectRejectsBadInput() {
        XCTAssertNil(MoshBootstrap.parseConnect("nothing here"))
        XCTAssertNil(MoshBootstrap.parseConnect("MOSH CONNECT 60001 tooShortKey"),
                     "22-char key required")
        XCTAssertNil(MoshBootstrap.parseConnect("MOSH CONNECT notaport g6gXNAErZ7iAcDQ8h7VtUA"),
                     "port must be numeric")
        XCTAssertNil(MoshBootstrap.parseConnect("MOSH CONNECT"))
    }
}
