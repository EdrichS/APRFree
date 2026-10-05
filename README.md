# APRFree

A personal debt-payoff app for iPhone. It keeps every credit card, buy-now-pay-later plan and loan in one place, splits each paycheck across them, and shows when you will be debt-free. Everything stays on the device: there is no account, no server and no network code.

Built with SwiftUI for iOS 26.

## What it does

- **Home.** A total balance card with every card and pay-later plan stacked under it, loans as boarding-pass tiles, and four tools. Tapping the total opens a ring chart of every balance with its share and its interest per day.
- **Make a Payment.** Enter the payday amount; the app keeps your safety buffer, covers every minimum due before the next payday, and sends the rest to the first debt in your strategy. You pay in each bank's own app, then mark each line paid.
- **Due dates that work like a bank's.** A due date stays until its minimum is met. Partial payments shrink what is left. Once met, the next due date is the same day next month, and extra payments never push it further. Payments start counting toward the next due date nine days after the previous one.
- **Four strategies.** Avalanche (highest APR first), Snowball (smallest balance first), Highest Balance (biggest monthly interest charge in dollars first) and Custom (drag to reorder). A table compares all four on your own debts.
- **Simulator.** Try a one-time payment, any monthly extra, a new purchase or another strategy. Hold and drag the chart to read the balance on any date for the current plan and the what-if.
- **Detail screens.** Cards show balance, payment due, APR, utilization, payoff month and the total cost of the card on your plan versus minimums only. Loans show projected total interest and a "pay a bit extra" calculator. Pay-later plans show the installment schedule.
- **Progress.** A payoff countdown and balance chart you can swipe between Total, Credit cards and Loans, a shelf for paid-off loans and plans, upcoming due dates and recent activity.
- **History and undo.** Every payment, charge and balance edit is recorded with the balance it left. Tap any entry to undo it; later entries for that debt are re-applied so they stay correct.
- **Setup.** First run asks for your debts (add as many as you like, with all their numbers, or skip), how often you are paid (weekly, every two weeks or monthly), a safety buffer, a strategy and reminders. Settings has Reset Everything, which erases all data and starts setup again.
- **Paydays that keep their rhythm.** Weekly and every-two-weeks pay always lands on the same weekday. Monthly pay lands on the same day of the month, or the last day of a shorter month: the 31st gives Jan 31, Feb 28, Mar 31.
- **Also:** local reminders for due dates and paydays, CSV and PDF export, backup and restore, and a Home Screen widget that can follow the total, the cards or the loans.

## Requirements

- Xcode 26.3 or later
- iOS 26.0 or later (iPhone, portrait)

## Running it

```bash
open APRFree.xcodeproj
```

Choose the `APRFree` scheme and an iPhone simulator, then Run. To run on a device, set your signing team on both the `APRFree` and `APRFreeWidgetsExtension` targets; both use the app group `group.com.edrichsilva.APRFree`.

Launch arguments (set in the scheme, or pass to `simctl launch`):

| Argument | Effect |
|---|---|
| `-demo` | Loads the fictional demo debts with the clock pinned to Oct 4, 2026. Saved data is not touched. |
| `-seedDemo` | Debug builds only. Replaces saved data with the demo debts. |
| `-onboarding` | Debug builds only. Starts on first-run setup with an empty, unsaved store. Saved data is not touched. |
| `-screen <name>` | Debug builds only. Opens straight on a screen: `progress`, `strategy`, `simulator`, `insights`, `export`, `settings`, `activity`, `breakdown`, `add`, `pay`, `celebrate`, or the start of a debt's name such as `chase`. |

## Tests

```bash
xcodebuild test -project APRFree.xcodeproj -scheme APRFree -destination 'platform=iOS Simulator,name=iPhone 17'
```

51 tests cover the payoff engine, due-date rules, paydays, the payday split, history, undo, formatting, export, backup, and loading data saved in another time zone. The expected figures were worked out with a separate Python model of the same rules, written independently of the Swift code (the script is not in this repository). One test runs all 720 orderings of the six interest-bearing demo debts and confirms none costs less interest than Avalanche; the Python model found the same across all 5,040 orderings of seven.

## How the math works

- Interest is APR / 365 per day. Cards compound it into the balance. Loans charge it on principal and the next payment covers it first.
- A plan pays, on each payday, everything due before the next payday, then sends the remainder down the strategy order. Pay-later plans follow their own schedules. A 0% promo card can be held at its minimum until the promo ends.
- A debt's payoff month is the month of the due date its final payment covers.
- Card balances do not grow on their own: interest shows up when you edit the balance or add a charge.
- Dates are whole local days. A saved file records its time zone, and its dates are moved when it is opened in another one, so a due date keeps its calendar day.

## Project layout

| Path | Contents |
|---|---|
| `APRFree/Models` | `Debt`, payment records, settings |
| `APRFree/Engine` | Payoff simulation, payday split, schedules, formatting |
| `APRFree/Store` | App state, persistence, reminders, export, demo data |
| `APRFree/Design` | Colors, brands, shared components, card and pass views |
| `APRFree/Screens` | One file per screen or flow. `OnboardingMotion.swift` holds every animation in first-run setup |
| `APRFreeWidgets` | Widget extension (small, medium, lock screen) |
| `Shared` | The snapshot the app writes for the widget |
| `APRFreeTests` | Engine and store tests |
| `Config` | Entitlements and the widget's Info.plist |

## Bank names

There is no logo artwork in the app. Each bank or provider name is drawn as text in a typeface that ships with iOS, chosen to suggest that brand's wordmark (see `Brand` in `APRFree/Design/Theme.swift`). The banks' own logo typefaces are proprietary and are not used. Setting `Wordmark.styled` to `false` in that file draws every name in the plain system font instead.

## Privacy

No network code, no analytics, no account. Data is one JSON file in the app's own storage, written with complete file protection. Both targets carry a privacy manifest (`PrivacyInfo.xcprivacy`) declaring their use of `UserDefaults`.

## Other documents

- `preparation.txt`: what is needed before an App Store release.
- `checkup_oct5.txt`: the October 5, 2026 review: what was checked, found and fixed.
- `FUTURE_DEVELOPMENT.txt`: features and decisions still open.

## Known gaps

- Only run in the iOS Simulator so far, not on a physical iPhone.
- Lock-screen widget sizes, reminders actually firing, and the CSV, PDF, backup and restore dialogs have not been exercised end to end.
- There is no app icon yet, and no signing team is set.

## Notes

The demo data is fictional. Bank and provider names are used only to label debts; this project is not affiliated with any of them. APRFree is a planning tool, not financial advice.
