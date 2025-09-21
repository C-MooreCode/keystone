import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct KeystoneExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.keystoneArchive] }
    static var writableContentTypes: [UTType] { [.keystoneArchive] }

    var archiveURL: URL?

    init(archiveURL: URL?) {
        self.archiveURL = archiveURL
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupported)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let archiveURL else {
            return FileWrapper(regularFileWithContents: Data())
        }
        return try FileWrapper(url: archiveURL, options: .immediate)
    }

    static var empty: KeystoneExportDocument { KeystoneExportDocument(archiveURL: nil) }
}
