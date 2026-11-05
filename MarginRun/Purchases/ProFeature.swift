import Foundation

/// The capability a customer reached for when the paywall was raised.
///
/// The paywall is one component; this is the only thing that varies between
/// entry points. Six separate paywalls would be six things to keep in sync.
nonisolated enum ProFeature: String, CaseIterable, Identifiable, Sendable {
    case unlimitedJobs
    case receiptScan
    case laborTimer
    case insights
    case marginAlerts
    case extraRevenue

    var id: String { rawValue }

    /// Speaks to the moment the customer was interrupted. The general headline
    /// is the fallback, not the norm — a gate that names what you just tried to
    /// do reads as an explanation rather than a toll booth.
    var headline: String {
        switch self {
        case .unlimitedJobs: "Keep every active job on track."
        case .receiptScan: "Turn receipts into job costs in seconds."
        case .laborTimer: "Track labor while the work happens."
        case .insights: "See which jobs actually make you money."
        case .marginAlerts: "Catch overruns before they erase profit."
        case .extraRevenue: "See how added work affects profit before you accept it."
        }
    }

    var subheadline: String {
        switch self {
        case .unlimitedJobs:
            "Free covers \(FreePlanLimits.maxActiveJobs) active jobs. Pro removes the limit so nothing waits."
        case .receiptScan:
            "Pro reads the vendor, total, and date off the photo so you don't type them."
        case .laborTimer:
            // MarginRun tracks what labor *costs* the job. Plenty of contractors
            // don't bill by the hour, so the copy never implies they do.
            "Start the timer on site and MarginRun tracks your hours and labor cost automatically."
        case .insights:
            "Pro shows margin, estimate accuracy, and cost patterns across finished jobs."
        case .marginAlerts:
            "Pro watches every active budget and tells you the moment one slips."
        case .extraRevenue:
            "Pro tracks change orders and add-ons alongside the original contract."
        }
    }

    var systemImage: String {
        switch self {
        case .unlimitedJobs: "hammer.fill"
        case .receiptScan: "doc.text.viewfinder"
        case .laborTimer: "timer"
        case .insights: "chart.line.uptrend.xyaxis"
        case .marginAlerts: "bell.badge.fill"
        case .extraRevenue: "plus.circle.fill"
        }
    }

    /// Names the outcome behind the gate instead of presenting every surface
    /// as the same generic upgrade. The paywall still comes first, so these
    /// labels describe what the customer is exploring rather than pretending
    /// the locked action has already happened.
    var upgradeActionTitle: String {
        switch self {
        case .unlimitedJobs: "Explore Unlimited Jobs"
        case .receiptScan: "Explore Receipt Scanning"
        case .laborTimer: "Explore Labor Timer"
        case .insights: "Explore Profit Insights"
        case .marginAlerts: "Explore Margin Alerts"
        case .extraRevenue: "Explore Change Orders"
        }
    }

    /// This capability stated as a benefit, for the paywall's feature rows.
    var benefit: ProBenefit {
        switch self {
        case .unlimitedJobs:
            ProBenefit(
                systemImage: systemImage,
                title: "Unlimited active jobs",
                outcome: "Run unlimited jobs at the same time."
            )
        case .receiptScan:
            ProBenefit(
                systemImage: systemImage,
                title: "Automatic receipt scanning",
                outcome: "Turn receipts into job costs in seconds."
            )
        case .laborTimer:
            ProBenefit(
                systemImage: systemImage,
                title: "Built-in labor timer",
                outcome: "Never reconstruct hours at the end of the week."
            )
        case .insights, .marginAlerts:
            // One row, because they are one idea to a contractor: the app
            // watching the money and telling you when it moves.
            ProBenefit(
                systemImage: "chart.line.uptrend.xyaxis",
                title: "Margin alerts & insights",
                outcome: "Catch overruns before they erase profit."
            )
        case .extraRevenue:
            ProBenefit(
                systemImage: systemImage,
                title: "Change orders & add-ons",
                outcome: "See what extra work really adds to your profit."
            )
        }
    }
}

/// The general pitch, used when no single feature prompted the paywall.
nonisolated enum ProPitch {
    static let headline = "Know what every job is really making."
    static let subheadline =
        "Track costs, catch overruns, and protect your margin before the job is finished."

    /// How many rows a paywall shows. Three is the point where each one is
    /// still read; a full feature list is a list nobody finishes.
    static let benefitCount = 3

    /// What the broad pitch leads with, for the deliberate Settings entry point
    /// where nothing was interrupted.
    static let generalOrder: [ProFeature] = [.unlimitedJobs, .receiptScan, .insights]

    /// The rows to show when the paywall was raised by `feature`.
    ///
    /// The capability the customer just reached for always leads — the rest is
    /// context for a decision they have already started making. Derived rather
    /// than hand-written per feature so six lists cannot drift apart.
    static func benefits(for feature: ProFeature?) -> [ProBenefit] {
        let candidates: [ProFeature] = switch feature {
        case .unlimitedJobs:
            [.unlimitedJobs, .insights, .receiptScan]
        case .receiptScan:
            [.receiptScan, .unlimitedJobs, .insights]
        case .laborTimer:
            [.laborTimer, .receiptScan, .insights]
        case .insights:
            [.insights, .unlimitedJobs, .receiptScan]
        case .marginAlerts:
            [.marginAlerts, .unlimitedJobs, .receiptScan]
        case .extraRevenue:
            [.extraRevenue, .insights, .receiptScan]
        case nil:
            generalOrder
        }

        var rows: [ProBenefit] = []
        var seen: Set<String> = []

        for candidate in candidates {
            let benefit = candidate.benefit
            guard seen.insert(benefit.title).inserted else { continue }
            rows.append(benefit)
            if rows.count == benefitCount { break }
        }

        return rows
    }

    /// The rows for the general pitch.
    static var benefits: [ProBenefit] { benefits(for: nil) }
}

nonisolated struct ProBenefit: Identifiable, Equatable, Sendable {
    let systemImage: String
    let title: String
    let outcome: String

    var id: String { title }
}
