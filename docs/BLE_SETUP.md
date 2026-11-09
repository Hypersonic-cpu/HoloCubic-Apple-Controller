# BLE setup

MacCtrlHTTP advertises a BLE GATT peripheral when **BLE advertising** is enabled. Select
**BLE Only** to send taps and queue-size settings only over BLE; this mode does not use the
device address or the HTTP token. **Auto** prefers a reachable HTTP service and falls back to
an authenticated BLE session. **HTTP Only** preserves the original HTTP path.

The plaintext BLE configuration is stored at:

`~/Library/Application Support/MacCtrlHTTP/ble.json`

The app creates the file on first launch. Its initial debug token is
`clocteck-ble-debug-2026`. To use another token, edit the `token` field and restart
MacCtrlHTTP. The HoloCubic must use the same value in
`/sd/data/blebridge/config.json`. The token is a debugging gate only; it does not encrypt BLE
traffic or protect against radio eavesdropping. Do not reuse the HTTP token.

`docs/ble.example.json` shows the file format. The app settings panel displays the actual
configuration path and the current advertising, HTTP, and BLE states. macOS may ask for
Bluetooth access on first use; allow it for peripheral advertising.

The WidgetKit extension remains HTTP-only and does not use the BLE transport.
