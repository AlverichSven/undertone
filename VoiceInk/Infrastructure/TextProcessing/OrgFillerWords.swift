import Foundation

/// Filler sounds and stuttered words of the organisation build (Undertone).
///
/// Two parts, one switch in the settings (`orgFillerWordsEnabled`, default on):
/// - Filler sounds: handed to VoiceInk's own filler cleanup (`TranscriptionOutputFilter`), which
///   already removes surrounding commas and repairs spacing and capitalisation. German sounds
///   („äh“, „ähm“, „öh“, „öhm“, „hm“, „hmm“, „mhm“) are added. VoiceInk's English default list
///   contains „um“, a real German word („um 10 Uhr“), so „um“ is only removed when English is
///   selected.
/// - Repeated words: „das das“ → „das“ (case-insensitive, letters only, so numbers never count).
///   Deliberate doubles stay: „so so“, „ja ja“, „sehr sehr“ and similar, „Sie sie“ (formal „Sie“
///   followed by the pronoun) and, after a comma, relative clauses such as „…, die die Zeitung“.
///
/// Switched off: no filler sound and no repeated word is removed (also not VoiceInk's list).
enum OrgFillerWords {
    static let enabledKey = "orgFillerWordsEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static let germanFillers = ["äh", "ähm", "öh", "öhm", "hm", "hmm", "mhm"]
    static let englishFillers = ["uh", "um", "uhm", "umm", "er", "erm"]

    /// Words in VoiceInk's English filler list that are real German words.
    static let germanWordsInEnglishList: Set<String> = ["um"]

    static func isEnglish(_ language: String?) -> Bool {
        guard let language else { return false }
        return language.lowercased().hasPrefix("en")
    }

    /// Filler list for `TranscriptionOutputFilter`. Normal VoiceInk build: unchanged.
    static func fillers(base: [String], language: String?) -> [String] {
        guard OrgEdition.isEnabled else { return base }
        guard isEnabled else { return [] }
        return effectiveFillers(base: base, language: language)
    }

    /// Pure part of `fillers(base:language:)` (also used by the test harness).
    static func effectiveFillers(base: [String], language: String?) -> [String] {
        if isEnglish(language) {
            // English: VoiceInk's list plus a few more English sounds. „er“ only here.
            return Array(Set(base.map { $0.lowercased() } + englishFillers))
        }
        // German or automatic: German sounds, VoiceInk's list without real German words.
        let filtered = base.filter { !germanWordsInEnglishList.contains($0.lowercased()) }
        return Array(Set(filtered.map { $0.lowercased() } + germanFillers))
    }

    /// Stutter around a filler: „das, äh, das Release“ → „das Release“. Runs before VoiceInk's
    /// filler cleanup, which would otherwise leave „das, das“ (a comma it cannot judge).
    static func collapseStutterAroundFillers(_ text: String, language: String?) -> String {
        guard OrgEdition.isEnabled, isEnabled else { return text }
        return collapseStutter(text, language: language)
    }

    static func collapseStutter(_ text: String, language: String?) -> String {
        let fillers = (isEnglish(language) ? englishFillers : germanFillers)
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        let pattern = "(?<![\\p{L}\\p{N}])(\\p{L}+)[ \\t]*,?[ \\t]+(?:" + fillers
            + ")[ \\t]*[,.]?[ \\t]+\\1(?![\\p{L}\\p{N}])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        return regex.stringByReplacingMatches(
            in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "$1")
    }

    // MARK: - Repeated words

    /// Doubles that are usually meant: „so so“, „ja ja“, „sehr sehr gut“.
    private static let deliberateDoublesGerman: Set<String> = [
        "so", "ja", "nein", "na", "nee", "naja", "ha", "haha", "hey", "bla", "tja", "aha", "oh", "ach",
        "sehr", "ganz", "viel", "viele", "immer", "lange", "schnell", "bitte", "danke", "tschüss", "gut",
        // „Können Sie sie anrufen?“: formal „Sie“ and the pronoun „sie“.
        "sie",
    ]
    private static let deliberateDoublesEnglish: Set<String> = [
        "so", "yes", "no", "ha", "haha", "hey", "bye", "very", "really", "bla", "blah", "oh",
        // „I know that that is true“, „She had had enough“, „What it is is …“.
        "that", "had", "is",
    ]
    /// Articles that may legitimately repeat after a comma: „Die Frau, die die Zeitung liest“.
    private static let relativePronouns: Set<String> = ["der", "die", "das", "dem", "den", "des", "dessen", "deren"]

    static func removeRepeatedWords(_ text: String, language: String?) -> String {
        guard OrgEdition.isEnabled, isEnabled else { return text }
        return collapseRepeatedWords(text, language: language)
    }

    /// Pure part of `removeRepeatedWords` (also used by the test harness).
    static func collapseRepeatedWords(_ text: String, language: String?) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\p{L}+(?:['’]\\p{L}+)?") else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard matches.count > 1 else { return text }
        let deliberate = isEnglish(language) ? deliberateDoublesEnglish : deliberateDoublesGerman

        var removals: [NSRange] = []
        var index = 1
        while index < matches.count {
            let previous = matches[index - 1].range
            let current = matches[index].range
            let previousWord = ns.substring(with: previous).lowercased()
            let currentWord = ns.substring(with: current).lowercased()
            let gapRange = NSRange(location: NSMaxRange(previous), length: current.location - NSMaxRange(previous))
            let gap = ns.substring(with: gapRange)
            // Only plain spaces between the words (no comma, no line break, no hyphen).
            let isPlainGap = !gap.isEmpty && gap.allSatisfy { $0 == " " || $0 == "\t" }
            // Glued to digits or other word characters (e.g. „das2“) → not a plain word.
            let followedByWordChar: Bool = {
                let end = NSMaxRange(current)
                guard end < ns.length else { return false }
                let next = ns.substring(with: NSRange(location: end, length: 1))
                return next.range(of: "[\\p{L}\\p{N}_@/]", options: .regularExpression) != nil
            }()
            let precededByComma: Bool = {
                var position = previous.location - 1
                while position >= 0 {
                    let character = ns.substring(with: NSRange(location: position, length: 1))
                    if character == " " || character == "\t" { position -= 1; continue }
                    return character == ","
                }
                return false
            }()

            if previousWord == currentWord, isPlainGap, !followedByWordChar,
                !deliberate.contains(currentWord),
                !(precededByComma && relativePronouns.contains(currentWord))
            {
                // Drop the gap and the second word; the first keeps its spelling.
                removals.append(NSRange(location: gapRange.location, length: NSMaxRange(current) - gapRange.location))
                // Compare the next word with the kept one (handles „das das das“).
                var next = index + 1
                while next < matches.count {
                    let candidate = matches[next].range
                    let lastRemovedEnd = NSMaxRange(removals[removals.count - 1])
                    let nextGap = ns.substring(with: NSRange(location: lastRemovedEnd, length: candidate.location - lastRemovedEnd))
                    guard ns.substring(with: candidate).lowercased() == previousWord,
                        !nextGap.isEmpty, nextGap.allSatisfy({ $0 == " " || $0 == "\t" })
                    else { break }
                    removals.append(NSRange(location: lastRemovedEnd, length: NSMaxRange(candidate) - lastRemovedEnd))
                    next += 1
                }
                index = next + 1
                continue
            }
            index += 1
        }

        guard !removals.isEmpty else { return text }
        let output = NSMutableString(string: text)
        for range in removals.reversed() {
            output.replaceCharacters(in: range, with: "")
        }
        return output as String
    }
}
