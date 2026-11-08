import AppKit
import MacCtrlHTTPCore
import SwiftUI

struct ControlPanelView: View {
    @StateObject private var model = ControlPanelModel()
    @State private var revealsToken = false

    var body: some View {
        VStack(spacing: 15) {
            header
            Rectangle()
                .fill(.white.opacity(0.13))
                .frame(height: 1)
                .padding(.horizontal, 2)
            controlSurface
            tokenEntry
            addressEntry
            footer
        }
        .padding(19)
        .frame(width: 344, height: 486)
        .background {
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 27, style: .continuous)
                        .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.2), radius: 24, y: 12)
        }
        .background(KeyboardShortcutCapture { model.send($0) }.frame(width: 1, height: 1))
        .onChange(of: model.token) { newValue in model.saveToken(newValue) }
        .onChange(of: model.deviceAddress) { newValue in model.saveDeviceAddress(newValue) }
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
                Text("局域网手柄控制")
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
                .fill(model.online ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(model.online ? "在线" : "待连接")
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
            DirectionPad { model.send($0) }
            Spacer(minLength: 0)
            VStack(spacing: 15) {
                ActionKey(button: .a, tint: .cyan) { model.send(.a) }
                ActionKey(button: .b, tint: .orange) { model.send(.b) }
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

    private var tokenEntry: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("AUTH TOKEN", systemImage: "key.fill")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("自动保存")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 8) {
                Group {
                    if revealsToken {
                        TextField("输入 ActionCtrlHTTP Token", text: $model.token)
                    } else {
                        SecureField("输入 ActionCtrlHTTP Token", text: $model.token)
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .textContentType(.password)
                .autocorrectionDisabled()
                .onSubmit { model.confirmToken() }

                Button {
                    revealsToken.toggle()
                } label: {
                    Image(systemName: revealsToken ? "eye.slash" : "eye")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(revealsToken ? "隐藏 Token" : "显示 Token")
                .accessibilityLabel(revealsToken ? "隐藏 Token" : "显示 Token")

                ConfirmationButton(
                    isLoading: model.isConfirmingToken
                ) {
                    model.confirmToken()
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(.black.opacity(0.17), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.13), lineWidth: 1)
            }
            Text("Token 自动保存 · 上箭头发送 B")
                .font(.system(size: 9, weight: .regular, design: .rounded))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    private var addressEntry: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("DEVICE IP", systemImage: "network")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("自动保存")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 8) {
                TextField("输入设备 IP 或主机名", text: $model.deviceAddress)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .autocorrectionDisabled()
                    .onSubmit { model.testConnection() }

                ConnectionTestButton(isLoading: model.isTestingConnection) {
                    model.testConnection()
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(.black.opacity(0.17), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.13), lineWidth: 1)
            }
            Text("联通测试只读取 ActionCtrlHTTP 服务状态")
                .font(.system(size: 9, weight: .regular, design: .rounded))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
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
            Spacer(minLength: 4)
            Text("← ↑ ↓ →  ·  A / B")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .fixedSize()
        }
        .padding(.bottom, 1)
        .help(model.connectionMessage)
    }
}

private struct ConfirmationButton: View {
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .overlay {
                        Circle().strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
                    }
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primary.opacity(0.82))
                }
            }
            .frame(width: 34, height: 34)
            .contentShape(Circle())
        }
        .buttonStyle(SoftPressStyle())
        .disabled(isLoading)
        .help("确认 Token 并发送 B")
        .accessibilityLabel(isLoading ? "正在验证 Token" : "确认 Token 并发送 B")
    }
}

private struct ConnectionTestButton: View {
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.24), lineWidth: 1))
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.82))
                }
            }
            .frame(width: 34, height: 34)
            .contentShape(Circle())
        }
        .buttonStyle(SoftPressStyle())
        .disabled(isLoading)
        .help("测试设备联通")
        .accessibilityLabel(isLoading ? "正在测试联通" : "测试设备联通")
    }
}

private struct DirectionPad: View {
    let action: (RemoteButton) -> Void

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Spacer(minLength: 0)
                DirectionKey(button: .up, rotation: 0, action: action)
                Spacer(minLength: 0)
            }
            HStack(spacing: 3) {
                DirectionKey(button: .left, rotation: -90, action: action)
                Circle().fill(.white.opacity(0.13)).frame(width: 5, height: 5)
                DirectionKey(button: .right, rotation: 90, action: action)
            }
            HStack {
                Spacer(minLength: 0)
                DirectionKey(button: .down, rotation: 180, action: action)
                Spacer(minLength: 0)
            }
        }
        .frame(width: 158, height: 150)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("方向键")
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
                .frame(width: 48, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
        .accessibilityLabel(button.title)
        .help(button.title)
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

private struct SoftPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.76 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

private struct KeyboardShortcutCapture: NSViewRepresentable {
    let action: (RemoteButton) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.action = action
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        weak var view: NSView?
        var action: (RemoteButton) -> Void
        private var monitor: Any?

        init(action: @escaping (RemoteButton) -> Void) {
            self.action = action
        }

        func installMonitor() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      let window = self.view?.window,
                      NSApp.keyWindow === window,
                      !Self.isEditingText(in: window),
                      !event.isARepeat,
                      let button = Self.button(forKeyCode: event.keyCode) else {
                    return event
                }
                self.action(button)
                return nil
            }
        }

        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private static func isEditingText(in window: NSWindow) -> Bool {
            window.firstResponder is NSTextView || window.firstResponder is NSTextField
        }

        private static func button(forKeyCode keyCode: UInt16) -> RemoteButton? {
            switch keyCode {
            case 126: .up
            case 125: .down
            case 123: .left
            case 124: .right
            case 0: .a
            case 11: .b
            default: nil
            }
        }
    }
}
