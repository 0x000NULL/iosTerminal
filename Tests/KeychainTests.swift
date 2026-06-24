import XCTest
@testable import iosTerminal

final class KeychainTests: XCTestCase {
    func testRoundtrip() throws {
        let store = KeychainStore.shared
        let id = "iosterm-test-\(UUID().uuidString)"
        do {
            try store.setString("hunter2-\(id)", for: id)
        } catch KeychainError.status(let s) {
            throw XCTSkip("Keychain unavailable in this test context (OSStatus \(s))")
        }
        XCTAssertEqual(store.getString(id), "hunter2-\(id)")

        // Overwrite replaces, not duplicates.
        try store.setString("changed", for: id)
        XCTAssertEqual(store.getString(id), "changed")

        store.delete(id)
        XCTAssertNil(store.get(id))
    }

    func testProfileAuthKindMapping() {
        let p = ConnectionProfile(name: "box", host: "100.64.0.1", username: "me")
        XCTAssertEqual(p.authKind, .password)
        p.authKind = .privateKey
        XCTAssertEqual(p.authKindRaw, "privateKey")
        XCTAssertEqual(p.initialCommand, "tmux new -A -s main") // tmuxAttach default
        XCTAssertEqual(p.displayTitle, "me@100.64.0.1")
    }
}
