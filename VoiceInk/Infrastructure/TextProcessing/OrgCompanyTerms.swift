import Foundation

/// File format of the company dictionary (organisation build, `Undertone-Woerterbuch.json`):
///
/// ```json
/// {
///   "beschreibung": "Beispiel",
///   "version": "2026-01-15",
///   "woerter": ["Beispielwort", "Produktname"],
///   "jiraSchluessel": ["ABCDEF", "XYZW"],
///   "ersetzungen": [{ "von": "A und B", "nach": "A&B" }]
/// }
/// ```
/// All fields are optional; unknown fields are ignored.
struct OrgCompanyDictionaryContent: Codable, Equatable {
    struct Replacement: Codable, Equatable {
        let von: String
        let nach: String
    }

    var beschreibung: String?
    var version: String?
    var woerter: [String]
    var jiraSchluessel: [String]
    var ersetzungen: [Replacement]

    init(
        beschreibung: String? = nil, version: String? = nil, woerter: [String] = [],
        jiraSchluessel: [String] = [], ersetzungen: [Replacement] = []
    ) {
        self.beschreibung = beschreibung
        self.version = version
        self.woerter = woerter
        self.jiraSchluessel = jiraSchluessel
        self.ersetzungen = ersetzungen
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        beschreibung = try? container.decodeIfPresent(String.self, forKey: .beschreibung)
        version = try? container.decodeIfPresent(String.self, forKey: .version)
        woerter = (try? container.decodeIfPresent([String].self, forKey: .woerter)) ?? []
        jiraSchluessel = (try? container.decodeIfPresent([String].self, forKey: .jiraSchluessel)) ?? []
        ersetzungen = (try? container.decodeIfPresent([Replacement].self, forKey: .ersetzungen)) ?? []
    }

    static func decode(_ data: Data) throws -> OrgCompanyDictionaryContent {
        let content = try JSONDecoder().decode(OrgCompanyDictionaryContent.self, from: data)
        guard !content.woerter.isEmpty || !content.jiraSchluessel.isEmpty || !content.ersetzungen.isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return content
    }

    var cleanedWords: [String] {
        woerter.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

/// Pure text functions of the company dictionary (no app state; used by the pipeline and the tests).
struct OrgCompanyTerms {
    /// Minimum key length: shorter keys would hit normal abbreviations.
    static let minimumKeyLength = 4
    /// Most word pieces a spelled key may consist of („c p c o n p n c“ = 8).
    static let maximumPieces = 12

    private let keys: Set<String>          // lowercased
    private let keyPrefixes: Set<String>   // lowercased prefixes of all keys
    private let replacements: [(regex: NSRegularExpression, template: String)]

    init(keys: [String], replacements: [OrgCompanyDictionaryContent.Replacement]) {
        var keySet = Set<String>()
        var prefixes = Set<String>()
        for key in keys {
            let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleaned.count >= Self.minimumKeyLength,
                cleaned.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) })
            else { continue }
            let lower = cleaned.lowercased()
            keySet.insert(lower)
            var prefix = ""
            for character in lower {
                prefix.append(character)
                prefixes.insert(prefix)
            }
        }
        self.keys = keySet
        self.keyPrefixes = prefixes

        let wordChar = "[\\p{L}\\p{M}\\p{N}]"
        self.replacements = replacements
            .map { (von: $0.von.trimmingCharacters(in: .whitespacesAndNewlines), nach: $0.nach) }
            .filter { !$0.von.isEmpty }
            // Longest first, like VoiceInk's own replacements („Muster AB“ before „AB“).
            .sorted { $0.von.count != $1.von.count ? $0.von.count > $1.von.count : $0.von < $1.von }
            .compactMap { rule in
                let words = rule.von.split(whereSeparator: { $0.isWhitespace })
                    .map { NSRegularExpression.escapedPattern(for: String($0)) }
                let pattern = "(?<!\(wordChar))" + words.joined(separator: "[ \\t]+") + "(?!\(wordChar))"
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                    return nil
                }
                return (regex, NSRegularExpression.escapedTemplate(for: rule.nach))
            }
    }

    init(content: OrgCompanyDictionaryContent) {
        self.init(keys: content.jiraSchluessel, replacements: content.ersetzungen)
    }

    var isEmpty: Bool { keys.isEmpty && replacements.isEmpty }

    // MARK: - Project keys

    private static let pieceRegex = try! NSRegularExpression(pattern: "[\\p{L}\\p{N}]+")
    /// Separators the model puts between spelled pieces: spaces, dots, hyphens (at most three).
    private static let gapRegex = try! NSRegularExpression(pattern: "^[ \\t.\\-]{1,3}$")
    /// Ticket number right after a key: „1234“, „-1234“, „ Bindestrich 1234“, „1.234“.
    private static let ticketRegex = try! NSRegularExpression(
        pattern: "^(?:[ \\t]*[-–—][ \\t]*|[ \\t,]*(?:bindestrich|minus|strich)[ \\t,.]*|[ \\t]+)(\\d{1,3}(?:\\.\\d{3})+|\\d+)(?![\\p{L}\\p{N}])",
        options: [.caseInsensitive]
    )

    /// A piece that looks like a normal word (at least 4 letters, contains a lower-case letter).
    private static func isNormalWord(_ piece: String) -> Bool {
        piece.count >= 4 && piece.contains(where: { $0.isLowercase }) && piece.allSatisfy({ $0.isLetter })
    }

    /// Joins spelled or split project keys („AB CD EF“, „a.b.cd-ef“) into the key and
    /// a directly following number into the ticket („ABCDEF-1234“).
    ///
    /// Rules: word pieces separated only by spaces, dots or hyphens whose concatenation equals a
    /// key (case-insensitive); longest match first; keys of at least 4 characters. If one of the
    /// pieces is a normal word („IT Security“, „E-Board“), the pieces are joined only when a
    /// ticket number follows, so ordinary phrases stay untouched.
    func applyProjectKeys(to text: String) -> String {
        guard !keys.isEmpty, !text.isEmpty else { return text }
        let ns = text as NSString
        let pieces = Self.pieceRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map(\.range)
        guard !pieces.isEmpty else { return text }

        var edits: [(range: NSRange, replacement: String)] = []
        var index = 0
        while index < pieces.count {
            var joined = ""
            var best: (end: Int, key: String)?
            var last = index
            while last < pieces.count, last - index < Self.maximumPieces {
                if last > index {
                    let gapStart = NSMaxRange(pieces[last - 1])
                    let gap = ns.substring(with: NSRange(location: gapStart, length: pieces[last].location - gapStart))
                    guard Self.gapRegex.firstMatch(in: gap, range: NSRange(location: 0, length: (gap as NSString).length)) != nil
                    else { break }
                }
                joined += ns.substring(with: pieces[last]).lowercased()
                guard keyPrefixes.contains(joined) else { break }
                if keys.contains(joined) { best = (last, joined) }
                last += 1
            }

            guard let match = best else {
                index += 1
                continue
            }

            let start = pieces[index].location
            var end = NSMaxRange(pieces[match.end])
            var replacement = match.key.uppercased()

            let rest = NSRange(location: end, length: ns.length - end)
            let restString = ns.substring(with: rest)
            var hasTicket = false
            if let ticket = Self.ticketRegex.firstMatch(
                in: restString, range: NSRange(location: 0, length: (restString as NSString).length))
            {
                let number = (restString as NSString).substring(with: ticket.range(at: 1))
                    .replacingOccurrences(of: ".", with: "")
                replacement += "-" + number
                end += ticket.range.length
                hasTicket = true
            }

            let usedPieces = (index...match.end).map { ns.substring(with: pieces[$0]) }
            let containsNormalWord = usedPieces.count > 1 && usedPieces.contains(where: Self.isNormalWord)
            if containsNormalWord && !hasTicket {
                index += 1
                continue
            }

            let range = NSRange(location: start, length: end - start)
            if ns.substring(with: range) != replacement {
                edits.append((range, replacement))
            }
            // Continue after the consumed text.
            index = match.end + 1
            while index < pieces.count, pieces[index].location < end { index += 1 }
        }

        guard !edits.isEmpty else { return text }
        let output = NSMutableString(string: text)
        for edit in edits.reversed() {
            output.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        return output as String
    }

    // MARK: - Replacements

    /// Whole words or word sequences, case-insensitive, longest first.
    func applyReplacements(to text: String) -> String {
        guard !replacements.isEmpty, !text.isEmpty else { return text }
        var result = text
        for rule in replacements {
            let range = NSRange(location: 0, length: (result as NSString).length)
            result = rule.regex.stringByReplacingMatches(in: result, range: range, withTemplate: rule.template)
        }
        return result
    }
}
