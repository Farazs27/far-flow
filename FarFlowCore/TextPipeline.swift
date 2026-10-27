import Foundation
import NaturalLanguage

public enum TextPipeline {
    public static func detectedLanguage(_ text: String, preferred: DictationLanguage) -> String {
        if preferred != .auto { return preferred.code }
        let recognizer = NLLanguageRecognizer(); recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue ?? "und"
    }
    public static func normalizedTrigger(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    public static func snippet(_ text: String, snippets: [VoiceSnippet]) -> String? {
        snippets.first { !$0.trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && normalizedTrigger($0.trigger) == normalizedTrigger(text) }?.expansion
    }
    public static func applyDictionary(_ text: String, entries: [DictionaryEntry], language: String) -> String {
        let rules=entries.filter { ($0.language == .auto || $0.language.code == language) && !$0.word.isEmpty }.map { ($0.alias.isEmpty ? $0.word:$0.alias,$0.word) }.filter { !$0.0.isEmpty }.sorted { $0.0.count > $1.0.count }
        guard !rules.isEmpty else { return text }
        // Match the original once: a replacement must never become another alias's input.
        let alternatives=rules.map { NSRegularExpression.escapedPattern(for:$0.0) }.joined(separator:"|")
        let pattern="(?<![\\p{L}\\p{N}_])(?:"+alternatives+")(?![\\p{L}\\p{N}_])"
        guard let regex=try? NSRegularExpression(pattern:pattern,options:.caseInsensitive) else { return text }
        var result=text
        for match in regex.matches(in:text,range:NSRange(text.startIndex...,in:text)).reversed() {
            guard let originalRange=Range(match.range,in:text), let replacement=rules.first(where: { $0.0.localizedCaseInsensitiveCompare(String(text[originalRange])) == .orderedSame }), let range=Range(match.range,in:result) else { continue }
            result.replaceSubrange(range,with:replacement.1)
        }
        return result
    }
    public static func lightRules(_ text: String, language: String) -> String {
        var value = resolveNumericCorrections(text).trimmingCharacters(in: .whitespacesAndNewlines)
        let filler = language == "nl" ? "(?i)(?<![\\p{L}])(?:ehm+|uhm+|eh+)(?![\\p{L}])[, ]*" : "(?i)(?<![\\p{L}])(?:umm+|um|uh+|erm)(?![\\p{L}])[, ]*"
        value = value.replacingOccurrences(of: filler, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: " +([,.;!?])", with: "$1", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public static func resolveNumericCorrections(_ text: String) -> String {
        let number="(?:[0-9]+(?:[.,:][0-9]+)?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|een|één|twee|drie|vier|vijf|zes|zeven|acht|negen|tien|elf|twaalf|dertien|veertien|vijftien|zestien|zeventien|achttien|negentien|twintig)"
        let pattern="(?i)\\b("+number+")(\\s*(?:uur|o'clock|euros?|dollars?))?(\\s+afspreken)?[\\s,.]*(?:actually|nee|sorry|no|ik bedoel)[\\s,.:]*(?:(?:at|om)\\s+)?("+number+")(\\s*(?:uur|o'clock|euros?|dollars?))?\\b"
        guard let regex=try? NSRegularExpression(pattern:pattern) else { return text }
        var output=text
        for match in regex.matches(in:text,range:NSRange(text.startIndex...,in:text)).reversed() {
            func part(_ i: Int)->String { Range(match.range(at:i),in:text).map{String(text[$0])} ?? "" }
            let unit=part(5).isEmpty ? part(2):part(5)
            if let range=Range(match.range,in:output) {output.replaceSubrange(range,with:part(4)+unit+part(3))}
        }
        return output
    }
    public static func protectedSpans(_ text: String, dictionary: [DictionaryEntry]) -> [String] {
        let patterns = [#"https?://[^\s]+"#, #"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}"#, #"\b\d+(?:[.,:]\d+)*\b"#, #"\b[a-z]+(?:_[A-Za-z0-9]+)+\b"#, #"\b[a-z]+[A-Z][A-Za-z0-9]*\b"#]
        var result: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            result += regex.matches(in: text, range: NSRange(text.startIndex...,in:text)).compactMap { Range($0.range,in:text).map { String(text[$0]) } }
        }
        result += dictionary.map(\.word).filter { !$0.isEmpty && text.localizedCaseInsensitiveContains($0) }
        return result
    }
    public static func isSafeEdit(original: String, candidate: String, dictionary: [DictionaryEntry] = []) -> Bool {
        guard !candidate.isEmpty, candidate.count <= max(original.count * 2, original.count + 100) else { return false }
        let originalLower = original.lowercased().replacingOccurrences(of:"n't",with:" not"), candidateLower = candidate.lowercased().replacingOccurrences(of:"n't",with:" not")
        for marker in ["not", "never", "niet", "geen", "nooit"] {
            let words = originalLower.components(separatedBy: CharacterSet.letters.inverted)
            if words.contains(marker) != candidateLower.components(separatedBy: CharacterSet.letters.inverted).contains(marker) { return false }
        }
        for span in protectedSpans(original, dictionary: dictionary) {
            let pattern="(?<![\\p{L}\\p{N}_])"+NSRegularExpression.escapedPattern(for:span)+"(?![\\p{L}\\p{N}_])"
            if candidate.range(of:pattern,options:[.regularExpression,.caseInsensitive]) == nil { return false }
        }
        if original.count > 45, candidate.count > 30 {
            let before = detectedLanguage(original, preferred: .auto), after = detectedLanguage(candidate, preferred: .auto)
            if ["en","nl"].contains(before), ["en","nl"].contains(after), before != after { return false }
        }
        return true
    }
    public static func wordErrorRate(reference: String, hypothesis: String) -> Double {
        func tokens(_ s: String) -> [String] { s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty } }
        let a=tokens(reference), b=tokens(hypothesis)
        guard !a.isEmpty else { return b.isEmpty ? 0 : 1 }
        var previous=Array(0...b.count)
        for (i,x) in a.enumerated() {
            var current=[i+1]+Array(repeating:0,count:b.count)
            for (j,y) in b.enumerated() { current[j+1]=min(current[j]+1, previous[j+1]+1, previous[j]+(x == y ? 0:1)) }
            previous=current
        }
        return Double(previous[b.count])/Double(a.count)
    }
}
