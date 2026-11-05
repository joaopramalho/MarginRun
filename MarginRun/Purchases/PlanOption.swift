import Foundation
import RevenueCat

/// One purchasable plan, prepared for display.
///
/// Built from the offering so the paywall stays declarative, prices are never
/// hardcoded, and the arithmetic below stays independently testable.
nonisolated struct PlanOption: Identifiable, Equatable {
    let packageIdentifier: String
    /// Uppercased in the UI, e.g. `"YEARLY"`.
    let title: String
    /// Localized by StoreKit, e.g. `"$119.99"`. Never assembled by hand.
    let price: String
    /// e.g. `"/year"`. `nil` for one-time purchases.
    let periodSuffix: String?
    /// The anchor that makes an annual price legible, e.g. `"$9.99/mo billed yearly"`.
    let equivalentLine: String?
    /// StoreKit-backed free-trial copy, present only when RevenueCat reports
    /// both an introductory free trial and current-user eligibility.
    let trial: TrialOfferDisplay?
    /// e.g. `"BEST VALUE · SAVE 33%"`. Only the recommended plan carries one,
    /// and the percentage is always computed from the two live prices.
    let badge: String?
    /// Renewal wording for the selected plan.
    let terms: String
    /// Stable across price and identifier changes, so UI tests never depend on
    /// marketing copy or on the dashboard's package naming.
    let accessibilityIdentifier: String
    /// Which product this is, for the `plan` analytics property. Categorical —
    /// no price ever leaves the app.
    let analyticsPlan: AnalyticsPlan

    var id: String { packageIdentifier }

    /// The button names the actual decision being made. A customer choosing
    /// Monthly should not see the same generic action as an eligible Yearly
    /// trial, and an ineligible customer must never see trial language.
    var purchaseButtonTitle: String {
        if let trial { return trial.callToAction }

        return switch analyticsPlan {
        case .yearly: "Continue with Yearly"
        case .monthly: "Continue with Monthly"
        case .other: "Continue"
        }
    }
}

/// Display information derived from an eligible StoreKit introductory offer.
nonisolated struct TrialOfferDisplay: Equatable, Sendable {
    let duration: String
    let renewalLine: String

    var summary: String { "\(duration) free" }

    /// Turns the StoreKit-derived duration into concise action copy. The
    /// fallback stays truthful for an SDK unit we do not recognize.
    var callToAction: String {
        let parts = duration.split(separator: " ")
        guard parts.count == 2, Int(parts[0]) != nil else { return "Start Free Trial" }

        let unit = parts[1].hasSuffix("s") ? parts[1].dropLast() : parts[1][...]
        return "Start \(parts[0])-\(unit.capitalized) Free Trial"
    }
}

/// Pricing arithmetic for the paywall.
nonisolated enum PlanPricing {

    /// How much cheaper `monthlyEquivalent` is than paying `monthlyReference`
    /// every month, as a whole percentage.
    ///
    /// This is the anchor that makes an annual plan legible: without it the
    /// customer compares a large yearly number against a small monthly one and
    /// the yearly plan reads as more expensive.
    ///
    /// - Returns: `nil` when either price is non-positive, when the candidate is
    ///   not actually cheaper, or when the saving is too small to be worth a
    ///   badge — an honest "Save 2%" undersells the plan more than no badge.
    static func savingsPercent(
        monthlyEquivalent: Decimal,
        monthlyReference: Decimal,
        minimumWorthShowing: Int = 5
    ) -> Int? {
        guard monthlyEquivalent > 0, monthlyReference > 0 else { return nil }
        guard monthlyEquivalent < monthlyReference else { return nil }

        let ratio = (monthlyReference - monthlyEquivalent) / monthlyReference
        var scaled = ratio * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)

        let percent = (rounded as NSDecimalNumber).intValue
        guard percent >= minimumWorthShowing else { return nil }
        return percent
    }

    /// The badge on the recommended plan.
    ///
    /// "BEST VALUE" says why it leads; the percentage says by how much, and is
    /// only claimed when the two live prices actually support it. A hardcoded
    /// number becomes a lie the day pricing changes.
    static func recommendedBadge(savingsPercent: Int?) -> String {
        guard let savingsPercent else { return "BEST VALUE" }
        return "BEST VALUE · SAVE \(savingsPercent)%"
    }
}

extension PlanOption {

    /// Builds the display list for `offering`, recommended plan first.
    ///
    /// Returns an empty array when the offering carries nothing purchasable, so
    /// the paywall can show its unavailable state instead of an empty picker.
    static func options(
        from offering: Offering,
        introEligibilityByProductID: [String: IntroEligibilityStatus] = [:]
    ) -> [PlanOption] {
        let monthlyReference = offering.monthly?.storeProduct.price
        var options: [PlanOption] = []

        if let annual = offering.annual {
            // Savings are always derived from the two live prices. A hardcoded
            // percentage silently becomes a lie the first time pricing changes.
            let savings = (annual.storeProduct.pricePerMonth as Decimal?).flatMap { perMonth in
                monthlyReference.flatMap {
                    PlanPricing.savingsPercent(monthlyEquivalent: perMonth, monthlyReference: $0)
                }
            }
            let trial = eligibleFreeTrial(
                for: annual,
                plan: .yearly,
                eligibility: introEligibilityByProductID[annual.storeProduct.productIdentifier]
            )

            options.append(
                PlanOption(
                    packageIdentifier: annual.identifier,
                    title: "Yearly",
                    price: annual.localizedPriceString,
                    periodSuffix: "/year",
                    equivalentLine: annual.storeProduct.localizedPricePerMonth.map {
                        "\($0)/mo billed yearly"
                    },
                    trial: trial,
                    badge: PlanPricing.recommendedBadge(savingsPercent: savings),
                    terms: trial.map {
                        "\($0.summary), then \(annual.localizedPriceString)/year. Renews automatically until cancelled."
                    } ?? "Renews yearly until cancelled.",
                    accessibilityIdentifier: "planYearly",
                    analyticsPlan: .yearly
                )
            )
        }

        if let monthly = offering.monthly {
            options.append(
                PlanOption(
                    packageIdentifier: monthly.identifier,
                    title: "Monthly",
                    price: monthly.localizedPriceString,
                    periodSuffix: "/month",
                    equivalentLine: nil,
                    // Monthly never advertises a trial. The product must remain
                    // trial-free in App Store Connect as well; this protects the
                    // native copy if a dashboard product is misconfigured.
                    trial: nil,
                    badge: nil,
                    terms: "Renews monthly until cancelled.",
                    accessibilityIdentifier: "planMonthly",
                    analyticsPlan: .monthly
                )
            )
        }


        // Anything custom the dashboard adds later still sells rather than
        // silently disappearing from the paywall — except lifetime, which
        // MarginRun no longer offers. Excluding it explicitly means an old
        // package left attached to the offering cannot reappear here.
        var known = Set(options.map(\.packageIdentifier))
        known.insert(RevenueCatConfig.PackageID.lifetime)
        for package in offering.availablePackages where !known.contains(package.identifier) {
            options.append(
                PlanOption(
                    packageIdentifier: package.identifier,
                    title: package.storeProduct.localizedTitle.isEmpty
                        ? package.identifier
                        : package.storeProduct.localizedTitle,
                    price: package.localizedPriceString,
                    periodSuffix: nil,
                    equivalentLine: nil,
                    trial: nil,
                    badge: nil,
                    terms: "",
                    accessibilityIdentifier: "plan_\(package.identifier)",
                    analyticsPlan: .other
                )
            )
        }

        return options
    }

    /// A trial is shown only when all authoritative facts agree: Yearly is the
    /// selected plan, StoreKit exposes a free-trial introductory discount, and
    /// RevenueCat says this customer is eligible. Unknown is deliberately
    /// treated as ineligible so the paywall never makes a promise it cannot keep.
    static func eligibleFreeTrial(
        for package: Package,
        plan: AnalyticsPlan,
        eligibility: IntroEligibilityStatus?
    ) -> TrialOfferDisplay? {
        guard plan == .yearly,
              eligibility == .eligible,
              let discount = package.storeProduct.introductoryDiscount,
              discount.paymentMode == .freeTrial else { return nil }

        return TrialOfferDisplay(
            duration: trialDuration(discount),
            renewalLine: "Then \(package.localizedPriceString)/year"
        )
    }

    private static func trialDuration(_ discount: StoreProductDiscount) -> String {
        let count = discount.subscriptionPeriod.value * discount.numberOfPeriods
        switch discount.subscriptionPeriod.unit {
        case .day:
            return unitText(count, singular: "day")
        case .week:
            // A one-week App Store trial is the requested seven-day offer. Use
            // the product period as the source, not a locally timed countdown.
            return count == 1 ? "7 days" : unitText(count, singular: "week")
        case .month:
            return unitText(count, singular: "month")
        case .year:
            return unitText(count, singular: "year")
        @unknown default:
            return "Introductory period"
        }
    }

    private static func unitText(_ count: Int, singular: String) -> String {
        "\(count) \(count == 1 ? singular : singular + "s")"
    }
}
