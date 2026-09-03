import Foundation
import PostHog

/// Centralized, environment-swappable PostHog configuration.
///
/// Xcode expands the two matching Info.plist build settings for normal builds;
/// scheme environment variables with the same names can override them for a
/// local verification run. Missing or malformed values intentionally produce
/// no backend, which keeps Debug, previews and tests safe and offline.
nonisolated enum PostHogConfiguration {
    static let apiKeyName = "POSTHOG_API_KEY"
    static let hostName = "POSTHOG_HOST"

    struct Values: Equatable, Sendable {
        let apiKey: String
        let host: URL
    }

    static func values(
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Values? {
        guard let apiKey = configuredValue(
            named: apiKeyName,
            infoDictionary: infoDictionary,
            environment: environment
        ), let hostText = configuredValue(
            named: hostName,
            infoDictionary: infoDictionary,
            environment: environment
        ), let host = URL(string: hostText),
           ["http", "https"].contains(host.scheme?.lowercased() ?? ""),
           host.host != nil else { return nil }

        return Values(apiKey: apiKey, host: host)
    }

    static func makeBackend(
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> any AnalyticsBackend {
        guard let configuration = values(
            infoDictionary: infoDictionary,
            environment: environment
        ) else {
            return NoOpAnalyticsBackend()
        }
        return PostHogAnalyticsService(configuration: configuration)
    }

    private static func configuredValue(
        named name: String,
        infoDictionary: [String: Any],
        environment: [String: String]
    ) -> String? {
        let raw = environment[name] ?? infoDictionary[name] as? String
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }
}

/// The only vendor-specific implementation in MarginRun.
///
/// It receives already-sanitized payloads from `AnalyticsService`, translates
/// the narrow value vocabulary to PostHog properties, and never throws back
/// into navigation, persistence, purchases or financial calculations.
nonisolated final class PostHogAnalyticsService: AnalyticsBackend, @unchecked Sendable {
    init(configuration: PostHogConfiguration.Values) {
        let config = PostHogConfig(
            projectToken: configuration.apiKey,
            host: configuration.host.absoluteString
        )

        // Manual typed events are the source of truth for V1. Explicitly turn
        // off every broad capture surface whose SDK default could add noise or
        // collect more context than MarginRun intends.
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        config.captureElementInteractions = false
        config.capturePushNotificationSubscriptions = false
        config.capturePushNotificationOpened = false
        config.sessionReplay = false
        config.surveys = false
        config.preloadFeatureFlags = false
        config.enableSwizzling = false
        config.errorTrackingConfig.autoCapture = false
        config.errorTrackingConfig.exceptionSteps.enabled = false

        #if DEBUG
        config.debug = true
        #else
        config.debug = false
        #endif

        // Keep the SDK's production batching defaults. In particular, do not
        // set `flushAt = 1` just to make local dashboard checks look immediate.
        PostHogSDK.shared.setup(config)
    }

    func record(_ payload: AnalyticsPayload) {
        let properties = payload.properties.mapValues { value -> Any in
            switch value {
            case .string(let value): value
            case .int(let value): value
            case .bool(let value): value
            }
        }
        PostHogSDK.shared.capture(payload.name, properties: properties)
    }
}
