import XCTest
import JLiveCore
@testable import JLive

@MainActor
final class BilibiliSessionTests: XCTestCase {
    func testLoginRequiresAllSessionFieldsFromTheBilibiliDomain() throws {
        let valid = try cookies(domain: ".bilibili.com")
        let credentials = try XCTUnwrap(BilibiliSession.credentials(from: valid))
        XCTAssertEqual(credentials.uid, 42)
        XCTAssertEqual(credentials.csrf, "csrf-test")
        XCTAssertTrue(credentials.cookie.contains("SESSDATA=session-test;"))
        XCTAssertNil(BilibiliSession.credentials(from: Array(valid.dropFirst())))
        XCTAssertNil(BilibiliSession.credentials(from: try cookies(domain: "fakebilibili.com")))
    }

    private func cookies(domain: String) throws -> [HTTPCookie] {
        try [("SESSDATA", "session-test"), ("bili_jct", "csrf-test"), ("DedeUserID", "42")].map { name, value in
            try XCTUnwrap(HTTPCookie(properties: [.domain: domain, .path: "/", .name: name, .value: value]))
        }
    }
}
