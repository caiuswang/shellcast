import Foundation
import SwiftUI

extension View {
    func iPadContentWidth(_ maxWidth: CGFloat = 600) -> some View {
        frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
    }
}

extension Date {
    var relativeDescription: String {
        let interval = Date().timeIntervalSince(self)
        if abs(interval) < 60 {
            return "just now"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
