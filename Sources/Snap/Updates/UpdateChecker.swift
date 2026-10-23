import AppKit
import SnapCore

/// Looks for a newer release on GitHub: shortly after launch, then once a day, and on demand.
/// It only tells the user and links to the download; it never installs anything.
@MainActor
final class UpdateChecker {
    /// Called with the newer release, or nil once there's none.
    var onUpdateAvailable: ((GitHubRelease?) -> Void)?
    private(set) var available: GitHubRelease? {
        didSet { onUpdateAvailable?(available) }
    }

    private let settings: AppSettings
    private var timer: Timer?
    private static let interval: TimeInterval = 24 * 60 * 60
    private static let lastCheckKey = "lastUpdateCheck"

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// "owner/repo" from Info.plist, so forks check their own releases.
    private var repository: String {
        Bundle.main.object(forInfoDictionaryKey: "SnapReleasesRepository") as? String ?? "szupzj18/snap"
    }

    private var currentVersion: SemanticVersion? {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(SemanticVersion.init)
    }

    func start() {
        // Hourly ticks; a check only happens once a day.
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.checkIfDue() }
    }

    private func checkIfDue() {
        guard settings.checkForUpdates else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= Self.interval else { return }
        Task { await check(userInitiated: false) }
    }

    func check(userInitiated: Bool) async {
        do {
            let latest = try await fetchLatest()
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
            if let latest, let current = currentVersion, current < latest.version {
                available = latest
                if userInitiated { offer(latest) }
            } else {
                available = nil
                if userInitiated { tellUpToDate() }
            }
        } catch {
            // A failed background check isn't worth an alert; the next one will try again.
            if userInitiated { ErrorPresenter.present(error) }
        }
    }

    func offer(_ release: GitHubRelease) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Snap \(release.version) is available"
        alert.informativeText = "You have \(currentVersion?.description ?? "an older version"). Download the new version from GitHub?"
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.page)
        }
    }

    private func tellUpToDate() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Snap is up to date"
        alert.informativeText = "\(currentVersion?.description ?? "This") is the latest version."
        alert.runModal()
    }

    /// Nil when the repository has no published release yet.
    private func fetchLatest() async throws -> GitHubRelease? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: return try GitHubRelease.decode(data)
        case 404: return nil
        default: throw URLError(.badServerResponse)
        }
    }
}
