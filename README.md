# Rupio – Expense Tracker

_Formerly RupeeTrack. The Android package id is `com.rupio.app` (test builds
before November 2026 used `com.kspstadk.rupeetrack`; move data across with
Settings › Back up and Restore)._

**Download the latest APK:**
https://github.com/maheshraikg/rupio/releases/download/latest-build/Rupio.apk

A personal finance tracker in Indian rupees for Android, built with Flutter.
It tracks savings accounts, credit cards and investments, and recording an
expense takes only a few seconds. All data stays on the phone. There is no
sign-up and no bank login.

## Features

- **Home**: switch between Expense and Income; one big total for the
  month, year or all time (1M / 1Y / All) with a bar chart; budget left;
  alerts; an overview (net worth, accounts, card dues, investments, EMIs per
  month, savings goals) and that period's entries by day.
- **Loans & EMIs**: home, car, bike, personal or phone EMIs with the EMI
  amount, number of EMIs and first EMI date. Shows EMIs paid and left, the
  next due date, when the loan ends, total EMIs per month and what is left
  to pay. Paying an EMI records it as an expense from your account; an alert
  appears 3 days before each due date.
- **Savings goals**: a target (and optional date) for an emergency fund,
  phone, bike or trip; add or take out money and see how much to put aside
  each month.
- **Graphs that explain themselves**: red bars for spending and green for
  income, one bar per day (1M), month (1Y) or year (All), with a caption
  and a tap-to-read amount; arrows to go back through months and years;
  the 1Y and All views list every month or year, tap one to open it.
- **Insights**: where your income goes ("31% of your income goes to
  EMIs", "out of every ₹100, ₹40 is left") as one stacked bar, no-spend
  streak, change vs last month, daily average, spending pace, income vs
  spending by month and a category breakdown.
- **Loans payoff graph**: what is left to pay month by month (or year by
  year) and the "debt-free by" month; each loan shows % paid.
- **Home screen widget**: this month's spending with a bar per day.
- **First-run tour**: four pages showing the main features, with Skip.
- **Languages**: English, हिन्दी (Hindi), ಕನ್ನಡ (Kannada), മലയാളം
  (Malayalam), தமிழ் (Tamil) and తెలుగు (Telugu);
  chosen from Settings or More › Language (the phone's language is used on
  first start). Translations live in `tool/l10n/<code>.txt`; run
  `python3 tool/l10n/extract.py` after adding text and
  `python3 tool/l10n/build.py` to regenerate `lib/l10n/translations.dart`.
  PDF/Excel reports and CSV exports stay in English.
- **Quick add**: enter the amount, tap a category, tap the account or card,
  then Save. The last category and source are remembered. Also covers income,
  transfers, card bills, refunds and investments. Optional receipt photo
  (camera or gallery) and a **Repeat** option (weekly, monthly, yearly).
- **Activity**: grouped by day with daily totals, search ("petrol", "250",
  "SBI") and filters. Tap to edit, swipe to delete (with undo).
- **Credit cards**: each card is drawn as a card face, with usage, available
  credit, the bill, spend this cycle, the due date and a Pay bill button.
- **Investments**: mutual funds / SIPs, stocks, PPF, NSC, FDs, RDs, Post
  Office schemes, NPS, gold and others, kept separate from spending. Shows
  portfolio value, allocation, gain, return % and yearly return (XIRR). Mutual
  funds can be **linked to the daily NAV from AMFI** (units × NAV); other
  holdings use a value you enter, with its date. When adding a holding you
  already have, enter the amount invested so far and today's value to see
  the gain straight away.
- **Accounts**: bank accounts, cash and UPI wallets, with the total balance
  and savings rate.
- **Budgets**: monthly limit per category, with a warning at 80% and once
  it is exceeded.
- **Recurring entries**: rent, SIPs, subscriptions and salary are recorded
  automatically on each due date.
- **Reminders** (local notifications at 9 AM): card bills 7 days before, 3
  days before and on the due date; recurring entries on their date.
- **Your data**: **Excel (.xlsx) and PDF reports** (summary, accounts,
  cards, investments, budgets and every transaction); export transactions or
  a monthly summary as CSV; back up everything as a JSON file and restore it
  later; **import bank or card
  statements** (CSV), with column detection, category guessing and
  duplicate skipping.
- **Auto-detect** (Settings › Automatic): reads bank SMS on the phone and
  fills in card spends, refunds, payments, the bank's bill (total, minimum,
  due date) and bank account debits/credits for HDFC, SBI / SBI Card, ICICI,
  Axis, Kotak, AU, IDFC FIRST, Amex, OneCard, RBL, IndusInd, Yes, HSBC,
  Standard Chartered, Canara, Bank of Baroda, PNB, Union Bank and more.
  Cards and accounts found in messages can be added with one tap. Entries
  you already typed in, or that arrive by both SMS and email, are counted
  once; deleted imports never come back. New SMS are read whenever the app
  opens.
- **Statement PDFs**: choose one, or share/open it with Rupio from
  Gmail, WhatsApp or Files. Password-protected statements are unlocked on
  the phone.
- **Gmail (optional)**: read-only access to bank alert emails and
  statement PDFs, straight from the phone to Google (see setup below).
- **Pay bill**: open CRED, PhonePe, Google Pay, Paytm, Amazon Pay, BHIM or
  MobiKwik to pay, then record the full, minimum or a custom amount.
- Account, card and investment screens read like a bank statement: entries
  by date with the balance after each one; edit or delete anything.
- Minimal black design (default; a light theme is in Settings): pure black
  background, dark grey cards, white and grey text, green only for money in
  and the main button, coral only for dues and EMIs, neutral vector icons,
  the Inter typeface and a round + button in the bottom bar. Works fully
  offline; the internet is used only when you choose to update fund NAVs.

## Accounting rules

Balances are never stored. They are always recalculated from opening
balances and transactions, so editing or deleting an entry fixes every total.

| Entry | Account | Card owed | Spending | Investments |
|---|---|---|---|---|
| Expense from account | − | | + | |
| Expense on card | | + | + | |
| Income | + | | | |
| Transfer between own accounts | − / + | | | |
| Card bill payment | − | − | (not a second expense) | |
| Refund | + (or card −) | | − | |
| Invest (from account or card) | − | (+) | | + |
| Withdraw from investment | + | | | − |
| Dividend / interest | + if paid out | | | reinvested: already in value |

Amounts are stored as whole paise, so totals never pick up rounding errors.

## Code layout

- `lib/models/`: data types, budgets, recurring rules, validation, rupee
  formatting and parsing
- `lib/ledger/`: balances, card billing cycle, alerts, budgets, returns and
  XIRR (plain Dart, unit-tested)
- `lib/data/`: CSV export, statement import and the AMFI NAV parser
- `lib/sync/`: bank SMS/email parser, statement PDF text parser, the sync
  engine (matching and de-duplication), SMS and Gmail sources
- `lib/app/`: `FinanceStore` (shared_preferences JSON), `AppScope`,
  reminders, file sharing and receipts
- `lib/screens/`, `lib/widgets/`: UI (`widgets/design.dart` holds the theme
  and shared components)

## Build

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Release signing reads `android/key.properties` (`storeFile`,
`storePassword`, `keyAlias`, `keyPassword`) when it exists. Without it, the
committed dev key `android/app/dev-keystore.jks` (password
`rupeetrack-dev`) is used, so every test build has the same signature and
installs over the previous one. It is public: use your own key for the Play
Store.

Dev key fingerprints (for Google Cloud):

- SHA-1 `69:D6:00:FA:B9:D1:38:67:36:72:B5:93:68:E2:7C:F0:6D:A4:DE:C5`

## Gmail setup (optional)

Google allows reading Gmail only for registered apps. For personal use (up
to 100 test users) it is free:

1. In console.cloud.google.com create a project and enable the **Gmail
   API**.
2. **OAuth consent screen**: External; add the scope
   `https://www.googleapis.com/auth/gmail.readonly`; add your Gmail
   address(es) as **test users**.
3. **Credentials**: create an **Android** OAuth client (package
   `com.rupio.app`, the SHA-1 above) and a **Web application**
   client.
4. In the GitHub repository add an Actions **variable**
   `GMAIL_WEB_CLIENT_ID` with the web client id; the next CI build turns the
   Gmail option on. Locally: `flutter build apk
   --dart-define=GMAIL_WEB_CLIENT_ID=…`.

Publishing to everyone on the Play Store additionally needs Google's
verification and a yearly security assessment for this scope. Reading SMS
on the Play Store needs the SMS permission declaration ("SMS-based money
management").

## Google Play

`store/PLAY_CONSOLE.md` walks through publishing step by step, with the
answers for every Play Console form. `store/` holds the icon, feature
graphic, screenshots and the listing text in six languages; `PRIVACY.md`
is the privacy policy. The Play build (`--flavor play`) has no SMS
permission; CI builds a signed `.aab` once the `RUPIO_UPLOAD_*` secrets are
set. `python3 tool/store/make_store_graphics.py` redraws the feature
graphic, the framed Play screenshots and the first-run tour images from
the raw screenshots in `store/screenshots/raw/`.

## Icons

The logo (a white wallet with a green tab) is `store/icon-source.png`.
`python3 tool/icon/make_icons.py` rebuilds the launcher icons (legacy,
adaptive and themed), the notification icon, `store/icon-512.png` and the
Play feature graphic `store/feature-graphic.png` from it.

## Notes

- The app uses the Inter typeface (SIL Open Font License,
  `assets/fonts/Inter-OFL.txt`) and fl_chart for charts.
- PDF reports use the Carlito font (SIL Open Font License,
  `assets/fonts/Carlito-OFL.txt`) for the ₹ sign.
- Receipt photos stay in the app's private folder and are not part of the
  JSON backup.
- Live prices cover mutual funds only (AMFI publishes them free). Stocks,
  PPF, FDs and others use the value you enter.
