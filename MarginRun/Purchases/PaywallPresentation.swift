import RevenueCat
import RevenueCatUI
import SwiftUI

/// Remote value stored in the current RevenueCat Offering metadata.
nonisolated enum PaywallMode: String, Sendable {
    static let metadataKey = "paywall_mode"

    case native
    case revenueCat = "revenuecat"

    /// Native is deliberately the safe default for missing/invalid metadata and
    /// whenever the Offering has no dashboard-authored RevenueCat paywall.
    static func resolve(
        metadataValue: String?,
        offeringAvailable: Bool = true,
        revenueCatPaywallAvailable: Bool
    ) -> PaywallMode {
        guard offeringAvailable else { return .native }
        guard
            let normalized = metadataValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
            let requested = PaywallMode(rawValue: normalized)
        else { return .native }

        guard requested != .revenueCat || revenueCatPaywallAvailable else { return .native }
        return requested
    }
}

/// The resolved destination retains the exact Offering that chose it.
enum PaywallRoute {
    case native
    case revenueCat(Offering)

    var source: PaywallSource {
        switch self {
        case .native: .native
        case .revenueCat: .revenueCat
        }
    }
}

extension SubscriptionStore {
    @discardableResult
    func requirePro(
        _ feature: ProFeature,
        presenting paywall: Binding<ProFeature?>
    ) -> Bool {
        guard !isPro else { return true }
        trackProFeatureAttempt(feature)
        paywall.wrappedValue = feature
        return false
    }

    func isUnlocked(_ feature: ProFeature) -> Bool {
        isPro
    }

    @discardableResult
    func requireActiveJobSlot(
        activeJobCount: Int,
        presenting paywall: Binding<ProFeature?>
    ) -> Bool {
        guard !FreePlanLimits.canCreateActiveJob(isPro: isPro, activeJobCount: activeJobCount) else {
            return true
        }
        trackProFeatureAttempt(.unlimitedJobs)
        paywall.wrappedValue = .unlimitedJobs
        return false
    }
}

extension View {
    func proPaywall(
        for feature: Binding<ProFeature?>,
        onUnlocked: @escaping (ProFeature) -> Void = { _ in }
    ) -> some View {
        modifier(ProPaywallModifier(feature: feature, onUnlocked: onUnlocked))
    }

    func proPaywall(isPresented: Binding<Bool>) -> some View {
        modifier(GeneralProPaywallModifier(isPresented: isPresented))
    }

    func subscriptionErrorAlert() -> some View {
        modifier(SubscriptionErrorAlert())
    }
}

private struct ProPaywallModifier: ViewModifier {
    @Binding var feature: ProFeature?
    let onUnlocked: (ProFeature) -> Void

    @EnvironmentObject private var store: SubscriptionStore
    @State private var pendingFeature: ProFeature?

    func body(content: Content) -> some View {
        content.sheet(item: $feature) { feature in
            RoutedPaywall(feature: feature)
                .onAppear { pendingFeature = feature }
        }
        .onChange(of: feature) { previous, current in
            guard current == nil, let resumed = pendingFeature ?? previous else { return }
            pendingFeature = nil
            guard store.isPro else { return }
            onUnlocked(resumed)
        }
    }
}

private struct GeneralProPaywallModifier: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            RoutedPaywall(feature: nil)
        }
    }
}

/// Every entry point lands here. The current Offering is loaded once, its
/// metadata selects the renderer, and all failure paths resolve to native.
private struct RoutedPaywall: View {
    let feature: ProFeature?

    @EnvironmentObject private var store: SubscriptionStore
    @EnvironmentObject private var analytics: AnalyticsService
    @State private var route: PaywallRoute?
    @State private var analyticsReporter = PaywallAnalyticsReporter()

    var body: some View {
        Group {
            switch route {
            case nil:
                ProgressView("Loading plans…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .native:
                MarginRunPaywall(feature: feature, loadsOfferingOnAppear: false)

            case .revenueCat(let offering):
                RevenueCatPaywall(offering: offering, feature: feature)
            }
        }
        .task {
            let resolved = await store.resolvePaywallRoute()
            route = resolved
            analyticsReporter.reportIfNeeded(
                feature: feature,
                source: resolved.source,
                analytics: analytics
            )
        }
    }
}

private struct RevenueCatPaywall: View {
    let offering: Offering
    let feature: ProFeature?

    @EnvironmentObject private var store: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @State private var pendingPackage: Package?

    var body: some View {
        PaywallView(offering: offering, displayCloseButton: true)
            .onPurchaseStarted { package in
                pendingPackage = package
                store.revenueCatPaywallPurchaseStarted(package: package, feature: feature)
            }
            .onPurchaseCompleted { _, customerInfo in
                store.revenueCatPaywallPurchaseCompleted(
                    package: pendingPackage,
                    customerInfo: customerInfo,
                    feature: feature
                )
                pendingPackage = nil
                if store.isPro { dismiss() }
            }
            .onPurchaseCancelled {
                store.revenueCatPaywallPurchaseCancelled(package: pendingPackage, feature: feature)
                pendingPackage = nil
            }
            .onPurchaseFailure { error in
                store.revenueCatPaywallPurchaseFailed(
                    package: pendingPackage,
                    feature: feature,
                    error: error
                )
                pendingPackage = nil
            }
            .onRestoreStarted {
                store.revenueCatPaywallRestoreStarted()
            }
            .onRestoreCompleted { customerInfo in
                store.revenueCatPaywallRestoreCompleted(customerInfo: customerInfo)
                if store.isPro { dismiss() }
            }
            .onRestoreFailure { error in
                store.revenueCatPaywallRestoreFailed(error: error)
            }
            .onChange(of: store.isPro) { _, isPro in
                if isPro { dismiss() }
            }
    }
}

private struct SubscriptionErrorAlert: ViewModifier {
    @EnvironmentObject private var store: SubscriptionStore

    func body(content: Content) -> some View {
        content.alert(
            "Something went wrong",
            isPresented: $store.isShowingError
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}
