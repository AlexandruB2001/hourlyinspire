import Foundation

/// Distance text used throughout the app. All maths is on integer metres.
public enum DistanceFormatting {
    /// "2.4 km". Rounds *down* to 0.1 km so 999 m never reads "1.0 km"
    /// while the walker is still in the first zone.
    public static func kilometres(_ meters: Int, locale: Locale = .current) -> String {
        let tenths = max(0, meters) / 100
        return "\(tenths / 10)\(separator(locale))\(tenths % 10) km"
    }

    /// A remaining distance: "600 m" below 1 km, otherwise "1.2 km".
    /// Rounds *up* so a non-zero remainder never reads "0 m".
    public static func remaining(_ meters: Int, locale: Locale = .current) -> String {
        let meters = max(0, meters)
        if meters < 1_000 {
            let rounded = meters == 0 ? 0 : ((meters + 9) / 10) * 10
            return rounded >= 1_000 ? "1\(separator(locale))0 km" : "\(rounded) m"
        }
        let tenths = (meters + 99) / 100
        return "\(tenths / 10)\(separator(locale))\(tenths % 10) km"
    }

    /// Magnitude of a gap, rounded to the nearest 0.1 km: "4.8 km".
    public static func gap(_ meters: Int, locale: Locale = .current) -> String {
        let tenths = (abs(meters) + 50) / 100
        return "\(tenths / 10)\(separator(locale))\(tenths % 10) km"
    }

    /// Signed gap: "+4.8 km", "−2.1 km", "±0.0 km".
    public static func signedGap(_ meters: Int, locale: Locale = .current) -> String {
        let magnitude = gap(meters, locale: locale)
        if (abs(meters) + 50) / 100 == 0 { return "±\(magnitude)" }
        return (meters > 0 ? "+" : "−") + magnitude
    }

    public static func steps(_ steps: Int, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: max(0, steps))) ?? "\(steps)"
    }

    private static func separator(_ locale: Locale) -> String {
        locale.decimalSeparator ?? "."
    }
}
