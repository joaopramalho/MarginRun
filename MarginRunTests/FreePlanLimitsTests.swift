import Foundation
import Testing
@testable import MarginRun

struct FreePlanLimitsTests {

    @Test func freeAccountMayRunUpToTheActiveJobLimit() {
        #expect(FreePlanLimits.canCreateActiveJob(isPro: false, activeJobCount: 0))
        #expect(FreePlanLimits.canCreateActiveJob(isPro: false, activeJobCount: 1))
    }

    @Test func freeAccountIsBlockedAtTheThirdActiveJob() {
        // Two active jobs already running: creating job #3 is the gate.
        #expect(!FreePlanLimits.canCreateActiveJob(isPro: false, activeJobCount: 2))
        #expect(!FreePlanLimits.canCreateActiveJob(isPro: false, activeJobCount: 7))
    }

    @Test func proAccountHasNoActiveJobLimit() {
        #expect(FreePlanLimits.canCreateActiveJob(isPro: true, activeJobCount: 2))
        #expect(FreePlanLimits.canCreateActiveJob(isPro: true, activeJobCount: 500))
    }

    @Test func completingAJobFreesASlotForFreeAccounts() {
        // The count passed in is active jobs only, so finishing work restores
        // the ability to start something new without upgrading.
        #expect(!FreePlanLimits.canCreateActiveJob(isPro: false, activeJobCount: 2))
        #expect(FreePlanLimits.canCreateActiveJob(isPro: false, activeJobCount: 1))
    }
}
