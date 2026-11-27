import Foundation
import SwiftData

@MainActor
final class CustomVocabularyService {
    static let shared = CustomVocabularyService()

    private init() {}

    func loadSavedVocabulary(from context: ModelContext) -> RecordingVocabulary {
        let descriptor = FetchDescriptor<VocabularyWord>(sortBy: [SortDescriptor(\VocabularyWord.word)])
        let words = (try? context.fetch(descriptor)) ?? []
        // Undertone: company words (OrgCompanyDictionary) after the user's own words, so the
        // user's spelling wins collisions. Empty in the normal VoiceInk build.
        return RecordingVocabulary(savedTerms: words.map(\.word) + OrgCompanyDictionary.shared.vocabularyWords)
    }
}
