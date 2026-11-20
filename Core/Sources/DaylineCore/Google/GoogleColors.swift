import Foundation

enum GoogleColors {
    static let fallback = RGBColor(hex: "#4285F4")!

    static func event(colorID: String?) -> RGBColor? {
        colorID.flatMap { eventPalette[$0] }.flatMap { RGBColor(hex: $0) }
    }

    static func calendar(colorID: String?, background: String?) -> RGBColor {
        if let colorID, let swatch = calendarPalette[colorID], background == nil || background?.lowercased() == swatch.classic {
            return RGBColor(hex: swatch.modern)!
        }
        return background.flatMap { RGBColor(hex: $0) } ?? fallback
    }

    private static let eventPalette: [String: String] = [
        "1": "#7986CB",
        "2": "#33B679",
        "3": "#8E24AA",
        "4": "#E67C73",
        "5": "#F6BF26",
        "6": "#F4511E",
        "7": "#039BE5",
        "8": "#616161",
        "9": "#3F51B5",
        "10": "#0B8043",
        "11": "#D50000",
    ]

    private static let calendarPalette: [String: (classic: String, modern: String)] = [
        "1": ("#ac725e", "#795548"),
        "2": ("#d06b64", "#E67C73"),
        "3": ("#f83a22", "#D50000"),
        "4": ("#fa573c", "#F4511E"),
        "5": ("#ff7537", "#EF6C00"),
        "6": ("#ffad46", "#F09300"),
        "7": ("#42d692", "#009688"),
        "8": ("#16a765", "#0B8043"),
        "9": ("#7bd148", "#7CB342"),
        "10": ("#b3dc6c", "#C0CA33"),
        "11": ("#fbe983", "#E4C441"),
        "12": ("#fad165", "#F6BF26"),
        "13": ("#92e1c0", "#33B679"),
        "14": ("#9fe1e7", "#039BE5"),
        "15": ("#9fc6e7", "#4285F4"),
        "16": ("#4986e7", "#3F51B5"),
        "17": ("#9a9cff", "#7986CB"),
        "18": ("#b99aff", "#B39DDB"),
        "19": ("#c2c2c2", "#616161"),
        "20": ("#cabdbf", "#A79B8E"),
        "21": ("#cca6ac", "#AD1457"),
        "22": ("#f691b2", "#D81B60"),
        "23": ("#cd74e6", "#8E24AA"),
        "24": ("#a47ae2", "#9E69AF"),
    ]
}
