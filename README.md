# MacCtrlHTTP

A small translucent macOS controller for the HoloCubic `ActionCtrlHTTP` service.

## Build and launch

Requires macOS 13 or later and Xcode Command Line Tools.

```sh
./scripts/build-app.sh
./scripts/run-app.sh
```

The device IP is entered in the app and automatically saved in its macOS preferences. The app does not depend on an environment variable.

## Use

- Click the four rounded triangle buttons or press the arrow keys.
- Enter sends A, Escape sends Home, and Space sends B. A/B letter keys remain available as aliases.
- Enter the `ActionCtrlHTTP` token and device IP. Both are saved in the app's macOS preferences and restored on the next launch. The eye button toggles token visibility.
- The app checks `GET /remote/api/v1/status` on launch. The settings-row pill checks connectivity and uploads `BUFFER SIZE` through `POST /remote/api/v1/settings` only when it differs from the onboard value.
- `BUFFER SIZE` is saved locally and on the device (1–32, default 16). `KEY DELAY` is saved locally (0–999 ms, default 500 ms); new key presses inside the interval are ignored instead of queued.
- Controller buttons use `POST /remote/api/v1/tap` with `X-ActionCtrl-Token`.

The app sends one tap per key-down and ignores keyboard auto-repeat. HTTP is plain text on the local network, matching the device service.

## Tests

```sh
swift test
```

Tests use a mock HTTP transport and do not send button events to the physical device.
