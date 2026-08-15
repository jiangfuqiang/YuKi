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

/// Self-assessed proficiency for a scene. Only a coarse hint for the prompt:
/// the small model follows "match the user's level" far more reliably than it
/// can estimate the level by itself.
enum SceneLevel: String, Codable, CaseIterable, Identifiable {
    case a1 = "A1", a2 = "A2", b1 = "B1", b2 = "B2", c1 = "C1"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .a1: "入门"
        case .a2: "初级"
        case .b1: "中级"
        case .b2: "中高级"
        case .c1: "高级"
        }
    }
}

@Model
final class Scene {
    @Attribute(.unique) var id: UUID
    var name: String
    var coverImage: String
    var language: String
    var sceneDescription: String
    /// Optional scene flow, e.g. "打招呼 → 点饮料 → 结账". Injected into the
    /// system prompt so the small model follows a known progression instead of
    /// steering the whole conversation by itself.
    var sceneFlow: String?
    /// The user's role inside the scene, e.g. "顾客" / "面试者".
    var userRole: String?
    /// The role the buddy plays inside the scene, e.g. "店员" / "面试官".
    var aiRole: String?
    /// SceneLevel raw value; nil means "not specified".
    var level: String?
    /// What the user wants to practice, e.g. "点餐用语、过去时".
    var goals: String?
    var buddyId: UUID
    var seriesId: UUID?
    var createdAt: Date
    var lastChatTime: Date?
    var statusRaw: String

    init(id: UUID = UUID(), name: String, coverImage: String, language: String, description: String,
         flow: String? = nil, userRole: String? = nil, aiRole: String? = nil,
         level: String? = nil, goals: String? = nil,
         buddyId: UUID, seriesId: UUID? = nil, createdAt: Date = .now,
         lastChatTime: Date? = nil, status: SceneStatus = .active) {
        self.id = id
        self.name = name
        self.coverImage = coverImage
        self.language = language
        self.sceneDescription = description
        self.sceneFlow = flow
        self.userRole = userRole
        self.aiRole = aiRole
        self.level = level
        self.goals = goals
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
