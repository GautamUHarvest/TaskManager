# Task Manager Flutter Web

Flutter Web demo for account registration, sign-in, and a small authenticated
profile. The UI uses Material Design 3.

## Requirements

- Flutter SDK with Dart (Flutter 3.22 or newer)
- A browser supported by Flutter Web
- The Task Manager HTTPS backend running and reachable from the browser

## Run locally

From this directory, fetch dependencies and start Flutter's web development
server:

```sh
flutter pub get
flutter run -d chrome \
  --web-port=5000 \
  --dart-define=API_BASE_URL=https://localhost:5555
```

Replace the API URL with the backend host and port when it runs on another
machine. The backend certificate must be valid for that host and trusted by the
browser; do not disable TLS verification in the app.

Set `TASK_MANAGER_CORS_ORIGIN` on the backend to the exact origin shown by
Flutter's development server (for example `http://localhost:5000`). The backend
uses an exact-origin allowlist and handles auth API `OPTIONS` preflight requests.
Do not use a wildcard origin.

## Demo flow

1. Register with a valid `@uharvest.in` address, employee ID, name, and a
   password meeting the backend requirements. After registration, the app
   returns to the sign-in form.
2. Sign in with employee ID or email, then view the profile fetched from
   `/api/auth/me`.

Access and refresh tokens remain in memory and are cleared on page reload or
sign-out. This avoids persisting bearer credentials in browser storage for this
demo; users sign in again after reloading the page.
