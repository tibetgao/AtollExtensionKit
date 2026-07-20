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
        let webContent = AtollWidgetWebContentDescriptor(
            html: dashboardHTML(snapshot),
            preferredHeight: 78,
            isTransparent: true,
            allowLocalhostRequests: false,
            allowRemoteRequests: false
        )
        let tab = AtollNotchExperienceDescriptor.TabConfiguration(
            title: "Codex",
            iconSymbolName: "circle.hexagongrid.fill",
            badgeIcon: codexIcon(),
            preferredHeight: 170,
            appearance: appearance,
            sections: [],
            webContent: webContent,
            allowWebInteraction: false
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

    private func dashboardHTML(_ snapshot: CodexDashboardSnapshot) -> String {
        let quota = snapshot.quota
        let window = quota.headlineWindow
        let remaining = window?.remainingPercent ?? 0
        let quotaLabel = window.map { quota.label(for: $0).uppercased() } ?? "QUOTA"
        let state = activityStyle(snapshot.activity)
        let task = snapshot.latestThread
        let taskTitle = escapeHTML(task.map { trim($0.displayName, length: 48) } ?? "No recent task")
        let project = escapeHTML(task.map { trim(URL(fileURLWithPath: $0.cwd).lastPathComponent, length: 28) } ?? "Ready when you are")
        let reset = window.map { Self.compactResetFormatter.string(from: $0.resetDate) } ?? "Unavailable"
        let percentage = Int(remaining.rounded())
        let degrees = Int((remaining * 3.6).rounded())
        let quotaColor = cssColor(for: remaining)

        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
        *{box-sizing:border-box}html,body{margin:0;width:100%;height:78px;overflow:hidden;background:transparent;color:#fff;font-family:-apple-system,BlinkMacSystemFont,sans-serif}
        .face{height:78px;display:grid;grid-template-columns:1fr .9fr 1.45fr;gap:8px;padding:0 1px}
        .tile{height:72px;border:1px solid rgba(255,255,255,.07);border-radius:18px;background:rgba(255,255,255,.055);display:flex;align-items:center;min-width:0;padding:8px 12px}
        .ring{width:52px;height:52px;flex:0 0 52px;border-radius:50%;display:grid;place-items:center;background:conic-gradient(\(quotaColor) \(degrees)deg,rgba(255,255,255,.10) 0);position:relative}
        .ring:after{content:"";position:absolute;inset:5px;border-radius:50%;background:#0c110e}
        .ring b{z-index:1;font-size:13px;font-variant-numeric:tabular-nums}.copy{min-width:0;margin-left:10px}.eyebrow{font-size:9px;font-weight:700;letter-spacing:.12em;color:rgba(255,255,255,.48)}
        .main{font-size:13px;font-weight:650;line-height:1.15;margin-top:3px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.sub{font-size:10px;color:rgba(255,255,255,.48);margin-top:3px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
        .stateIcon{width:38px;height:38px;flex:0 0 38px;border-radius:50%;display:grid;place-items:center;background:\(state.background);color:\(state.foreground)}
        .stateIcon svg{width:20px;height:20px;fill:currentColor}.note{position:relative;padding-left:14px}.note:before{content:"";position:absolute;left:0;top:10px;bottom:10px;width:3px;border-radius:3px;background:#ff9f0a}
        </style></head><body><div class="face">
          <div class="tile"><div class="ring"><b>\(percentage)%</b></div><div class="copy"><div class="eyebrow">\(quotaLabel) QUOTA</div><div class="main">\(percentage)% left</div><div class="sub">Resets \(reset)</div></div></div>
          <div class="tile"><div class="stateIcon"><svg viewBox="0 0 24 24"><path d="\(state.svgPath)"/></svg></div><div class="copy"><div class="eyebrow">ACTIVITY</div><div class="main">\(state.title)</div><div class="sub">\(state.subtitle)</div></div></div>
          <div class="tile note"><div class="copy"><div class="eyebrow">CURRENT TASK</div><div class="main">\(taskTitle)</div><div class="sub">\(project)</div></div></div>
        </div></body></html>
        """
    }

    private func activityStyle(
        _ activity: CodexTaskActivity
    ) -> (svgPath: String, background: String, foreground: String, title: String, subtitle: String) {
        switch activity {
        case .running:
            return ("M13 2 5 14h6l-1 8 9-13h-6z", "rgba(48,209,88,.16)", "#30d158", "Running", "Codex is working")
        case .waiting:
            return ("M6 2h12v4c0 3-2 5-4 6 2 1 4 3 4 6v4H6v-4c0-3 2-5 4-6-2-1-4-3-4-6zm3 3c0 2 1 4 3 5 2-1 3-3 3-5z", "rgba(255,159,10,.16)", "#ff9f0a", "Waiting", "Action required")
        case .failed:
            return ("M12 2 1 21h22zm-1 6h2v7h-2zm0 9h2v2h-2z", "rgba(255,69,58,.16)", "#ff453a", "Error", "Check latest task")
        case .idle:
            return ("M7 5h4v14H7zm6 0h4v14h-4z", "rgba(174,174,178,.14)", "#aeaeb2", "Idle", "Ready for a task")
        }
    }

    private func cssColor(for remaining: Double) -> String {
        switch remaining {
        case ...10: return "#ff453a"
        case ...25: return "#ff9f0a"
        default: return "#30d158"
        }
    }

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
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

    private func trim(_ string: String, length: Int) -> String {
        string.count <= length ? string : String(string.prefix(length - 1)) + "…"
    }

    private static let compactResetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "E HH:mm"
        return formatter
    }()
}
