# Policy Compliance Audit

## Scope

This audit covers permissions, analytics, notifications, background behavior, in-app disclosures, and release readiness concerns visible in the current MetroSafar codebase.

## Current Findings

### Permissions

- `ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION` are requested in Android.
- Location is used for nearby station suggestions and route convenience flows.
- No background location permission is requested.
- Recommendation:
  Keep location strictly foreground-only unless a future feature truly needs background access. If that changes, add a dedicated disclosure, runtime rationale, and Play Console background location declaration.

### Notifications

- Local notifications are initialized in the app startup path.
- No scheduled or background notification workflow is currently implemented in code.
- Recommendation:
  Add user-facing notification settings, explain the purpose in-app, and ensure only user-benefiting reminders or service alerts are sent.

### Analytics

- No analytics SDK was found in the Flutter dependencies or app initialization path.
- Recommendation:
  If analytics or crash reporting is added later, update the privacy policy, disclosures, consent flow, and Play Data Safety form before release.

### Background Behavior

- No background fetch, persistent background services, or long-running workers were found.
- Recommendation:
  Keep background behavior disabled until there is a clearly justified commuter feature and corresponding policy review.

### Network and Security

- The new in-repo backend currently uses local HTTP for development.
- Android manifest allows cleartext traffic so local development can connect to the backend.
- Recommendation:
  Replace the local dev backend URL with a production HTTPS deployment before Play Store release, remove broad cleartext usage, and restrict Google Maps keys by package/signing certificate.

### Legal and Support

- Privacy policy, terms, support, and in-app disclosures are now available through backend-driven screens.
- Recommendation:
  Review the legal copy with the business/legal owner before release and ensure the published website versions match the in-app language.

## Release Blocking Items

- Replace debug signing with a production upload key
- Deploy the backend over HTTPS
- Remove or scope cleartext traffic to debug-only behavior
- Complete the Play Data Safety form using the final production architecture
- Confirm support email, phone number, and company details with TL Ventures
