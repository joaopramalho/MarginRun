//
//  ContentView.swift
//  MarginRun
//
//  Created by João Pedro da Silva Ramalho on 31/08/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject private var laborTimer: LaborTimerStore
    @StateObject private var subscriptions: SubscriptionStore
    @StateObject private var analytics: AnalyticsService
    @StateObject private var router: DeepLinkRouter

    @Environment(\.scenePhase) private var scenePhase
    @Query private var jobs: [Job]

    /// The single source of truth for "has first-run setup happened". Settings
    /// and the migration check write the same key.
    @AppStorage(OnboardingStorageKeys.completed) private var onboardingCompleted = false
    @AppStorage(AppPreferenceKeys.trade) private var tradeRawValue = ""

    /// - Parameters:
    ///   - analytics: supplied by the app so the whole process shares one
    ///     service. `nil` builds a local one, which is what previews want.
    ///   - liveActivity: the ActivityKit seam handed to the timer store. `nil`
    ///     leaves the store on its no-op default, so a preview or a UI-test
    ///     run cannot put a real activity on a real Lock Screen.
    init(
        entitlementOverride: Bool? = nil,
        analytics: AnalyticsService? = nil,
        liveActivity: LaborLiveActivityManaging? = nil
    ) {
        let analytics = analytics ?? AnalyticsService(backend: NoOpAnalyticsBackend())
        _analytics = StateObject(wrappedValue: analytics)
        _subscriptions = StateObject(
            wrappedValue: SubscriptionStore(
                entitlementOverride: entitlementOverride,
                analytics: analytics
            )
        )
        _router = StateObject(wrappedValue: DeepLinkRouter(analytics: analytics))
        _laborTimer = StateObject(
            wrappedValue: liveActivity.map { LaborTimerStore(liveActivity: $0) }
                ?? LaborTimerStore()
        )
    }

    var body: some View {
        // Tagged and bound so the Live Activity can select the Timer tab. The
        // tabs, their order and their labels are unchanged.
        TabView(selection: $router.selectedTab) {
            NavigationStack {
                DashboardView()
            }
            .tabItem {
                Label("Dashboard", systemImage: "chart.bar.fill")
            }
            .tag(AppTab.dashboard)

            NavigationStack {
                JobsListView()
            }
            .tabItem {
                Label("History", systemImage: "clock.fill")
            }
            .tag(AppTab.history)

            NavigationStack {
                LaborTimerView()
            }
            .tabItem {
                Label("Timer", systemImage: "timer")
            }
            .tag(AppTab.timer)

            NavigationStack {
                InsightsView()
            }
            .tabItem {
                Label("Insights", systemImage: "chart.line.uptrend.xyaxis")
            }
            .tag(AppTab.insights)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tag(AppTab.settings)
        }
        .environmentObject(laborTimer)
        .environmentObject(subscriptions)
        .environmentObject(analytics)
        .fullScreenCover(isPresented: showsOnboarding) {
            // Attached explicitly: a cover presented from the root of a
            // TabView does not pick up the environment objects installed on
            // that TabView, and first run is the one launch that cannot afford
            // to trap on a missing one. Sheets opened from inside the cover
            // inherit normally from here.
            OnboardingView()
                .environmentObject(analytics)
                .environmentObject(subscriptions)
                .environmentObject(laborTimer)
        }
        // The single handler for the Live Activity's tap target. Reporting
        // happens here, in the URL path, rather than in any view lifecycle —
        // that is what keeps one tap to one `labor_live_activity_opened`
        // however many times SwiftUI re-renders the Timer tab afterwards.
        .onOpenURL { router.handle($0) }
        // Defensive reconciliation. A Live Activity can outlive the process
        // that requested it — a crash, a force quit, Live Activities switched
        // on or off while the app was away — so becoming active is the moment
        // to make the Lock Screen agree with the timer again. Reads the timer,
        // edits activities, and touches no financial data in either direction.
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            laborTimer.reconcileLiveActivity()
        }
        // Refreshed rather than captured: a closure over `jobs` would freeze
        // the counts at the first render.
        .task(id: analyticsContextID) {
            analytics.context = AnalyticsContext(
                isPro: subscriptions.isPro,
                activeJobCount: activeJobCount,
                totalJobCount: jobs.count,
                completedJobCount: jobs.count - activeJobCount,
                onboardingCompleted: onboardingCompleted,
                trade: ContractorTrade(rawValue: tradeRawValue)
            )
            // Self-deduplicating, so running it on every refresh still emits
            // `app_first_open` exactly once per install.
            analytics.trackAppOpen()
        }
    }

    private var activeJobCount: Int {
        jobs.filter { $0.status == .active }.count
    }

    private var analyticsContextID: String {
        "\(subscriptions.isPro)|\(jobs.count)|\(activeJobCount)|\(onboardingCompleted)|\(tradeRawValue)"
    }

    /// Presented while setup is outstanding; dismissing it, by any route, is
    /// what marks setup done.
    private var showsOnboarding: Binding<Bool> {
        Binding(
            get: { !onboardingCompleted },
            set: { isPresented in
                if !isPresented { onboardingCompleted = true }
            }
        )
    }
}

#Preview {
    ContentView(entitlementOverride: true)
        .modelContainer(PreviewSupport.container())
}
