import AppKit

/// SwiftUI creates the standard macOS menus using the system language. Update
/// their known labels when the app's own language changes or a menu opens.
@MainActor
enum SystemMenuLocalization {
    private static let labels: [(String, String)] = [
        ("Файл", "File"), ("Правка", "Edit"), ("Вид", "View"),
        ("Окно", "Window"), ("Справка", "Help"),
        ("Закрыть", "Close"), ("Закрыть все", "Close All"),
        ("Отменить", "Undo"), ("Повторить", "Redo"),
        ("Вырезать", "Cut"), ("Скопировать", "Copy"), ("Копировать", "Copy"),
        ("Вставить", "Paste"), ("Вставить и согласовать стиль", "Paste and Match Style"),
        ("Удалить", "Delete"), ("Выбрать все", "Select All"), ("Выделить все", "Select All"),
        ("Поиск", "Find"), ("Найти…", "Find…"), ("Найти следующий", "Find Next"),
        ("Найти предыдущий", "Find Previous"), ("Использовать выделенное для поиска", "Use Selection for Find"),
        ("Перейти к выделенному", "Jump to Selection"),
        ("Правописание и грамматика", "Spelling and Grammar"),
        ("Показать правописание и грамматику", "Show Spelling and Grammar"),
        ("Проверить документ сейчас", "Check Document Now"),
        ("Проверять правописание при наборе", "Check Spelling While Typing"),
        ("Проверять грамматику и правописание", "Check Grammar With Spelling"),
        ("Исправлять правописание автоматически", "Correct Spelling Automatically"),
        ("Замены", "Substitutions"), ("Показать замены", "Show Substitutions"),
        ("Смарт-кавычки", "Smart Quotes"), ("Смарт-тире", "Smart Dashes"),
        ("Смарт-ссылки", "Smart Links"), ("Замена текста", "Text Replacement"),
        ("Преобразования", "Transformations"), ("Сделать все прописными", "Make Upper Case"),
        ("Сделать все строчными", "Make Lower Case"), ("Начинать слова с прописных", "Capitalize"),
        ("Речь", "Speech"), ("Начать произнесение", "Start Speaking"),
        ("Остановить произнесение", "Stop Speaking"),
        ("Эмодзи и символы", "Emoji & Symbols"),
        ("Свернуть", "Minimize"), ("Свернуть все", "Minimize All"),
        ("Масштабировать", "Zoom"), ("На передний план", "Bring All to Front"),
        ("Войти в полноэкранный режим", "Enter Full Screen"),
        ("Выйти из полноэкранного режима", "Exit Full Screen"),
        ("Показать панель инструментов", "Show Toolbar"), ("Скрыть панель инструментов", "Hide Toolbar"),
        ("Настроить панель инструментов…", "Customize Toolbar…"),
        ("Службы", "Services"), ("Скрыть Tonica", "Hide Tonica"),
        ("Скрыть остальные", "Hide Others"), ("Показать все", "Show All"),
        ("Завершить Tonica", "Quit Tonica"), ("О программе Tonica", "About Tonica"),
        ("Настройки…", "Settings…"), ("Настройки Tonica…", "Tonica Settings…"),
        ("Справка Tonica", "Tonica Help")
    ]

    static func update() {
        guard let menu = NSApp.mainMenu else { return }
        let english = UserDefaults.standard.string(forKey: "language") == AppLanguage.english.rawValue
        update(menu, english: english)
    }

    static func update(_ menu: NSMenu, english: Bool) {
        for item in menu.items {
            if let pair = labels.first(where: { $0.0 == item.title || $0.1 == item.title }) {
                item.title = english ? pair.1 : pair.0
            }
            if let submenu = item.submenu { update(submenu, english: english) }
        }
    }
}
