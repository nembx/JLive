import Foundation
import Testing
@testable import JLiveCore

struct BilibiliQRLoginTests {
    @Test func codeKeepsTheConfirmationPageAndOpensItInTheBilibiliApp() throws {
        let response = try json(#"{"code":0,"message":"OK","data":{"url":"https://account.bilibili.com/h5/account-h5/auth/scan-web?navhide=1&callback=close&qrcode_key=abc123&from=","qrcode_key":"abc123"}}"#)
        let code = try BilibiliQRLogin.code(from: response)
        #expect(code.key == "abc123")
        #expect(code.url.host == "account.bilibili.com")
        #expect(code.appURL?.absoluteString == "bilibili://browser?url=https%3A%2F%2Faccount.bilibili.com%2Fh5%2Faccount-h5%2Fauth%2Fscan-web%3Fnavhide%3D1%26callback%3Dclose%26qrcode_key%3Dabc123%26from%3D")
        #expect(try BilibiliQRLogin.pollURL(key: "abc123").absoluteString == "https://passport.bilibili.com/x/passport-login/web/qrcode/poll?qrcode_key=abc123")
    }

    @Test func codeRejectsFailuresAndPagesOutsideBilibili() throws {
        #expect(throws: LiveError.self) { try BilibiliQRLogin.code(from: try json(#"{"code":-412,"message":"请求被拦截","data":null}"#)) }
        #expect(throws: LiveError.self) { try BilibiliQRLogin.code(from: try json(#"{"code":0,"data":{"url":"https://fakebilibili.com/scan?qrcode_key=abc","qrcode_key":"abc"}}"#)) }
        #expect(throws: LiveError.self) { try BilibiliQRLogin.code(from: try json(#"{"code":0,"data":{"url":"https://account.bilibili.com/scan","qrcode_key":""}}"#)) }
        #expect(throws: LiveError.self) { try BilibiliQRLogin.code(from: try json(#"{"data":{"url":"https://account.bilibili.com/scan","qrcode_key":"abc"}}"#)) }
    }

    @Test func pollStatesFollowThePlatformCodes() throws {
        func state(_ code: Int) throws -> BilibiliQRLogin.State {
            try BilibiliQRLogin.state(from: try json(#"{"code":0,"message":"OK","data":{"url":"","refresh_token":"","timestamp":0,"code":\#(code),"message":"状态说明"}}"#))
        }
        #expect(try state(86101) == .waiting)
        #expect(try state(86090) == .scanned)
        #expect(try state(86038) == .expired)
        #expect(try state(0) == .confirmed)
        #expect(throws: LiveError.self) { try state(-1) }
        // A rejected request has no state; it must not be read as a confirmed sign-in.
        #expect(throws: LiveError.self) { try BilibiliQRLogin.state(from: try json(#"{"code":-412,"message":"请求被拦截"}"#)) }
        #expect(throws: LiveError.self) { try BilibiliQRLogin.state(from: try json(#"{"code":0,"data":{}}"#)) }
        #expect(throws: LiveError.self) { try BilibiliQRLogin.state(from: try json(#"{"data":{"code":0}}"#)) }
        #expect(throws: LiveError.self) { try BilibiliQRLogin.state(from: try json(#"{"code":0,"data":{"code":"invalid"}}"#)) }
    }

    private func json(_ source: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(source.utf8)) }
}
