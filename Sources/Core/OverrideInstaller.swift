import Foundation

enum OverrideInstallerError: LocalizedError {
    case adminCancelled
    case commandFailed(String)
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .adminCancelled: return "已取消管理员授权"
        case .commandFailed(let message): return message
        case .verificationFailed: return "写入后系统没有列出新档位，可能需要在系统设置里拔插线或重启一次"
        }
    }
}

/// 负责 override 文件的备份、提权写入、还原与校验。
final class OverrideInstaller {
    static let shared = OverrideInstaller()

    let backupRoot: URL
    private let fm = FileManager.default

    init() {
        let base = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DisplayPilot/backups", isDirectory: true)
        backupRoot = base
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
    }

    // MARK: - 备份

    /// 首次覆盖前把系统原有的（或第三方工具留下的）override 备份下来。
    @discardableResult
    func backupIfNeeded(_ file: OverrideFile) -> URL? {
        guard fm.fileExists(atPath: file.fileURL.path) else { return nil }
        let name = "DisplayProductID-\(file.productHex)-\(Self.stamp()).plist"
        let destination = backupRoot.appendingPathComponent(name)
        if fm.fileExists(atPath: destination.path) { return destination }
        do {
            try fm.copyItem(at: file.fileURL, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    func backups(for identity: DisplayIdentity) -> [URL] {
        let prefix = "DisplayProductID-\(identity.productHex)-"
        let contents = (try? fm.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return contents
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// 有没有需要还原的原始文件（用于「还原原生模式表」按钮的可用性判断）。
    func hasBackup(for identity: DisplayIdentity) -> Bool {
        !backups(for: identity).isEmpty
    }

    // MARK: - 写入 / 还原

    /// 写入 override：内容一致就直接返回（不弹密码），否则备份 + 提权复制。
    func install(_ file: OverrideFile) throws {
        if file.matches() { return }
        backupIfNeeded(file)

        let temporary = fm.temporaryDirectory.appendingPathComponent("displaypilot-override-\(UUID().uuidString).plist")
        try file.write(to: temporary)
        defer { try? fm.removeItem(at: temporary) }

        let command = "mkdir -p '\(file.directoryURL.path)' && cp '\(temporary.path)' '\(file.fileURL.path)' "
            + "&& chown root:wheel '\(file.fileURL.path)' && chmod 644 '\(file.fileURL.path)'"
        try runAsAdmin(command)
    }

    /// 还原：有备份就恢复备份，没有就把 override 删掉（回到系统原生模式表）。
    func restore(identity: DisplayIdentity) throws {
        let directory = OverrideFile.overridesRoot
            .appendingPathComponent("DisplayVendorID-\(String(format: "%x", identity.vendorID))")
        let target = directory.appendingPathComponent("DisplayProductID-\(String(format: "%x", identity.productID))")

        if let latest = backups(for: identity).first {
            let command = "mkdir -p '\(directory.path)' && cp '\(latest.path)' '\(target.path)' "
                + "&& chown root:wheel '\(target.path)' && chmod 644 '\(target.path)'"
            try runAsAdmin(command)
        } else {
            try runAsAdmin("rm -f '\(target.path)'")
        }
    }

    // MARK: - 提权执行

    /// 用 osascript 的 `with administrator privileges` 弹一次系统密码框执行命令。
    func runAsAdmin(_ shellCommand: String) throws {
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if message.contains("-128") || message.lowercased().contains("cancel") {
                throw OverrideInstallerError.adminCancelled
            }
            throw OverrideInstallerError.commandFailed(message.isEmpty ? "命令执行失败" : message)
        }
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
