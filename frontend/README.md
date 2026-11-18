# Task Manager Flutter Web

Flutter Web demo for account registration, email verification, sign-in, and a
small authenticated profile. The UI uses Material Design 3.

## Requirements

- Flutter SDK with Dart (Flutter 3.22 or newer)
- A browser supported by Flutter Web
- The Task Manager HTTPS backend running and reachable from the browser

## Run locally

Start the backend in a separate terminal. This local mode prints verification
tokens in the backend terminal instead of sending email:

```sh
cd ../backend
./run-local.sh
```

If port `5555` is already in use, use the backend that is already running or
stop it before starting another instance. The backend's local verification
mode listens only on this machine.

Then, from this directory, fetch dependencies and start Flutter's web
development server:

```sh
flutter pub get
flutter run -d chrome \
  --web-port=5000 \
  --dart-define=API_BASE_URL=https://localhost:5555
```

Replace the API URL with the backend host and port when it runs on another
machine. The backend certificate must be valid for that host and trusted by the
browser; do not disable TLS verification in the app.

The local launcher allows `http://localhost:5000` by default. If Flutter uses a
different origin, set `TASK_MANAGER_CORS_ORIGIN` before starting the backend.
The backend uses an exact-origin allowlist and handles auth API `OPTIONS`
preflight requests. Do not use a wildcard origin.

The backend's local verification-token mode binds to loopback by default. It
works when the browser and API run on the same machine, but a browser on another
device cannot reach it; use the configured SMTP mode for a remote demo.

## Demo flow

1. Register with a valid `@uharvest.in` address, employee ID, name, and a
   password meeting the backend requirements.
2. Verify using the token delivered by email. In the backend's explicit local
   verification-token mode, the token is printed in the backend terminal.
3. Sign in with employee ID or email, then view the profile fetched from
   `/api/auth/me`.

Access and refresh tokens remain in memory and are cleared on page reload or
sign-out. This avoids persisting bearer credentials in browser storage for this
demo; users sign in again after reloading the page.
