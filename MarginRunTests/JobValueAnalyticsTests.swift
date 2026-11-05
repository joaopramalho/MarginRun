import Foundation
import Testing
@testable import MarginRun

struct JobValueAnalyticsTests {
    @Test func bucketBoundariesAreExplicitAndStable() {
        #expect(JobValueAnalytics.bucket(for: 0) == .under1K)
        #expect(JobValueAnalytics.bucket(for: 999) == .under1K)
        #expect(JobValueAnalytics.bucket(for: 1_000) == .oneTo5K)
        #expect(JobValueAnalytics.bucket(for: 4_999) == .oneTo5K)
        #expect(JobValueAnalytics.bucket(for: 5_000) == .fiveTo10K)
        #expect(JobValueAnalytics.bucket(for: 9_999) == .fiveTo10K)
        #expect(JobValueAnalytics.bucket(for: 10_000) == .tenTo25K)
        #expect(JobValueAnalytics.bucket(for: 24_999) == .tenTo25K)
        #expect(JobValueAnalytics.bucket(for: 25_000) == .twentyFiveTo50K)
        #expect(JobValueAnalytics.bucket(for: 49_999) == .twentyFiveTo50K)
        #expect(JobValueAnalytics.bucket(for: 50_000) == .fiftyTo100K)
        #expect(JobValueAnalytics.bucket(for: 99_999) == .fiftyTo100K)
        #expect(JobValueAnalytics.bucket(for: 100_000) == .hundredKPlus)
        #expect(JobValueAnalytics.bucket(for: 500_000) == .hundredKPlus)
    }

    @Test func roundingIsCoarseDeterministicAndDoesNotInflateSmallJobs() {
        #expect(JobValueAnalytics.roundedValue(for: -100) == 0)
        #expect(JobValueAnalytics.roundedValue(for: 0) == 0)
        #expect(JobValueAnalytics.roundedValue(for: 499) == 0)
        #expect(JobValueAnalytics.roundedValue(for: 999) == 0)
        #expect(JobValueAnalytics.roundedValue(for: 1_000) == 1_000)
        #expect(JobValueAnalytics.roundedValue(for: 1_499) == 1_000)
        #expect(JobValueAnalytics.roundedValue(for: 1_500) == 2_000)
        #expect(JobValueAnalytics.roundedValue(for: 10_437) == 10_000)
        #expect(JobValueAnalytics.roundedValue(for: 10_740) == 11_000)
    }

    @Test func currencyUsesISOCodeWithoutAssumingUSD() {
        #expect(JobValueAnalytics.currencyCode(locale: Locale(identifier: "en_US")) == "USD")
        #expect(JobValueAnalytics.currencyCode(locale: Locale(identifier: "pt_BR")) == "BRL")
        #expect(JobValueAnalytics(value: 10_000, currency: " brl ").currency == "BRL")
        #expect(JobValueAnalytics(value: 10_000, currency: " ").currency == "XXX")
    }

    @Test func reopenAndSecondCompletionCannotClaimAnotherAggregateEvent() {
        let job = Job(
            name: "Private job",
            customerName: "Private customer",
            contractValue: 15_000,
            targetMargin: 30,
            estimatedMaterials: 4_000,
            estimatedLabor: 3_000,
            estimatedSubcontractors: 0,
            estimatedEquipment: 0,
            estimatedOther: 0
        )

        #expect(job.markCompletionAnalyticsReportedIfNeeded() == false)
        job.complete()
        #expect(job.markCompletionAnalyticsReportedIfNeeded() == true)
        #expect(job.hasReportedCompletionAnalytics)

        job.discardCompletion()
        #expect(job.hasReportedCompletionAnalytics)
        job.complete()

        #expect(job.markCompletionAnalyticsReportedIfNeeded() == false)
    }
}
