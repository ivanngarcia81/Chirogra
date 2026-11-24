# Chirogra · Information Security Policy

**Version 1.0 · Effective November 23, 2026 · Owner: Ivan Garcia, Founder & Lead Developer (ig07644@gmail.com)**

Reviewed at least once a year and whenever the system or its providers change materially.

## 1. Purpose and scope

Chirogra is a bookkeeping app for US small businesses (invoices, expenses, banking, reports and sales tax) for
iPhone, iPad and Mac. This policy covers the people, systems and providers that store or process Chirogra customer
data, including bank data received from Plaid through the optional "Chirogra + Bank" plan. Its goal is to protect
the confidentiality, integrity and availability of that data and to identify, mitigate and monitor security risks.

## 2. Roles and responsibility

The Founder is responsible for information security: maintaining this policy, granting and revoking access,
reviewing providers, and responding to incidents. Anyone given access in the future must read and accept this
policy first, and gets only the access their work requires.

## 3. Data we handle and where it lives

- **The business's books** (customers, vendors, invoices, expenses, journal entries, receipts): stored on the
  user's own devices and, if the user turns it on, in the private database of the user's own iCloud account
  (Apple CloudKit). **Chirogra's server never stores the books.**
- **Account data:** users who turn on a connected feature sign in with Apple. Chirogra receives only Apple's
  stable user identifier and, if the user shares it, an email address (which may be Apple's private relay).
- **Bank data (optional, US only, through Plaid):** institution name, account names and last four digits,
  balances, transactions and monthly statements. **Chirogra is read-only: it never moves money.** Bank usernames
  and passwords are entered in Plaid Link and are never seen or stored by Chirogra.
- **On the server** (Supabase): the Plaid access tokens, the status of each connection, and a short-lived
  delivery queue ("mailbox"). New bank data waits in the mailbox only until the user's app collects it, writes it
  into the books and confirms; it is then deleted from the server.
- Chirogra has no advertising and no third-party analytics. Subscriptions are billed by Apple; Chirogra never sees
  payment card details.

## 4. Access control and authentication

- **Centralized identity:** the Founder has one company identity (Google account with passkey and a hardware
  security key). Administrative accounts (GitHub, Supabase, Plaid, Apple Developer) sign in through that
  identity wherever the provider supports it, and every credential is kept in a single password manager
  (1Password, unlocked with a hardware key). Accounts are personal and never shared.
- **Phishing-resistant MFA:** administrative accounts use passkeys or hardware security keys where the provider
  supports them, and authenticator-app codes only where it does not. SMS is not used.
- **Least privilege:** each person gets only the access their work requires, and the list of who has access is
  reviewed every quarter.
- **Provisioning and de-provisioning:** access is granted only through the central identity and the provider's
  team settings. When someone leaves or changes role, their identity is disabled and their access to every system
  is removed or adjusted **the same day**, following a written checklist (identity, GitHub, Supabase, Plaid,
  Apple, 1Password, and rotation of any secret they could have seen).
- **Zero trust:** there is no trusted internal network. All production systems are cloud services reached over
  TLS, and every access is authenticated per person with MFA and authorized by role; no access is granted based on
  network location.
- **Customer accounts:** connected features require **Sign in with Apple**, which requires the user's Apple
  Account to have two-factor authentication. Only the owner of a business's books can open Plaid Link for that
  business; the server checks the signed-in user and an active "Chirogra + Bank" subscription (verified with Apple
  on the server) before creating a Link session. On the device, the app can require Face ID, Touch ID or the
  device passcode to open.
- **Plaid access tokens** are stored encrypted in the Supabase Vault, in a schema with no access for app users at
  all. Only server functions running with the service role can read them; no device ever receives one. Each user
  can read only their own connections and mailbox, enforced by row-level security in the database.

## 5. Data protection and encryption

- **In transit:** all traffic between the apps, the server, Apple and Plaid uses TLS (HTTPS).
- **At rest:** server data is stored in Supabase (PostgreSQL), which encrypts it at rest (AES-256); Plaid access
  tokens are additionally encrypted in the Supabase Vault. Books synced through iCloud are stored in the user's
  private CloudKit database, encrypted by Apple. On devices, the app's database uses iOS/iPadOS data protection,
  and Macs used for development have FileVault turned on.
- **Backups made by users** (`.chirogra` files) can be protected with a password (AES-GCM with a PBKDF2-derived
  key) and carry an integrity checksum (SHA-256).
- **Machine authentication:** services authenticate with signed tokens (JWT) and secret keys over TLS. Plaid
  access tokens and service keys are never sent to devices.
- **Secrets** (Plaid client ID and secret, service keys) live only in the server's secret store, never in source
  code. The source repository is checked for leaked secrets (GitHub secret scanning and push protection).

## 6. Secure development and change management

- All code changes go through version control (Git/GitHub) with a written description and are tested before
  release: unit tests and user-interface tests run automatically on every push (GitHub Actions), plus manual tests
  on simulators and devices.
- Database changes are made only through reviewed migrations. Permission and isolation rules have automated tests
  that must pass before a migration is applied to production.
- Apps are distributed only through the Apple App Store (and TestFlight for beta testers).

## 7. Vulnerability and patch management

- **Scanning:** the code repository is scanned automatically for vulnerable dependencies (GitHub Dependabot alerts
  and security updates) and for leaked secrets. The database is scanned with the Supabase Security and Performance
  Advisors at least monthly and before every release. Work devices run current OS security updates and XProtect.
- **Patch SLA:** confirmed vulnerabilities are fixed or mitigated within **7 days** if critical, **30 days** if
  high, and **90 days** (or the next release) if medium or low. A leaked secret is rotated immediately.
- Development tools, operating systems and third-party libraries (Supabase, Plaid Link) are kept up to date;
  end-of-life software is replaced before it stops receiving security updates.
- Work devices use full-disk encryption, a screen lock and current OS updates.

## 8. Logging and monitoring

- Every change to the books is recorded in an audit log on the user's devices (what changed, when and on which
  device) that cannot be edited or deleted from the app. Posted entries are never deleted: corrections reverse
  the original entry and record a new one, and closed periods require a password or a recorded reason.
- Server function and database logs (Supabase) are reviewed when anomalies are reported and as part of each
  release.

## 9. Incident response

When a security incident is suspected (unauthorized access, a leaked key, data exposure):

1. **Contain:** revoke or rotate the affected credentials and keys (including Plaid secrets and, if needed,
   remove affected Plaid Items) and block the access path.
2. **Assess:** use the server logs to determine what data and which users were affected.
3. **Notify:** tell affected customers, Plaid (as its agreement requires) and authorities where the law
   requires, without undue delay.
4. **Fix and review:** fix the root cause, add a test that would have caught it, and update this policy if
   needed.

## 10. Data retention and deletion

- The books stay on the user's devices and iCloud, under the user's control; deleting the app's data or the
  business in the app removes them.
- Bank data on the server is kept only until the user's app collects it. Anything not collected within
  **30 days** is deleted automatically.
- A user can disconnect a bank at any time. Chirogra then calls Plaid `/item/remove` and deletes the access
  token. Transactions already imported stay part of the user's books.
- When a user deletes their Chirogra account (available in the app), Chirogra removes every bank connection in
  Plaid **before** deleting the account and its server data. If Plaid cannot be reached, nothing is deleted and
  the deletion can be retried. Accounts whose bank subscription has ended have their bank connections removed.
- Users can request access to or deletion of their data through the contact at chirogra.com/support.

## 11. Third-party providers

Chirogra relies on Apple (iCloud, Sign in with Apple, App Store and subscriptions), Supabase (server database,
authentication and functions), Plaid (bank connections) and GitHub (source code and automated tests). Providers
are chosen for their security practices and reviewed at least once a year. Data is shared with them only as needed
to run the service, as described in the privacy policy at chirogra.com/privacy.
