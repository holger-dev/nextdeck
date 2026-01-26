//
//  RunnerUITests.swift
//  RunnerUITests
//
//  Created by Holger Heidkamp on 26.01.26.
//

import XCTest

final class RunnerUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        if ProcessInfo.processInfo.environment["FASTLANE_SNAPSHOT"] == "YES" {
            throw XCTSkip("Skip default template tests during snapshot runs.")
        }

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}

final class SnapshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSnapshotsLight() throws {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launch()

        runSnapshotSequence(app: app, suffix: "_light")
    }

    @MainActor
    func testSnapshotsDark() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleInterfaceStyle", "Dark"]
        setupSnapshot(app)
        app.launch()

        runSnapshotSequence(app: app, suffix: "_dark")
    }

    @MainActor
    private func runSnapshotSequence(app: XCUIApplication, suffix: String) {
        let waitSeconds = snapshotWaitSeconds()

        waitForUser("Settings", seconds: waitSeconds)
        setPortrait()
        snapshot("01_settings\(suffix)")

        waitForUser("Board overview", seconds: waitSeconds)
        setPortrait()
        snapshot("02_board_overview\(suffix)")

        waitForUser("Board view", seconds: waitSeconds)
        setPortrait()
        snapshot("03_board_view\(suffix)")

        waitForUser("Due view", seconds: waitSeconds)
        setPortrait()
        snapshot("04_due_view\(suffix)")

        waitForUser("Card detail (with description)", seconds: waitSeconds)
        setPortrait()
        snapshot("05_card_detail\(suffix)")
    }

    private func snapshotWaitSeconds() -> UInt32 {
        if let value = ProcessInfo.processInfo.environment["SNAPSHOT_STEP_WAIT"],
           let seconds = UInt32(value) {
            return seconds
        }
        return 20
    }

    private func waitForUser(_ label: String, seconds: UInt32) {
        NSLog("snapshot-step: Prepare '%@' – waiting %d seconds", label, seconds)
        sleep(seconds)
    }

    private func setPortrait() {
        XCUIDevice.shared.orientation = .portrait
    }
}
