import Foundation
import SwiftData

enum SceneStatus: String, Codable, CaseIterable {
    case active, archived
}

enum BuddyRelationship: String, Codable, CaseIterable, Identifiable {
    case friend, classmate, teacher, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .friend: "朋友"
        case .classmate: "同学"
        case .teacher: "老师"
        case .custom: "自定义"
        }
    }
}

enum CorrectionLevel: String, Codable, CaseIterable, Identifiable {
    case light, moderate, detailed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .light: "轻度"
        case .moderate: "适中"
        case .detailed: "详细"
        }
    }
}

enum MessageRole: String, Codable { case user, assistant }

@Model
final class Scene {
    @Attribute(.unique) var id: UUID
    var name: String
    var coverImage: String
    var language: String
    var sceneDescription: String
    var buddyId: UUID
    var seriesId: UUID?
    var createdAt: Date
    var lastChatTime: Date?
    var statusRaw: String

    init(id: UUID = UUID(), name: String, coverImage: String, language: String, description: String,
         buddyId: UUID, seriesId: UUID? = nil, createdAt: Date = .now,
         lastChatTime: Date? = nil, status: SceneStatus = .active) {
        self.id = id
        self.name = name
        self.coverImage = coverImage
        self.language = language
        self.sceneDescription = description
        self.buddyId = buddyId
        self.seriesId = seriesId
        self.createdAt = createdAt
        self.lastChatTime = lastChatTime
        self.statusRaw = status.rawValue
    }

    var status: SceneStatus {
        get { SceneStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }
}

@Model
final class Series {
    @Attribute(.unique) var id: UUID
    var name: String
    var sceneIds: [UUID]
    var createdAt: Date

    init(id: UUID = UUID(), name: String, sceneIds: [UUID] = [], createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.sceneIds = sceneIds
        self.createdAt = createdAt
    }
}

@Model
final class Buddy {
    @Attribute(.unique) var id: UUID
    var name: String
    var avatar: String
    var language: String
    var relationshipRaw: String
    var personality: String
    var correctionLevelRaw: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, avatar: String = "person.crop.circle.fill", language: String,
         relationship: BuddyRelationship, personality: String, correctionLevel: CorrectionLevel,
         createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.language = language
        self.relationshipRaw = relationship.rawValue
        self.personality = personality
        self.correctionLevelRaw = correctionLevel.rawValue
        self.createdAt = createdAt
    }

    var relationship: BuddyRelationship {
        get { BuddyRelationship(rawValue: relationshipRaw) ?? .friend }
        set { relationshipRaw = newValue.rawValue }
    }
    var correctionLevel: CorrectionLevel {
        get { CorrectionLevel(rawValue: correctionLevelRaw) ?? .moderate }
        set { correctionLevelRaw = newValue.rawValue }
    }
}

@Model
final class ChatSession {
    @Attribute(.unique) var id: UUID
    var sceneId: UUID
    var startedAt: Date
    var endedAt: Date?
    var isEnded: Bool

    init(id: UUID = UUID(), sceneId: UUID, startedAt: Date = .now, endedAt: Date? = nil, isEnded: Bool = false) {
        self.id = id
        self.sceneId = sceneId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.isEnded = isEnded
    }
}

@Model
final class Message {
    @Attribute(.unique) var id: UUID
    var sessionId: UUID
    var roleRaw: String
    var content: String
    var audioPath: String?
    var timestamp: Date
    var correction: String?

    init(id: UUID = UUID(), sessionId: UUID, role: MessageRole, content: String,
         audioPath: String? = nil, timestamp: Date = .now, correction: String? = nil) {
        self.id = id
        self.sessionId = sessionId
        self.roleRaw = role.rawValue
        self.content = content
        self.audioPath = audioPath
        self.timestamp = timestamp
        self.correction = correction
    }

    var role: MessageRole {
        get { MessageRole(rawValue: roleRaw) ?? .user }
        set { roleRaw = newValue.rawValue }
    }
}
