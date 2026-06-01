# MetroSafar

MetroSafar is a Flutter commuter app for Hyderabad Metro journeys with booking, rewards, games, legal/support screens, and a lightweight local backend for development.

## Run The Backend

```bash
node backend/server.js
```

The backend listens on `http://127.0.0.1:8080`.

## Run The App

For Android emulators, the app defaults to `http://10.0.2.2:8080`.

To point the app at a different API host:

```bash
flutter run --dart-define=METROSAFAR_API_BASE_URL=https://your-api-host
```

## Tests

Targeted widget tests currently cover:

- splash permission + navigation flow
- booking flow
- navigation from the games hub
- ticket persistence fallback
