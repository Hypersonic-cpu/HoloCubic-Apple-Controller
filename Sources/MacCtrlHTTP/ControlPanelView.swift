import AppKit
#if SWIFT_PACKAGE
import MacCtrlHTTPCore
#endif
import SwiftUI
import WidgetKit

struct ControlPanelView: View {
    @StateObject private var model = ControlPanelModel()
    @AppStorage(ControllerLanguage.preferenceKey, store: AppSharedPreferences.defaults)
    private var languageCode = ControllerLanguage.chinese.rawValue
    @AppStorage("settingsExpanded", store: AppSharedPreferences.defaults)
    private var settingsExpanded = true
    @FocusState private var focusedInput: InputField?

    private var language: ControllerLanguage {
        ControllerLanguage(rawValue: languageCode) ?? .chinese
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            Rectangle()
                .fill(.white.opacity(0.13))
                .frame(height: 1)
                .padding(.horizontal, 2)
            controlSurface
            settingsPanel
            footer
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .frame(width: 344)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 27, style: .continuous)
                        .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.2), radius: 24, y: 12)
                .contentShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
                .onTapGesture { leaveInputMode() }
        }
        .background(KeyboardShortcutCapture(
            action: { send($0, isAutoRepeat: $1) },
            leaveInputMode: { leaveInputMode() },
            onEscape: { isLongPress in
                send(.home, holdMilliseconds: isLongPress ? 1000 : nil)
            },
            onBufferStep: { delta in
                guard focusedInput == .buffer else { return false }
                model.adjustBufferSize(by: delta)
                return true
            }
        ).frame(width: 1, height: 1))
        .onChange(of: model.token) { _, newValue in
            model.saveToken(newValue)
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onChange(of: model.deviceAddress) { _, newValue in
            model.saveDeviceAddress(newValue)
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onChange(of: model.bufferSize) { _, newValue in model.saveBufferSize(newValue) }
        .onChange(of: model.keyDelayMilliseconds) { _, newValue in model.saveKeyDelay(newValue) }
        // @Published emits in willSet; refresh after the manager stores its new state.
        .onReceive(model.bleManager.$state.receive(on: DispatchQueue.main)) { _ in
            model.refreshTransportStatus()
        }
        .onChange(of: languageCode) { _, newValue in
            AppSharedPreferences.save(newValue, forKey: ControllerLanguage.preferenceKey)
            model.setLanguage(ControllerLanguage(rawValue: newValue) ?? .chinese)
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onChange(of: settingsExpanded) { _, newValue in
            AppSharedPreferences.save(newValue, forKey: "settingsExpanded")
        }
        .onAppear {
            model.setLanguage(language)
            model.checkConnection()
            WidgetCenter.shared.reloadAllTimelines()
        }
        .animation(.easeInOut(duration: 0.2), value: settingsExpanded)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [Color.cyan.opacity(0.9), Color.blue.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("HoloCubic")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(language.text(.appSubtitle))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            connectionBadge
        }
        .padding(.top, 4)
    }

    private var connectionBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.online ? Color.green : (model.isCheckingConnection ? Color.cyan : Color.orange))
                .frame(width: 6, height: 6)
            Text(model.online ? language.text(.online) : (model.isCheckingConnection ? language.text(.connecting) : language.text(.waiting)))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.white.opacity(0.07), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1))
        .accessibilityLabel(model.connectionMessage)
    }

    private var controlSurface: some View {
        HStack(spacing: 24) {
            DirectionPad(language: language) { send($0) }
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                ActionKey(button: .a, tint: .cyan) { send(.a) }
                ActionKey(button: .b, tint: .orange) { send(.b) }
                HomeKey { send(.home) }
            }
            .padding(.trailing, 5)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 171)
        .padding(.horizontal, 14)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.black.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.11), lineWidth: 1)
                }
        }
    }

    private var settingsPanel: some View {
        VStack(spacing: 9) {
            Button {
                leaveInputMode()
                settingsExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text(language.text(.settings))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: settingsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.text(.settings))
            .accessibilityValue(settingsExpanded ? language.text(.expanded) : language.text(.collapsed))

            if settingsExpanded {
                VStack(alignment: .leading, spacing: 9) {
                    tokenEntry
                    addressEntry
                    transportSettings
                    settingControls
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var tokenEntry: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(language.text(.tokenLabel), systemImage: "key.fill")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Group {
                    if model.revealsToken {
                        TextField(language.text(.tokenPlaceholder), text: $model.token)
                            .focused($focusedInput, equals: .token)
                    } else {
                        SecureField(language.text(.tokenPlaceholder), text: $model.token)
                            .focused($focusedInput, equals: .token)
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .textContentType(.password)
                .autocorrectionDisabled()
                .onSubmit {
                    leaveInputMode()
                    model.syncDeviceSettings()
                }

                Button {
                    leaveInputMode()
                    model.revealsToken.toggle()
                } label: {
                    Image(systemName: model.revealsToken ? "eye.slash" : "eye")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.revealsToken ? language.text(.hideToken) : language.text(.showToken))
                .accessibilityLabel(model.revealsToken ? language.text(.hideToken) : language.text(.showToken))
            }
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(.black.opacity(0.17), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.13), lineWidth: 1)
            }
        }
    }

    private var addressEntry: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(language.text(.deviceIPLabel), systemImage: "network")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            TextField(language.text(.addressPlaceholder), text: $model.deviceAddress)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .autocorrectionDisabled()
                .focused($focusedInput, equals: .address)
                .onSubmit {
                    leaveInputMode()
                    model.syncDeviceSettings()
                }
                .padding(.horizontal, 11)
                .frame(height: 38)
                .background(.black.opacity(0.17), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.13), lineWidth: 1)
                }
        }
    }

    private var settingControls: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                settingLabel(language.text(.bufferSize))
                HStack(spacing: 4) {
                    TextField("16", value: $model.bufferSize, format: .number)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .focused($focusedInput, equals: .buffer)
                        .onSubmit {
                            leaveInputMode()
                            model.saveBufferSize(model.bufferSize)
                        }
                    VStack(spacing: 1) {
                        bufferStepButton("chevron.up", delta: 1)
                        bufferStepButton("chevron.down", delta: -1)
                    }
                }
                .padding(.horizontal, 7)
                .frame(height: 38)
                .background(.black.opacity(0.17), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.13), lineWidth: 1)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                settingLabel(language.text(.minInterval))
                HStack(spacing: 4) {
                    TextField("500", value: $model.keyDelayMilliseconds, format: .number)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .multilineTextAlignment(.leading)
                        .focused($focusedInput, equals: .keyDelay)
                        .onSubmit {
                            leaveInputMode()
                            model.saveKeyDelay(model.keyDelayMilliseconds)
                        }
                    Text("ms")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .frame(height: 38)
                .background(.black.opacity(0.17), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.13), lineWidth: 1)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                settingLabel(language.text(.device))
                Button {
                    leaveInputMode()
                    model.syncDeviceSettings()
                } label: {
                    HStack(spacing: 5) {
                        if model.isCheckingConnection || model.isSyncingSettings {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.white)
                        } else if model.syncSucceeded == true {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                        } else if model.syncSucceeded == false {
                            Image(systemName: "exclamationmark")
                                .font(.system(size: 10, weight: .bold))
                        } else {
                            Image(systemName: "arrow.up.to.line")
                                .font(.system(size: 10, weight: .bold))
                        }
                            Text(model.syncButtonTitle)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .foregroundStyle(.white.opacity(0.96))
                    .background(syncButtonColor.opacity(0.76), in: Capsule())
                    .overlay(Capsule().strokeBorder(syncButtonColor.opacity(0.82), lineWidth: 1))
                }
                .buttonStyle(SoftPressStyle())
                .disabled(model.isCheckingConnection || model.isSyncingSettings)
                .help(language.text(.syncHelp))
                .accessibilityLabel(language.text(.checkAndSync))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var transportSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            settingLabel(language.text(.controlTransport))
            HStack(spacing: 2) {
                ForEach(ControlTransportMode.allCases) { mode in
                    Button {
                        leaveInputMode()
                        model.setTransportMode(mode)
                    } label: {
                        Text(mode.title(in: language))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .frame(height: 26)
                            .background {
                                if model.transportMode == mode {
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(Color.cyan.opacity(0.3))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.transportMode == mode ? .isSelected : [])
                }
            }
            .padding(3)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(language.text(.controlTransport))

            HStack(spacing: 6) {
                statusIndicator(
                    title: language.text(.httpStatus),
                    value: language.text(model.httpOnline ? .statusAvailable : .statusUnavailable),
                    symbol: "network",
                    active: model.httpOnline
                )
                statusIndicator(
                    title: language.text(.bleStatus),
                    value: model.bleStateMessage,
                    symbol: "dot.radiowaves.left.and.right",
                    active: model.bleManager.state.canControl
                )
            }

            HStack(spacing: 8) {
                Toggle(isOn: Binding(
                    get: { model.bleManager.advertiseOnLaunch },
                    set: { model.setBLEAdvertising($0) }
                )) {
                    Text(language.text(.advertiseBLE))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                Spacer(minLength: 4)
            }
            Text(language.text(.bleConfigLocation, model.bleManager.configurationPath))
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(model.bleManager.configurationPath)
        }
    }

    private func statusIndicator(title: String, value: String, symbol: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(active ? Color.green : Color.secondary)
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 26)
        .background(.white.opacity(0.055), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1))
        .help("\(title): \(value)")
    }

    private var syncButtonColor: Color {
        if model.syncSucceeded == true { return .green }
        if model.syncSucceeded == false { return .red }
        return .cyan
    }

    private func settingLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .tracking(0.55)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func bufferStepButton(_ symbol: String, delta: Int) -> some View {
        Button {
            model.adjustBufferSize(by: delta)
            focusedInput = .buffer
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 15)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(delta > 0 ? language.text(.increaseBuffer) : language.text(.decreaseBuffer))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "wave.3.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(model.online ? Color.green : Color.secondary)
            Text(model.online ? model.actionMessage : model.connectionMessage)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 1)
        .help(model.connectionMessage)
    }

    private func send(
        _ button: RemoteButton,
        holdMilliseconds: Int? = nil,
        isAutoRepeat: Bool = false
    ) {
        leaveInputMode()
        model.send(button, holdMilliseconds: holdMilliseconds, isAutoRepeat: isAutoRepeat)
    }

    private func leaveInputMode() {
        focusedInput = nil
        if let window = NSApp.keyWindow,
           window.firstResponder is NSTextView || window.firstResponder is NSTextField {
            window.makeFirstResponder(nil)
        }
    }
}

private enum InputField: Hashable {
    case token
    case address
    case buffer
    case keyDelay
}

private struct DirectionPad: View {
    let language: ControllerLanguage
    let action: (RemoteButton) -> Void

    var body: some View {
        ZStack {
            DirectionKey(button: .up, rotation: 0, action: action)
                .offset(y: -45)
            DirectionKey(button: .down, rotation: 180, action: action)
                .offset(y: 45)
            DirectionKey(button: .left, rotation: -90, action: action)
                .offset(x: -45)
            DirectionKey(button: .right, rotation: 90, action: action)
                .offset(x: 45)
            Circle()
                .fill(.white.opacity(0.13))
                .frame(width: 5, height: 5)
        }
        .frame(width: 148, height: 148)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(language.text(.directionPad))
    }
}

private struct DirectionKey: View {
    let button: RemoteButton
    let rotation: Double
    let action: (RemoteButton) -> Void

    var body: some View {
        Button { action(button) } label: {
            RoundedTriangle()
                .fill(LinearGradient(colors: [.white.opacity(0.36), .white.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    RoundedTriangle().stroke(.white.opacity(0.4), lineWidth: 1)
                }
                .rotationEffect(.degrees(rotation))
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
        .focusable(false)
        .accessibilityLabel(button.title(in: ControllerLanguage.preferred))
        .help(button.title(in: ControllerLanguage.preferred))
    }
}

private struct RoundedTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        let vertices = [
            CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.08),
            CGPoint(x: rect.maxX - rect.width * 0.06, y: rect.maxY - rect.height * 0.08),
            CGPoint(x: rect.minX + rect.width * 0.06, y: rect.maxY - rect.height * 0.08),
        ]
        let radius = min(rect.width, rect.height) * 0.14
        func point(from vertex: CGPoint, toward other: CGPoint) -> CGPoint {
            let dx = other.x - vertex.x
            let dy = other.y - vertex.y
            let length = max(1, hypot(dx, dy))
            return CGPoint(x: vertex.x + dx / length * radius, y: vertex.y + dy / length * radius)
        }

        var path = Path()
        path.move(to: point(from: vertices[0], toward: vertices[1]))
        for index in [1, 2, 0] {
            let vertex = vertices[index]
            let previous = vertices[(index + 2) % 3]
            let next = vertices[(index + 1) % 3]
            path.addLine(to: point(from: vertex, toward: previous))
            path.addQuadCurve(to: point(from: vertex, toward: next), control: vertex)
        }
        path.closeSubpath()
        return path
    }
}

private struct ActionKey: View {
    let button: RemoteButton
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(button.rawValue.uppercased())
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.94))
                .frame(width: 46, height: 46)
                .background {
                    Circle()
                        .fill(tint.opacity(0.28))
                        .overlay(Circle().strokeBorder(tint.opacity(0.62), lineWidth: 1))
                        .shadow(color: tint.opacity(0.22), radius: 8, y: 3)
                }
                .contentShape(Circle())
        }
        .buttonStyle(SoftPressStyle())
        .accessibilityLabel(button.title)
        .help(button.title)
    }
}

private struct HomeKey: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "house.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.86))
                .frame(width: 36, height: 36)
                .background {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
                }
                .contentShape(Circle())
        }
        .buttonStyle(SoftPressStyle())
        .accessibilityLabel(ControllerLanguage.preferred.text(.home))
        .help(ControllerLanguage.preferred.text(.homeHelp))
    }
}

private struct SoftPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.76 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

private struct KeyboardShortcutCapture: NSViewRepresentable {
    let action: (RemoteButton, Bool) -> Void
    let leaveInputMode: () -> Void
    let onEscape: (Bool) -> Void
    let onBufferStep: (Int) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action, leaveInputMode: leaveInputMode, onEscape: onEscape, onBufferStep: onBufferStep)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.action = action
        context.coordinator.leaveInputMode = leaveInputMode
        context.coordinator.onEscape = onEscape
        context.coordinator.onBufferStep = onBufferStep
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        weak var view: NSView?
        var action: (RemoteButton, Bool) -> Void
        var leaveInputMode: () -> Void
        var onEscape: (Bool) -> Void
        var onBufferStep: (Int) -> Bool
        private var monitor: Any?
        private var keyUpMonitor: Any?
        private var mouseMonitor: Any?
        private var escapeKeyDownAt: TimeInterval?

        init(
            action: @escaping (RemoteButton, Bool) -> Void,
            leaveInputMode: @escaping () -> Void,
            onEscape: @escaping (Bool) -> Void,
            onBufferStep: @escaping (Int) -> Bool
        ) {
            self.action = action
            self.leaveInputMode = leaveInputMode
            self.onEscape = onEscape
            self.onBufferStep = onBufferStep
        }

        func installMonitor() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      let window = self.view?.window,
                      NSApp.keyWindow === window else {
                    return event
                }
                if event.keyCode == 53 {
                    guard !event.isARepeat else { return nil }
                    if Self.isEditingText(in: window) {
                        self.leaveInputMode()
                    }
                    self.escapeKeyDownAt = event.timestamp
                    return nil
                }
                if Self.isEditingText(in: window), [126, 125].contains(event.keyCode) {
                    let step = event.keyCode == 126 ? 1 : -1
                    if self.onBufferStep(step) { return nil }
                }
                guard !Self.isEditingText(in: window),
                      let button = Self.button(for: event) else { return event }
                if event.isARepeat {
                    switch button {
                    case .up, .down, .left, .right:
                        break
                    default:
                        return nil
                    }
                }
                self.action(button, event.isARepeat)
                return nil
            }

            keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
                guard let self,
                      let window = self.view?.window,
                      NSApp.keyWindow === window,
                      event.keyCode == 53,
                      let escapeKeyDownAt = self.escapeKeyDownAt else {
                    return event
                }
                self.escapeKeyDownAt = nil
                self.onEscape(event.timestamp - escapeKeyDownAt >= 0.8)
                return nil
            }

            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self,
                      let window = self.view?.window,
                      NSApp.keyWindow === window,
                      Self.isEditingText(in: window) else {
                    return event
                }
                guard let field = Self.activeTextField(in: window) else {
                    self.leaveInputMode()
                    return event
                }
                let fieldBounds = field.convert(field.bounds, to: nil)
                if !fieldBounds.contains(event.locationInWindow) {
                    self.leaveInputMode()
                }
                return event
            }
        }

        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            if let keyUpMonitor { NSEvent.removeMonitor(keyUpMonitor) }
            if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
            monitor = nil
            keyUpMonitor = nil
            mouseMonitor = nil
            escapeKeyDownAt = nil
        }

        private static func isEditingText(in window: NSWindow) -> Bool {
            window.firstResponder is NSTextView || window.firstResponder is NSTextField
        }

        private static func activeTextField(in window: NSWindow) -> NSTextField? {
            if let field = window.firstResponder as? NSTextField { return field }
            if let editor = window.firstResponder as? NSTextView {
                return editor.delegate as? NSTextField
            }
            return nil
        }

        private static func button(for event: NSEvent) -> RemoteButton? {
            if event.keyCode == 115 {
                return .home
            }
            return switch event.keyCode {
            case 126: .up
            case 125: .down
            case 123: .left
            case 124: .right
            case 36, 76: .a
            case 49: .b
            case 0: .a
            case 11: .b
            default: nil
            }
        }
    }
}
