import Foundation

/// Finds a folder under `submodules` from this file's path, the working directory or the test bundle (under Bazel the
/// bundle sits in the exec root, next to the `submodules` link). Shared by the source-scan guards (build 23).
enum HarnessgramSourceScan {
    static func directory(_ relative: String, anchor: AnyClass) -> URL? {
        let starts = [
            URL(fileURLWithPath: #filePath).deletingLastPathComponent(),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            Bundle(for: anchor).bundleURL
        ]
        for start in starts {
            var directory = start.standardizedFileURL
            for _ in 0 ..< 64 {
                for candidate in [directory.appendingPathComponent(relative), directory.appendingPathComponent("submodules/" + relative)] {
                    var isDirectory: ObjCBool = false
                    if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
                        return candidate
                    }
                }
                if directory.path == "/" {
                    break
                }
                directory = directory.deletingLastPathComponent().standardizedFileURL
            }
        }
        return nil
    }

    /// Every .swift file under `relative`, with its text.
    static func swiftFiles(_ relative: String, anchor: AnyClass) -> [(name: String, text: String)] {
        guard let root = HarnessgramSourceScan.directory(relative, anchor: anchor), let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        var files: [(String, String)] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                files.append((url.lastPathComponent, text))
            }
        }
        return files.sorted { $0.0 < $1.0 }
    }
}
