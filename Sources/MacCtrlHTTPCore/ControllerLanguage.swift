import Foundation

public enum ControllerLanguage: String, CaseIterable, Identifiable, Sendable {
    case chinese = "zh-Hans"
    case english = "en"
    case french = "fr"

    public static let preferenceKey = "appLanguage"
    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .chinese: "简体中文"
        case .english: "English"
        case .french: "Français"
        }
    }

    public var menuTitle: String { text(.languageMenu) }

    public func text(_ key: ControllerCopy, _ arguments: CVarArg...) -> String {
        let template = Self.translations[self]?[key] ?? key.rawValue
        return String(format: template, locale: Locale(identifier: rawValue), arguments: arguments)
    }

    public static var preferred: ControllerLanguage {
        guard let stored = UserDefaults.standard.string(forKey: preferenceKey) else {
            return .chinese
        }
        return ControllerLanguage(rawValue: stored) ?? .chinese
    }

    private static let translations: [ControllerLanguage: [ControllerCopy: String]] = [
        .chinese: [
            .languageMenu: "语言", .appSubtitle: "局域网手柄控制", .online: "在线", .connecting: "连接中", .waiting: "待连接",
            .settings: "设置", .tokenLabel: "AUTH TOKEN", .tokenPlaceholder: "输入 ActionCtrlHTTP Token",
            .hideToken: "隐藏 Token", .showToken: "显示 Token", .deviceIPLabel: "DEVICE IP", .addressPlaceholder: "输入设备 IP 或主机名",
            .bufferSize: "BUFFER SIZE", .minInterval: "MIN INTERVAL", .device: "设备", .sync: "同步", .syncing: "同步中",
            .synced: "已同步", .retry: "重试", .syncHelp: "检查设备连接，并同步 BUFFER SIZE", .checkAndSync: "检查连接并同步 BUFFER SIZE",
            .increaseBuffer: "增加 BUFFER SIZE", .decreaseBuffer: "减少 BUFFER SIZE", .fillDevice: "填写设备 IP 后同步", .fillToken: "填写 Token 后同步",
            .checkingDevice: "正在检查设备连接…", .tokenModified: "Token 已修改，待检查", .tokenSaveFailed: "保存 Token 失败",
            .addressChanged: "设备地址已修改，待检查", .addressSaveFailed: "保存设备 IP 失败", .bufferPending: "BUFFER SIZE 待同步",
            .deviceOnline: "设备在线", .deviceOnlineCapacity: "设备在线 · BUFFER SIZE %d", .onboardUpdateRequired: "在线，但 Onboard 服务需更新",
            .serviceUpdate: "设备在线 · 请更新 Onboard 服务", .serviceNoBufferSync: "服务版本不支持 BUFFER SIZE 同步",
            .bufferChanged: "BUFFER SIZE 已变化，请再次同步", .bufferSynced: "设备在线 · BUFFER SIZE 已同步",
            .bufferUploaded: "BUFFER SIZE 已上传并保存到设备", .settingsSyncing: "正在检查连接并同步 BUFFER SIZE…",
            .missingAuth: "先填写 Auth Token", .invalidAddress: "设备 IP 无效", .repeatLimited: "方向键自动重复受 MIN INTERVAL 限制",
            .ready: "准备就绪", .sendingTap: "正在发送 %@…", .sendingHold: "正在发送 %@ 长按 %d ms…", .duplicate: "%@ 已去重",
            .tapSent: "%@ 已发送 · 设备已接收", .holdSent: "%@ 长按 %d ms 已发送 · 设备已接收", .requestFailed: "请求失败，请检查设备连接",
            .invalidDeviceAddress: "设备 IP 无效，请检查地址", .invalidHoldDuration: "按住时长必须为 120–5000 ms",
            .invalidResponse: "设备返回了无法识别的响应", .tokenMismatch: "Token 不匹配，请检查输入", .serviceBusy: "ble-main 正被其他服务占用",
            .queueFull: "设备按键队列已满，请稍后再试", .serviceNotReady: "ActionCtrlHTTP 尚未配置或未就绪",
            .unsupportedBuffer: "Onboard ActionCtrlHTTP 尚不支持 BUFFER SIZE 同步，请更新服务", .deviceRejected: "设备拒绝请求（HTTP %d）",
            .directionPad: "方向键", .homeHelp: "Home：返回 Launcher", .keyboardLegend: "← ↑ ↓ →  ·  A / B · Home",
            .up: "上", .down: "下", .left: "左", .right: "右", .home: "主页", .expanded: "已展开", .collapsed: "已折叠",
        ],
        .english: [
            .languageMenu: "Language", .appSubtitle: "Local Network Controller", .online: "Online", .connecting: "Connecting", .waiting: "Offline",
            .settings: "Settings", .tokenLabel: "AUTH TOKEN", .tokenPlaceholder: "ActionCtrlHTTP token",
            .hideToken: "Hide token", .showToken: "Show token", .deviceIPLabel: "DEVICE IP", .addressPlaceholder: "Device IP or hostname",
            .bufferSize: "BUFFER SIZE", .minInterval: "MIN INTERVAL", .device: "DEVICE", .sync: "Sync", .syncing: "Syncing",
            .synced: "Synced", .retry: "Retry", .syncHelp: "Check the connection and sync BUFFER SIZE", .checkAndSync: "Check connection and sync BUFFER SIZE",
            .increaseBuffer: "Increase BUFFER SIZE", .decreaseBuffer: "Decrease BUFFER SIZE", .fillDevice: "Enter the device address to sync", .fillToken: "Enter the token to sync",
            .checkingDevice: "Checking device connection…", .tokenModified: "Token changed; check the connection", .tokenSaveFailed: "Could not save the token",
            .addressChanged: "Device address changed; check the connection", .addressSaveFailed: "Could not save the device address", .bufferPending: "BUFFER SIZE needs syncing",
            .deviceOnline: "Device online", .deviceOnlineCapacity: "Device online · BUFFER SIZE %d", .onboardUpdateRequired: "Online, but update the Onboard service",
            .serviceUpdate: "Device online · Update the Onboard service", .serviceNoBufferSync: "This service version cannot sync BUFFER SIZE",
            .bufferChanged: "BUFFER SIZE changed; sync again", .bufferSynced: "Device online · BUFFER SIZE synced",
            .bufferUploaded: "BUFFER SIZE uploaded and saved on the device", .settingsSyncing: "Checking the connection and syncing BUFFER SIZE…",
            .missingAuth: "Enter the Auth Token first", .invalidAddress: "Invalid device address", .repeatLimited: "Arrow key repeat limited by MIN INTERVAL",
            .ready: "Ready", .sendingTap: "Sending %@…", .sendingHold: "Holding %@ for %d ms…", .duplicate: "%@ was deduplicated",
            .tapSent: "%@ sent · Device received it", .holdSent: "%@ held for %d ms · Device received it", .requestFailed: "Request failed; check the device connection",
            .invalidDeviceAddress: "Invalid device address", .invalidHoldDuration: "Hold duration must be 120–5000 ms",
            .invalidResponse: "The device returned an invalid response", .tokenMismatch: "Token mismatch; check the value", .serviceBusy: "ble-main is in use by another service",
            .queueFull: "The device input queue is full; try again shortly", .serviceNotReady: "ActionCtrlHTTP is not configured or ready",
            .unsupportedBuffer: "This ActionCtrlHTTP version cannot sync BUFFER SIZE; update the service", .deviceRejected: "The device rejected the request (HTTP %d)",
            .directionPad: "Directional pad", .homeHelp: "Home: return to Launcher", .keyboardLegend: "← ↑ ↓ →  ·  A / B · Home",
            .up: "Up", .down: "Down", .left: "Left", .right: "Right", .home: "Home", .expanded: "Expanded", .collapsed: "Collapsed",
        ],
        .french: [
            .languageMenu: "Langue", .appSubtitle: "Manette sur réseau local", .online: "En ligne", .connecting: "Connexion…", .waiting: "Hors ligne",
            .settings: "Réglages", .tokenLabel: "JETON D’AUTHENTIFICATION", .tokenPlaceholder: "Jeton ActionCtrlHTTP",
            .hideToken: "Masquer le jeton", .showToken: "Afficher le jeton", .deviceIPLabel: "IP DE L’APPAREIL", .addressPlaceholder: "Adresse IP ou nom d’hôte",
            .bufferSize: "TAILLE DE FILE", .minInterval: "INTERVALLE MIN.", .device: "APPAREIL", .sync: "Sync", .syncing: "Sync…",
            .synced: "Synchronisé", .retry: "Réessayer", .syncHelp: "Vérifier la connexion et synchroniser la file", .checkAndSync: "Vérifier et synchroniser la file",
            .increaseBuffer: "Augmenter la taille de file", .decreaseBuffer: "Réduire la taille de file", .fillDevice: "Saisissez l’adresse de l’appareil", .fillToken: "Saisissez le jeton",
            .checkingDevice: "Vérification de la connexion…", .tokenModified: "Jeton modifié ; vérifiez la connexion", .tokenSaveFailed: "Impossible d’enregistrer le jeton",
            .addressChanged: "Adresse modifiée ; vérifiez la connexion", .addressSaveFailed: "Impossible d’enregistrer l’adresse", .bufferPending: "Taille de file à synchroniser",
            .deviceOnline: "Appareil en ligne", .deviceOnlineCapacity: "En ligne · file %d", .onboardUpdateRequired: "En ligne, mais mettez à jour le service Onboard",
            .serviceUpdate: "Appareil en ligne · Mettez à jour Onboard", .serviceNoBufferSync: "Cette version ne synchronise pas la taille de file",
            .bufferChanged: "Taille modifiée ; synchronisez à nouveau", .bufferSynced: "En ligne · taille de file synchronisée",
            .bufferUploaded: "Taille envoyée et enregistrée sur l’appareil", .settingsSyncing: "Vérification et synchronisation…",
            .missingAuth: "Saisissez d’abord le jeton", .invalidAddress: "Adresse de l’appareil invalide", .repeatLimited: "Répétition des flèches limitée par l’intervalle min.",
            .ready: "Prêt", .sendingTap: "Envoi de %@…", .sendingHold: "Maintien de %@ pendant %d ms…", .duplicate: "%@ ignoré (doublon)",
            .tapSent: "%@ envoyé · reçu par l’appareil", .holdSent: "%@ maintenu %d ms · reçu par l’appareil", .requestFailed: "Échec ; vérifiez la connexion",
            .invalidDeviceAddress: "Adresse de l’appareil invalide", .invalidHoldDuration: "La durée doit être comprise entre 120 et 5000 ms",
            .invalidResponse: "Réponse invalide de l’appareil", .tokenMismatch: "Jeton incorrect ; vérifiez sa valeur", .serviceBusy: "ble-main est utilisé par un autre service",
            .queueFull: "File de commandes pleine ; réessayez bientôt", .serviceNotReady: "ActionCtrlHTTP n’est pas configuré ou prêt",
            .unsupportedBuffer: "Cette version ne synchronise pas la taille de file ; mettez-la à jour", .deviceRejected: "Requête refusée par l’appareil (HTTP %d)",
            .directionPad: "Pavé directionnel", .homeHelp: "Accueil : revenir au Launcher", .keyboardLegend: "← ↑ ↓ →  ·  A / B · Home",
            .up: "Haut", .down: "Bas", .left: "Gauche", .right: "Droite", .home: "Accueil", .expanded: "Développé", .collapsed: "Replié",
        ],
    ]
}

public enum ControllerCopy: String, CaseIterable, Sendable {
    case languageMenu, appSubtitle, online, connecting, waiting
    case settings, tokenLabel, tokenPlaceholder, hideToken, showToken, deviceIPLabel, addressPlaceholder
    case bufferSize, minInterval, device, sync, syncing, synced, retry, syncHelp, checkAndSync, increaseBuffer, decreaseBuffer
    case fillDevice, fillToken, checkingDevice, tokenModified, tokenSaveFailed, addressChanged, addressSaveFailed, bufferPending
    case deviceOnline, deviceOnlineCapacity, onboardUpdateRequired, serviceUpdate, serviceNoBufferSync, bufferChanged, bufferSynced, bufferUploaded
    case settingsSyncing, missingAuth, invalidAddress, repeatLimited, ready, sendingTap, sendingHold, duplicate, tapSent, holdSent
    case requestFailed, invalidDeviceAddress, invalidHoldDuration, invalidResponse, tokenMismatch, serviceBusy, queueFull, serviceNotReady, unsupportedBuffer, deviceRejected
    case directionPad, homeHelp, keyboardLegend, up, down, left, right, home, expanded, collapsed
}
