# AI 口语搭子

纯本地、Offline First 的 SwiftUI 口语聊天 App。用户自行创建场景和 AI 搭子，不包含课程、打卡、等级或推荐系统。

## 运行

1. 使用 Xcode 打开 `YuKi.xcodeproj`。
2. 选择 iPhone 真机目标并设置开发团队。
3. 构建运行（最低 iOS 17）。

项目文件由 XcodeGen 管理。修改 `project.yml` 后执行：

```sh
xcodegen generate
```

## 本地能力

- SwiftData：场景、系列、搭子、聊天会话和消息。
- AVAudioEngine：录音和实时音量波纹。
- whisper.cpp：使用随包提供的 `ggml-small-q8_0.bin` 完全离线转写。
- DeepFilterNet3：录音转写前的本地人声降噪。
- AVSpeechSynthesizer：本地 TTS。
- `LocalLLMResponding`：本地 LLM 的稳定接入边界，当前内置演示响应。

Whisper/DeepFilterNet 的 arm64 静态库沿用 VoiceThought 的真机构建产物，因此包含完整语音能力的目标应在 iPhone 真机上运行。
