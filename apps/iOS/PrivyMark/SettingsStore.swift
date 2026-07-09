//
//  SettingsStore.swift
//  PrivyMark
//
//  Persistent user preferences (PRD §10.4 设置页).
//

import SwiftUI
import Combine

@MainActor
final class SettingsStore: ObservableObject {
    @AppStorage("hasSeenWelcome") var hasSeenWelcome = false
    @AppStorage("defaultToolRaw") private var defaultToolRaw = RedactionStyle.block.rawValue
    @AppStorage("autoEditLatest") var autoEditLatest = false
    /// On-device AI-enhanced detection (iOS 26+ Foundation Models). Default on;
    /// no effect on devices without an available on-device model.
    @AppStorage("aiDetectionEnabled") var aiDetectionEnabled = true

    var defaultTool: RedactionStyle {
        get { RedactionStyle(rawValue: defaultToolRaw) ?? .block }
        set { defaultToolRaw = newValue.rawValue }
    }
}
