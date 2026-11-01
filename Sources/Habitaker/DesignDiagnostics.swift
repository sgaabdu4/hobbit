import CoreText
import UIKit

enum DesignDiagnostics {
    static func record() {
        #if DEBUG
        let fonts = ["Manrope", "DM Sans"].map { name -> [String: Any] in
            let font = CTFontCreateWithName(name as CFString, 20, nil)
            return ["requested": name, "family": CTFontCopyFamilyName(font) as String,
                    "postScript": CTFontCopyPostScriptName(font) as String,
                    "availableFaces": UIFont.fontNames(forFamilyName: name)]
        }
        let result: [String: Any] = ["fonts": fonts, "updatedAt": ISO8601DateFormatter().string(from: Date()), "theme": "dark_olive"]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL.documentsDirectory.appendingPathComponent("design-check.json"), options: .atomic)
        }
        #endif
    }
}
