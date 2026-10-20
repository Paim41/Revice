import Foundation

struct IssuedIdentity: Decodable { let deviceId: String; let credential: String }
struct PairingReply: Decodable { let state: String; let ownerUid: String?; let deviceId: String? }
struct AgentStatus: Decodable { let name: String; let lastSequence: Int64; let revoked: Bool }
struct Ack: Decodable { let accepted: Bool }
struct Requested: Decodable { let state: String }
struct AgentRef: Encodable { let ownerUid: String; let deviceId: String }
struct Envelope: Encodable { let ownerUid: String; let deviceId: String; let reading: CloudReading }
struct JoinRequest: Encodable { let code: String; let deviceId: String; let credential: String; let name: String; let platform = "ios" }
struct StatusRequest: Encodable { let code: String; let credential: String }
struct Empty: Encodable {}

@MainActor protocol GatewayServing {
    func issue() async throws -> IssuedIdentity
    func join(_ identity: AgentIdentity) async throws
    func approval(_ identity: AgentIdentity) async throws -> PairingReply
    func status(_ identity: AgentIdentity) async throws -> AgentStatus
    func upload(_ identity: AgentIdentity, reading: CloudReading) async throws
    func unpair(_ identity: AgentIdentity) async throws
}
final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
@MainActor final class GatewayClient: GatewayServing {
    static let defaultURL = "https://revice-gateway.revicepaim41.workers.dev"
    let base: URL
    private let session: URLSession
    init(base: URL = URL(string: GatewayClient.defaultURL)!) {
        self.base = base
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 20
        config.urlCache = nil; config.httpCookieStorage = nil
        session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }
    private func post<Body: Encodable, Reply: Decodable>(_ path: String, _ body: Body, token: String? = nil) async throws -> Reply {
        guard base.scheme == "https", base.host != nil, base.user == nil, base.password == nil else { throw AgentError.message("An HTTPS gateway is required.") }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw AgentError.message("No gateway response.") }
        guard (200..<300).contains(response.statusCode) else {
            let error = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw AgentError.server(response.statusCode, error?["error"] as? String ?? "UNKNOWN")
        }
        return try JSONDecoder().decode(Reply.self, from: data)
    }
    func issue() async throws -> IssuedIdentity { try await post("v1/ios/identity", Empty()) }
    func join(_ identity: AgentIdentity) async throws {
        let _: Requested = try await post("v1/pairing/join", JoinRequest(code: identity.code ?? "", deviceId: identity.deviceId, credential: identity.credential, name: identity.name))
    }
    func approval(_ identity: AgentIdentity) async throws -> PairingReply {
        try await post("v1/pairing/status", StatusRequest(code: identity.code ?? "", credential: identity.credential))
    }
    func status(_ identity: AgentIdentity) async throws -> AgentStatus {
        try await post("v1/agent/status", AgentRef(ownerUid: identity.ownerUid ?? "", deviceId: identity.deviceId), token: identity.credential)
    }
    func upload(_ identity: AgentIdentity, reading: CloudReading) async throws {
        let ack: Ack = try await post("v1/telemetry", Envelope(ownerUid: identity.ownerUid ?? "", deviceId: identity.deviceId, reading: reading), token: identity.credential)
        guard ack.accepted else { throw AgentError.message("The gateway did not acknowledge this observation.") }
    }
    func unpair(_ identity: AgentIdentity) async throws {
        let _: AgentStatus = try await post("v1/agent/unpair", AgentRef(ownerUid: identity.ownerUid ?? "", deviceId: identity.deviceId), token: identity.credential)
    }
}
