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
- Click A/B or press the physical A/B keys.
- Enter the `ActionCtrlHTTP` token and device IP. Both save automatically in the app's macOS preferences and restore on the next launch. The eye button toggles token visibility.
- The circular radio-wave button beside the IP field tests connectivity with `GET /remote/api/v1/status`; it does not press a controller button. The top indicator turns green when the authenticated status request succeeds.
- The circular up-arrow beside the token sends one B tap to confirm that the token works. Editing either field resets the connection state. Pressing Return in either field performs that row's action.
- Controller buttons use `POST /remote/api/v1/tap` with `X-ActionCtrl-Token`.

The app sends one tap per key-down and ignores keyboard auto-repeat. HTTP is plain text on the local network, matching the device service.

## Tests

```sh
swift test
```

Tests use a mock HTTP transport and do not send button events to the physical device.
