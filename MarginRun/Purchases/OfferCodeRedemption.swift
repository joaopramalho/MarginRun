import Combine
import StoreKit
import SwiftUI

/// Ephemeral presentation state for Apple's offer-code sheet.
///
/// The code itself never enters MarginRun: this object only controls whether
/// StoreKit's system UI is visible and forwards its completion result to the
/// existing RevenueCat-backed subscription store.
@MainActor
final class OfferCodeRedemptionPresentation: ObservableObject {
    @Published var isPresented = false

    func present(using store: SubscriptionStore, from source: OfferCodeRedemptionSource) {
        guard !isPresented else { return }
        store.offerCodeRedemptionOpened(from: source)
        isPresented = true
    }

    func presentationFinished() {
        isPresented = false
    }
}

private struct OfferCodeRedemptionModifier: ViewModifier {
    @EnvironmentObject private var store: SubscriptionStore

    @ObservedObject var presentation: OfferCodeRedemptionPresentation
    let source: OfferCodeRedemptionSource

    func body(content: Content) -> some View {
        content.offerCodeRedemption(isPresented: $presentation.isPresented) { result in
            presentation.presentationFinished()
            Task {
                await store.offerCodeRedemptionFinished(result, from: source)
            }
        }
    }
}

extension View {
    /// Presents Apple's official App Store offer-code UI.
    ///
    /// iOS 17 is the app's deployment target, so this is available everywhere
    /// MarginRun runs. StoreKit owns entry and validation; the app never sees
    /// or stores the code.
    func appStoreOfferCodeRedemption(
        presentation: OfferCodeRedemptionPresentation,
        source: OfferCodeRedemptionSource
    ) -> some View {
        modifier(OfferCodeRedemptionModifier(presentation: presentation, source: source))
    }
}
