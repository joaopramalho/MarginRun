import ActivityKit
import SwiftUI
import WidgetKit

/// The Lock Screen and Dynamic Island presentation of a running Labor Timer.
///
/// Every surface here draws elapsed time with `Text(timerInterval:)`, which
/// the system advances from the persisted start date on its own. The extension
/// therefore never receives a content update while a timer runs — one
/// `Activity.request` at Stop-less start, one `Activity.end` at Stop — and the
/// number keeps climbing with MarginRun closed, backgrounded, or terminated.
struct LaborTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LaborTimerActivityAttributes.self) { context in
            LaborTimerLockScreenView(context: context)
                // Tapping anywhere on the card lands on the running timer.
                .widgetURL(LaborTimerDeepLink.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "hammer.fill")
                        .font(.title3)
                        .foregroundStyle(Color.marginRunActivityAccent)
                        .accessibilityLabel("MarginRun")
                }

                DynamicIslandExpandedRegion(.center) {
                    Text("Labor Timer")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedTimeText(startedAt: context.state.startedAt)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        // Right-aligned in a fixed lane so the digits do not
                        // shove the centre label around as the hour rolls over.
                        .frame(maxWidth: 88, alignment: .trailing)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(context.attributes.jobName)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .privacySensitive()

                        Spacer(minLength: 0)

                        TrackingStatusLabel()
                    }
                    // The bottom region runs the full width of the island, and
                    // the island is a rounded capsule: text pinned to the outer
                    // edges is clipped by the curve. This keeps both ends
                    // inside the shape.
                    .padding(.horizontal, 8)
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(Color.marginRunActivityAccent)
                    .accessibilityLabel("Labor timer running")
            } compactTrailing: {
                // The elapsed value earns the compact space; the job name does
                // not fit here and would only truncate.
                ElapsedTimeText(startedAt: context.state.startedAt)
                    .font(.caption2)
                    .frame(maxWidth: 52, alignment: .trailing)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(Color.marginRunActivityAccent)
                    .accessibilityLabel("Labor timer running")
            }
            .widgetURL(LaborTimerDeepLink.url)
            .keylineTint(Color.marginRunActivityAccent)
        }
    }
}

// MARK: - Lock Screen

/// Reads as a native iOS utility rather than a miniature Dashboard: one
/// accent-tinted eyebrow, the job it identifies, the number that matters, and
/// a status. No cards, no gradients, no Pro marketing.
private struct LaborTimerLockScreenView: View {
    let context: ActivityViewContext<LaborTimerActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "hammer.fill")
                    .imageScale(.small)
                Text("MarginRun · Labor Timer")
                    .lineLimit(1)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.marginRunActivityAccent)

            Text(context.attributes.jobName)
                .font(.headline)
                .lineLimit(1)
                // User-entered text on a surface a stranger can see. The system
                // redacts it when the device is locked and content is hidden.
                .privacySensitive()

            HStack(alignment: .lastTextBaseline, spacing: 12) {
                ElapsedTimeText(startedAt: context.state.startedAt)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                TrackingStatusLabel()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Shared pieces

/// The elapsed duration, counted by the system.
///
/// `Text(timerInterval:)` re-renders itself from the device clock, so nothing
/// in MarginRun schedules a tick and no `Activity.update` is ever sent for the
/// passage of time. The open-ended range is what makes it count *up* from the
/// start date rather than down to a deadline.
private struct ElapsedTimeText: View {
    let startedAt: Date

    var body: some View {
        Text(
            timerInterval: startedAt...Date.distantFuture,
            pauseTime: nil,
            countsDown: false,
            showsHours: true
        )
        .monospacedDigit()
        .accessibilityLabel("Elapsed labor time")
    }
}

/// "Tracking labor", with a live dot that stands down in Always-On.
private struct TrackingStatusLabel: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isLuminanceReduced ? Color.secondary : Color.green)
                .frame(width: 6, height: 6)
            Text("Tracking labor")
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

private extension Color {
    /// MarginRun's blue, stated rather than inherited.
    ///
    /// The app's `AccentColor` asset is empty, so in-app `Color.accentColor`
    /// resolves to the system blue. A widget extension does not pick up the
    /// host app's tint, so the same blue is named here to keep the activity
    /// visually part of MarginRun in both appearances.
    static let marginRunActivityAccent = Color.blue
}

// MARK: - Previews

private extension LaborTimerActivityAttributes {
    static let preview = LaborTimerActivityAttributes(
        sessionID: UUID(),
        jobID: UUID(),
        jobName: "Kitchen remodel"
    )
}

private extension LaborTimerActivityAttributes.ContentState {
    /// Just over an hour and a half in, so every preview shows the wide
    /// `H:MM:SS` form rather than the short one that fits anywhere.
    static let running = LaborTimerActivityAttributes.ContentState(
        startedAt: Date(timeIntervalSinceNow: -6_138)
    )
}

#Preview("Lock Screen", as: .content, using: LaborTimerActivityAttributes.preview) {
    LaborTimerLiveActivity()
} contentStates: {
    LaborTimerActivityAttributes.ContentState.running
}

#Preview(
    "Dynamic Island compact",
    as: .dynamicIsland(.compact),
    using: LaborTimerActivityAttributes.preview
) {
    LaborTimerLiveActivity()
} contentStates: {
    LaborTimerActivityAttributes.ContentState.running
}

#Preview(
    "Dynamic Island expanded",
    as: .dynamicIsland(.expanded),
    using: LaborTimerActivityAttributes.preview
) {
    LaborTimerLiveActivity()
} contentStates: {
    LaborTimerActivityAttributes.ContentState.running
}

#Preview(
    "Dynamic Island minimal",
    as: .dynamicIsland(.minimal),
    using: LaborTimerActivityAttributes.preview
) {
    LaborTimerLiveActivity()
} contentStates: {
    LaborTimerActivityAttributes.ContentState.running
}
