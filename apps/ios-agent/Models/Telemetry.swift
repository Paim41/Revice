import Foundation

enum BatteryState: String, Codable { case charging, unplugged, full, unknown }
struct BatteryReading: Codable, Equatable {
    let percentage: Double?
    let charging: Bool?
    let state: BatteryState
    init(level: Float, state: BatteryState) {
        percentage = level.isFinite && level >= 0 && level <= 1 ? Double(level) * 100 : nil
        charging = state == .unknown ? nil : (state == .charging || state == .full)
        self.state = state
    }
    enum CodingKeys: String, CodingKey { case percentage, charging, state }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(percentage, forKey: .percentage)
        try c.encode(charging, forKey: .charging)
        try c.encode(state, forKey: .state)
    }
    var label: String { percentage.map { String(format: "%.0f%%", $0) } ?? "N/A" }
    var stateLabel: String {
        switch state { case .charging: return "Charging"; case .unplugged: return "Not Charging"; case .full: return "Full"; case .unknown: return "Unknown" }
    }
}
// Deliberately has no local disk-capacity property. Null storage is required by v1.
struct CloudReading: Codable, Equatable {
    let schemaVersion: Int
    let sequenceId: Int64
    let observedAt: String
    let agentVersion: String
    let battery: BatteryReading
    init(sequence: Int64, date: Date, battery: BatteryReading) {
        schemaVersion = 1; sequenceId = sequence
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        observedAt = formatter.string(from: date)
        agentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        self.battery = battery
    }
    enum CodingKeys: String, CodingKey { case schemaVersion, sequenceId, observedAt, agentVersion, battery, storage }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        sequenceId = try c.decode(Int64.self, forKey: .sequenceId)
        observedAt = try c.decode(String.self, forKey: .observedAt)
        agentVersion = try c.decode(String.self, forKey: .agentVersion)
        battery = try c.decode(BatteryReading.self, forKey: .battery)
        guard try c.decodeNil(forKey: .storage) else { throw AgentError.message("Invalid queued telemetry.") }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion); try c.encode(sequenceId, forKey: .sequenceId)
        try c.encode(observedAt, forKey: .observedAt); try c.encode(agentVersion, forKey: .agentVersion)
        try c.encode(battery, forKey: .battery); try c.encodeNil(forKey: .storage)
    }
}
// Local-only and intentionally NOT Codable; never passed to GatewayClient or QueueStore.
struct LocalStorageReading {
    let total: Int64
    let available: Int64
    var used: Int64 { total - available }
    var fraction: Double { Double(used) / Double(total) }
    static func make(total: Int64, available: Int64) -> Self? {
        guard total > 0, available >= 0, available <= total else { return nil }
        return Self(total: total, available: available)
    }
}
struct AgentIdentity: Codable {
    let deviceId: String
    let credential: String
    var ownerUid: String?
    var code: String?
    var name: String
}
struct QueueState: Codable {
    var deviceId: String? = nil
    var nextSequence: Int64 = 0
    var pending: [CloudReading] = []
    var lastSuccess: Date? = nil
    var backgroundEnabled = false
    var automaticSync = true
    mutating func append(battery: BatteryReading, now: Date) {
        pending.removeAll { item in
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = f.date(from: item.observedAt) else { return true }
            return now.timeIntervalSince(date) > 6 * 86400
        }
        pending.append(CloudReading(sequence: nextSequence, date: now, battery: battery)); nextSequence += 1
        pending = Array(pending.suffix(32))
    }
}
enum AgentError: Error, LocalizedError {
    case message(String), server(Int, String)
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .server(let status, let code):
            if status == 401 { return "Credential revoked or invalid. Unpair locally and reconnect with the owner." }
            if status == 429 { return "Please wait before trying again. Your reading remains queued." }
            if code == "PAIRING_UNAVAILABLE" { return "Pairing expired or unavailable. Request a new code from the owner." }
            return "Gateway request failed (\(status)). Check your connection and pairing."
        }
    }
}
func validName(_ input: String) -> String? {
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, text.unicodeScalars.count <= 40,
          !input.unicodeScalars.contains(where: { $0.properties.generalCategory == .control || $0.properties.generalCategory == .format }) else { return nil }
    return text
}
