import XCTest

/// Captures every screen in the app for design review and for the App Store
/// listing.
///
/// Not a pass/fail suite: it asserts only enough to know it reached the screen
/// it is photographing. Appearance is set on the simulator before the run, so
/// the same catalogue produces the light and dark sets.
///
/// Every launch here is pinned to English (United States) — see
/// ``marketingLocaleArguments``. That is a property of the *marketing* run, not
/// of the app: MarginRun follows the device locale at runtime and continues to,
/// and the localized QA suite in `MarginRunUITests` is untouched.
final class ScreenshotCatalog: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Screenshots are only comparable if every run is framed the same way.
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: - First run

    @MainActor
    func test01Onboarding() throws {
        let app = launch(.freshInstall)

        let primary = app.buttons["onboardingPrimaryButton"]
        XCTAssertTrue(primary.waitForExistence(timeout: 10))
        shoot(app, "01-onboarding-value")

        primary.tap()
        XCTAssertTrue(app.textFields["onboardingBusinessNameField"].waitForExistence(timeout: 5))
        shoot(app, "02-onboarding-business")

        primary.tap()
        XCTAssertTrue(app.textFields["onboardingHourlyCostField"].waitForExistence(timeout: 5))
        shoot(app, "03-onboarding-defaults")

        primary.tap()
        XCTAssertTrue(app.textFields["createJobNameField"].waitForExistence(timeout: 10))
        shoot(app, "04-create-job-empty")
    }

    @MainActor
    func test02FirstJobAndNextStep() throws {
        let app = launch(.freshInstall)

        let primary = app.buttons["onboardingPrimaryButton"]
        XCTAssertTrue(primary.waitForExistence(timeout: 10))
        primary.tap()
        primary.tap()
        primary.tap()

        let name = app.textFields["createJobNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("Deck rebuild")

        app.textFields["createJobCustomerField"].tap()
        app.textFields["createJobCustomerField"].typeText("Alvarez")

        app.textFields["createJobContractValueField"].tap()
        app.textFields["createJobContractValueField"].typeText("18400")

        app.textFields["createJobMaterialsField"].tap()
        app.textFields["createJobMaterialsField"].typeText("6200")

        app.textFields["createJobLaborField"].tap()
        app.textFields["createJobLaborField"].typeText("4800")

        // Close the keyboard so the whole form is in frame — and so the save
        // button below it is reachable. Waited out rather than slept through:
        // a screenshot taken while the keyboard is still sliding is both a bad
        // screenshot and a scroll that then misses the save button.
        dismissKeyboard(in: app)
        shoot(app, "05-create-job-filled")

        let save = app.buttons["createJobSaveButton"].firstMatch
        XCTAssertTrue(scrollTo(save, in: app))
        save.tap()

        XCTAssertTrue(app.buttons["startTrackingAddExpenseButton"].waitForExistence(timeout: 10))
        shoot(app, "06-start-tracking")
    }

    // MARK: - Free account

    @MainActor
    func test03FreeAccount() throws {
        let app = launch(.usedInstall)

        XCTAssertTrue(app.tabBars.buttons["Dashboard"].waitForExistence(timeout: 10))
        shoot(app, "07-dashboard-free")

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        shoot(app, "08-history-active")

        app.segmentedControls.buttons["Completed"].tap()
        shoot(app, "09-history-completed")

        app.tabBars.buttons["Timer"].tap()
        XCTAssertTrue(app.buttons["Choose a Job"].waitForExistence(timeout: 5))
        shoot(app, "10-timer-empty")

        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(app.buttons["unlockProButton"].waitForExistence(timeout: 5))
        shoot(app, "11-insights-locked")

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        shoot(app, "12-settings-free")
    }

    @MainActor
    func test04JobDetail() throws {
        let app = launch(.usedInstall)

        let active = app.staticTexts["Backyard fence"].firstMatch
        XCTAssertTrue(active.waitForExistence(timeout: 10))
        active.tap()
        XCTAssertTrue(app.staticTexts["Job health"].waitForExistence(timeout: 5))
        shoot(app, "13-job-detail-active")

        let complete = app.buttons["completeJobButton"].firstMatch
        XCTAssertTrue(scrollTo(complete, in: app))
        complete.tap()
        XCTAssertTrue(app.buttons["confirmCompleteJobButton"].firstMatch.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.2)
        shoot(app, "14-complete-job-dialog")
    }

    @MainActor
    func test05CompletedJobReport() throws {
        let app = launch(.usedInstall)

        app.tabBars.buttons["History"].tap()
        app.segmentedControls.buttons["Completed"].tap()
        let completed = app.staticTexts["Kitchen remodel"].firstMatch
        XCTAssertTrue(completed.waitForExistence(timeout: 10))
        completed.tap()
        XCTAssertTrue(app.staticTexts["Final results"].waitForExistence(timeout: 5))
        shoot(app, "15-job-detail-completed")

        app.swipeUp()
        shoot(app, "16-completed-cost-drivers")
    }

    @MainActor
    func test06CostEntry() throws {
        let app = launch(.usedInstall)

        let active = app.staticTexts["Backyard fence"].firstMatch
        XCTAssertTrue(active.waitForExistence(timeout: 10))
        active.tap()

        app.buttons["addExpenseButton"].tap()
        XCTAssertTrue(app.staticTexts["receiptSectionHeader"].waitForExistence(timeout: 5))
        shoot(app, "17-add-expense")
        app.buttons["Cancel"].firstMatch.tap()

        let addLabor = app.buttons["addLaborButton"]
        XCTAssertTrue(scrollTo(addLabor, in: app))
        addLabor.tap()
        XCTAssertTrue(app.navigationBars["Add Labor"].waitForExistence(timeout: 5))
        shoot(app, "18-add-labor")
    }

    // MARK: - Paywall

    @MainActor
    func test07Paywall() throws {
        let app = launch(.usedInstall)

        app.tabBars.buttons["Insights"].tap()
        let unlock = app.buttons["unlockProButton"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 10))
        unlock.tap()

        XCTAssertTrue(app.buttons["paywallPurchaseButton"].waitForExistence(timeout: 25))
        shoot(app, "19-paywall-insights")

        app.buttons["planMonthly"].tap()
        shoot(app, "20-paywall-monthly-selected")
    }

    @MainActor
    func test08PaywallFromLaborTimer() throws {
        let app = launch(.usedInstall)

        let active = app.staticTexts["Backyard fence"].firstMatch
        XCTAssertTrue(active.waitForExistence(timeout: 10))
        active.tap()

        let startWork = app.buttons["Start Work"].firstMatch
        XCTAssertTrue(scrollTo(startWork, in: app))
        startWork.tap()

        XCTAssertTrue(app.buttons["paywallPurchaseButton"].waitForExistence(timeout: 25))
        shoot(app, "21-paywall-labor-timer")
    }

    // MARK: - Pro account

    @MainActor
    func test09ProAccount() throws {
        let app = launch(.pro)

        XCTAssertTrue(app.tabBars.buttons["Insights"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(app.segmentedControls.firstMatch.waitForExistence(timeout: 5))
        shoot(app, "22-insights-unlocked")

        app.swipeUp()
        shoot(app, "23-insights-detail")

        app.tabBars.buttons["Dashboard"].tap()
        XCTAssertTrue(app.staticTexts["Top alerts"].waitForExistence(timeout: 5))
        shoot(app, "24-dashboard-pro")

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        shoot(app, "25-settings-pro")
    }

    @MainActor
    func test10ProTimerAndExtras() throws {
        let app = launch(.pro)

        app.tabBars.buttons["Timer"].tap()
        let choose = app.buttons["Choose a Job"]
        XCTAssertTrue(choose.waitForExistence(timeout: 10))
        choose.tap()
        XCTAssertTrue(app.navigationBars["Choose a Job"].waitForExistence(timeout: 5))
        shoot(app, "26-timer-job-picker")
        app.buttons["Cancel"].firstMatch.tap()

        app.tabBars.buttons["Dashboard"].tap()
        let active = app.staticTexts["Backyard fence"].firstMatch
        XCTAssertTrue(active.waitForExistence(timeout: 5))
        active.tap()

        let addExtra = app.buttons["Add Extra Revenue"].firstMatch
        XCTAssertTrue(scrollTo(addExtra, in: app))
        addExtra.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        shoot(app, "27-add-extra-revenue")
    }

    // MARK: - Accessibility

    /// The screens most likely to break at large text: the paywall, whose
    /// bottom bar has to keep both plans and the CTA reachable, and onboarding.
    @MainActor
    func test11AccessibilityLargeType() throws {
        let app = launch(.usedInstall, extraArguments: [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityL",
        ])

        app.tabBars.buttons["Insights"].tap()
        let unlock = app.buttons["unlockProButton"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 10))
        shoot(app, "28-a11y-insights-gate")

        XCTAssertTrue(scrollTo(unlock, in: app))
        unlock.tap()
        XCTAssertTrue(app.buttons["paywallPurchaseButton"].waitForExistence(timeout: 25))
        shoot(app, "29-a11y-paywall")
    }

    @MainActor
    func test12AccessibilityOnboarding() throws {
        let app = launch(.freshInstall, extraArguments: [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityL",
        ])

        let primary = app.buttons["onboardingPrimaryButton"]
        XCTAssertTrue(primary.waitForExistence(timeout: 10))
        shoot(app, "30-a11y-onboarding-value")

        primary.tap()
        primary.tap()
        XCTAssertTrue(app.textFields["onboardingHourlyCostField"].waitForExistence(timeout: 5))
        shoot(app, "31-a11y-onboarding-defaults")
    }

    // MARK: - Helpers

    private enum World {
        case usedInstall
        case freshInstall
        case pro

        var arguments: [String] {
            switch self {
            case .usedInstall: ["-ui-testing"]
            case .freshInstall: ["-ui-testing", "-ui-testing-fresh-install"]
            case .pro: ["-ui-testing", "-ui-testing-pro"]
            }
        }
    }

    /// Pins the run to the US App Store listing's locale.
    ///
    /// The screenshots ship against a `en-US` storefront, so the money in them
    /// has to read `$18,000` rather than `R$18.000`. `MoneyFormat` formats from
    /// `Locale.autoupdatingCurrent`, so setting the launch locale is enough —
    /// nothing in the app is hard-coded to a currency, and nothing here changes
    /// that. Other locales stay reachable by launching with different values.
    private static let marketingLocaleArguments = [
        "-AppleLanguages", "(en-US)",
        "-AppleLocale", "en_US",
    ]

    @MainActor
    private func launch(
        _ world: World,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = world.arguments + Self.marketingLocaleArguments + extraArguments
        app.launch()
        return app
    }

    /// Closes the keyboard and waits for it to actually be gone.
    @MainActor
    private func dismissKeyboard(in app: XCUIApplication) {
        let done = app.buttons["keyboardDoneButton"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Done should sit above the keys")
        done.tap()

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, app.keyboards.element.exists {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertFalse(app.keyboards.element.exists, "Done should close the keyboard")
    }

    /// Brings `element` into view and reports success only once it is tappable,
    /// polling rather than reading `isHittable` a single time mid-animation.
    @MainActor
    private func scrollTo(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 8
    ) -> Bool {
        // No `waitForExistence` first: a Form renders lazily, so a control
        // below the fold does not exist until a scroll brings it in.
        if waitUntilHittable(element, timeout: 2) { return true }

        for _ in 0..<maxSwipes {
            app.swipeUp()
            if waitUntilHittable(element, timeout: 1) { return true }
        }
        return element.exists && element.isHittable
    }

    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists, element.isHittable { return true }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return element.exists && element.isHittable
    }

    private func shoot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
