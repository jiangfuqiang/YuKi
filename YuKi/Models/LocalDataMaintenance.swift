import Foundation
import SwiftData

@MainActor
enum LocalDataMaintenance {
    static func deleteScene(_ scene: Scene, in context: ModelContext) {
        let sceneID = scene.id
        let sessions = ((try? context.fetch(FetchDescriptor<ChatSession>())) ?? []).filter { $0.sceneId == sceneID }
        let sessionIDs = Set(sessions.map(\.id))
        let messages = ((try? context.fetch(FetchDescriptor<Message>())) ?? []).filter { sessionIDs.contains($0.sessionId) }
        for message in messages {
            if let path = message.audioPath { try? FileManager.default.removeItem(atPath: path) }
            context.delete(message)
        }
        sessions.forEach(context.delete)
        let allSeries = (try? context.fetch(FetchDescriptor<Series>())) ?? []
        for item in allSeries { item.sceneIds.removeAll { $0 == sceneID } }
        context.delete(scene)
        try? context.save()
    }

    static func deleteSession(_ session: ChatSession, in context: ModelContext) {
        let sessionID = session.id
        let messages = ((try? context.fetch(FetchDescriptor<Message>())) ?? []).filter { $0.sessionId == sessionID }
        for message in messages {
            if let path = message.audioPath { try? FileManager.default.removeItem(atPath: path) }
            context.delete(message)
        }
        context.delete(session)
        try? context.save()
    }

    static func deleteSeries(_ series: Series, in context: ModelContext) {
        let seriesID = series.id
        let scenes = (try? context.fetch(FetchDescriptor<Scene>())) ?? []
        for scene in scenes where scene.seriesId == seriesID { scene.seriesId = nil }
        context.delete(series)
        try? context.save()
    }
}

