import Foundation
import SwiftData

enum SampleData {
    static func seedIfNeeded(in context: ModelContext) {
        let descriptor = FetchDescriptor<Buddy>()
        guard (try? context.fetchCount(descriptor)) == 0 else { return }

        let yuki = Buddy(name: "Yuki", avatar: "person.crop.circle.fill", language: "日本語", relationship: .friend, personality: "友好、耐心", correctionLevel: .moderate)
        let michael = Buddy(name: "Michael", avatar: "person.crop.circle.fill", language: "English", relationship: .teacher, personality: "清晰、鼓励", correctionLevel: .detailed)
        let emma = Buddy(name: "Emma", avatar: "person.crop.circle.fill", language: "English", relationship: .classmate, personality: "开朗、自然", correctionLevel: .light)
        [yuki, michael, emma].forEach(context.insert)

        let japanSeries = Series(name: "日本旅行")
        let workSeries = Series(name: "工作英语")
        let lifeSeries = Series(name: "留学生活")
        [japanSeries, workSeries, lifeSeries].forEach(context.insert)

        let scenes = [
            Scene(name: "日本旅行", coverImage: "suitcase.fill", language: "日本語", description: "第一次去日本旅行，练习机场、酒店和餐厅的自然交流。", buddyId: yuki.id, seriesId: japanSeries.id, createdAt: .now.addingTimeInterval(-172_800)),
            Scene(name: "工作面试", coverImage: "briefcase.fill", language: "English", description: "模拟工作面试，清楚自然地介绍自己的经历。", buddyId: michael.id, seriesId: workSeries.id, createdAt: .now.addingTimeInterval(-432_000)),
            Scene(name: "日常聊天", coverImage: "gamecontroller.fill", language: "English", description: "像朋友一样聊聊今天发生的事情。", buddyId: emma.id, createdAt: .now.addingTimeInterval(-604_800)),
            Scene(name: "留学生活", coverImage: "graduationcap.fill", language: "English", description: "练习校园生活、课堂讨论与同学交流。", buddyId: emma.id, seriesId: lifeSeries.id, createdAt: .now.addingTimeInterval(-1_209_600))
        ]
        scenes.forEach(context.insert)
        japanSeries.sceneIds = [scenes[0].id]
        workSeries.sceneIds = [scenes[1].id]
        lifeSeries.sceneIds = [scenes[3].id]
        try? context.save()
    }

    static func seedChineseModelTest(in context: ModelContext) {
        let scenes = (try? context.fetch(FetchDescriptor<Scene>())) ?? []
        guard !scenes.contains(where: { $0.name == "中文模型测试" }) else { return }
        let buddy = Buddy(
            name: "小语",
            language: "中文",
            relationship: .friend,
            personality: "自然、真诚、会接话",
            correctionLevel: .moderate
        )
        context.insert(buddy)
        context.insert(Scene(
            name: "中文模型测试",
            coverImage: "bubble.left.and.bubble.right.fill",
            language: "中文",
            description: "像朋友一样用中文聊聊今天发生的事情。",
            buddyId: buddy.id
        ))
        try? context.save()
    }
}
