# MarginRun

MarginRun is a native iPhone app for independent contractors and small service businesses to organize jobs and understand their costs, labor, and margins.

## Features

- Create, edit, complete, reopen, and delete jobs with contract values and cost estimates.
- Track expenses, extra revenue, labor entries, and receipt images.
- Calculate job-level profit and margin, and review portfolio insights.
- Track labor with a timer and an iOS Live Activity.
- Capture receipts and extract text on-device with Apple Vision.
- Onboarding to configure the app for a contractor's trade.
- Access Pro features through RevenueCat-backed subscriptions, including unlimited active jobs, insights, and receipt scanning.
- Send product events through PostHog. Financial values sent for job creation and completion are bucketed and rounded by the analytics layer.

## Technology

- Swift 5 language mode, SwiftUI, and SwiftData
- Apple Vision for receipt text recognition
- ActivityKit and WidgetKit for the labor timer Live Activity
- RevenueCat and RevenueCatUI for subscription purchases and paywall support
- PostHog iOS for product analytics
- Swift Package Manager for third-party dependencies

## Requirements

- Xcode with an iOS 17 SDK and simulator runtime. The project file does not declare a minimum Xcode version; the current project was last inspected with Xcode 26.6.
- iOS 17 or later for the app and Live Activity extension.
- An iPhone simulator or device. The main app target is iPhone-only.

The project uses Swift 5 language mode. Test targets currently specify an iOS 26.5 deployment target, so running tests may require a recent Xcode and simulator even though the app itself targets iOS 17.

## Getting Started

After the repository has a GitHub URL, clone it and open the Xcode project:

```sh
git clone <repository-url>
cd MarginRun
open MarginRun.xcodeproj
```

In Xcode, select the `MarginRun` scheme and an iPhone simulator, then choose **Product → Build** or **Run**. Xcode resolves the pinned Swift Package Manager dependencies from `Package.resolved`; use **File → Packages → Resolve Package Versions** if needed.

The app's code includes client SDK identifiers for RevenueCat and a PostHog ingestion key. These identifiers are intended to be embedded in client apps and are not server credentials. A developer can replace them with their own project values for local experimentation. Never add RevenueCat secret API keys, App Store Connect credentials, signing certificates, provisioning profiles, or other server secrets to the repository. RevenueCat products and offerings must exist in the associated dashboard for real purchase behavior. PostHog analytics is disabled when its configuration is absent; core local app flows do not depend on PostHog.

The checked-in RevenueCat configuration chooses the Test Store key for Debug and the App Store public SDK key for Release. Do not distribute a build without reviewing the app's own store and subscription configuration.

## Testing

The repository contains unit tests in `MarginRunTests` and UI tests in `MarginRunUITests`. In Xcode, select the `MarginRun` scheme and choose **Product → Test**. From the command line:

```sh
xcodebuild test \
  -project MarginRun.xcodeproj \
  -scheme MarginRun \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Use an iPhone simulator installed by the selected Xcode; adjust the destination name to match `xcrun simctl list devices available`. The UI suite uses launch configurations and fixtures to avoid live purchases and analytics in its test flows.

## Project Structure

| Path | Responsibility |
| --- | --- |
| `MarginRun/Models` | SwiftData job, expense, labor, and revenue models |
| `MarginRun/Views` | SwiftUI screens and input drafts |
| `MarginRun/Finance` | Money input/formatting and job/portfolio calculations |
| `MarginRun/Labor` | Timer state and Live Activity coordination |
| `MarginRun/Receipt` and `MarginRun/Storage` | Receipt OCR and local receipt image storage |
| `MarginRun/Purchases` | RevenueCat integration, paywall, plan limits, and Pro gating |
| `MarginRun/Analytics` | Product events, analytics backends, and value bucketing |
| `MarginRun/Onboarding`, `Navigation`, `Alerts`, `Settings` | Supporting app flows |
| `MarginRunWidgets` and `MarginRunShared` | Live Activity extension and shared activity attributes |
| `MarginRunTests` | Unit tests |
| `MarginRunUITests` | UI tests and screenshot catalog |
| `Config` | Info.plist files for app and extension |

## Development Status

MarginRun is an existing application under continued development. This repository reflects an in-progress product; integrations and store configuration may require project-specific setup.

## Roadmap

See [ROADMAP.md](ROADMAP.md) for proposed technical improvements. Items are proposals only and are not approved or scheduled.

## License

This project is licensed under the Mozilla Public License 2.0 (MPL-2.0). See [LICENSE](LICENSE) for the license text.
