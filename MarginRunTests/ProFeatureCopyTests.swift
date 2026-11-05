import Foundation
import Testing
@testable import MarginRun

/// The paywall reuses one component and swaps only the hero and the leading
/// benefit, so a case added without copy would silently ship an empty headline.
@MainActor
struct ProFeatureCopyTests {

    @Test func everyFeatureHasContextualCopy() {
        for feature in ProFeature.allCases {
            #expect(!feature.headline.isEmpty, "missing headline for \(feature.rawValue)")
            #expect(!feature.subheadline.isEmpty, "missing subheadline for \(feature.rawValue)")
            #expect(!feature.systemImage.isEmpty, "missing symbol for \(feature.rawValue)")
            #expect(!feature.benefit.title.isEmpty, "missing benefit for \(feature.rawValue)")
            #expect(!feature.benefit.outcome.isEmpty, "missing outcome for \(feature.rawValue)")
            #expect(feature.upgradeActionTitle.hasPrefix("Explore "))
        }
    }

    @Test func contextualHeadlinesAreDistinctFromEachOther() {
        let headlines = Set(ProFeature.allCases.map(\.headline))
        #expect(headlines.count == ProFeature.allCases.count)
    }

    /// MarginRun tracks what labor *costs* a job. Plenty of contractors don't
    /// bill by the hour, so no copy may imply that hours are billed.
    @Test func laborCopyTalksAboutTrackingRatherThanBilling() {
        let laborCopy = [
            ProFeature.laborTimer.headline,
            ProFeature.laborTimer.subheadline,
            ProFeature.laborTimer.benefit.title,
            ProFeature.laborTimer.benefit.outcome,
        ]

        for line in laborCopy {
            #expect(
                line.localizedCaseInsensitiveContains("bill") == false,
                "labor copy should not imply hours are billed: \(line)"
            )
        }
    }

    @Test func noBenefitAnywhereClaimsHoursAreBilled() {
        let everyBenefit = ProFeature.allCases.map(\.benefit) + ProPitch.benefits

        for benefit in everyBenefit {
            #expect(benefit.outcome.localizedCaseInsensitiveContains("bill the hours") == false)
        }
    }

    // MARK: - Benefit rows

    /// Three rows is a deliberate cap: it is what keeps both plans above the
    /// fold on a normal phone.
    @Test func everyContextShowsExactlyThreeBenefits() {
        for feature in ProFeature.allCases {
            #expect(
                ProPitch.benefits(for: feature).count == ProPitch.benefitCount,
                "wrong row count for \(feature.rawValue)"
            )
        }
        #expect(ProPitch.benefits.count == ProPitch.benefitCount)
    }

    @Test func theGatedCapabilityAlwaysLeads() {
        for feature in ProFeature.allCases {
            #expect(
                ProPitch.benefits(for: feature).first == feature.benefit,
                "\(feature.rawValue) should lead its own paywall"
            )
        }
    }

    @Test func benefitRowsAreNeverRepeatedWithinAPaywall() {
        for feature in ProFeature.allCases {
            let titles = ProPitch.benefits(for: feature).map(\.title)
            #expect(Set(titles).count == titles.count, "duplicate row for \(feature.rawValue)")
        }
    }

    /// The reviewed hierarchy for the labor timer context, pinned so a later
    /// reordering of the supporting list is a deliberate change.
    @Test func theLaborTimerPaywallShowsTheReviewedHierarchy() {
        let titles = ProPitch.benefits(for: .laborTimer).map(\.title)

        #expect(
            titles == [
                "Built-in labor timer",
                "Automatic receipt scanning",
                "Margin alerts & insights",
            ]
        )
    }

    @Test func coreContextsPrioritizeTheCustomersIntent() {
        #expect(ProPitch.benefits(for: .insights).map(\.title) == [
            "Margin alerts & insights",
            "Unlimited active jobs",
            "Automatic receipt scanning",
        ])
        #expect(ProPitch.benefits(for: .unlimitedJobs).map(\.title) == [
            "Unlimited active jobs",
            "Margin alerts & insights",
            "Automatic receipt scanning",
        ])
        #expect(ProPitch.benefits(for: .receiptScan).map(\.title) == [
            "Automatic receipt scanning",
            "Unlimited active jobs",
            "Margin alerts & insights",
        ])
    }

    /// Alerts and insights are one idea to a contractor, so they share a row —
    /// and either gate must lead with it.
    @Test func alertsAndInsightsShareOneRow() {
        #expect(ProFeature.insights.benefit == ProFeature.marginAlerts.benefit)
        #expect(
            ProPitch.benefits(for: .marginAlerts).first?.title == "Margin alerts & insights"
        )
    }

    @Test func benefitsPairAFeatureWithAnOutcome() {
        for benefit in ProPitch.benefits {
            #expect(!benefit.title.isEmpty)
            #expect(!benefit.outcome.isEmpty)
            #expect(benefit.title != benefit.outcome)
        }
    }

    @Test func theGeneralPitchLeadsWithTheFreeLimit() {
        #expect(ProPitch.benefits.first?.title == "Unlimited active jobs")
    }
}
