import SwiftUI

struct SessionEndView: View {
    let scene: Scene
    let messageCount: Int
    let elapsedSeconds: Int
    /// Structured mistakes collected during the session ("原句→更好的表达"),
    /// already capped by the caller according to the buddy's correction level.
    let mistakes: [String]
    let resume: () -> Void
    let exit: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle().fill(AppTheme.purple.opacity(0.16)).frame(width: 102, height: 102)
                Circle().stroke(AppTheme.gradient, lineWidth: 3).frame(width: 82, height: 82)
                Image(systemName: "checkmark").font(.system(size: 37, weight: .medium)).foregroundStyle(.white)
            }
            Text("本次场景已结束").font(.system(size: 23, weight: .bold))
            VStack(spacing: 0) {
                statRow("本次时长", value: durationText)
                Divider().overlay(AppTheme.separator)
                statRow("对话轮数", value: "\(max(messageCount / 2, 1))")
                Divider().overlay(AppTheme.separator)
                statRow("消息数量", value: "\(messageCount)")
            }.appCard()
            if !mistakes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("本次值得注意").font(.system(size: 14, weight: .semibold))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(mistakes, id: \.self) { mistakeRow($0) }
                        }
                    }.frame(maxHeight: 150)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading).appCard(cornerRadius: 14)
            }
            Spacer()
            VStack(spacing: 11) {
                Button("继续聊天", action: resume)
                    .foregroundStyle(AppTheme.purpleLight).frame(maxWidth: .infinity).frame(height: 50).appCard(cornerRadius: 16)
                Button("返回场景", action: exit).buttonStyle(PurpleButtonStyle())
            }
        }.padding(20).appBackground()
    }

    private func mistakeRow(_ mistake: String) -> some View {
        let parts = mistake.components(separatedBy: "→").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return HStack(alignment: .top, spacing: 6) {
            Image(systemName: "sparkles").font(.caption).foregroundStyle(AppTheme.purpleLight)
            if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(parts[0]).font(.system(size: 12)).foregroundStyle(AppTheme.secondaryText).strikethrough()
                    Text(parts[1]).font(.system(size: 13))
                }
            } else {
                Text(mistake).font(.system(size: 13))
            }
        }
    }

    private var durationText: String { String(format: "%02d:%02d", elapsedSeconds / 60, elapsedSeconds % 60) }
    private func statRow(_ title: String, value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(AppTheme.secondaryText) }.font(.system(size: 15)).padding(.horizontal, 17).frame(height: 56)
    }
}

