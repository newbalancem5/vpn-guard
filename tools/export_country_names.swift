// Optional maintainer utility: export localized ISO country names from Foundation.
// Output is reviewed before merging into the Flutter ARB catalogs.
import Foundation

var result: [String: [String: String]] = [:]
for language in ["en", "ru"] {
    let locale = Locale(identifier: language)
    var names: [String: String] = [:]
    for region in Locale.Region.isoRegions {
        let code = region.identifier
        guard code.count == 2, code.allSatisfy({ $0.isUppercase && $0.isASCII }),
              let name = locale.localizedString(forRegionCode: code) else { continue }
        names[code] = name
    }
    result[language] = names
}
let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
