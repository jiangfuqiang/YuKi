import Foundation
import SwiftData

@MainActor
final class CreateSceneViewModel: ObservableObject {
    @Published var step = 1
    @Published var name = ""
    @Published var language: String
    @Published var selectedBuddyID: UUID?
    @Published var relationship: BuddyRelationship = .friend
    @Published var buddyName = ""
    @Published var personality = "友好、耐心"
    @Published var correctionLevel: CorrectionLevel = .moderate
    @Published var description = ""
    @Published var flow = ""
    @Published var userRole = ""
    @Published var aiRole = ""
    @Published var level: SceneLevel?
    @Published var goals = ""
    @Published var selectedSeriesID: UUID?

    let languages = ["English", "日本語", "한국어", "中文", "Français", "Español"]

    init() {
        let stored = UserDefaults.standard.string(forKey: "defaultSceneLanguage")
        let supportedLanguages = ["English", "日本語", "한국어", "中文", "Français", "Español"]
        if let stored, supportedLanguages.contains(stored) {
            language = stored
        } else {
            language = "日本語"
        }
    }

    var canContinue: Bool {
        switch step {
        case 1: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 2: selectedBuddyID != nil || !buddyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func create(in context: ModelContext) {
        var buddyID = selectedBuddyID
        if buddyID == nil {
            let buddy = Buddy(name: buddyName, language: language, relationship: relationship, personality: personality, correctionLevel: correctionLevel)
            context.insert(buddy)
            buddyID = buddy.id
        }
        guard let buddyID else { return }
        func nonempty(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let scene = Scene(name: name, coverImage: coverIcon, language: language, description: description,
                          flow: nonempty(flow), userRole: nonempty(userRole), aiRole: nonempty(aiRole),
                          level: level?.rawValue, goals: nonempty(goals),
                          buddyId: buddyID, seriesId: selectedSeriesID)
        context.insert(scene)
        if let selectedSeriesID,
           let series = try? context.fetch(FetchDescriptor<Series>()).first(where: { $0.id == selectedSeriesID }) {
            series.sceneIds.append(scene.id)
        }
        try? context.save()
    }

    private var coverIcon: String {
        if name.contains("旅行") || name.contains("酒店") || name.contains("机场") { return "suitcase.fill" }
        if name.contains("工作") || name.contains("面试") { return "briefcase.fill" }
        if name.contains("留学") || name.contains("学校") { return "graduationcap.fill" }
        return "bubble.left.and.bubble.right.fill"
    }
}
