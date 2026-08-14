import SwiftUI

struct SessionEndView: View {
    let scene: Scene
    let messageCount: Int
    let elapsedSeconds: Int
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
            Spacer()
            VStack(spacing: 11) {
                Button("继续聊天", action: resume)
                    .foregroundStyle(AppTheme.purpleLight).frame(maxWidth: .infinity).frame(height: 50).appCard(cornerRadius: 16)
                Button("返回场景", action: exit).buttonStyle(PurpleButtonStyle())
            }
        }.padding(20).appBackground()
    }

    private var durationText: String { String(format: "%02d:%02d", elapsedSeconds / 60, elapsedSeconds % 60) }
    private func statRow(_ title: String, value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(AppTheme.secondaryText) }.font(.system(size: 15)).padding(.horizontal, 17).frame(height: 56)
    }
}

