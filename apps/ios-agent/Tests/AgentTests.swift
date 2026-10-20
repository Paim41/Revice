import XCTest
@testable import ReviceAgent

@MainActor final class MemoryCredentials: CredentialStoring {
    var value: AgentIdentity?
    func load() throws -> AgentIdentity? { value }
    func save(_ identity: AgentIdentity) throws { value = identity }
    func clear() throws { value = nil }
}
@MainActor final class MemoryQueue: QueueStoring {
    var value = QueueState()
    func load() throws -> QueueState { value }
    func save(_ state: QueueState) throws { value = state }
}
@MainActor struct TestBattery: BatteryCollecting {
    func read() -> BatteryReading { BatteryReading(level: 0.76, state: .unplugged) }
}
@MainActor final class TestGateway: GatewayServing {
    var uploads: [CloudReading] = []
    var error: Error?
    var response = PairingReply(state: "approved", ownerUid: "owner", deviceId: String(repeating: "a", count: 32))
    var didUnpair = false
    func issue() async throws -> IssuedIdentity { IssuedIdentity(deviceId: String(repeating: "a", count: 32), credential: String(repeating: "b", count: 64)) }
    func join(_ identity: AgentIdentity) async throws { if let error { throw error } }
    func approval(_ identity: AgentIdentity) async throws -> PairingReply { if let error { throw error }; return response }
    func status(_ identity: AgentIdentity) async throws -> AgentStatus { if let error { throw error }; return AgentStatus(name: "paIM iPhone", lastSequence: -1, revoked: false) }
    func upload(_ identity: AgentIdentity, reading: CloudReading) async throws { if let error { throw error }; uploads.append(reading) }
    func unpair(_ identity: AgentIdentity) async throws { if let error { throw error }; didUnpair = true }
}
final class AgentTests: XCTestCase {
    func testBatteryUnknownAndStates() throws {
        let unknown = BatteryReading(level: -1, state: .unknown)
        XCTAssertNil(unknown.percentage); XCTAssertNil(unknown.charging); XCTAssertEqual(unknown.label, "N/A")
        XCTAssertEqual(BatteryReading(level: 0.76, state: .charging).label, "76%")
        XCTAssertEqual(BatteryReading(level: 1, state: .full).charging, true)
        XCTAssertNil(BatteryReading(level: .nan, state: .unknown).percentage)
        XCTAssertEqual(BatteryReading(level: 0.5, state: .unplugged).charging, false)
    }
    func testPayloadContainsNoDiskValuesAndNullsSerialize() throws {
        let value = CloudReading(sequence: 7, date: Date(timeIntervalSince1970: 1700000000), battery: BatteryReading(level: -1, state: .unknown))
        let data = try JSONEncoder().encode(value)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(json["storage"] is NSNull)
        XCTAssertEqual(Set(json.keys), Set(["schemaVersion", "sequenceId", "observedAt", "agentVersion", "battery", "storage"]))
        let battery = try XCTUnwrap(json["battery"] as? [String: Any])
        XCTAssertTrue(battery["percentage"] is NSNull); XCTAssertTrue(battery["charging"] is NSNull)
        XCTAssertEqual(battery["state"] as? String, "unknown")
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertNotNil(f.date(from: value.observedAt))
        XCTAssertEqual(try JSONDecoder().decode(CloudReading.self, from: data), value)
    }
    func testStorageValidationAndNamePolicy() {
        XCTAssertNil(LocalStorageReading.make(total: 0, available: 0))
        XCTAssertNil(LocalStorageReading.make(total: 100, available: 101))
        XCTAssertEqual(LocalStorageReading.make(total: 100, available: 30)?.used, 70)
        XCTAssertEqual(validName("  paIM 家  "), "paIM 家")
        XCTAssertNil(validName("a\nb")); XCTAssertNil(validName(String(repeating: "a", count: 41)))
    }
    func testBoundedQueuePreservesSequenceAndNoSecrets() throws {
        var queue = QueueState()
        for _ in 0..<100 { queue.append(battery: BatteryReading(level: 0.5, state: .unplugged), now: Date()) }
        XCTAssertEqual(queue.pending.count, 32); XCTAssertEqual(queue.nextSequence, 100)
        let json = String(decoding: try JSONEncoder().encode(queue), as: UTF8.self)
        XCTAssertFalse(json.contains("credential")); XCTAssertFalse(json.contains("totalBytes"))
    }
    @MainActor func testQueuePersistsAcrossRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = QueueStore(directory: directory)
        var queue = QueueState(); queue.deviceId = "id"
        queue.append(battery: BatteryReading(level: 0.2, state: .charging), now: Date())
        try store.save(queue)
        XCTAssertEqual(try QueueStore(directory: directory).load().pending, queue.pending)
    }
    @MainActor func testPairApprovalSyncAliasAndUnpair() async throws {
        let credentials = MemoryCredentials(), queue = MemoryQueue(), gateway = TestGateway()
        let model = AgentModel(credentials: credentials, queue: queue, gateway: gateway, collector: TestBattery())
        await model.requestPairing(code: "bad", name: "iPhone"); XCTAssertNil(credentials.value)
        await model.requestPairing(code: "123456", name: "My iPhone")
        XCTAssertNotNil(credentials.value?.credential); XCTAssertFalse(model.paired)
        await model.checkApproval()
        XCTAssertTrue(model.paired); XCTAssertEqual(model.identity?.name, "paIM iPhone")
        XCTAssertEqual(gateway.uploads.count, 1); XCTAssertNotNil(model.state.lastSuccess)
        await model.unpair()
        XCTAssertTrue(gateway.didUnpair); XCTAssertNil(credentials.value); XCTAssertTrue(model.state.pending.isEmpty)
    }
    @MainActor func testOfflineRetryAndRevocationDoNotClaimSuccess() async throws {
        let credentials = MemoryCredentials(), queue = MemoryQueue(), gateway = TestGateway()
        credentials.value = AgentIdentity(deviceId: "id", credential: String(repeating: "b", count: 64), ownerUid: "owner", name: "Phone")
        let model = AgentModel(credentials: credentials, queue: queue, gateway: gateway, collector: TestBattery())
        gateway.error = URLError(.timedOut)
        let failed = await model.sync(); XCTAssertFalse(failed)
        XCTAssertEqual(model.state.pending.count, 1); XCTAssertNil(model.state.lastSuccess)
        gateway.error = nil
        let success = await model.sync(); XCTAssertTrue(success)
        XCTAssertEqual(gateway.uploads.first?.sequenceId, 0)
        let acknowledged = model.state.lastSuccess
        gateway.error = AgentError.server(401, "AGENT_REVOKED_OR_INVALID")
        let revoked = await model.sync(); XCTAssertFalse(revoked)
        XCTAssertEqual(model.state.lastSuccess, acknowledged)
        await model.unpair(); XCTAssertNil(credentials.value)
    }
    @MainActor func testRejectionExpiredAndLocalForget() async {
        let credentials = MemoryCredentials(), queue = MemoryQueue(), gateway = TestGateway()
        let model = AgentModel(credentials: credentials, queue: queue, gateway: gateway, collector: TestBattery())
        await model.requestPairing(code: "123456", name: "iPhone")
        gateway.response = PairingReply(state: "rejected", ownerUid: nil, deviceId: nil)
        await model.checkApproval(); XCTAssertFalse(model.paired); XCTAssertTrue(model.message?.contains("rejected") == true)
        gateway.error = AgentError.server(404, "PAIRING_UNAVAILABLE")
        await model.checkApproval(); XCTAssertFalse(model.paired)
        await model.unpair(localOnly: true); XCTAssertNil(credentials.value)
    }
    @MainActor func testCancellationKeepsQueue() async {
        let credentials = MemoryCredentials(), queue = MemoryQueue(), gateway = TestGateway()
        credentials.value = AgentIdentity(deviceId: "id", credential: "secret", ownerUid: "owner", name: "Phone")
        let model = AgentModel(credentials: credentials, queue: queue, gateway: gateway, collector: TestBattery())
        gateway.error = CancellationError()
        let success = await model.sync(); XCTAssertFalse(success)
        XCTAssertNil(model.state.lastSuccess); XCTAssertEqual(model.state.pending.count, 1)
    }
    @MainActor func testConflictingSequenceDoesNotPermanentlyBlockQueue() async {
        let credentials = MemoryCredentials(), queue = MemoryQueue(), gateway = TestGateway()
        credentials.value = AgentIdentity(deviceId: "id", credential: "secret", ownerUid: "owner", name: "Phone")
        let model = AgentModel(credentials: credentials, queue: queue, gateway: gateway, collector: TestBattery())
        gateway.error = AgentError.server(409, "SEQUENCE_REPLAY")
        let rejected = await model.sync(); XCTAssertFalse(rejected)
        XCTAssertNil(model.state.lastSuccess); XCTAssertTrue(model.state.pending.isEmpty)
        gateway.error = nil
        let recovered = await model.sync(); XCTAssertTrue(recovered)
        XCTAssertEqual(gateway.uploads.first?.sequenceId, 1)
    }
}
