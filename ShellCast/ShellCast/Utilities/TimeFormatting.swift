import Foundation

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
