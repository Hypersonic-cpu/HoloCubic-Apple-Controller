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

The advertisement includes the 128-bit service UUID without a local name. The HoloCubic scans
for that UUID, and keeping the payload small avoids placing the UUID only in a scan response.

MacCtrlHTTP shows **Authorized** only after the HoloCubic confirms receipt of `auth_ok` with an
`auth_confirm` write on the same session. If the state falls back to Advertising, the central
disconnected; the HoloCubic Service logs its active connection handle and retry state.

The WidgetKit extension remains HTTP-only and does not use the BLE transport.

### Reconnection mitigation (device bridge 0.1.3)

The bridge attempts the last authenticated peer directly about 100 ms after a ready session disconnects, retries up to five direct attempts in total with about 100 ms between a failure and the next attempt, then falls back to active scanning if the attempts fail or the cached peer expires. It re-discovers GATT and re-authenticates on every connection. MTU 247 reduces authentication fragmentation where supported. Measured disconnect-to-authenticated recovery was 2.03–2.33 seconds in the latest samples; this does not fix the periodic disconnect or provide seamless control. No commands are buffered across reconnection. The GUI now refreshes its main status after the new BLE state is stored, avoiding a stale Authorizing label.
