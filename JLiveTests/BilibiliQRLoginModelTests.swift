import XCTest
import JLiveCore
@testable import JLive

@MainActor
final class BilibiliQRLoginModelTests: XCTestCase {
    private let account = BilibiliCredentials(cookie: "SESSDATA=session-test;", csrf: "csrf-test", uid: 42)
    private var signedIn: [BilibiliCredentials] = []

    func testConfirmedCodeSignsInWithTheAccountFromTheLoginSession() async {
        let model = makeModel(ScriptedTransport([.success(.waiting), .success(.scanned), .success(.confirmed)], account: account))
        await model.run()
        XCTAssertEqual(model.phase, .signedIn)
        XCTAssertEqual(signedIn.map(\.uid), [42])
        XCTAssertFalse(model.canConfirm)
    }

    func testCodeStaysOpenUntilTheViewerConfirmsOrLeaves() async {
        let transport = ScriptedTransport([.success(.scanned)], account: account, thenHolds: true)
        let model = makeModel(transport)
        let running = Task { await model.run() }
        while await !transport.isHolding { await Task.yield() }
        XCTAssertEqual(model.phase, .scanned)
        XCTAssertTrue(model.canConfirm)
        XCTAssertEqual(model.code?.key, "key1")
        running.cancel()
        await transport.release()
        await running.value
        XCTAssertEqual(model.phase, .scanned, "离开登录页不是登录失败")
        XCTAssertTrue(signedIn.isEmpty)
    }

    func testExpiredCodeStopsAndTheNextRunShowsAFreshCode() async {
        let transport = ScriptedTransport([.success(.expired), .success(.confirmed)], account: account)
        let model = makeModel(transport)
        await model.run()
        XCTAssertEqual(model.phase, .expired)
        XCTAssertFalse(model.canConfirm, "过期的二维码不能再用于确认")
        XCTAssertTrue(signedIn.isEmpty)
        await model.run()
        XCTAssertEqual(model.code?.key, "key2")
        XCTAssertEqual(model.phase, .signedIn)
    }

    func testDroppedRequestsAreRetriedBeforeGivingUp() async {
        let dropped = Result<BilibiliQRLogin.State, any Error>.failure(URLError(.networkConnectionLost))
        let recovering = makeModel(ScriptedTransport(Array(repeating: dropped, count: 4) + [.success(.confirmed)], account: account))
        await recovering.run()
        XCTAssertEqual(recovering.phase, .signedIn, "切到哔哩哔哩 App 确认时的短暂断网不应中断登录")
        let failing = makeModel(ScriptedTransport(Array(repeating: dropped, count: 5) + [.success(.confirmed)], account: account))
        await failing.run()
        guard case .failed = failing.phase else { return XCTFail("连续失败后应提示重试") }
        XCTAssertEqual(signedIn.count, 1)
    }

    func testConfirmationWithoutAnAccountOrARejectedAccountFails() async {
        let missing = makeModel(ScriptedTransport([.success(.confirmed)], account: nil))
        await missing.run()
        XCTAssertEqual(missing.phase, .failed(LiveError.platform("未能读取登录信息，请重试").localizedDescription))
        XCTAssertTrue(signedIn.isEmpty)
        let rejected = BilibiliQRLoginModel(transport: ScriptedTransport([.success(.confirmed)], account: account), interval: .milliseconds(1)) { _ in
            throw LiveError.platform("未能确认 B站登录，请重新登录")
        }
        await rejected.run()
        XCTAssertEqual(rejected.phase, .failed(LiveError.platform("未能确认 B站登录，请重新登录").localizedDescription))
    }

    private func makeModel(_ transport: ScriptedTransport) -> BilibiliQRLoginModel {
        BilibiliQRLoginModel(transport: transport, interval: .milliseconds(1)) { [weak self] in self?.signedIn.append($0) }
    }
}

private actor ScriptedTransport: BilibiliQRTransport {
    private var steps: [Result<BilibiliQRLogin.State, any Error>]
    private let account: BilibiliCredentials?
    private let thenHolds: Bool
    private var generated = 0
    private var gate: CheckedContinuation<Void, Never>?
    var isHolding: Bool { gate != nil }

    init(_ steps: [Result<BilibiliQRLogin.State, any Error>], account: BilibiliCredentials?, thenHolds: Bool = false) {
        self.steps = steps
        self.account = account
        self.thenHolds = thenHolds
    }

    func release() { gate?.resume(); gate = nil }
    func generate() async throws -> BilibiliQRLogin.Code {
        generated += 1
        return BilibiliQRLogin.Code(url: URL(string: "https://account.bilibili.com/scan?qrcode_key=key\(generated)")!, key: "key\(generated)")
    }
    func poll(key: String) async throws -> BilibiliQRLogin.State {
        if steps.isEmpty {
            if thenHolds { await withCheckedContinuation { gate = $0 } }
            return .waiting
        }
        return try steps.removeFirst().get()
    }
    func credentials() async -> BilibiliCredentials? { account }
}
