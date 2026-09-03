import RevenueCat
import RevenueCatUI
import SwiftUI

/// Which paywall implementation the app presents.
///
/// Declared once so switching is a one-line change here rather than an audit of
/// every gate. The custom paywall is the default while it is the better-designed
/// of the two; the RevenueCat option stays wired up so a dashboard-authored
/// paywall can be A/B tested without touching feature code.
nonisolated enum PaywallPresentationMode: Sendable {
    case custom
    case revenueCat
}

/// The single place that decides how a paywall is shown.
nonisolated enum PaywallPresenter {
    static let mode: PaywallPresentationMode = .custom
}

extension SubscriptionStore {

    /// Gates `feature`, routing to the paywall when it is locked.
    ///
    /// This is the only entitlement check feature code should perform. It keeps
    /// `isPro` out of call sites and guarantees every gate presents the same
    /// paywall with the context that triggered it.
    ///
    /// - Returns: `true` when the caller may proceed.
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

    /// Whether `feature` is unlocked, without presenting anything.
    ///
    /// For places that must *adapt* rather than interrupt — silently skipping an
    /// automatic enhancement, or rendering an inline upsell. Presenting a paywall
    /// the customer did not ask for is how a gate turns hostile.
    func isUnlocked(_ feature: ProFeature) -> Bool {
        isPro
    }

    /// The active-job gate, which depends on how many jobs are already running
    /// rather than on the entitlement alone.
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

    /// Presents the paywall for whichever feature was gated.
    ///
    /// Presentation is local to each gate — SwiftUI cannot show two sheets from
    /// one host — while the paywall itself and the custom/RevenueCat switch stay
    /// centralized here.
    ///
    /// - Parameter onUnlocked: run when the paywall closes with the entitlement
    ///   active, carrying the feature that raised it. Gates use it to resume the
    ///   action the customer originally tapped, so buying Pro to start a timer
    ///   starts the timer rather than returning them to the button.
    func proPaywall(
        for feature: Binding<ProFeature?>,
        onUnlocked: @escaping (ProFeature) -> Void = { _ in }
    ) -> some View {
        modifier(ProPaywallModifier(feature: feature, onUnlocked: onUnlocked))
    }

    /// Presents the general paywall, with no feature context.
    ///
    /// For entry points the customer chose deliberately — the Settings upgrade
    /// row — where nothing was interrupted and the broad pitch is the honest one.
    func proPaywall(isPresented: Binding<Bool>) -> some View {
        modifier(GeneralProPaywallModifier(isPresented: isPresented))
    }

    /// Binds an alert to ``SubscriptionStore/errorMessage``.
    func subscriptionErrorAlert() -> some View {
        modifier(SubscriptionErrorAlert())
    }
}

private struct ProPaywallModifier: ViewModifier {
    @Binding var feature: ProFeature?
    let onUnlocked: (ProFeature) -> Void

    @EnvironmentObject private var store: SubscriptionStore

    /// Remembered across the dismissal because `feature` is nil by the time
    /// `onDismiss` runs — `sheet(item:)` clears the binding to close the sheet.
    @State private var pendingFeature: ProFeature?

    func body(content: Content) -> some View {
        content.sheet(item: $feature) { feature in
            Group {
                switch PaywallPresenter.mode {
                case .custom:
                    MarginRunPaywall(feature: feature)

                case .revenueCat:
                    RevenueCatPaywall()
                }
            }
            .onAppear { pendingFeature = feature }
        }
        .onChange(of: feature) { previous, current in
            guard current == nil, let resumed = pendingFeature ?? previous else { return }
            pendingFeature = nil
            // Only resume on a real unlock. A customer who closed the paywall
            // chose not to buy, and re-triggering their action would be hostile.
            guard store.isPro else { return }
            onUnlocked(resumed)
        }
    }
}

/// The dashboard-authored paywall, kept behind ``PaywallPresenter/mode``.
private struct GeneralProPaywallModifier: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            // Same component and same mode switch as every contextual gate;
            // only the hero differs.
            switch PaywallPresenter.mode {
            case .custom:
                MarginRunPaywall(feature: nil)
            case .revenueCat:
                RevenueCatPaywall()
            }
        }
    }
}

private struct RevenueCatPaywall: View {
    @EnvironmentObject private var store: SubscriptionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PaywallView(displayCloseButton: true)
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
