# Publishing Rupio on Google Play

Everything the Play Console asks for, with the answers for Rupio. The files
mentioned are in this `store/` folder.

## 0. What is ready

| Item | File |
|---|---|
| App icon 512 × 512 | `icon-512.png` |
| Feature graphic 1024 × 500 | `feature-graphic.png` |
| Phone screenshots 1080 × 1920 (6) | `screenshots/phone/*.png` |
| Title, short and full description (6 languages) | `listing/<language>/` |
| Privacy policy | `../PRIVACY.md` (see step 4) |
| App bundle (.aab) | built by GitHub Actions, see step 2 |

The Google Play build has **no SMS permission** and no Gmail login: Google
only allows reading SMS after a separate "SMS permission declaration" is
approved, and Gmail read access needs a paid security review. Statement
PDFs, manual entry and everything else work the same. The APK on GitHub
keeps SMS auto-detect.

## 1. Developer account (once)

Rupio is published from a **business (organization) account**. The
account's organization name is shown as the developer on Google Play; the
app itself is still called Rupio.

Organization accounts do **not** need the 12-tester, 14-day closed test
that new personal accounts must run: after the internal test (step 7) you
can go straight to production (step 9).

## 2. Signing key and app bundle (once)

The private upload key was generated for you (`rupio-upload-key.jks` plus a
README with its password). Keep both in a safe place, such as your Google
Drive. **Never put them in the repository.**

On GitHub, open the repository → **Settings → Secrets and variables →
Actions → New repository secret**, and add:

| Name | Value |
|---|---|
| `RUPIO_UPLOAD_KEYSTORE_BASE64` | the whole content of `rupio-upload-key.base64.txt` |
| `RUPIO_UPLOAD_STORE_PASSWORD` | the password from the README |
| `RUPIO_UPLOAD_KEY_ALIAS` | `rupio-upload` |
| `RUPIO_UPLOAD_KEY_PASSWORD` | the password from the README |

After that, each run of the "Rupio (Flutter)" workflow also produces an
artifact named **rupio-play-bundle** (`app-play-release.aab`). Download it
from the run's page (Actions → the run → Artifacts).

Every upload to Play needs a higher version code: before a new release,
raise `version:` in `pubspec.yaml`, for example `1.0.0+1` → `1.0.1+2`.

## 3. Create the app

Play Console → **Create app**:
- App name: `Rupio – Expense & EMI Tracker`
- Default language: English (United States) – en-US
- App or game: **App** · Free or paid: **Free**
- Accept the declarations.

## 4. App content (Policy → App content)

- **Privacy policy:** the public link to `PRIVACY.md`, for example
  `https://maheshraikg.github.io/rupio/privacy.html`
- **App access:** All functionality is available without special access.
- **Ads:** No, the app does not contain ads (if ads are added later, answer
  Yes and update the privacy policy and Data safety form).
- **Content rating:** start the questionnaire, category **Utility,
  productivity, communication or other**; answer **No** to every question
  (no violence, no sexual content, no gambling, no user-generated content
  shared with others, no location sharing). Expected rating: Everyone / 3+.
- **Target audience:** 18 and over (it is a finance app; choosing only
  adults keeps it out of the Families programme).
- **News app:** No.
- **Government app:** No.
- **Financial features:** declare that the app provides **personal finance
  management / budgeting**; it offers no loans, no payments processing, no
  banking, no crypto, no trading. (Pay bill only opens other payment apps.)
- **Health apps:** No.
- **Data safety:**
  - Does the app collect or share user data? **No.** All data stays on the
    device; nothing is sent to the developer or third parties.
  - Is data encrypted in transit? Not applicable (no data is transmitted;
    the only network use is downloading public fund prices from AMFI).
  - Can users request deletion? Users delete data in the app, or by
    uninstalling it.

## 5. Store listing (Grow → Store presence → Main store listing)

- App name, short description, full description: from `listing/en-US/`.
- App icon: `icon-512.png` · Feature graphic: `feature-graphic.png`.
- Phone screenshots: all files in `screenshots/phone/` in their order.
- Category: **Finance** · Tags: Budgeting, Personal finance.
- Contact email: maheshraikg@gmail.com (the same address is in
  `PRIVACY.md`). Website: optional; your business website if you have one.
- **Translations:** "Manage translations → Add your own translation text"
  for Hindi, Kannada, Malayalam, Tamil and Telugu, using the files in
  `listing/hi-IN`, `kn-IN`, `ml-IN`, `ta-IN` and `te-IN`.

## 6. App signing

On the first upload Play asks how to sign: keep **"Use Play App Signing"**
(recommended). Google keeps the final signing key; the upload key only
proves the upload comes from you. If the upload key is ever lost or
leaked: Setup → App signing → **Request upload key reset**.

## 7. Internal test (optional, quick check)

Testing → Internal testing → Create release → upload
`app-play-release.aab` → add your own Gmail as a tester → install from the
opt-in link and check the app.

## 8. Closed test (only for personal accounts – skip with a business account)

New *personal* accounts created after November 2023 must run this before
production. Business accounts can skip this step.


1. Testing → Closed testing → create a track, upload the same `.aab`.
2. Testers: add an email list with **at least 12 Gmail addresses** (friends
   and family) and share the opt-in link with them.
3. They install it from the link and keep it for **14 days**; ask them to
   open it a few times and add an entry.
4. After 14 days: Dashboard → **Apply for production access** and answer
   the short questions about the test.

## 9. Production

Production → Create release → upload the `.aab` → release notes (e.g.
"First release of Rupio") → Review → Start rollout. Review usually takes a
few days.

## Later: bank SMS on Google Play

To bring SMS auto-detect to the Play version, submit the **Permissions
declaration form** for READ_SMS choosing the "SMS-based money management"
use case, with a short screen recording, and build the Play flavor with the
SMS permission. Approval is up to Google and can take weeks; until then
the Play build stays without SMS.
