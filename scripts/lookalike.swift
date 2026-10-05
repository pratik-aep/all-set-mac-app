// Which pictures look like the same wallpaper, even recoloured.
//
//     lookalike list.txt [--threshold 0.5]
//
// list.txt holds one "id<TAB>path" per line. For each picture Apple's Vision
// framework makes a feature print (what the picture shows, largely
// independent of its colours); every pair closer than the threshold is
// printed as one JSON line {"a", "b", "distance"}. Nothing is decided here:
// the importer and a person review the pairs.

import Foundation
import Vision

let arguments = Array(CommandLine.arguments.dropFirst())
guard let listPath = arguments.first, let list = try? String(contentsOfFile: listPath, encoding: .utf8) else {
    print(#"{"error": "usage: lookalike list.txt [--threshold 0.5]"}"#)
    exit(2)
}
let threshold: Float = {
    if let i = arguments.firstIndex(of: "--threshold"), i + 1 < arguments.count { return Float(arguments[i + 1]) ?? 0.5 }
    return 0.5
}()

var ids: [String] = []
var prints: [VNFeaturePrintObservation] = []
for line in list.split(separator: "\n") {
    let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { continue }
    let request = VNGenerateImageFeaturePrintRequest()
    let handler = VNImageRequestHandler(url: URL(fileURLWithPath: parts[1]), options: [:])
    guard (try? handler.perform([request])) != nil, let result = request.results?.first else { continue }
    ids.append(parts[0])
    prints.append(result)
}
FileHandle.standardError.write("feature prints: \(prints.count)\n".data(using: .utf8)!)
for i in 0..<prints.count {
    for j in (i + 1)..<prints.count {
        var distance: Float = 0
        guard (try? prints[i].computeDistance(&distance, to: prints[j])) != nil else { continue }
        if distance <= threshold {
            print(#"{"a": "\#(ids[i])", "b": "\#(ids[j])", "distance": \#(distance)}"#)
        }
    }
}
