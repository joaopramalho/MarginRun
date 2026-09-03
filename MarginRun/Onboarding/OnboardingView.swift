import SwiftData
import SwiftUI
import UIKit

/// First-run setup.
///
/// Three short screens with one job between them: get a contractor to their own
/// first job in well under a minute. Everything here is optional and every
/// screen can be left, because the thing that proves onboarding worked is a job
/// existing — not a carousel being read to the end.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var analytics: AnalyticsService

    @State private var step: OnboardingStep = .value
    @State private var draft: OnboardingDraft
    @State private var isCreatingFirstJob = false
    @FocusState private var focusedField: Field?

    /// The margin MarginRun already defaults to, kept so analytics can report
    /// whether the contractor actually changed it.
    private let suggestedTargetMarginText: String
    private let preferences: AppPreferences

    init(preferences: AppPreferences = AppPreferences()) {
        self.preferences = preferences
        let suggested = preferences.defaultTargetMarginText
        suggestedTargetMarginText = suggested
        _draft = State(initialValue: OnboardingDraft(targetMarginText: suggested))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                stepIndicator
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                // Paging rather than a swapped subview, so the screens can be
                // swiped as well as tapped through. Selection is the same
                // `step` the buttons and the indicator use, so the two ways of
                // moving can never disagree.
                TabView(selection: $step) {
                    page { valueScreen }.tag(OnboardingStep.value)
                    page { businessScreen }.tag(OnboardingStep.business)
                    page { defaultsScreen }.tag(OnboardingStep.defaults)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .background(Color(uiColor: .systemBackground))
            .safeAreaInset(edge: .bottom) { actions }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            analytics.track(.onboardingStarted)
        }
        // Paging with the keyboard up leaves it hanging over the next screen's
        // content; dropping focus on every move keeps swipe and tap identical.
        .onChange(of: step) { _, _ in focusedField = nil }
        .sheet(isPresented: $isCreatingFirstJob, onDismiss: finish) {
            CreateJobView(source: .onboarding)
        }
    }

    /// One swipeable screen.
    ///
    /// Each page scrolls on its own so long content still reaches the keyboard
    /// at large text sizes, while the pager owns the horizontal gesture.
    private func page<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            content()
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: - Progress

    /// Three dots rather than "Step 2 of 3" in prose: it reads at a glance and
    /// costs one line at any type size. VoiceOver still hears the sentence.
    private var stepIndicator: some View {
        HStack(spacing: 7) {
            ForEach(OnboardingStep.allCases, id: \.self) { indicator in
                Capsule()
                    .fill(indicator == step ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: indicator == step ? 22 : 7, height: 7)
            }
        }
        .animation(.snappy(duration: 0.25), value: step)
        .accessibilityElement()
        .accessibilityLabel("Step \(stepNumber) of \(OnboardingStep.allCases.count)")
        .accessibilityIdentifier("onboardingStepIndicator")
    }

    private var stepNumber: Int {
        (OnboardingStep.allCases.firstIndex(of: step) ?? 0) + 1
    }

    // MARK: - Screens

    private var valueScreen: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Placeholder: swap for a monochrome, simplified mark of the real
            // MarginRun logo once it exists — not the square app icon.
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
                .padding(.top, 8)

            headline("Know what every job is really making.")
            supporting("Track costs, labor, and margin while the job is still running.")
        }
    }

    private var businessScreen: some View {
        VStack(alignment: .leading, spacing: 22) {
            headline("Tell us about your business")
            supporting("Personalize MarginRun for your business. You can change this anytime.")

            field(title: "Business name") {
                TextField("Johnson Remodeling", text: $draft.businessName)
                    .textContentType(.organizationName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .businessName)
                    .submitLabel(.done)
                    .accessibilityIdentifier("onboardingBusinessNameField")
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Trade")

                Picker("Trade", selection: $draft.trade) {
                    Text("Choose a trade").tag(ContractorTrade?.none)
                    ForEach(ContractorTrade.allCases) { trade in
                        Text(trade.title).tag(ContractorTrade?.some(trade))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .roundedFieldBackground()
                .accessibilityIdentifier("onboardingTradePicker")
            }
        }
    }

    private var defaultsScreen: some View {
        VStack(alignment: .leading, spacing: 22) {
            headline("Set your defaults")
            supporting("Both prefill new work. You can change either one at any time in Settings.")

            field(
                title: "Hourly labor cost",
                help: "Used to estimate what your labor actually costs the job."
            ) {
                HStack(spacing: 6) {
                    CurrencyTextField(
                        title: "45",
                        text: $draft.hourlyCostText,
                        accessibilityLabel: "Hourly labor cost",
                        accessibilityIdentifier: "onboardingHourlyCostField"
                    )
                    Text("/ hr").foregroundStyle(.secondary)
                }
            }

            if draft.hasInvalidHourlyCost {
                validationMessage("Enter an hourly cost greater than zero, or leave it empty.")
            }

            field(
                title: "Target margin",
                help: "MarginRun warns you when a job is falling below this. 30% is a common starting point."
            ) {
                HStack(spacing: 6) {
                    TextField("30", text: $draft.targetMarginText)
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                        .focused($focusedField, equals: .targetMargin)
                        .accessibilityLabel("Target margin percent")
                        .accessibilityIdentifier("onboardingTargetMarginField")
                    Text("%").foregroundStyle(.secondary)
                }
            }

            if draft.hasInvalidTargetMargin {
                validationMessage("Enter a target margin between 0 and 99.")
            }
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 10) {
            Button(action: advance) {
                Text(primaryTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            // Only the last screen can be blocked, and only by a value that is
            // present and wrong. Nothing on the way there is required, so
            // moving forward — by tap or by swipe — never hits validation.
            .disabled(step == .defaults && !draft.canFinish)
            .accessibilityIdentifier("onboardingPrimaryButton")

            if let secondaryTitle {
                Button(secondaryTitle, action: performSecondary)
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("onboardingSecondaryButton")
            } else {
                // Reserves the row so the primary CTA holds still while a
                // screen without a secondary action swipes past.
                Text(" ")
                    .font(.subheadline.weight(.medium))
                    .hidden()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private var primaryTitle: String {
        switch step {
        case .value: "Set up MarginRun"
        case .business: "Continue"
        case .defaults: "Create your first job"
        }
    }

    /// `nil` on the business screen: both of its fields are already optional,
    /// so "Continue" with nothing typed is the same action a Skip would be.
    private var secondaryTitle: String? {
        switch step {
        case .value: "Skip setup"
        case .business: nil
        case .defaults: "Skip for now"
        }
    }

    private func advance() {
        focusedField = nil
        switch step {
        case .value:
            withAnimation(.snappy(duration: 0.25)) { step = .business }
        case .business:
            withAnimation(.snappy(duration: 0.25)) { step = .defaults }
        case .defaults:
            guard draft.canFinish else { return }
            commitSetup()
            analytics.track(
                .onboardingCompleted(
                    setBusinessName: !draft.trimmedBusinessName.isEmpty,
                    setTrade: draft.trade != nil,
                    setHourlyCost: draft.hourlyCost != nil,
                    changedTargetMargin: draft.changedTargetMargin(from: suggestedTargetMarginText)
                )
            )
            // Straight into the real Create Job flow rather than an "all set"
            // screen over an empty dashboard.
            isCreatingFirstJob = true
        }
    }

    private func performSecondary() {
        focusedField = nil
        switch step {
        case .value:
            analytics.track(.onboardingSkipped(step: .value))
            commitSetup()
            finish()
        case .business:
            break
        case .defaults:
            analytics.track(.onboardingSkipped(step: .defaults))
            commitSetup()
            finish()
        }
    }

    /// Writes whatever was filled in. Safe on every exit path because the draft
    /// only writes fields the contractor actually completed.
    private func commitSetup() {
        draft.apply(to: preferences)
    }

    /// Leaving marks onboarding done — the presenting binding owns that flag, so
    /// there is exactly one place it is written.
    private func finish() {
        dismiss()
    }

    // MARK: - Building blocks

    private func headline(_ text: String) -> some View {
        Text(text)
            .font(.largeTitle.bold())
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func supporting(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.4)
    }

    private func field<Control: View>(
        title: String,
        help: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel(title)

            control()
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .roundedFieldBackground()

            if let help {
                Text(help)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func validationMessage(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle.fill")
            .font(.footnote)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }

    private enum Field: Hashable {
        case businessName
        case hourlyCost
        case targetMargin
    }
}

private extension View {
    /// The shared input surface. `secondarySystemBackground` resolves against
    /// the active colour scheme, so one call is correct in light and dark.
    func roundedFieldBackground() -> some View {
        background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
    }
}

#Preview("Onboarding") {
    OnboardingView()
        .modelContainer(PreviewSupport.container())
        .environmentObject(AnalyticsService(backend: NoOpAnalyticsBackend()))
        .environmentObject(SubscriptionStore(entitlementOverride: false))
}
