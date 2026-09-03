import Foundation
import Testing
@testable import MarginRun

@MainActor
struct LaborTimerStoreTests {
    @Test func persistsRunningTimerAndCalculatesFromDates() throws {
        let suiteName = "LaborTimerStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let startedAt = Date(timeIntervalSince1970: 1_788_000_000)
        let jobID = UUID()

        let store = LaborTimerStore(defaults: defaults)
        try store.start(
            jobID: jobID,
            jobName: "Kitchen remodel",
            hourlyCost: 50,
            at: startedAt
        )

        let restored = LaborTimerStore(defaults: defaults)
        let session = try #require(restored.session)
        #expect(session.jobID == jobID)
        #expect(session.isRunning)
        #expect(session.durationHours(at: startedAt.addingTimeInterval(5_400)) == Decimal(string: "1.5"))
        #expect(session.cost(at: startedAt.addingTimeInterval(5_400)) == 75)
    }

    @Test func blocksSecondTimerAndPersistsStoppedReview() throws {
        let suiteName = "LaborTimerStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let startedAt = Date(timeIntervalSince1970: 1_788_000_000)
        let store = LaborTimerStore(defaults: defaults)

        try store.start(jobID: UUID(), jobName: "Deck", hourlyCost: 60, at: startedAt)
        #expect(throws: LaborTimerError.self) {
            try store.start(jobID: UUID(), jobName: "Fence", hourlyCost: 60, at: startedAt)
        }

        try store.stop(at: startedAt.addingTimeInterval(3_600))
        try store.updateReview(hourlyCost: 65, note: "  Framing  ")

        let restored = LaborTimerStore(defaults: defaults)
        #expect(restored.session?.isRunning == false)
        #expect(restored.session?.hourlyCost == 65)
        #expect(restored.session?.note == "Framing")

        restored.discard()
        #expect(LaborTimerStore(defaults: defaults).session == nil)
    }

    @Test func canStartImmediatelyWithoutARateAndAddItDuringReview() throws {
        let suiteName = "LaborTimerStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LaborTimerStore(defaults: defaults)

        try store.start(jobID: UUID(), jobName: "Roof repair", hourlyCost: 0)
        #expect(store.session?.isRunning == true)
        #expect(store.session?.hourlyCost == 0)

        try store.stop()
        try store.updateReview(hourlyCost: 72, note: "Flashing")
        #expect(store.session?.hourlyCost == 72)
        #expect(store.session?.note == "Flashing")
    }
}
