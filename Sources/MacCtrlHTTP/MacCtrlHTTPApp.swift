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

final class WindowSizeController: NSObject {
    static let shared = WindowSizeController()

    private var window: NSWindow?

    func bind(_ window: NSWindow) {
        self.window = window
    }

    func resizeToContentMinimum() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self,
                  let window = self.window,
                  !window.styleMask.contains(.fullScreen) else { return }
            let targetSize = window.contentMinSize
            guard targetSize.width > 1, targetSize.height > 1 else { return }
            let currentSize = window.contentView?.bounds.size ?? .zero
            guard abs(currentSize.width - targetSize.width) > 0.5
                    || abs(currentSize.height - targetSize.height) > 0.5 else { return }
            let topEdge = window.frame.maxY
            window.setContentSize(targetSize)
            let resizedFrame = window.frame
            window.setFrameOrigin(NSPoint(x: resizedFrame.minX, y: topEdge - resizedFrame.height))
        }
    }

    @objc func closeWindow(_ sender: Any?) {
        window?.orderOut(sender)
    }

    func reopen() {
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }

}
