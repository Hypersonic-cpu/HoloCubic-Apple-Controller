import AppIntents
import Foundation
import SwiftUI
import WidgetKit

private enum WidgetLanguage: String {
    case chinese = "zh-Hans"
    case english = "en"
    case french = "fr"

    static var preferred: WidgetLanguage {
        let raw = UserDefaults(suiteName: "group.com.clocteck.MacCtrlHTTP")?.string(forKey: "appLanguage")
        return raw.flatMap(WidgetLanguage.init(rawValue:)) ?? .chinese
    }

    var online: String {
        switch self {
        case .chinese: "在线"
        case .english: "Online"
        case .french: "En ligne"
        }
    }

    var offline: String {
        switch self {
        case .chinese: "离线"
        case .english: "Offline"
        case .french: "Hors ligne"
        }
    }

    var description: String {
        switch self {
        case .chinese: "HoloCubic 手柄快捷控制"
        case .english: "Quick controls for HoloCubic"
        case .french: "Commandes rapides HoloCubic"
        }
    }

    func buttonTitle(_ button: String) -> String {
        switch (self, button) {
        case (.chinese, "up"): "上"
        case (.chinese, "down"): "下"
        case (.chinese, "left"): "左"
        case (.chinese, "right"): "右"
        case (.chinese, "home"): "主页"
        case (.english, "up"): "Up"
        case (.english, "down"): "Down"
        case (.english, "left"): "Left"
        case (.english, "right"): "Right"
        case (.english, "home"): "Home"
        case (.french, "up"): "Haut"
        case (.french, "down"): "Bas"
        case (.french, "left"): "Gauche"
        case (.french, "right"): "Droite"
        case (.french, "home"): "Accueil"
        default: button.uppercased()
        }
    }
}

private struct ControlWidgetEntry: TimelineEntry {
    let date: Date
    let online: Bool
    let language: WidgetLanguage
}

private struct ControlWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ControlWidgetEntry {
        ControlWidgetEntry(date: .now, online: false, language: .preferred)
    }

    func getSnapshot(in context: Context, completion: @escaping (ControlWidgetEntry) -> Void) {
        Task { completion(await makeEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ControlWidgetEntry>) -> Void) {
        Task {
            let entry = await makeEntry()
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(5 * 60))))
        }
    }

    private func makeEntry() async -> ControlWidgetEntry {
        ControlWidgetEntry(date: .now, online: await isDeviceOnline(), language: .preferred)
    }

    private func isDeviceOnline() async -> Bool {
        guard let defaults = UserDefaults(suiteName: "group.com.clocteck.MacCtrlHTTP"),
              let token = defaults.string(forKey: "actionCtrlToken"), !token.isEmpty,
              let address = defaults.string(forKey: "deviceAddress"),
              let baseURL = makeURL(address),
              let url = URL(string: "/remote/api/v1/status", relativeTo: baseURL)?.absoluteURL else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 3
        request.setValue(token, forHTTPHeaderField: "X-ActionCtrl-Token")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            return object["ok"] as? Bool == true
        } catch {
            return false
        }
    }

    private func makeURL(_ address: String) -> URL? {
        let raw = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = raw.hasPrefix("http://") ? raw : "http://\(raw)"
        guard let url = URL(string: normalized), url.scheme == "http", url.host != nil,
              url.query == nil, url.fragment == nil else { return nil }
        return url
    }
}

private struct ControlWidgetView: View {
    let entry: ControlWidgetEntry

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text("HoloCubic")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 2)
                HStack(spacing: 3) {
                    Image(systemName: entry.online ? "checkmark.circle.fill" : "wifi.slash")
                        .font(.system(size: 8, weight: .semibold))
                    Text(entry.online ? entry.language.online : entry.language.offline)
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(entry.online ? Color.green : Color.secondary)
                .accessibilityElement(children: .combine)
            }
            .foregroundStyle(.primary.opacity(0.88))

            HStack(spacing: 8) {
                DirectionWidgetPad(language: entry.language)
                Spacer(minLength: 0)
                VStack(spacing: 4) {
                    ActionWidgetButton(button: "a", title: "A", language: entry.language, symbol: nil, tint: .cyan)
                    ActionWidgetButton(button: "b", title: "B", language: entry.language, symbol: nil, tint: .orange)
                    ActionWidgetButton(button: "home", title: entry.language.buttonTitle("home"), language: entry.language, symbol: "house.fill", tint: .secondary)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(9)
        .containerBackground(for: .widget) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct DirectionWidgetPad: View {
    let language: WidgetLanguage

    var body: some View {
        VStack(spacing: 3) {
            DirectionWidgetButton(button: "up", symbol: "arrow.up", language: language)
            HStack(spacing: 3) {
                DirectionWidgetButton(button: "left", symbol: "arrow.left", language: language)
                Circle().fill(.primary.opacity(0.22)).frame(width: 4, height: 4)
                DirectionWidgetButton(button: "right", symbol: "arrow.right", language: language)
            }
            DirectionWidgetButton(button: "down", symbol: "arrow.down", language: language)
        }
        .frame(width: 83, height: 86)
    }
}

private struct DirectionWidgetButton: View {
    let button: String
    let symbol: String
    let language: WidgetLanguage

    var body: some View {
        Button(intent: WidgetTapIntent(button: button)) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 26, height: 26)
                .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.primary.opacity(0.16), lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .widgetAccentable()
        .accessibilityLabel(language.buttonTitle(button))
    }
}

private struct ActionWidgetButton: View {
    let button: String
    let title: String
    let language: WidgetLanguage
    let symbol: String?
    let tint: Color

    var body: some View {
        Button(intent: WidgetTapIntent(button: button)) {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .semibold))
                } else {
                    Text(title)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
            }
            .frame(width: 26, height: 26)
            .background(tint.opacity(0.18), in: Circle())
            .overlay(Circle().strokeBorder(tint.opacity(0.5), lineWidth: 1))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .widgetAccentable()
        .accessibilityLabel(language.buttonTitle(button))
    }
}

struct HoloCubicControlWidget: Widget {
    let kind = "HoloCubicControlWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ControlWidgetProvider()) { entry in
            ControlWidgetView(entry: entry)
        }
        .configurationDisplayName("HoloCubic Controls")
        .description(WidgetLanguage.preferred.description)
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

@main
struct HoloCubicWidgetBundle: WidgetBundle {
    var body: some Widget {
        HoloCubicControlWidget()
    }
}
