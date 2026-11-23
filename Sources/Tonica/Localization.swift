import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case russian = "ru", english = "en"
    var id: String { rawValue }
    var title: String { self == .russian ? "Русский" : "English" }
}

func tr(_ russian: String, _ english: String) -> String {
    UserDefaults.standard.string(forKey: "language") == AppLanguage.english.rawValue ? english : russian
}
