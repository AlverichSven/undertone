import Foundation

/// Spoken formatting commands and smileys of the organisation build (Undertone).
///
/// Runs on the final transcript before it is pasted. Two independent switches in the settings:
/// - Commands: „neue Zeile“, „neuer Absatz“, „Doppelpunkt“, „Semikolon“, „Ausrufezeichen“,
///   „Fragezeichen“, „Anführungszeichen (auf/zu)“, „Klammer auf/zu“, „Bindestrich“, „Schrägstrich“.
/// - Smileys: „Smiley <Name>“ (also „Smilie“, „Emoji“), short names first (e.g. „Smiley LOL“,
///   „Smiley Daumen hoch“), then the full list from `smileys.json` in the app bundle.
/// Plain „Punkt“ and „Komma“ are deliberately not commands: the model punctuates itself and
/// both words occur in normal speech.
enum OrgVoiceCommands {
    static let commandsEnabledKey = "orgVoiceCommandsEnabled"
    static let smileysEnabledKey = "orgSmileysEnabled"

    static func apply(_ text: String) -> String {
        guard OrgEdition.isEnabled else { return text }
        var result = text
        let defaults = UserDefaults.standard
        if defaults.object(forKey: smileysEnabledKey) as? Bool ?? true {
            result = replaceSmileys(in: result)
        }
        if defaults.object(forKey: commandsEnabledKey) as? Bool ?? true {
            result = applyCommands(to: result)
        }
        return result
    }

    // MARK: - Commands

    private enum Kind {
        case closing      // attaches to the previous word: "Text!"
        case opening      // attaches to the next word: "(Text", „Text
        case glue         // no spaces on either side: "E-Mail", "und/oder"
        case lineBreak    // "\n" or "\n\n"
    }

    private struct Command {
        let pattern: String
        let output: String
        let kind: Kind
    }

    // Longer phrases first so "Anführungszeichen auf" wins over "Anführungszeichen".
    private static let commands: [Command] = [
        Command(pattern: "neuer absatz", output: "\n\n", kind: .lineBreak),
        Command(pattern: "neue zeile", output: "\n", kind: .lineBreak),
        Command(pattern: "anführungszeichen (?:auf|unten)", output: "„", kind: .opening),
        Command(pattern: "anführungszeichen (?:zu|oben)", output: "“", kind: .closing),
        Command(pattern: "klammer auf", output: "(", kind: .opening),
        Command(pattern: "klammer zu", output: ")", kind: .closing),
        Command(pattern: "doppelpunkt", output: ":", kind: .closing),
        Command(pattern: "semikolon", output: ";", kind: .closing),
        Command(pattern: "ausrufezeichen", output: "!", kind: .closing),
        Command(pattern: "fragezeichen", output: "?", kind: .closing),
        Command(pattern: "bindestrich", output: "-", kind: .glue),
        Command(pattern: "schrägstrich", output: "/", kind: .glue),
    ]

    /// Punctuation the model tends to put around a spoken command word.
    private static let modelPunctuation = "[.,;:!?]*"

    private static func applyCommands(to text: String) -> String {
        var result = text
        for command in commands {
            result = replace(command, in: result)
        }
        result = replaceToggleQuotes(in: result)
        return tidy(result)
    }

    private static func replace(_ command: Command, in text: String) -> String {
        let core = "(?<![\\p{L}\\p{N}])" + command.pattern + "(?![\\p{L}\\p{N}])"
        let pattern: String
        let template: String
        switch command.kind {
        case .closing:
            // Drop model punctuation and spaces before, model punctuation right after.
            pattern = "[\\s,.]*" + core + modelPunctuation
            template = command.output
        case .opening:
            pattern = core + modelPunctuation + "\\s*"
            template = command.output
        case .glue:
            pattern = "\\s*" + core + modelPunctuation + "\\s*"
            template = command.output
        case .lineBreak:
            // Keep the sentence end before, drop a comma before and punctuation after.
            pattern = "[ \\t]*,?[ \\t]*" + core + modelPunctuation + "[ \\t]*"
            template = command.output
        }
        return regexReplace(pattern, in: text, with: template)
    }

    /// Plain „Anführungszeichen“: alternates between opening and closing quote.
    private static func replaceToggleQuotes(in text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "[\\s,]*(?<![\\p{L}\\p{N}])anführungszeichen(?![\\p{L}\\p{N}])" + modelPunctuation + "\\s*",
            options: [.caseInsensitive]
        ) else { return text }
        var output = ""
        var cursor = text.startIndex
        var open = true
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            output += text[cursor..<range.lowerBound]
            output += open ? " „" : "“ "
            open.toggle()
            cursor = range.upperBound
        }
        output += text[cursor...]
        return output
    }

    /// Spacing and capitalisation after the replacements.
    private static func tidy(_ text: String) -> String {
        var result = text
        // One space after closing marks when text follows directly.
        result = regexReplace("([!?:;)“])(?=[\\p{L}\\p{N}„(])", in: result, with: "$1 ")
        // No space after an opening mark.
        result = regexReplace("([„(])\\s+", in: result, with: "$1")
        // Collapse runs of spaces, trim spaces around line breaks.
        result = regexReplace("[ \\t]{2,}", in: result, with: " ")
        result = regexReplace("[ \\t]*\\n[ \\t]*", in: result, with: "\n")
        // Capital letter at the start of a new line and after ! or ?.
        result = capitalise(after: "(?:^|\\n|[!?]\\s)", in: result)
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func capitalise(after prefix: String, in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: prefix + "(\\p{Ll})", options: [.anchorsMatchLines])
        else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range(at: 1), in: result) else { continue }
            result.replaceSubrange(range, with: result[range].uppercased())
        }
        return result
    }

    // MARK: - Smileys

    private struct SmileyTable {
        let names: [String: String]   // normalised name -> emoji, short names win
        let maxWords: Int
    }

    private static let smileyTable: SmileyTable = {
        var names: [String: String] = [:]
        if let url = Bundle.main.url(forResource: "smileys", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]]
        {
            for (name, emoji) in json["alle"] ?? [:] { names[normalise(name)] = emoji }
            for (name, emoji) in json["kurz"] ?? [:] { names[normalise(name)] = emoji }
        }
        let maxWords = names.keys.map { $0.split(separator: " ").count }.max() ?? 1
        return SmileyTable(names: names, maxWords: min(maxWords, 12))
    }()

    private static func normalise(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "[^\\p{L}\\p{N} ]", with: " ", options: .regularExpression)
            .split(separator: " ")
            .joined(separator: " ")
    }

    private static func replaceSmileys(in text: String) -> String {
        let table = smileyTable
        guard !table.names.isEmpty,
            let trigger = try? NSRegularExpression(
                pattern: "[ \\t]*,?[ \\t]*(?<![\\p{L}\\p{N}])(?:smiley|smilie|smily|smileys|emoji)(?![\\p{L}\\p{N}])[,.:]?",
                options: [.caseInsensitive]
            )
        else { return text }

        var result = text
        // Work from the end so earlier ranges stay valid.
        for match in trigger.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let triggerRange = Range(match.range, in: result) else { continue }
            let rest = result[triggerRange.upperBound...]
            guard let found = longestSmiley(in: rest, table: table) else { continue }
            var replaceEnd = found.end
            // Swallow one punctuation mark the model put right after the smiley name.
            if replaceEnd < result.endIndex, ".,".contains(result[replaceEnd]) {
                replaceEnd = result.index(after: replaceEnd)
            }
            let needsSpaceBefore = triggerRange.lowerBound > result.startIndex
                && !result[result.index(before: triggerRange.lowerBound)].isWhitespace
            result.replaceSubrange(
                triggerRange.lowerBound..<replaceEnd,
                with: (needsSpaceBefore || triggerRange.lowerBound > result.startIndex ? " " : "") + found.emoji
            )
        }
        return regexReplace("[ \\t]{2,}", in: result, with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// Longest run of up to `maxWords` words after the trigger that names a smiley.
    private static func longestSmiley(in rest: Substring, table: SmileyTable) -> (emoji: String, end: String.Index)? {
        guard let wordRegex = try? NSRegularExpression(pattern: "[\\p{L}\\p{N}]+") else { return nil }
        let string = String(rest)
        let words = wordRegex.matches(in: string, range: NSRange(string.startIndex..., in: string)).prefix(table.maxWords)
        guard !words.isEmpty else { return nil }
        // Only words separated by spaces (or a hyphen) belong to the name; stop at sentence ends.
        var candidates: [NSTextCheckingResult] = []
        var previousEnd = string.startIndex
        for word in words {
            guard let range = Range(word.range, in: string) else { break }
            let gap = string[previousEnd..<range.lowerBound]
            if !candidates.isEmpty, gap.contains(where: { ".!?;:\n".contains($0) }) { break }
            candidates.append(word)
            previousEnd = range.upperBound
        }
        for count in stride(from: candidates.count, through: 1, by: -1) {
            let slice = candidates.prefix(count)
            let name = slice.compactMap { Range($0.range, in: string).map { String(string[$0]) } }
                .joined(separator: " ")
            if let emoji = table.names[normalise(name)],
                let lastRange = Range(slice.last!.range, in: string)
            {
                let offset = string.distance(from: string.startIndex, to: lastRange.upperBound)
                return (emoji, rest.index(rest.startIndex, offsetBy: offset))
            }
        }
        return nil
    }

    // MARK: - Helpers

    private static func regexReplace(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        return regex.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}
