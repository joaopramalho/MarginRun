import RevenueCat
import SwiftUI

/// MarginRun's own subscription screen.
///
/// Reads as a financial tool rather than a generic upsell: restrained cards, the
/// app's own accent, and monospaced figures so prices line up the way money does
/// everywhere else in MarginRun. One component serves every gate — only the hero
/// and the leading benefit change, driven by ``ProFeature``.
///
/// At standard text sizes the pitch scrolls while the decision stays visible.
/// Accessibility text sizes put the entire paywall in one scroll view, keeping
/// both plans, the CTA and all legal controls reachable on compact phones.
struct MarginRunPaywall: View {
    /// What the customer reached for. `nil` uses the general pitch.
    var feature: ProFeature?
    /// The centralized router has already loaded the current Offering. Direct
    /// previews can still ask this view to load it itself.
    var loadsOfferingOnAppear = true

    @EnvironmentObject private var store: SubscriptionStore
    @EnvironmentObject private var analytics: AnalyticsService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var selectedPlanID: String?
    @StateObject private var offerCodeRedemption = OfferCodeRedemptionPresentation()
    var body: some View {
        NavigationStack {
            Group {
                switch store.offeringState {
                case .loading:
                    LoadingState()

                case .loaded(let offering):
                    let plans = PlanOption.options(
                        from: offering,
                        introEligibilityByProductID: store.introEligibilityByProductID
                    )
                    if plans.isEmpty {
                        // Rather than render an empty picker with a live buy
                        // button that cannot succeed.
                        UnavailableState(
                            reason: "No plans are available right now.",
                            retry: { Task { await store.loadOffering() } }
                        )
                    } else {
                        content(offering: offering, plans: plans)
                    }

                case .unavailable(let reason):
                    UnavailableState(
                        reason: reason,
                        retry: { Task { await store.loadOffering() } }
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.bold))
                    }
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("paywallCloseButton")
                }
            }
        }
        .task {
            if loadsOfferingOnAppear { await store.loadOffering() }
        }
        .onChange(of: store.isPro) { _, isPro in
            // The gated feature unlocks the moment the entitlement lands, with
            // no restart: the customer info stream drives this.
            if isPro { dismiss() }
        }
        .appStoreOfferCodeRedemption(
            presentation: offerCodeRedemption,
            source: .nativePaywall
        )
        .subscriptionErrorAlert()
    }

    // MARK: - Loaded content

    @ViewBuilder
    private func content(offering: Offering, plans: [PlanOption]) -> some View {
        let selected = selectedPlan(in: plans)

        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // At accessibility sizes the decision area joins the same
                // scroll view as the pitch. Nothing is capped or permanently
                // pinned over content, so both plans, the CTA and every legal
                // control remain reachable on the smallest supported phones.
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        pitch
                        decisionBar(offering: offering, plans: plans, selected: selected)
                    }
                    .padding(.bottom, 12)
                }
            } else {
                ScrollView {
                    pitch
                        .padding(.bottom, 12)
                }
                .safeAreaInset(edge: .bottom) {
                    decisionBar(offering: offering, plans: plans, selected: selected)
                }
            }
        }
        .onAppear {
            // The recommended plan leads and is preselected; the customer is
            // free to change it, but is never forced to make the comparison
            // before they can continue.
            if selectedPlanID == nil { selectedPlanID = plans.first?.id }
        }
    }

    private var pitch: some View {
        VStack(alignment: .leading, spacing: 20) {
            hero
            benefits
        }
        .padding(.horizontal, 20)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: feature?.systemImage ?? "chart.bar.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text(feature?.headline ?? ProPitch.headline)
                .font(.title.bold())
                .fixedSize(horizontal: false, vertical: true)

            Text(feature?.subheadline ?? ProPitch.subheadline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    /// Three rows, led by whatever was gated. More than three and none of them
    /// are read — and every extra row is vertical space the monthly plan needs.
    private var benefits: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(ProPitch.benefits(for: feature)) { benefit in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: benefit.systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 26)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(benefit.title)
                            .font(.subheadline.weight(.semibold))
                        Text(benefit.outcome)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Decision bar

    /// Plans, CTA and legal chrome, pinned below the scrolling pitch.
    ///
    /// Pinned rather than appended so the comparison a customer needs to make is
    /// never below the fold on a normal phone. The pitch above scrolls instead.
    private func decisionBar(
        offering: Offering,
        plans: [PlanOption],
        selected: PlanOption?
    ) -> some View {
        VStack(spacing: 12) {
            planPicker(plans: plans, selected: selected)
            trialMessage(for: selected)
            purchaseButton(offering: offering, selected: selected)

            VStack(spacing: 8) {
                Text(disclosure(for: selected))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                secondaryLinks
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(.bar)
        // The disclosure text changes with the plan; crossfade it rather than
        // letting the whole bar snap to a new height.
        .animation(.snappy(duration: 0.22), value: selected?.id)
    }

    private func planPicker(plans: [PlanOption], selected: PlanOption?) -> some View {
        VStack(spacing: 10) {
            ForEach(plans) { plan in
                PlanCard(plan: plan, isSelected: plan.id == selected?.id) {
                    guard plan.id != selectedPlanID else { return }
                    withAnimation(.snappy(duration: 0.22)) {
                        selectedPlanID = plan.id
                    }
                    analytics.track(
                        .paywallPlanSelected(
                            plan: plan.analyticsPlan,
                            feature: feature,
                            source: .native
                        )
                    )
                }
            }
        }
    }

    /// Makes the trial feel concrete at the decision point: value now, exact
    /// renewal terms next. It only exists for an eligible StoreKit offer, so an
    /// ineligible customer never sees a promise the App Store cannot honor.
    @ViewBuilder
    private func trialMessage(for plan: PlanOption?) -> some View {
        if let trial = plan?.trial {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(trial.reassuranceHeadline)
                        .font(.subheadline.weight(.semibold))
                    Text(trial.reassuranceDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("paywallTrialMessage")
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private func purchaseButton(offering: Offering, selected: PlanOption?) -> some View {
        Button {
            guard let selected, let package = package(for: selected, in: offering) else { return }
            Task {
                await store.purchase(
                    package,
                    plan: selected.analyticsPlan,
                    feature: feature,
                    paywallSource: .native,
                    purchaseKind: selected.trial == nil ? .paid : .introductoryTrial
                )
            }
        } label: {
            Group {
                if store.isPurchasing {
                    ProgressView()
                } else {
                    Text(selected?.trial == nil ? "Start MarginRun Pro" : "Start Free Trial")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .sensoryFeedback(.success, trigger: store.isPro) { was, now in !was && now }
        // Guards against a second tap while StoreKit is mid-flight. The store
        // refuses a concurrent purchase as well, so a race cannot double-charge
        // or double-count.
        .disabled(selected == nil || store.isPurchasing || store.isRestoring)
        .accessibilityIdentifier("paywallPurchaseButton")
    }

    /// Required by Apple, and deliberately quiet: present and reachable without
    /// competing with the decision.
    @ViewBuilder
    private var secondaryLinks: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                restoreButton
                redeemOfferCodeButton
                privacyLink
                termsLink
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 8) {
                HStack(spacing: 18) {
                    restoreButton
                    redeemOfferCodeButton
                }

                HStack(spacing: 18) {
                    privacyLink
                    termsLink
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var restoreButton: some View {
        Button("Restore") {
            Task { await store.restorePurchases(from: .paywall, paywallSource: .native) }
        }
        .disabled(store.isRestoring)
        .accessibilityIdentifier("paywallRestoreButton")
    }

    private var redeemOfferCodeButton: some View {
        Button("Redeem Offer Code") {
            offerCodeRedemption.present(using: store, from: .nativePaywall)
        }
        .accessibilityIdentifier("paywallRedeemOfferCodeButton")
    }

    private var privacyLink: some View {
        Link("Privacy Policy", destination: RevenueCatConfig.Legal.privacyPolicy)
            .accessibilityIdentifier("paywallPrivacyLink")
    }

    private var termsLink: some View {
        Link("Terms of Use", destination: RevenueCatConfig.Legal.termsOfUse)
            .accessibilityIdentifier("paywallTermsLink")
    }

    private func disclosure(for plan: PlanOption?) -> String {
        guard let plan else { return "" }
        guard plan.periodSuffix != nil else { return plan.terms }

        return """
        \(plan.terms) Payment is charged to your Apple Account at confirmation. \
        Cancel anytime in Settings at least 24 hours before renewal.
        """
    }

    // MARK: - Selection

    private func selectedPlan(in plans: [PlanOption]) -> PlanOption? {
        plans.first { $0.id == selectedPlanID } ?? plans.first
    }

    private func package(for plan: PlanOption?, in offering: Offering) -> Package? {
        guard let plan else { return nil }
        return offering.availablePackages.first { $0.identifier == plan.packageIdentifier }
    }
}

// MARK: - Plan card

private struct PlanCard: View {
    let plan: PlanOption
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    // The badge drops onto its own line rather than wrapping
                    // inside its capsule, which at accessibility sizes turns
                    // the pill into a blob with text running past its edge.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            planTitle
                            badge
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            planTitle
                            badge
                        }
                    }

                    // Money is monospaced everywhere else in MarginRun; the
                    // paywall is not the place to break that. Every figure here
                    // is StoreKit's own localized string.
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(plan.price)
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        if let suffix = plan.periodSuffix {
                            Text(suffix)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let trial = plan.trial {
                        Text(trial.summary)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tint)
                        Text(trial.renewalLine)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if let equivalentLine = plan.equivalentLine {
                        Text(equivalentLine)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.secondary.opacity(isSelected ? 0.14 : 0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.clear),
                        lineWidth: 2
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(plan.accessibilityIdentifier)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var planTitle: some View {
        Text(plan.title.uppercased())
            .font(.caption.weight(.bold))
            .kerning(0.6)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var badge: some View {
        if let badge = plan.badge {
            Text(badge)
                .font(.caption2.weight(.bold))
                .kerning(0.4)
                // A decorative marker, not content: the price it refers to is
                // spelled out right below it, so one line is enough.
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.tint, in: Capsule())
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Non-loaded states

private struct LoadingState: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading plans…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("paywallLoading")
    }
}

private struct UnavailableState: View {
    let reason: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Plans unavailable", systemImage: "wifi.exclamationmark")
        } description: {
            Text(reason)
        } actions: {
            Button("Try Again", action: retry)
                .accessibilityIdentifier("paywallRetryButton")
        }
        .accessibilityIdentifier("paywallUnavailable")
    }
}
