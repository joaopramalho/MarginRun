import SwiftUI

/// Shows `content` to Pro subscribers and a value-led locked state to everyone
/// else, routing through the same paywall as every other gate.
///
/// For whole screens. Single actions should call
/// ``SubscriptionStore/requirePro(_:presenting:)`` instead.
struct ProGate<Content: View, Teaser: View>: View {
    let feature: ProFeature
    /// Overrides the feature's stock headline when the screen can say something
    /// more specific from the customer's own data.
    var title: String?
    var message: String?
    @ViewBuilder let teaser: () -> Teaser
    @ViewBuilder let content: () -> Content

    @EnvironmentObject private var store: SubscriptionStore
    @State private var paywallFeature: ProFeature?

    var body: some View {
        if store.isPro {
            content()
        } else {
            ProLockedView(
                title: title ?? feature.headline,
                message: message ?? feature.subheadline,
                systemImage: feature.systemImage,
                teaser: teaser,
                // Through `requirePro` rather than setting the binding, so the
                // locked screen reports `pro_feature_attempted` like every
                // other gate.
                unlock: { store.requirePro(feature, presenting: $paywallFeature) }
            )
            .proPaywall(for: $paywallFeature)
            .subscriptionErrorAlert()
        }
    }
}

extension ProGate where Teaser == EmptyView {
    init(
        feature: ProFeature,
        title: String? = nil,
        message: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            feature: feature,
            title: title,
            message: message,
            teaser: { EmptyView() },
            content: content
        )
    }
}

/// The locked state.
///
/// Proof arrives before the ask: the customer sees the shape of the answer,
/// built from their own data, and only then the button.
private struct ProLockedView<Teaser: View>: View {
    let title: String
    let message: String
    let systemImage: String
    @ViewBuilder let teaser: () -> Teaser
    let unlock: () -> Void

    @EnvironmentObject private var store: SubscriptionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.largeTitle)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)

                    Text(title)
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                teaser()

                VStack(spacing: 10) {
                    Button(action: unlock) {
                        Text("Unlock MarginRun Pro")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("unlockProButton")

                    // Deliberately quieter than the primary action: two buttons
                    // of equal weight split attention, and restore is rarer.
                    Button("Restore purchases") {
                        Task { await store.restorePurchases(from: .proGate) }
                    }
                    .font(.footnote)
                    .disabled(store.isRestoring)
                    .accessibilityIdentifier("restorePurchasesButton")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A single Pro-only metric, shown with its value withheld.
struct LockedMetricRow: View {
    let label: String
    let placeholder: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer(minLength: 12)
            Text(placeholder)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .redacted(reason: .placeholder)
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), locked")
    }
}

/// An inline row offering a Pro capability at the moment it would have helped.
///
/// Used where the free path still works — attaching a receipt, logging labor by
/// hand — so the upsell explains what Pro would have done instead of blocking.
struct ProUpsellRow: View {
    let feature: ProFeature
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: feature.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
