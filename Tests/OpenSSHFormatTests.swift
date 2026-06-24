import XCTest
import CryptoKit
@testable import iosTerminal

final class OpenSSHFormatTests: XCTestCase {

    func testEcdsaP256PublicKeyEncoding() throws {
        let priv = P256.Signing.PrivateKey()
        let x963 = priv.publicKey.x963Representation
        XCTAssertEqual(x963.count, 65)            // 0x04 || X(32) || Y(32)
        XCTAssertEqual(x963.first, 0x04)

        let line = OpenSSHFormat.ecdsaP256PublicKey(x963: x963, comment: "test")
        XCTAssertTrue(line.hasPrefix("ecdsa-sha2-nistp256 "), line)
        XCTAssertTrue(line.hasSuffix(" test"))

        let b64 = String(line.split(separator: " ")[1])
        let blob = try XCTUnwrap(Data(base64Encoded: b64))

        var off = blob.startIndex
        func readString() -> Data {
            let len = (UInt32(blob[off]) << 24) | (UInt32(blob[off + 1]) << 16)
                    | (UInt32(blob[off + 2]) << 8) | UInt32(blob[off + 3])
            off += 4
            let s = blob[off ..< off + Int(len)]
            off += Int(len)
            return Data(s)
        }
        XCTAssertEqual(String(decoding: readString(), as: UTF8.self), "ecdsa-sha2-nistp256")
        XCTAssertEqual(String(decoding: readString(), as: UTF8.self), "nistp256")
        XCTAssertEqual(readString().count, 65)    // the public point
        XCTAssertEqual(off, blob.endIndex)        // exactly consumed
    }

    func testSshStringLengthPrefix() {
        let d = OpenSSHFormat.sshString("ab")
        XCTAssertEqual(Array(d), [0, 0, 0, 2, 0x61, 0x62])
    }
}
