import XCTest
@testable import iosTerminal

final class SSHLibraryTests: XCTestCase {
    func testLibssh2LinksAndIsVersion111() {
        XCTAssertTrue(SSHLibrary.initialize(), "libssh2_init should succeed")
        let v = SSHLibrary.version
        XCTAssertTrue(v.contains("1.11"), "expected libssh2 1.11.x (RSA-sha2 capable), got \(v)")
        SSHLibrary.shutdown()
    }
}
