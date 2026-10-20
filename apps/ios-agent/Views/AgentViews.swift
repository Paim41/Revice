import SwiftUI
import UIKit

// Use licensed system fonts; no unlicensed font dependencies.
enum Volt {
    static let background = Color(red: 5/255, green: 8/255, blue: 7/255)
    static let surface = Color(red: 17/255, green: 25/255, blue: 20/255)
    static let border = Color(red: 41/255, green: 55/255, blue: 45/255)
    static let lime = Color(red: 185/255, green: 243/255, blue: 90/255)
    static let cyan = Color(red: 78/255, green: 223/255, blue: 195/255)
    static let text = Color(red: 244/255, green: 248/255, blue: 238/255)
    static let secondary = Color(red: 147/255, green: 162/255, blue: 140/255)
}
struct AgentCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).foregroundStyle(Volt.cyan)
            content
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(Volt.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Volt.border))
    }
}
struct Brand: View {
    var body: some View { Image("ReviceHeader").resizable().scaledToFit().frame(maxWidth: 240).accessibilityLabel("Revice — Revive the Device") }
}
struct AgentRoot: View {
    @ObservedObject var model: AgentModel
    @State private var loaded = false
    @State private var pair = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Brand()
                    if !loaded { ProgressView("Revive the Device") }
                    else if model.paired { AgentHome(model: model) }
                    else {
                        Text("Your iPhone. Connected.").font(.largeTitle.bold())
                        Text("Share battery status with your Revice owner dashboard. Storage stays on this iPhone. You control pairing; iOS controls background opportunities.")
                        Button("Pair This iPhone") { pair = true }.buttonStyle(.borderedProminent)
                        if model.identity != nil { Button("Resume Pairing") { pair = true } }
                        AgentHome(model: model)
                    }
                    if let message = model.message { Text(message).foregroundStyle(.orange).accessibilityIdentifier("agentMessage") }
                    if model.busy { ProgressView("Working…") }
                }.padding(20)
            }.background(Volt.background).foregroundStyle(Volt.text)
                .navigationTitle("Revice Agent").navigationBarTitleDisplayMode(.inline)
                .toolbar { NavigationLink { AgentSettings(model: model) } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings") }
                .sheet(isPresented: $pair) { PairingView(model: model) }
                .task { model.refreshLocal(); loaded = true }
                .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
                    if UIApplication.shared.applicationState == .active { Task { await model.batteryChanged() } }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
                    if UIApplication.shared.applicationState == .active { Task { await model.batteryChanged() } }
                }
        }
    }
}
struct PairingView: View {
    @ObservedObject var model: AgentModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = "iPhone"
    @State private var code = ""
    var body: some View {
        NavigationStack {
            Form {
                Brand().listRowBackground(Volt.surface)
                Section("Pair This iPhone") {
                    TextField("Device Name", text: $name).textInputAutocapitalization(.never)
                    TextField("Six-digit Pairing Code", text: $code).keyboardType(.numberPad)
                    Text("Generate a code in Revice Android → Account & pairing, then approve this iPhone there.")
                    Button("Request Pairing") { Task { await model.requestPairing(code: code, name: name) } }.disabled(model.busy || model.paired || !model.ready)
                    Button("Check Approval") { Task { await model.checkApproval(); if model.paired { dismiss() } } }.disabled(model.identity == nil || model.busy)
                }.listRowBackground(Volt.surface)
                Section { Text(model.connection); if let message = model.message { Text(message).foregroundStyle(.orange) } }.listRowBackground(Volt.surface)
            }.scrollContentBackground(.hidden).background(Volt.background)
                .navigationTitle("Pair Device").toolbar { Button("Done") { dismiss() }.disabled(model.busy) }
                .onAppear { name = model.identity?.name ?? "iPhone"; code = model.identity?.code ?? "" }
        }.preferredColorScheme(.dark)
    }
}
struct AgentHome: View {
    @ObservedObject var model: AgentModel
    var body: some View {
        Text(model.identity?.name ?? "This iPhone").font(.title2.bold())
        Text("iPhone | iOS \(UIDevice.current.systemVersion) | \(model.paired ? "Paired" : "Local Only")").foregroundStyle(Volt.secondary)
        AgentCard(title: "Battery") {
            Text(model.battery.label).font(.system(size: 46, weight: .bold, design: .rounded)).foregroundStyle(Volt.lime)
            Text(model.battery.stateLabel)
            if let value = model.battery.percentage { ProgressView(value: value, total: 100).tint(Volt.lime) }
        }
        AgentCard(title: "Storage | Local Only") {
            if let storage = model.storage {
                Text("\(bytes(storage.used)) Estimated Used").font(.title3.bold())
                ProgressView(value: storage.fraction).tint(Volt.cyan)
                Text("\(bytes(storage.available)) Available / \(bytes(storage.total)) Total")
                Text(String(format: "%.1f%% Used", storage.fraction * 100))
            } else { Text("Storage unavailable") }
            Text("Displayed only on this iPhone. Available capacity can differ from iPhone Settings. No storage readings are uploaded.").font(.footnote).foregroundStyle(Volt.secondary)
        }
        AgentCard(title: "Connection") {
            Text(model.connection)
            Text("Last Cloud Sync: \(time(model.state.lastSuccess))")
            Text("Last Local Observation: \(time(model.observed))")
            Text("Pending Observations: \(model.state.pending.count)")
            Button("Sync Now") { Task { await model.sync() } }.buttonStyle(.borderedProminent).disabled(!model.paired || model.busy || !model.ready)
            Button("Refresh Local Readings") { model.refreshLocal() }.disabled(model.busy)
        }
        Text("Automatic synchronization depends on iOS background scheduling. Keep Revice open for current updates; force-quitting can prevent background work.").font(.footnote).foregroundStyle(Volt.secondary)
    }
    private func bytes(_ value: Int64) -> String { String(format: "%.1f GiB", Double(value) / 1_073_741_824) }
    private func time(_ date: Date?) -> String { date?.formatted(date: .abbreviated, time: .shortened) ?? "Not Yet" }
}
struct AgentSettings: View {
    @ObservedObject var model: AgentModel
    @State private var confirm = false
    @State private var forget = false
    var body: some View {
        Form {
            Section("Agent") {
                Text(model.identity?.name ?? "This iPhone")
                Text("Rename this device from its owner’s Revice Android dashboard. Sync to retrieve its latest name.").font(.footnote)
                Text(model.connection)
                Text("Gateway: \(GatewayClient.defaultURL)").font(.footnote).textSelection(.enabled)
            }.listRowBackground(Volt.surface)
            Section("Synchronization") {
                Toggle("Sync While Open", isOn: Binding(get: { model.state.automaticSync }, set: { model.preferences(automatic: $0) }))
                Toggle("Request Background Refresh", isOn: Binding(get: { model.state.backgroundEnabled }, set: { model.preferences(background: $0); BackgroundRefresh.shared.schedule() }))
                Text("Automatic synchronization depends on iOS background scheduling. No fixed update interval is guaranteed.")
            }.listRowBackground(Volt.surface).disabled(model.busy || !model.ready)
            Section("Privacy") {
                Text("Only battery observations are queued for cloud sync. Credentials stay in this iPhone’s Keychain. Disk capacity stays local.")
                Text("Local Storage Sharing: Not Available").foregroundStyle(Volt.secondary)
                Text("A future LAN-only feature requires separate consent and secure device-to-device pairing. No cloud relay is enabled.").font(.footnote)
            }.listRowBackground(Volt.surface)
            Section("Manage Pairing") {
                Button("Unpair This iPhone", role: .destructive) { confirm = true }.disabled(model.busy || model.identity == nil)
                Button("Forget Local Pairing Only", role: .destructive) { forget = true }.disabled(model.busy)
                Text("Local-only removal cannot revoke an offline server credential. Revoke this device from Android too.").font(.footnote)
            }.listRowBackground(Volt.surface)
            Section { NavigationLink("About & Developer Credits") { CreditsView() } }.listRowBackground(Volt.surface)
            if let message = model.message { Text(message).foregroundStyle(.orange).listRowBackground(Volt.surface) }
        }.scrollContentBackground(.hidden).background(Volt.background).navigationTitle("Agent Settings")
            .confirmationDialog("Revoke this agent and clear its credential and queue?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Unpair", role: .destructive) { Task { await model.unpair(); BackgroundRefresh.shared.schedule() } }
            }
            .confirmationDialog("Clear local pairing and queued observations? The server credential may still require revocation from Android.", isPresented: $forget, titleVisibility: .visible) {
                Button("Forget Locally", role: .destructive) { Task { await model.unpair(localOnly: true); BackgroundRefresh.shared.schedule() } }
            }
    }
}
struct CreditsView: View {
    var body: some View {
        ScrollView { VStack(spacing: 18) {
            Image("ReviceIcon").resizable().scaledToFit().frame(width: 120, height: 120)
            Text("Revice").font(.largeTitle.bold()); Text("Revive the Device").foregroundStyle(Volt.cyan)
            Text("Developed by Paim41")
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"))")
            Link("Open GitHub", destination: URL(string: "https://github.com/Paim41")!)
        }.padding(24).frame(maxWidth: .infinity) }.background(Volt.background).navigationTitle("Developer Credits")
    }
}
