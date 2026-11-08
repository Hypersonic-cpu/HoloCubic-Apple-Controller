# MacCtrlHTTP

A small translucent macOS controller for the HoloCubic `ActionCtrlHTTP` service.

## Build and launch

Requires macOS 13 or later and Xcode Command Line Tools.

```sh
./scripts/build-app.sh
./scripts/run-app.sh
```

The device IP is entered in the app and automatically saved in its macOS preferences. The app does not depend on an environment variable.

The app includes a `Language` menu in the macOS menu bar with Simplified Chinese, English, and French. The Settings section can be collapsed to shrink the window; its expanded state is saved.

## Use

- Click the four rounded triangle buttons or press the arrow keys.
- Enter sends A, Escape sends Home, and Space sends B. A/B letter keys remain available as aliases. A short Escape sends a normal Home tap; holding Escape for at least 800 ms sends one Home press with `hold_ms: 1000` after key release.
- Enter the `ActionCtrlHTTP` token and device IP. Both are saved in the app's macOS preferences and restored on the next launch. The eye button toggles token visibility.
- The app checks `GET /remote/api/v1/status` on launch. The settings-row pill checks connectivity and uploads `BUFFER SIZE` through `POST /remote/api/v1/settings` only when it differs from the onboard value.
- `BUFFER SIZE` is saved locally and on the device (1–32, default 16). `MIN INTERVAL` is saved locally (0–999 ms, default 500 ms) and limits macOS directional-key auto-repeat. Separate key presses are not locally discarded by this interval and can fill the Onboard FIFO.
- Controller buttons use `POST /remote/api/v1/tap` with `X-ActionCtrl-Token`.

Arrow key auto-repeat is sent at the configured `MIN INTERVAL`; Enter, Space, and letter-key auto-repeat are ignored. Escape is measured through key-up so a short press remains a tap and a long press can request a timed Home hold. HTTP is plain text on the local network, matching the device service.

## Tests

```sh
swift test
```

Tests use a mock HTTP transport and do not send button events to the physical device.
