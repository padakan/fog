import AppKit

/// Self-updater for GitHub Releases distribution.
///
/// Checks `https://api.github.com/repos/<repo>/releases/latest`, compares the tag to
/// the bundle version, and if newer: downloads the `.zip` asset, swaps the running
/// .app for the new one (via a tiny detached helper), strips quarantine, and relaunches.
///
/// The repo slug comes from the Info.plist key `FogUpdateRepo` (set in build.sh).
@MainActor
final class Updater {
    static let shared = Updater()

    private var repo: String {
        let r = (Bundle.main.object(forInfoDictionaryKey: "FogUpdateRepo") as? String) ?? ""
        return r.contains("/") && !r.hasPrefix("OWNER") ? r : ""
    }

    var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    }

    func checkForUpdates(userInitiated: Bool) {
        guard !repo.isEmpty, let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            if userInitiated { alert("Updates not configured", "Set FogUpdateRepo in build.sh to your GitHub repo first.") }
            return
        }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, err in
            Task { @MainActor in
                guard let self else { return }
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String else {
                    if userInitiated { self.alert("Check failed", err?.localizedDescription ?? "Couldn't reach GitHub.") }
                    return
                }
                let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let zip = (json["assets"] as? [[String: Any]] ?? [])
                    .compactMap { $0["browser_download_url"] as? String }
                    .first { $0.hasSuffix(".zip") }
                let notes = (json["body"] as? String) ?? ""

                if self.isNewer(latest, than: self.currentVersion), let zip, let z = URL(string: zip) {
                    self.promptInstall(version: latest, notes: notes, zip: z)
                } else if userInitiated {
                    self.alert("You're up to date", "Fog \(self.currentVersion) is the latest version.")
                }
            }
        }.resume()
    }

    private func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private func promptInstall(version: String, notes: String, zip: URL) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Fog \(version) is available"
        a.informativeText = notes.isEmpty ? "You have \(currentVersion). Install the update now?" : notes
        a.addButton(withTitle: "Install & Relaunch")
        a.addButton(withTitle: "Later")
        if a.runModal() == .alertFirstButtonReturn { download(zip) }
    }

    private func download(_ zip: URL) {
        URLSession.shared.downloadTask(with: zip) { [weak self] tmp, _, err in
            Task { @MainActor in
                guard let self else { return }
                guard let tmp else { self.alert("Download failed", err?.localizedDescription ?? ""); return }
                self.install(downloadedZip: tmp)
            }
        }.resume()
    }

    private func install(downloadedZip: URL) {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("fog-update-\(UUID().uuidString)")
        try? fm.createDirectory(at: work, withIntermediateDirectories: true)
        let zipPath = work.appendingPathComponent("Fog.zip")
        try? fm.moveItem(at: downloadedZip, to: zipPath)

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zipPath.path, work.path]
        try? unzip.run(); unzip.waitUntilExit()

        guard let newApp = (try? fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil))?
                .first(where: { $0.pathExtension == "app" }) else {
            alert("Update failed", "Couldn't find Fog.app in the download."); return
        }
        let dest = Bundle.main.bundleURL
        let pid = ProcessInfo.processInfo.processIdentifier

        // Helper waits for us to quit, swaps the bundle, clears quarantine, relaunches.
        let script = """
        #!/bin/bash
        while /bin/kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        /bin/rm -rf "\(dest.path)"
        /usr/bin/ditto "\(newApp.path)" "\(dest.path)"
        /usr/bin/xattr -dr com.apple.quarantine "\(dest.path)" 2>/dev/null
        /usr/bin/open "\(dest.path)"
        """
        let scriptURL = work.appendingPathComponent("swap.sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            let swap = Process()
            swap.executableURL = URL(fileURLWithPath: "/bin/bash")
            swap.arguments = [scriptURL.path]
            try swap.run()           // survives our exit; reparented to launchd
            NSApp.terminate(nil)
        } catch {
            alert("Update failed", error.localizedDescription)
        }
    }

    private func alert(_ title: String, _ msg: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = title; a.informativeText = msg
        a.addButton(withTitle: "OK"); a.runModal()
    }
}
