# TaskManager

Internal task management system with a C++ (Drogon) HTTPS API backend and a Flutter Web frontend.

## Repository layout

```
backend/          C++ API server (Drogon, SQLite, OpenSSL)
frontend/         Flutter Web client (auth + profile demo)
libraries/drogon/ Vendored Drogon source (reference only — not used by the build)
```

## Prerequisites

### System packages (Ubuntu / Debian / Raspberry Pi OS)

```sh
sudo apt update
sudo apt install -y \
  build-essential cmake git \
  libsqlite3-dev libssl-dev libjsoncpp-dev libcurl4-openssl-dev \
  uuid-dev zlib1g-dev
```

### Install Drogon from source

There is no `apt` package for Drogon — it must be built and installed system-wide.

```sh
git clone https://github.com/drogonframework/drogon.git
cd drogon
git submodule update --init
mkdir build && cd build
cmake ..
make -j$(nproc)
sudo make install
cd ../..
```

After this, `find_package(Drogon CONFIG REQUIRED)` in CMake will resolve correctly.

### Flutter (frontend only)

Install the [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel). The frontend is web-only, so no Android/iOS setup is needed.

## Clone and build

```sh
git clone <repo-url>
cd TaskManager
```

### Backend

```sh
# 1. Configure (run once, or after CMakeLists.txt changes)
cmake -S backend -B backend/build

# 2. Build
cmake --build backend/build -j$(nproc)
```

The binary lands at `backend/build/TaskManagerBackend`.

### Frontend

```sh
cd frontend
flutter pub get
```

## Running locally

### Backend — quick start

`run-local.sh` handles env vars, dev TLS certs, and rebuilding:

```sh
# Make sure you've run the cmake configure step above first
./backend/run-local.sh
```

This will:
- Generate (and reuse) a dev JWT secret
- Use `backend/dev-cert.pem` / `dev-key.pem` for HTTPS
- Create the SQLite database at `backend/task_manager.sqlite3`
- Listen on `https://0.0.0.0:5555`
- Allow CORS from `http://localhost:5000`

### Backend — manual start

Set the required environment variables and run the binary directly:

```sh
export TASK_MANAGER_JWT_SECRET="$(openssl rand -base64 48)"
export TASK_MANAGER_TLS_CERT=backend/dev-cert.pem
export TASK_MANAGER_TLS_KEY=backend/dev-key.pem
./backend/build/TaskManagerBackend
```

See `backend/README.md` for the full env-var table.

### Frontend

```sh
cd frontend
flutter run -d chrome --web-port=5000 --dart-define=API_BASE_URL=https://localhost:5555
```

The web port (`5000`) must match the backend's `TASK_MANAGER_CORS_ORIGIN`.

## Tests

```sh
# Run all backend tests
ctest --test-dir backend/build

# List test cases
./backend/build/test/TaskManagerBackend_test -l

# Run a single test case
./backend/build/test/TaskManagerBackend_test -r AuthInputValidation
```

## Command reference

| Task | Command |
|---|---|
| Configure backend | `cmake -S backend -B backend/build` |
| Build backend | `cmake --build backend/build -j$(nproc)` |
| Run backend (dev) | `./backend/run-local.sh` |
| Run all tests | `ctest --test-dir backend/build` |
| Run frontend | `cd frontend && flutter run -d chrome --web-port=5000 --dart-define=API_BASE_URL=https://localhost:5555` |
| Lint frontend | `cd frontend && flutter analyze` |

## Generating dev TLS certificates

If `dev-cert.pem` / `dev-key.pem` don't exist yet:

```sh
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout backend/dev-key.pem -out backend/dev-cert.pem \
  -days 365 -subj "/CN=localhost"
```

These are self-signed and for local development only.

## Notes

- The backend is HTTPS-only; startup fails if cert/key files are missing.
- SQLite is the only database — no external DB server needed.
- Registration is capped at 25 active accounts and restricted to `@uharvest.in` emails.
- Tokens are held in memory only (no browser-storage persistence).
- The vendored `libraries/drogon/` is not used by the build — only the system-installed Drogon is linked.
