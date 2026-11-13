import Foundation

struct SubtitleCue: Equatable {
    let start: Double
    let end: Double
    let text: String
}
struct SubtitleTrack: Decodable {
    let language: String
    let requestedLanguage: String
    let text: String
}
enum SubtitleParser {
    static func parse(_ input: String) -> [SubtitleCue] {
        input.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n\n").compactMap { block in
                let lines = block.components(separatedBy: "\n")
                guard let index = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
                let times = lines[index].components(separatedBy: "-->")
                guard times.count == 2, let start = seconds(times[0]), let end = seconds(times[1]), end > start else { return nil }
                let text = lines.dropFirst(index + 1).joined(separator: "\n")
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&lt;", with: "<")
                    .replacingOccurrences(of: "&gt;", with: ">")
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .replacingOccurrences(of: "&#39;", with: "'")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : SubtitleCue(start: start, end: end, text: text)
            }.sorted { $0.start < $1.start }
    }
    private static func seconds(_ value: String) -> Double? {
        let fields = value.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).first?
            .replacingOccurrences(of: ",", with: ".").components(separatedBy: ":") ?? []
        guard fields.count == 3, let hours = Double(fields[0]), let minutes = Double(fields[1]),
              let seconds = Double(fields[2]), hours >= 0, minutes >= 0, minutes < 60, seconds >= 0, seconds < 60 else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }
}
