import Foundation

public struct ColorValue: Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = Self.clamped(red)
        self.green = Self.clamped(green)
        self.blue = Self.clamped(blue)
        self.alpha = Self.clamped(alpha)
    }

    public init?(hexString: String) {
        guard let components = ClipboardClassifier.hexColorComponents(hexString) else {
            return nil
        }
        self.init(red: components.r, green: components.g, blue: components.b, alpha: components.a)
    }

    public var hexString: String {
        let redByte = Self.byte(red)
        let greenByte = Self.byte(green)
        let blueByte = Self.byte(blue)

        if alpha < 1.0 {
            return String(format: "#%02X%02X%02X%02X", redByte, greenByte, blueByte, Self.byte(alpha))
        }
        return String(format: "#%02X%02X%02X", redByte, greenByte, blueByte)
    }

    public var rgbString: String {
        let redByte = Self.byte(red)
        let greenByte = Self.byte(green)
        let blueByte = Self.byte(blue)

        if alpha < 1.0 {
            return String(format: "rgba(%d, %d, %d, %.2f)", redByte, greenByte, blueByte, alpha)
        }
        return String(format: "rgb(%d, %d, %d)", redByte, greenByte, blueByte)
    }

    public var hslString: String {
        let hsl = Self.hsl(red: red, green: green, blue: blue)
        if alpha < 1.0 {
            return String(format: "hsla(%d, %d%%, %d%%, %.2f)", hsl.hue, hsl.saturation, hsl.lightness, alpha)
        }
        return String(format: "hsl(%d, %d%%, %d%%)", hsl.hue, hsl.saturation, hsl.lightness)
    }

    private static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return 0.0 }
        return min(max(value, 0.0), 1.0)
    }

    private static func byte(_ value: Double) -> Int {
        min(max(Int((clamped(value) * 255.0).rounded()), 0), 255)
    }

    private static func hsl(red: Double, green: Double, blue: Double) -> (hue: Int, saturation: Int, lightness: Int) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        let lightness = (maximum + minimum) / 2.0

        guard delta > 0.0 else {
            return (0, 0, Self.percent(lightness))
        }

        let saturation = delta / (1.0 - abs((2.0 * lightness) - 1.0))
        var hue: Double
        if maximum == red {
            hue = 60.0 * ((green - blue) / delta).truncatingRemainder(dividingBy: 6.0)
        } else if maximum == green {
            hue = 60.0 * (((blue - red) / delta) + 2.0)
        } else {
            hue = 60.0 * (((red - green) / delta) + 4.0)
        }

        if hue < 0.0 {
            hue += 360.0
        }

        // Check vector: #FF5733 has Δ = 0.8, H ≈ 10.59° → 11, S = 100%, L = 60%.
        let roundedHue = Int(hue.rounded())
        return (roundedHue == 360 ? 0 : roundedHue, Self.percent(saturation), Self.percent(lightness))
    }

    private static func percent(_ value: Double) -> Int {
        min(max(Int((value * 100.0).rounded()), 0), 100)
    }
}
