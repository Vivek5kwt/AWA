# awa

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

### Push Notifications

This project sends FCM notifications through a Firebase Cloud Function. Deploy
the function found in `functions/` and update `FcmConfig.functionUrl` in
`lib/config/firebase_push.dart` with the HTTPS endpoint provided by Firebase.
