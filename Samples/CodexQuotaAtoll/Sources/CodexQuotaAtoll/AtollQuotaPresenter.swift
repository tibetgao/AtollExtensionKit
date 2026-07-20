import AtollExtensionKit
import CodexQuotaCore
import Foundation

@MainActor
final class AtollQuotaPresenter {
    static let activityID = "codex-quota"
    private let rpc = AtollRPCClient()
    private var hasPresented = false

    var isAtollInstalled: Bool {
        AtollClient.shared.isAtollInstalled
    }

    func requestAuthorization() async throws -> Bool {
        try await rpc.requestAuthorization()
    }

    func show(_ snapshot: CodexQuotaSnapshot) async throws {
        guard let window = snapshot.headlineWindow else { return }
        let remaining = window.remainingPercent
        let accent = color(for: snapshot.lowestRemainingPercent ?? remaining)
        let descriptor = AtollLiveActivityDescriptor(
            id: Self.activityID,
            bundleIdentifier: AtollRPCClient.bundleIdentifier,
            priority: remaining <= 10 || snapshot.limitReached ? .high : .normal,
            title: "Codex \(snapshot.label(for: window)) \(Int(remaining.rounded()))%",
            subtitle: subtitle(for: snapshot),
            leadingIcon: .symbol(name: "terminal.fill", size: 16, weight: .semibold),
            trailingContent: .none,
            progressIndicator: .percentage(color: accent),
            progress: remaining / 100,
            accentColor: accent,
            allowsMusicCoexistence: true,
            metadata: metadata(for: snapshot),
            centerTextStyle: .inheritUser,
            sneakPeekConfig: AtollSneakPeekConfig(
                enabled: true,
                duration: 3,
                style: .standard,
                showOnUpdate: false
            ),
            sneakPeekTitle: "Codex quota: \(Int(remaining.rounded()))% left",
            sneakPeekSubtitle: subtitle(for: snapshot)
        )

        if hasPresented {
            try await rpc.update(descriptor)
        } else {
            do {
                // Atoll persists activities across companion restarts. Update that
                // record when it exists, then fall back to a first presentation.
                try await rpc.update(descriptor)
            } catch {
                try await rpc.present(descriptor)
            }
            hasPresented = true
        }
    }

    func dismiss() async {
        guard hasPresented else { return }
        try? await rpc.dismiss(activityID: Self.activityID)
        hasPresented = false
    }

    func close() async {
        await rpc.close()
    }

    private func color(for remaining: Double) -> AtollColorDescriptor {
        switch remaining {
        case ...5: return .red
        case ...20: return .orange
        default: return .green
        }
    }

    private func subtitle(for snapshot: CodexQuotaSnapshot) -> String {
        var parts: [String] = []
        if let secondary = snapshot.weeklyWindow {
            parts.append("\(snapshot.label(for: secondary)) \(Int(secondary.remainingPercent.rounded()))%")
        }
        if let reset = snapshot.headlineWindow?.resetDate {
            parts.append("resets \(Self.resetFormatter.string(from: reset))")
        }
        if snapshot.limitReached { parts.append("limit reached") }
        return parts.joined(separator: " · ")
    }

    private func metadata(for snapshot: CodexQuotaSnapshot) -> [String: String] {
        var values: [String: String] = [:]
        if let plan = snapshot.planType { values["plan"] = plan }
        if let balance = snapshot.credits?.balance { values["creditsBalance"] = balance }
        if let weekly = snapshot.weeklyWindow {
            values["weeklyRemainingPercent"] = String(weekly.remainingPercent)
        }
        return values
    }

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "E HH:mm"
        return formatter
    }()
}
