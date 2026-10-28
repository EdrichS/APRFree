# APRFree

A personal debt-payoff app for iPhone. It keeps every credit card, buy-now-pay-later plan and loan in one place, splits each paycheck across them, and shows when you will be debt-free. Everything stays on the device: there is no account, no server and, in a release build, no network code.

Built with SwiftUI for iOS 26.

## What it does

The app has four pages you swipe between: Home, Progress, Statements and Credit Utilization.

- **Home.** A total balance card with every card and pay-later plan stacked under it, loans as boarding-pass tiles, and six tools: Strategy, Simulator, Insights, Income, Extra Money and Export. Tapping the total opens a ring chart of every balance with its share and its interest per day.
- **Make a Payment.** Two paths. A *paycheck* keeps your safety buffer, covers every minimum due before the next payday, and sends the rest to the first debt in your strategy. *Extra money* (a bonus, a refund) holds nothing back, goes to anything overdue and then straight down the strategy, shows the interest it saves, and uses up no payday. Either way you pay in each bank's own app, then mark each line paid.
- **Income.** As many incomes as you have, each weekly, every two weeks or monthly on the day or days you choose, with the next paydays worked out across all of them. Or one fixed amount a month in their place.
- **Due dates that work like a bank's.** A due date stays until its minimum is met. Partial payments shrink what is left. Once met, the next due date is the same day next month, and extra payments never push it further. A payment made on its own starts counting toward the next due date nine days after the previous one; a minimum ticked off in a paycheck split always counts, because it was paid as that minimum. Pay-later plans have no such wait: one payment settles one installment.
- **Three strategies.** Avalanche (highest APR first), Snowball (smallest balance first) and Custom (drag to reorder). A table compares all three on your own debts.
- **Simulator.** Try a one-time payment, any monthly extra, a new purchase or another strategy. Hold and drag the chart to read the balance on any date for the current plan and the what-if.
- **Detail screens.** Cards show balance, payment due, APR, utilization, payoff month and the total cost of the card on your plan versus minimums only. Loans show projected total interest and a "pay a bit extra" calculator. Pay-later plans show the installment schedule.
- **Progress.** A payoff countdown and balance chart you can swipe between Total, Credit cards and Loans, a shelf for paid-off loans and plans, upcoming due dates and recent activity.
- **Statements.** One statement for every month, stacked like passes from the oldest to the newest: what was paid, charged and recorded as interest, and where each balance ended. The monthly check-in sets each balance to what its real statement says, which is how card interest gets counted. Insights shows the same recorded interest for a month once it has a check-in.
- **Credit Utilization.** The last page: how much of your credit limits is in use now, over time and on your plan, month by month with the change from the month before, and card by card with the day each drops under 30%. It is measured against today's limits; past limits are not kept.
- **History, editing and undo.** Every payment, charge, check-in and balance edit is recorded with the balance it left. Tap an entry to change it (the amount or day of a payment or charge; the balance, interest or day of a check-in or balance change) or to undo it. Later entries for that debt are applied again so they stay correct, and the balance history is redrawn from the entries. Undo and Redo in the Home menu take back the last action of any kind, a deleted debt included.
- **Setup.** First run shows the privacy policy and a disclaimer, each of which has to be accepted, then asks for your debts, your pay, a safety buffer, a strategy and reminders. Settings has Reset Everything.
- **Also:** local reminders for due dates, paydays and the monthly statement check-in, CSV export, a PDF report with charts, backup and restore, and a Home Screen widget that can follow the total, the cards or the loans, with an eye button that hides the amounts.

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
| `-screen <name>` | Debug builds only. Opens straight on a screen: `progress`, `statements`, `utilization`, `strategy`, `simulator`, `insights`, `income`, `extra`, `export`, `settings`, `connected`, `activity`, `breakdown`, `add`, `pay`, `celebrate`, or the start of a debt's name such as `chase`. |
| `-connected` | Debug builds only. Turns Connected mode on with the first two sample banks signed in. Use it with `-demo`. |

## Tests

```bash
xcodebuild test -project APRFree.xcodeproj -scheme APRFree -destination 'platform=iOS Simulator,name=iPhone 17'
```

76 tests cover the payoff engine, due-date rules, incomes and paydays, both payment paths, history, undo and redo, entry editing, statements, utilization, reminders, Connected mode against the sample bank, the logo views, formatting, export, backup, and bringing older saved data up to date. The expected figures were worked out with a separate Python model of the same rules, written independently of the Swift code (the script is not in this repository).

Three of the tests are broader than the rest:

- Every ordering of the debts is run as a whole plan, 720 and then 5,040 of them, to confirm none costs less interest than Avalanche.
- The plan is checked against the original day-by-day method, kept in the test file as a reference, on 160 made-up situations.
- 1,320 random actions (payments, edits, undo and redo, check-ins, splits, deletions, time passing) are played against the store, and the data is checked for consistency after every one.

## How the math works

- Interest is APR / 365 per day. Cards compound it into the balance. Loans charge it on principal and the next payment covers it first.
- A plan pays, on each payday, everything due before the next payday, then sends the remainder down the strategy order. Pay-later plans follow their own schedules. A 0% promo card can be held at its minimum until the promo ends.
- The plan works in whole calendar days and takes each stretch between paydays in one step: n days of daily compounding multiply a card's balance by (1 + rate)^n. A test checks that against adding it up a day at a time.
- A debt's payoff month is the month of the due date its final payment covers.
- Card balances do not grow on their own: interest shows up when you check in a statement, edit the balance or add a charge.
- Dates are saved as calendar days ("2026-10-09"), with no time and no time zone, so a due date is the same day wherever the iPhone is. Older files, which held moments in time, are converted when they are opened.

## Project layout

| Path | Contents |
|---|---|
| `APRFree/Models` | `Debt`, payment records, incomes and settings |
| `APRFree/Engine` | Payoff simulation, payday and extra-money splits, the pay calendar, formatting |
| `APRFree/Store` | App state, persistence and migration, the undo journal, balance history, statements, reminders, export and the PDF report, demo data |
| `APRFree/Design` | Colors, brands, the app's own logo views, shared components, card and pass views |
| `APRFree/Connected` | Connected mode: what is kept about bank sign-ins, the bank service protocol, the sample bank, and how bank figures become entries |
| `APRFree/Screens` | One file per screen or flow. `OnboardingMotion.swift` holds every animation in first-run setup |
| `APRFreeWidgets` | Widget extension (small, medium, lock screen) |
| `Shared` | The calendar-day type and the snapshot the app writes for the widget |
| `APRFreeTests` | Engine and store tests |
| `Config` | Entitlements and the widget's Info.plist |
| `Brand` | The icon, logo and wordmark as PNG and SVG files, and the script that draws them and the app icon |

## Bank names

There is no logo artwork in the app. Each bank or provider name is drawn as text in a typeface that ships with iOS, chosen to suggest that brand's wordmark (see `Brand` in `APRFree/Design/Theme.swift`). The banks' own logo typefaces are proprietary and are not used. Setting `Wordmark.styled` to `false` in that file draws every name in the plain system font instead.

## Connected mode

An optional mode, off by default, that lets a bank fill in balances and terms. What a bank reports arrives as a "Bank update" entry in Activity that can be seen, edited and undone, never as a silent change; where the bank and the user disagree, both figures are shown and the user chooses once for that debt. It only reads: the app never moves money.

Only the app's half exists. Debug builds talk to a sample bank that makes its figures up on the iPhone from the debts already entered, so the whole flow can be tried (`-demo -connected -screen connected`). A release build has no bank service, so the switch, the screen and the menu entry do not appear in it. The server and the Plaid side are planned in `PlaidPlan.txt`.

## Icon and logo

The app icon (default, dark and tinted, at every size), the wordmark and the lockup follow the design canvas board "16 · App icon and logo". `swift Brand/make-brand.swift` draws all of them: the icon set in the asset catalog, and PNG and SVG files in `Brand/` for use outside the app. `Brand/README.txt` says what each file is for. The same drawings are SwiftUI views in `APRFree/Design/Logo.swift`.

## Privacy

No analytics, no account, and in a release build no network code. Data is one JSON file in the app's own storage, written with complete file protection. Both targets carry a privacy manifest (`PrivacyInfo.xcprivacy`) declaring their use of `UserDefaults`. Shipping Connected mode for real would change all of this; `PlaidPlan.txt`, section 8, lists how.

## Statement typeface

The month and year on each statement were asked for in Apple Chancery. That face ships with macOS but not with iOS, and its licence does not allow copying it into an app, so on an iPhone the app uses Snell Roundhand, the nearest script that iOS does ship. `StatementFont` in `APRFree/Screens/StatementsPage.swift` holds the list of names it tries, in order.

## Other documents

- `preparation.txt`: what is needed before an App Store release.
- `PlaidPlan.txt`: the plan for Connected mode with Plaid: what is free, the server, and what it changes for the App Store.
- `Brand/README.txt`: the icon and logo files and how to make them again.
- `FUTURE_DEVELOPMENT.txt`: features and decisions still open.

## Known gaps

- Only run in the iOS Simulator so far, not on a physical iPhone.
- Lock-screen widget sizes, reminders actually firing, and the CSV, PDF, backup and restore dialogs have not been exercised end to end.
- No signing team is set. The app icon has only been seen in the Simulator.
- Connected mode has only ever talked to the sample bank. There is no server, and no real bank has been connected.
- The privacy policy and the disclaimer were written for this app but have not been reviewed by a lawyer.

## Notes

The demo data is fictional. Bank and provider names are used only to label debts; this project is not affiliated with any of them. APRFree is a planning tool, not financial advice.
