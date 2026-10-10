import Foundation

enum LibraryAttachments {
    static func copy(_ source: URL, into root: URL) throws -> String {
        let directory = root.appendingPathComponent("attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suffix = source.pathExtension.filter { $0.isLetter || $0.isNumber }
        let name = UUID().uuidString + (suffix.isEmpty ? "" : "." + suffix)
        try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(name))
        return "attachments/" + name
    }
    static func snapshot(at root: URL) -> [String: Data] {
        let directory = root.appendingPathComponent("attachments", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
        var result: [String: Data] = [:]
        for file in files where (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            if let data = try? Data(contentsOf: file) { result[file.lastPathComponent] = data }
        }
        return result
    }
    static func restore(_ files: [String: Data], at root: URL) throws {
        let directory = root.appendingPathComponent("attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, data) in files {
            guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\") else { continue }
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        }
    }
}
