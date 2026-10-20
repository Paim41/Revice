import Foundation
import Combine
import OSLog

@MainActor final class AgentModel: ObservableObject {
    static let shared = AgentModel()
    @Published private(set) var identity: AgentIdentity?
    @Published private(set) var state = QueueState()
    @Published private(set) var battery = BatteryReading(level: -1, state: .unknown)
    @Published private(set) var storage: LocalStorageReading?
    @Published private(set) var storageObserved: Date?
    @Published private(set) var observed: Date?
    @Published private(set) var busy = false
    @Published private(set) var ready = false
    @Published var message: String?
    @Published private(set) var connection = "Not Connected"
    private let credentials: CredentialStoring
    private let queue: QueueStoring
    private let gateway: GatewayServing
    private let collector: BatteryCollecting
    private let log = Logger(subsystem: "app.revice.ios-agent", category: "sync")
    private var lastAttempt: Date?
    var paired: Bool { identity?.ownerUid != nil }
    convenience init() { self.init(credentials: KeychainCredentials(), queue: QueueStore(), gateway: GatewayClient(), collector: BatteryCollector()) }
    init(credentials: CredentialStoring, queue: QueueStoring, gateway: GatewayServing, collector: BatteryCollecting) {
        self.credentials = credentials; self.queue = queue; self.gateway = gateway; self.collector = collector
        do {
            identity = try credentials.load(); state = try queue.load()
            // A queue restored for a different enrollment must never be sent under a new token.
            if state.deviceId != identity?.deviceId {
                state = QueueState(); state.deviceId = identity?.deviceId; try queue.save(state)
            }
            ready = true; connection = paired ? "Ready to Sync" : "Not Paired"
        } catch { message = "Local secure state could not be read. Unlock and reopen Revice; no data will be sent." }
    }
    func refreshLocal(includeStorage: Bool = true) {
        battery = collector.read(); observed = Date()
        if includeStorage { storage = StorageCollector().read(); storageObserved = storage == nil ? nil : Date() }
    }
    func foreground() async {
        refreshLocal()
        if state.automaticSync && paired { _ = await sync(automatic: true) }
    }
    func batteryChanged() async {
        refreshLocal(includeStorage: false)
        if state.automaticSync && paired { _ = await sync(automatic: true) }
    }
    private func failure(_ error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            message = "Synchronization interrupted; unsent observations remain queued."
        } else { message = error.localizedDescription }
        connection = "Not Synced"
        // Never log credentials, request bodies, device names or telemetry.
        log.notice("Agent operation did not complete; details are shown locally.")
    }
    func requestPairing(code: String, name: String) async {
        guard ready, !busy, !paired else { return }
        guard code.range(of: "^[0-9]{6}$", options: .regularExpression) != nil,
              let name = validName(name) else { message = "Enter a six-digit code and a name of 1–40 characters without controls."; return }
        busy = true; message = nil; defer { busy = false }
        do {
            if identity == nil {
                let issued = try await gateway.issue()
                guard issued.deviceId.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil,
                      issued.credential.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw AgentError.message("Invalid gateway enrollment response.") }
                let pending = AgentIdentity(deviceId: issued.deviceId, credential: issued.credential, code: code, name: name)
                try credentials.save(pending); identity = pending
                state = QueueState(); state.deviceId = pending.deviceId; try queue.save(state)
            }
            guard var pending = identity else { return }
            pending.code = code; pending.name = name
            try credentials.save(pending); identity = pending
            try await gateway.join(pending)
            connection = "Waiting for Approval"; message = "Approve this iPhone on the Android dashboard, then Check Approval."
        } catch { failure(error) }
    }
    func checkApproval() async {
        guard ready, !busy, let pending = identity, !paired else { return }
        busy = true; message = nil
        do {
            let result = try await gateway.approval(pending)
            if result.state == "approved", let owner = result.ownerUid, result.deviceId == pending.deviceId {
                var approved = pending; approved.ownerUid = owner; approved.code = nil
                try credentials.save(approved); identity = approved
                connection = "Paired"
            } else { message = result.state == "rejected" ? "Owner rejected this request. Ask for a new pairing code." : "Still waiting for owner approval." }
        } catch { failure(error) }
        busy = false
        if paired { _ = await sync() }
    }
    @discardableResult func sync(automatic: Bool = false) async -> Bool {
        guard ready, !busy, let identity, identity.ownerUid != nil else { return false }
        if automatic, let lastAttempt, Date().timeIntervalSince(lastAttempt) < 20 { return false }
        busy = true; message = nil; lastAttempt = Date(); defer { busy = false }
        do {
            // Battery only: no call to StorageCollector from a background/cloud path.
            refreshLocal(includeStorage: false)
            state.append(battery: battery, now: observed ?? Date()); try queue.save(state)
            let status = try await gateway.status(identity)
            try Task.checkCancellation()
            guard !status.revoked else { throw AgentError.message("This device has been revoked.") }
            var named = identity; named.name = status.name
            try credentials.save(named); self.identity = named
            state.pending.removeAll { $0.sequenceId < status.lastSequence }
            // Recover sequence allocation if app files were removed but Keychain survived.
            if state.pending.allSatisfy({ $0.sequenceId < status.lastSequence }) || state.nextSequence <= status.lastSequence {
                state.pending.removeAll(); state.nextSequence = status.lastSequence + 1
                state.append(battery: battery, now: Date()); try queue.save(state)
            }
            guard let reading = state.pending.first else { return true }
            try await gateway.upload(named, reading: reading)
            try Task.checkCancellation()
            state.pending.removeAll { $0.sequenceId == reading.sequenceId }
            state.lastSuccess = Date(); try queue.save(state)
            connection = "Synced"; return true
        } catch {
            if case AgentError.server(400, "TIMESTAMP_OUT_OF_RANGE") = error {
                state.pending.removeAll(); try? queue.save(state)
            }
            failure(error); return false
        }
    }
    func preferences(background: Bool? = nil, automatic: Bool? = nil) {
        guard ready, !busy else { return }
        var next = state
        if let background { next.backgroundEnabled = background }
        if let automatic { next.automaticSync = automatic }
        do { try queue.save(next); state = next } catch { failure(error) }
    }
    func unpair(localOnly: Bool = false) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            if let identity, paired, !localOnly {
                do { try await gateway.unpair(identity) }
                catch AgentError.server(401, _) { /* Already revoked; local cleanup is safe. */ }
            }
            try credentials.clear(); identity = nil
            state = QueueState(); try queue.save(state)
            ready = true; connection = "Not Paired"; message = nil
        } catch { failure(error) }
    }
}
