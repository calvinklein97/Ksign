//
//  AccentColorManager.swift
//  Ksign
//
//  Created by Nagata Asami on 6/30/25.
//

import SwiftUI
import UIKit

// MARK: - Accent Color Manager
class AccentColorManager: ObservableObject {
    static let shared = AccentColorManager()
    
    @AppStorage("Feather.accentColor") private var _selectedAccentColor: Int = 0 {
        didSet {
            objectWillChange.send()
        }
    }
    
    /// Selection value that stands for the user's own color
    static let customIndex = -1

    @AppStorage("Feather.customAccentColor") private var _customHex: String = "#5394F7"

    var isCustom: Bool {
        _selectedAccentColor == Self.customIndex
    }

    var customColor: Color {
        Color(uiColor: Self.uiColor(hex: _customHex))
    }

    /// Stores a color picked by the user and makes it the accent color
    func setCustomColor(_ color: Color) {
        _customHex = Self.hex(from: UIColor(color))
        _selectedAccentColor = Self.customIndex
        updateGlobalTintColor()
    }

    private static func uiColor(hex: String) -> UIColor {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            return UIColor(red: 0x53/255, green: 0x94/255, blue: 0xF7/255, alpha: 1.0)
        }
        return UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1.0
        )
    }

    private static func hex(from color: UIColor) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    private let _accentColors: [(color: Color, uiColor: UIColor)] = [
        (Color(red: 0x53/255, green: 0x94/255, blue: 0xF7/255), UIColor(red: 0x53/255, green: 0x94/255, blue: 0xF7/255, alpha: 1.0)), // Default
        (Color(red: 0xFF/255, green: 0x8B/255, blue: 0x92/255), UIColor(red: 0xFF/255, green: 0x8B/255, blue: 0x92/255, alpha: 1.0)), //rgb(255, 139, 146)
        (.red, .systemRed),
        (.orange, .systemOrange),
        (.yellow, .systemYellow),
        (.green, .systemGreen),
        (.blue, .systemBlue),
        (.purple, .systemPurple),
        (.pink, .systemPink),
        (.indigo, .systemIndigo),
        (.mint, .systemMint),
        (.cyan, .systemCyan),
        (.teal, .systemTeal)
    ]
    
    var currentAccentColor: Color {
        if isCustom { return customColor }
        guard _selectedAccentColor >= 0, _selectedAccentColor < _accentColors.count else {
            return _accentColors[0].color
        }
        return _accentColors[_selectedAccentColor].color
    }
    
    var currentUIColor: UIColor {
        if isCustom { return Self.uiColor(hex: _customHex) }
        guard _selectedAccentColor >= 0, _selectedAccentColor < _accentColors.count else {
            return _accentColors[0].uiColor
        }
        return _accentColors[_selectedAccentColor].uiColor
    }
    
    /// Updates the global app tint color
    func updateGlobalTintColor() {
        DispatchQueue.main.async {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .forEach { window in
                    window.tintColor = self.currentUIColor
                }
        }
    }
} 