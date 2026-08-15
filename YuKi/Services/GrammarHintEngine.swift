import Foundation
import NaturalLanguage

/// Dictionary-free grammar hints produced on-device. Currently covers one
/// high-value English pattern: a past-time marker combined with a base-form
/// verb ("I go to school yesterday."). The engine only flags the suspicion;
/// the LLM supplies the actual past form, so no irregular-verb table or
/// bundled dictionary is needed. `NSLinguisticTagger` provides POS and lemma
/// on-device for all supported languages.
enum GrammarHintEngine {
    static func hints(for text: String, language: String) -> [String] {
        guard language == "English" else { return [] }
        let lowered = text.lowercased()
        let pastMarkers = ["yesterday", "last ", " ago", "this morning", "earlier"]
        guard pastMarkers.contains(where: { lowered.contains($0) }) else { return [] }

        var baseFormVerbs: [String] = []
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma])
        tagger.string = text
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: options) { tag, range in
            guard tag == .verb else { return true }
            let word = String(text[range])
            let (lemmaTag, _) = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma)
            // A verb whose lemma equals its surface form is in base form, which
            // conflicts with the past-time marker found above.
            if let lemma = lemmaTag?.rawValue,
               lemma.lowercased() == word.lowercased(),
               word.count > 1 {
                baseFormVerbs.append(word)
            }
            return true
        }
        guard let verb = baseFormVerbs.first else { return [] }
        return ["句中有过去时间标记，但动词“\(verb)”仍是原形，可能需要过去式"]
    }
}
