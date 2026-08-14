import XCTest

final class RecordingCrashUITests: XCTestCase {
    @MainActor
    func testChineseSceneUsesLocalModelAndRepliesInChinese() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--uitest-chinese-scene", "-autoTTS", "NO"]
        app.launch()

        let scene = app.buttons["scene-中文模型测试"]
        XCTAssertTrue(scene.waitForExistence(timeout: 10))
        scene.tap()
        let startChat = app.buttons["start-chat-button"]
        XCTAssertTrue(startChat.waitForExistence(timeout: 6))
        startChat.tap()

        let field = app.textFields["chat-text-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 6))
        field.tap()
        field.typeText("我今天很难过，因为考试没考好，你能安慰我吗？")
        app.buttons["send-text-button"].tap()

        let assistantMessages = app.otherElements.matching(identifier: "assistant-message")
        let secondReply = assistantMessages.element(boundBy: 1)
        let result = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in secondReply.exists || app.alerts.firstMatch.exists },
            object: nil
        )
        let waitResult = XCTWaiter.wait(for: [result], timeout: 60)
        guard waitResult == .completed else {
            XCTFail("Qwen 未在 60 秒内生成回复")
            return
        }
        if app.alerts.firstMatch.exists {
            let alertText = app.alerts.firstMatch.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " · ")
            XCTFail("Qwen 返回错误：\(alertText)")
            return
        }
        let reply = secondReply.label
        let containsChinese = reply.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        XCTAssertTrue(containsChinese, "中文场景收到了非中文回复：\(reply)")
        let understandsMessage = ["考试", "难过", "安慰", "没关系", "别灰心", "下次"].contains {
            reply.contains($0)
        }
        XCTAssertTrue(understandsMessage, "回复没有理解用户关于考试失利和情绪的内容：\(reply)")
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    func testRecordingCanStartAndStopWithoutCrashing() throws {
        let app = XCUIApplication()
        app.launch()

        let scene = app.buttons["scene-日本旅行"]
        XCTAssertTrue(scene.waitForExistence(timeout: 8))
        scene.tap()

        let startChat = app.buttons["start-chat-button"]
        if !startChat.waitForExistence(timeout: 3) {
            // A transient SpringBoard automation banner can consume the first
            // synthesized tap on a physical device.
            scene.tap()
        }
        XCTAssertTrue(startChat.waitForExistence(timeout: 5))
        startChat.tap()

        let record = app.buttons["record-button"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        let textField = app.textFields["chat-text-field"]
        XCTAssertTrue(textField.waitForExistence(timeout: 3))
        let textFieldFrameBeforeRecording = textField.frame
        record.tap()
        handleMicrophonePermissionIfNeeded(in: app)

        sleep(2)
        XCTAssertEqual(app.state, .runningForeground)
        let levelMeter = app.otherElements["recording-level-meter"]
        XCTAssertTrue(levelMeter.waitForExistence(timeout: 3))
        XCTAssertEqual(textFieldFrameBeforeRecording.minY, levelMeter.frame.minY, accuracy: 1)
        XCTAssertEqual(textFieldFrameBeforeRecording.height, levelMeter.frame.height, accuracy: 1)
        record.tap()
        // Keep the process alive through denoise, Whisper model loading and the
        // silent-audio error path, not only through AVAudioEngine.stop().
        sleep(12)
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    private func handleMicrophonePermissionIfNeeded(in app: XCUIApplication) {
        guard app.alerts.firstMatch.waitForExistence(timeout: 1) else { return }
        let allowLabels = ["允许", "Allow", "使用 App 时允许"]
        for label in allowLabels {
            let button = app.alerts.buttons[label]
            if button.exists {
                button.tap()
                return
            }
        }
    }
}
