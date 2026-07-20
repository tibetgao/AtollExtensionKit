import AtollExtensionKit
import CodexQuotaCore
import CoreGraphics
import Foundation

@MainActor
final class AtollQuotaPresenter {
    static let experienceID = "codex-dashboard"
    static let legacyActivityID = "codex-quota"

    private let rpc = AtollRPCClient()
    private var hasPresented = false

    var isAtollInstalled: Bool { AtollClient.shared.isAtollInstalled }

    func requestAuthorization() async throws -> Bool {
        try await rpc.requestAuthorization()
    }

    func removeLegacyActivity() async {
        try? await rpc.dismiss(activityID: Self.legacyActivityID)
    }

    func show(_ snapshot: CodexDashboardSnapshot) async throws {
        let descriptor = makeDescriptor(snapshot)
        if hasPresented {
            try await rpc.update(descriptor)
        } else {
            do {
                try await rpc.update(descriptor)
            } catch {
                try await rpc.present(descriptor)
            }
            hasPresented = true
        }
    }

    func close() async { await rpc.close() }

    private func makeDescriptor(_ snapshot: CodexDashboardSnapshot) -> AtollNotchExperienceDescriptor {
        let quota = snapshot.quota
        let accent = color(for: quota.lowestRemainingPercent ?? 100)
        let appearance = AtollWidgetAppearanceOptions(
            tintColor: accent,
            tintOpacity: 0.10,
            enableGlassHighlight: true,
            border: AtollWidgetBorderStyle(color: .white, opacity: 0.10, width: 0.5)
        )
        let sections: [AtollNotchContentSection] = [
            usageSection(snapshot),
            activitySection(snapshot),
            latestTaskSection(snapshot),
        ]
        let tab = AtollNotchExperienceDescriptor.TabConfiguration(
            title: "Codex",
            iconSymbolName: "circle.hexagongrid.fill",
            badgeIcon: codexIcon(),
            preferredHeight: 390,
            appearance: appearance,
            sections: sections,
            allowWebInteraction: false,
            footnote: "Updated \(Self.timeFormatter.string(from: snapshot.refreshedAt)) · Local Codex"
        )
        return AtollNotchExperienceDescriptor(
            id: Self.experienceID,
            bundleIdentifier: AtollRPCClient.bundleIdentifier,
            priority: .normal,
            accentColor: accent,
            metadata: metadata(for: snapshot),
            tab: tab,
            minimalistic: nil,
            durationHint: nil
        )
    }

    private func usageSection(_ snapshot: CodexDashboardSnapshot) -> AtollNotchContentSection {
        let quota = snapshot.quota
        let short = quota.shortWindow
        let weekly = quota.weeklyWindow
        var elements: [AtollWidgetContentElement] = []
        if let short {
            elements.append(.text(quota.label(for: short), font: .system(size: 12, weight: .medium), color: .gray))
            elements.append(.text(percent(short), font: .monospacedDigit(size: 20, weight: .semibold), color: color(for: short.remainingPercent)))
        }
        if let weekly {
            elements.append(.text(quota.label(for: weekly), font: .system(size: 12, weight: .medium), color: .gray))
            elements.append(.text(percent(weekly), font: .monospacedDigit(size: 20, weight: .semibold), color: color(for: weekly.remainingPercent)))
        } else if let reset = short?.resetDate {
            elements.append(.text("Resets", font: .system(size: 12, weight: .medium), color: .gray))
            elements.append(.text(Self.resetFormatter.string(from: reset), font: .monospacedDigit(size: 15, weight: .medium), color: .white))
        }
        if elements.isEmpty {
            elements = [.text("Quota unavailable", font: .system(size: 13, weight: .medium), color: .gray)]
        }
        return .init(
            id: "usage",
            title: "Usage",
            subtitle: quota.planType.map { $0.capitalized },
            layout: .columns,
            elements: elements
        )
    }

    private func activitySection(_ snapshot: CodexDashboardSnapshot) -> AtollNotchContentSection {
        let status: (String, AtollColorDescriptor, String)
        switch snapshot.activity {
        case .running: status = ("Running", .green, "Codex is working")
        case .waiting: status = ("Waiting", .orange, "Action required")
        case .failed: status = ("Error", .red, "Last task failed")
        case .idle: status = ("Idle", .gray, "Ready for a task")
        }
        let elements: [AtollWidgetContentElement] = [
            .text("Status", font: .system(size: 12, weight: .regular), color: .gray),
            .text(status.0, font: .system(size: 15, weight: .semibold), color: status.1),
            .text("Recent", font: .system(size: 12, weight: .regular), color: .gray),
            .text("\(snapshot.threads.count) tasks", font: .monospacedDigit(size: 15, weight: .medium), color: .white),
        ]
        return .init(
            id: "activity",
            title: "Activity",
            subtitle: status.2,
            layout: .metrics,
            elements: elements
        )
    }

    private func latestTaskSection(_ snapshot: CodexDashboardSnapshot) -> AtollNotchContentSection {
        guard let thread = snapshot.latestThread else {
            return .init(
                id: "latest",
                title: "Latest task",
                layout: .stack,
                elements: [.text("No recent Codex tasks", font: .system(size: 13), color: .gray)]
            )
        }
        let project = URL(fileURLWithPath: thread.cwd).lastPathComponent
        return .init(
            id: "latest",
            title: "Latest task",
            subtitle: project,
            layout: .stack,
            elements: [
                .text(trim(thread.displayName, length: 80), font: .system(size: 14, weight: .semibold), color: .white),
                .text("Updated \(relativeTime(thread.updatedAt))", font: .system(size: 11, weight: .regular), color: .gray),
            ]
        )
    }

    private func codexIcon() -> AtollIconDescriptor {
        let paths = [
            "/Applications/ChatGPT.app/Contents/Resources/icon-codex-dark-color.png",
            "/Applications/ChatGPT.app/Contents/Resources/icon-codex-light.png",
        ]
        for path in paths {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                return .image(data: data, size: CGSize(width: 32, height: 32), cornerRadius: 7)
            }
        }
        return .symbol(name: "circle.hexagongrid.fill", size: 24, weight: .semibold)
    }

    private func percent(_ window: CodexRateLimitWindow?) -> String {
        guard let window else { return "—" }
        return "\(Int(window.remainingPercent.rounded()))% left"
    }

    private func color(for remaining: Double) -> AtollColorDescriptor {
        switch remaining {
        case ...10: return .red
        case ...25: return .orange
        default: return .green
        }
    }

    private func metadata(for snapshot: CodexDashboardSnapshot) -> [String: String] {
        [
            "activity": snapshot.activity.rawValue,
            "threadCount": String(snapshot.threads.count),
            "updatedAt": ISO8601DateFormatter().string(from: snapshot.refreshedAt),
        ]
    }

    private func relativeTime(_ epoch: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(epoch))
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func trim(_ string: String, length: Int) -> String {
        string.count <= length ? string : String(string.prefix(length - 1)) + "…"
    }

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "E HH:mm"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
