import AppKit
#if SWIFT_PACKAGE
import MacCtrlHTTPCore
#endif
import SwiftUI

@main
struct MacCtrlHTTPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(ControllerLanguage.preferenceKey, store: AppSharedPreferences.defaults)
    private var languageCode = ControllerLanguage.chinese.rawValue

    private var language: ControllerLanguage {
        ControllerLanguage(rawValue: languageCode) ?? .chinese
    }

    var body: some Scene {
        WindowGroup {
            ControlPanelView()
                .frame(width: 344)
                .background(WindowChrome().frame(width: 1, height: 1))
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: WindowContentSizePreference.self, value: geometry.size)
                    }
                }
                .onPreferenceChange(WindowContentSizePreference.self) { size in
                    WindowSizeController.shared.request(size)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .defaultSize(width: 344, height: 560)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu(language.menuTitle) {
                ForEach(ControllerLanguage.allCases) { option in
                    Button {
                        languageCode = option.rawValue
                        AppSharedPreferences.save(option.rawValue, forKey: ControllerLanguage.preferenceKey)
                    } label: {
                        HStack {
                            if option == language {
                                Image(systemName: "checkmark")
                            }
                            Text(option.displayName)
                        }
                    }
                }
            }
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WindowSizeController.shared.reopen() }
        return true
    }
}

private struct WindowContentSizePreference: PreferenceKey {
    static var defaultValue = CGSize(width: 344, height: 560)

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 1, next.height > 1 {
            value = next
        }
    }
}

private struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowChromeView {
        WindowChromeView()
    }

    func updateNSView(_ nsView: WindowChromeView, context: Context) {}
}

private final class WindowChromeView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isMovableByWindowBackground = true
            window.hasShadow = true
            window.isReleasedWhenClosed = false
            window.styleMask.formUnion([.closable, .miniaturizable, .resizable])
            window.collectionBehavior.insert(.fullScreenPrimary)
            if let close = window.standardWindowButton(.closeButton) {
                close.target = WindowSizeController.shared
                close.action = #selector(WindowSizeController.closeWindow(_:))
            }
            if let zoom = window.standardWindowButton(.zoomButton) {
                zoom.isEnabled = true
                zoom.target = window
                zoom.action = #selector(NSWindow.toggleFullScreen(_:))
            }
            WindowSizeController.shared.bind(window)
        }
    }
}

private final class WindowSizeController: NSObject {
    static let shared = WindowSizeController()

    private var window: NSWindow?
    private var requestedSize: CGSize?

    func bind(_ window: NSWindow) {
        self.window = window
        applyRequestedSize()
    }

    @objc func closeWindow(_ sender: Any?) {
        window?.orderOut(sender)
    }

    func reopen() {
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }

    func request(_ size: CGSize) {
        guard size.width.isFinite, size.height.isFinite, size.width > 1, size.height > 1 else { return }
        DispatchQueue.main.async { [weak self] in
            self?.requestedSize = CGSize(width: ceil(size.width), height: ceil(size.height))
            self?.applyRequestedSize()
        }
    }

    private func applyRequestedSize() {
        guard let window,
              !window.styleMask.contains(.fullScreen),
              let requestedSize,
              let currentSize = window.contentView?.bounds.size,
              abs(currentSize.width - requestedSize.width) > 1
                || abs(currentSize.height - requestedSize.height) > 1 else {
            return
        }

        let topEdge = window.frame.maxY
        window.setContentSize(requestedSize)
        let resizedFrame = window.frame
        window.setFrameOrigin(NSPoint(x: resizedFrame.minX, y: topEdge - resizedFrame.height))
    }
}
