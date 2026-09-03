//
//  MarginRunUITests.swift
//  MarginRunUITests
//
//  Created by João Pedro da Silva Ramalho on 31/08/26.
//

import XCTest

final class MarginRunUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        // The simulator keeps whatever orientation the last run left it in, and
        // in landscape half these assertions are about content that has simply
        // dropped below the fold. Pinning it makes the suite say something
        // about the app rather than about the device it happened to run on.
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: - Existing work

    @MainActor
    func testCompletedJobOpensFinalReport() throws {
        let app = launchUsedInstall()

        app.tabBars.buttons["History"].tap()
        app.segmentedControls.buttons["Completed"].tap()

        let completedJob = app.staticTexts["Kitchen remodel"]
        XCTAssertTrue(completedJob.waitForExistence(timeout: 3))
        completedJob.tap()

        XCTAssertTrue(app.staticTexts["Final results"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "less than expected")
            ).firstMatch.exists
        )
        XCTAssertTrue(app.staticTexts["Cost drivers"].exists)
    }

    @MainActor
    func testAddExpenseOffersReceiptAttachment() throws {
        let app = launchUsedInstall()

        let activeJob = app.staticTexts["Backyard fence"].firstMatch
        XCTAssertTrue(activeJob.waitForExistence(timeout: 3))
        activeJob.tap()
        app.buttons["addExpenseButton"].tap()

        XCTAssertTrue(app.staticTexts["receiptSectionHeader"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["receiptLibraryButton"].exists)
        XCTAssertTrue(app.datePickers["expenseDatePicker"].exists)
        XCTAssertTrue(app.staticTexts["receiptGuidanceFooter"].exists)
    }

    @MainActor
    func testAddLaborShowsCalculatedCostForm() throws {
        let app = launchUsedInstall()

        let activeJob = app.staticTexts["Backyard fence"].firstMatch
        XCTAssertTrue(activeJob.waitForExistence(timeout: 3))
        activeJob.tap()

        // The job detail screen is a `List`, so rows below the fold are not in
        // the accessibility tree until they scroll into view.
        let addLabor = app.buttons["addLaborButton"]
        XCTAssertTrue(scrollToElement(addLabor, in: app), "Add Labor never came into view")
        addLabor.tap()

        XCTAssertTrue(app.navigationBars["Add Labor"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["laborHoursField"].exists)
        XCTAssertTrue(app.textFields["laborHourlyCostField"].exists)
        XCTAssertTrue(app.datePickers["laborDatePicker"].exists)
        XCTAssertTrue(app.staticTexts["laborCostLabel"].exists)
    }

    // MARK: - First run

    /// The activation path the whole release is judged on: a brand new install
    /// reaches the real Create Job form, and creating a job leaves the
    /// contractor with something obvious to do next.
    ///
    /// Every assertion is on an accessibility identifier, so rewriting the
    /// onboarding copy cannot break the funnel test.
    @MainActor
    func testFirstRunOnboardingReachesCreateJob() throws {
        let app = launchFreshInstall()

        let primary = app.buttons["onboardingPrimaryButton"]
        XCTAssertTrue(primary.waitForExistence(timeout: 5), "A fresh install should start setup")
        XCTAssertTrue(app.otherElements["onboardingStepIndicator"].exists)

        // Screen 1 → business, screen 2 → defaults, screen 3 → Create Job.
        primary.tap()
        XCTAssertTrue(app.textFields["onboardingBusinessNameField"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["onboardingTradePicker"].exists)

        primary.tap()
        XCTAssertTrue(app.textFields["onboardingHourlyCostField"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["onboardingTargetMarginField"].exists)

        primary.tap()

        let jobName = app.textFields["createJobNameField"]
        XCTAssertTrue(
            jobName.waitForExistence(timeout: 5),
            "Setup should hand straight over to the real Create Job flow"
        )
        XCTAssertTrue(app.textFields["createJobContractValueField"].exists)
    }

    /// Creating that first job must end somewhere with an obvious next action,
    /// not on an empty dashboard.
    @MainActor
    func testCreatingTheFirstJobOffersTheNextStep() throws {
        let app = launchFreshInstall()

        let primary = app.buttons["onboardingPrimaryButton"]
        XCTAssertTrue(primary.waitForExistence(timeout: 5))
        primary.tap()
        primary.tap()
        primary.tap()

        let jobName = app.textFields["createJobNameField"]
        XCTAssertTrue(jobName.waitForExistence(timeout: 5))
        jobName.tap()
        jobName.typeText("Deck rebuild")

        let contractValue = app.textFields["createJobContractValueField"]
        contractValue.tap()
        contractValue.typeText("8400")

        // Decimal pads have no return key, so the form's own Done is the way
        // out — and the save button sits behind the keyboard until it closes.
        // Waited on rather than assumed: tapping Done and reaching straight
        // for the button underneath is a race with the dismissal animation.
        dismissKeyboard(in: app)

        let save = app.buttons["createJobSaveButton"].firstMatch
        XCTAssertTrue(scrollToElement(save, in: app), "Create Job never came into view")
        save.tap()

        XCTAssertTrue(
            app.buttons["startTrackingAddExpenseButton"].waitForExistence(timeout: 5),
            "A new job should offer the first cost entry straight away"
        )
        XCTAssertTrue(app.buttons["startTrackingAddLaborButton"].exists)
        XCTAssertTrue(app.buttons["startTrackingDoneButton"].exists)
    }

    /// The upgrade case. An install that already holds jobs must land in the
    /// app, not be marched through setup it has effectively already done.
    @MainActor
    func testExistingInstallIsNotForcedThroughOnboarding() throws {
        let app = launchUsedInstall()

        XCTAssertTrue(
            app.tabBars.buttons["Dashboard"].waitForExistence(timeout: 5),
            "An install with jobs should open straight into the app"
        )
        XCTAssertFalse(
            app.buttons["onboardingPrimaryButton"].exists,
            "Existing work means setup has effectively happened"
        )
    }

    /// Setup pages back and forward under a swipe as well as a tap, and the
    /// two ways of moving stay in step.
    @MainActor
    func testOnboardingPagesBySwipeInBothDirections() throws {
        let app = launchFreshInstall()

        let primary = app.buttons["onboardingPrimaryButton"]
        XCTAssertTrue(primary.waitForExistence(timeout: 5))

        // Forward by swipe, all the way to the last screen.
        app.swipeLeft()
        let businessName = app.textFields["onboardingBusinessNameField"]
        XCTAssertTrue(businessName.waitForExistence(timeout: 3), "Swipe should advance")

        app.swipeLeft()
        XCTAssertTrue(app.textFields["onboardingHourlyCostField"].waitForExistence(timeout: 3))

        // The last screen has nowhere further to go: a swipe must not create
        // a job, which only the explicit CTA does.
        app.swipeLeft()
        XCTAssertTrue(app.textFields["onboardingHourlyCostField"].exists)
        XCTAssertFalse(
            app.textFields["createJobNameField"].exists,
            "Swiping past the last screen must never create a job"
        )

        // And back again.
        app.swipeRight()
        XCTAssertTrue(businessName.waitForExistence(timeout: 3), "Swipe back should return")
    }

    /// Nothing typed is lost by paging away and back, and no optional field
    /// blocks forward movement.
    @MainActor
    func testSwipingPreservesEnteredValues() throws {
        let app = launchFreshInstall()

        XCTAssertTrue(app.buttons["onboardingPrimaryButton"].waitForExistence(timeout: 5))
        app.swipeLeft()

        let businessName = app.textFields["onboardingBusinessNameField"]
        XCTAssertTrue(businessName.waitForExistence(timeout: 3))
        businessName.tap()
        businessName.typeText("Johnson Remodeling")

        app.swipeLeft()
        let hourlyCost = app.textFields["onboardingHourlyCostField"]
        XCTAssertTrue(hourlyCost.waitForExistence(timeout: 3))
        // Every field is optional, so paging forward must never be blocked.
        XCTAssertTrue(app.buttons["onboardingPrimaryButton"].isEnabled)

        app.swipeRight()
        XCTAssertTrue(businessName.waitForExistence(timeout: 3))
        XCTAssertEqual(businessName.value as? String, "Johnson Remodeling")
    }

    /// Both fields on the business screen are already optional, so Continue
    /// with nothing typed is the only action it needs.
    @MainActor
    func testBusinessScreenOffersNoRedundantSkip() throws {
        let app = launchFreshInstall()

        let primary = app.buttons["onboardingPrimaryButton"]
        XCTAssertTrue(primary.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboardingSecondaryButton"].exists, "screen 1 skips setup")

        primary.tap()
        XCTAssertTrue(app.textFields["onboardingBusinessNameField"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["onboardingSecondaryButton"].exists)

        primary.tap()
        XCTAssertTrue(app.textFields["onboardingHourlyCostField"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["onboardingSecondaryButton"].exists, "defaults can be skipped")
    }

    /// Setup is optional in full. Skipping from the first screen must still
    /// land in a usable app.
    @MainActor
    func testSetupCanBeSkippedEntirely() throws {
        let app = launchFreshInstall()

        let skip = app.buttons["onboardingSecondaryButton"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()

        XCTAssertTrue(app.tabBars.buttons["Dashboard"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboardingPrimaryButton"].exists)
    }

    /// Every text form offers a way out of the keyboard that does not depend
    /// on finding a gap to tap: an explicit Done above the keys, and a swipe
    /// over the content. Most fields here are decimal pads, which have no
    /// return key at all.
    @MainActor
    func testFormsOfferAWayOutOfTheKeyboard() throws {
        let app = launchUsedInstall()

        let job = app.staticTexts["Backyard fence"].firstMatch
        XCTAssertTrue(job.waitForExistence(timeout: 5))
        job.tap()

        let addLabor = app.buttons["addLaborButton"]
        XCTAssertTrue(scrollToElement(addLabor, in: app))
        addLabor.tap()

        let hours = app.textFields["laborHoursField"]
        XCTAssertTrue(hours.waitForExistence(timeout: 5))
        hours.tap()
        hours.typeText("6")
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5), "keyboard should open")

        let done = app.buttons["keyboardDoneButton"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 3), "Done should sit above the keys")
        done.tap()
        XCTAssertTrue(waitForKeyboardToDisappear(in: app), "Done should close the keyboard")

        // And a swipe over the content, for when Done is not where the thumb
        // already is.
        let hourlyCost = app.textFields["laborHourlyCostField"]
        hourlyCost.tap()
        hourlyCost.typeText("55")
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5))

        app.swipeDown()
        XCTAssertTrue(waitForKeyboardToDisappear(in: app), "a swipe should close the keyboard")
    }

    @MainActor
    private func waitForKeyboardToDisappear(
        in app: XCUIApplication,
        timeout: TimeInterval = 5
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !app.keyboards.element.exists { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return !app.keyboards.element.exists
    }

    /// Closes the keyboard through the form's own Done button, and does not
    /// return until it has actually gone.
    ///
    /// Tapping Done is not the same as the keyboard being closed: it slides out
    /// over several frames, and whatever it was covering stays unhittable until
    /// it has. A test that taps Done and immediately reaches underneath passes
    /// or fails on animation timing, which is the one thing a UI test must
    /// never be deciding.
    @MainActor
    private func dismissKeyboard(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let done = app.buttons["keyboardDoneButton"].firstMatch
        XCTAssertTrue(
            done.waitForExistence(timeout: 5),
            "The keyboard toolbar never offered a Done button",
            file: file,
            line: line
        )
        done.tap()
        XCTAssertTrue(
            waitForKeyboardToDisappear(in: app),
            "Done should close the keyboard",
            file: file,
            line: line
        )
    }

    /// A confirmation dialog anchors to the control that raised it.
    ///
    /// Regression: the dialog used to hang off the whole `List`, so iOS drew it
    /// pointing at the middle of the screen with its message clipped, far from
    /// the button the customer had just tapped.
    @MainActor
    func testCompleteJobDialogAnchorsToItsButton() throws {
        let app = launchUsedInstall()

        let job = app.staticTexts["Backyard fence"].firstMatch
        XCTAssertTrue(job.waitForExistence(timeout: 5))
        job.tap()

        // `.firstMatch`: the identifier lands on the button and on its label.
        let complete = app.buttons["completeJobButton"].firstMatch
        XCTAssertTrue(scrollToElement(complete, in: app), "Complete job never came into view")
        let sourceMidY = complete.frame.midY
        complete.tap()

        let confirm = app.buttons["confirmCompleteJobButton"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Dialog should open")

        // Anchored, not adrift at the top of the screen. A generous bound: the
        // point is the difference between "beside the button" and "nowhere
        // near it", not a pixel-exact layout.
        let distance = abs(confirm.frame.midY - sourceMidY)
        XCTAssertLessThan(
            distance,
            app.frame.height / 3,
            "Dialog drifted away from the button that raised it"
        )
        XCTAssertGreaterThan(
            confirm.frame.midY,
            app.frame.height / 2,
            "Dialog should stay in the lower half, beside its button"
        )
    }

    // MARK: - Paywall

    /// A free account reaching Insights must be offered the contextual paywall
    /// rather than the Pro screen.
    ///
    /// Asserts on accessibility identifiers only — never on marketing copy, which
    /// is expected to change without breaking the gate.
    @MainActor
    func testFreeUserHitsContextualPaywallFromInsights() throws {
        let app = launchUsedInstall()

        app.tabBars.buttons["Insights"].tap()

        let unlock = app.buttons["unlockProButton"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 5), "Free user should see the Insights gate")
        unlock.tap()

        // The paywall is presented and dismissible. Purchasing is deliberately
        // not exercised: no real transaction belongs in a UI test.
        let close = app.buttons["paywallCloseButton"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "Paywall should be presented")
        close.tap()

        XCTAssertTrue(unlock.waitForExistence(timeout: 5), "Dismissing returns to the gate")
    }

    /// A second contextual entry point, proving the gate is not specific to one
    /// screen and that the free path beside it still works.
    @MainActor
    func testFreeUserHitsContextualPaywallFromLaborTimer() throws {
        let app = launchUsedInstall()

        let activeJob = app.staticTexts["Backyard fence"].firstMatch
        XCTAssertTrue(activeJob.waitForExistence(timeout: 3))
        activeJob.tap()

        let startWork = app.buttons["Start Work"]
        XCTAssertTrue(scrollToElement(startWork, in: app), "Start Work never came into view")
        startWork.tap()

        let close = app.buttons["paywallCloseButton"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "Starting the timer should be gated")
        close.tap()

        // Manual labor entry stays free, so the gate must not have blocked it.
        let addLabor = app.buttons["addLaborButton"]
        XCTAssertTrue(scrollToElement(addLabor, in: app))
        addLabor.tap()
        XCTAssertTrue(app.navigationBars["Add Labor"].waitForExistence(timeout: 3))
    }

    /// The paywall review's headline requirement: nobody should be able to buy
    /// the yearly plan without having seen that a monthly one exists.
    ///
    /// `isHittable` rather than `exists`, because a control scrolled off the
    /// bottom of the screen still exists in the accessibility tree.
    @MainActor
    func testBothPlansAreVisibleWithoutScrolling() throws {
        let app = launchUsedInstall()

        openInsightsPaywall(in: app)

        let yearly = app.buttons["planYearly"]
        let monthly = app.buttons["planMonthly"]
        let purchase = app.buttons["paywallPurchaseButton"]

        XCTAssertTrue(yearly.waitForExistence(timeout: 10), "Yearly plan should be offered")
        XCTAssertTrue(monthly.exists, "Monthly plan should be offered")

        XCTAssertTrue(yearly.isHittable, "Yearly must be visible without scrolling")
        XCTAssertTrue(monthly.isHittable, "Monthly must be visible without scrolling")
        XCTAssertTrue(purchase.isHittable, "The CTA must be visible without scrolling")
    }

    /// Annual leads and is preselected, and choosing monthly actually moves the
    /// selection rather than only redrawing.
    @MainActor
    func testAnnualIsRecommendedAndTheSelectionCanBeChanged() throws {
        let app = launchUsedInstall()

        openInsightsPaywall(in: app)

        let yearly = app.buttons["planYearly"]
        let monthly = app.buttons["planMonthly"]
        XCTAssertTrue(yearly.waitForExistence(timeout: 10))

        XCTAssertTrue(yearly.isSelected, "Annual should be recommended by default")
        XCTAssertFalse(monthly.isSelected)

        monthly.tap()

        XCTAssertTrue(monthly.isSelected, "Tapping monthly should move the selection")
        XCTAssertFalse(yearly.isSelected)
        XCTAssertTrue(app.buttons["paywallPurchaseButton"].isEnabled)
    }

    /// Apple's required controls stay present and reachable, and the paywall is
    /// never hard to leave.
    @MainActor
    func testPaywallKeepsItsLegalAndDismissControls() throws {
        let app = launchUsedInstall()

        openInsightsPaywall(in: app)
        XCTAssertTrue(app.buttons["paywallPurchaseButton"].waitForExistence(timeout: 10))

        XCTAssertTrue(app.buttons["paywallRestoreButton"].exists)
        // `Link` surfaces as a button on iOS, so query the whole tree rather
        // than guessing the element type.
        XCTAssertTrue(app.descendants(matching: .any)["paywallTermsLink"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["paywallPrivacyLink"].exists)
        XCTAssertTrue(app.buttons["paywallCloseButton"].isHittable, "Dismissal must stay easy")
    }

    /// At accessibility sizes the decision area becomes part of the scroll,
    /// so the app honors the chosen text size without trapping any plan or
    /// Apple-required control below a fixed overlay.
    @MainActor
    func testPaywallControlsRemainReachableAtLargestAccessibilityText() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launch()

        openInsightsPaywall(in: app)

        let controls = [
            app.buttons["planYearly"],
            app.buttons["planMonthly"],
            app.buttons["paywallPurchaseButton"],
            app.buttons["paywallRestoreButton"],
            app.descendants(matching: .any)["paywallPrivacyLink"],
            app.descendants(matching: .any)["paywallTermsLink"],
        ]

        for control in controls {
            XCTAssertTrue(
                scrollToElement(control, in: app, maxSwipes: 16),
                "Every paywall control must remain reachable at accessibility text sizes"
            )
        }
        XCTAssertTrue(app.buttons["paywallCloseButton"].isHittable)
    }

    // MARK: - Helpers

    /// An install that already holds jobs — the state almost every test wants.
    @MainActor
    private func launchUsedInstall() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        return app
    }

    /// A genuinely empty install: no fixtures, no completed setup.
    @MainActor
    private func launchFreshInstall() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-fresh-install"]
        app.launch()
        return app
    }

    @MainActor
    private func openInsightsPaywall(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        app.tabBars.buttons["Insights"].tap()
        let unlock = app.buttons["unlockProButton"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 5), file: file, line: line)
        unlock.tap()
    }

    /// Scrolls `app` until `element` is on screen and can actually be tapped.
    ///
    /// Existence is not enough, and neither is a single reading of
    /// `isHittable`: a control can be in the accessibility tree while it is
    /// still under a closing keyboard, still travelling from a swipe, or below
    /// the safe area — with a frame that is no longer where a tap would land,
    /// which makes for tests that fail as if the app were broken. Every check
    /// here polls against a deadline, so a loaded machine gets the time it
    /// needs and a fast one does not pay a fixed sleep for it.
    ///
    /// - Returns: `true` once the element is hittable, `false` if it never got
    ///   there.
    @MainActor
    private func scrollToElement(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 10
    ) -> Bool {
        // Deliberately no `waitForExistence` up front: a Form renders lazily,
        // so a control below the fold is absent from the accessibility tree
        // until a scroll brings it in. Waiting for it to exist before scrolling
        // would be waiting for something only scrolling can produce.
        //
        // Settling for a beat first keeps a control that is merely
        // mid-animation from being mistaken for one that is off screen — the
        // swipe that would follow carries it past the target.
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
}
