import Foundation

struct WidgetBoard: Codable, Identifiable {
  let id: Int
  let title: String
  let color: String?
}

struct WidgetCard: Codable, Identifiable {
  let id: Int
  let title: String
  let boardId: Int
  let columnId: Int
  let due: Int64?
  let assignedToMe: Bool
}

struct WidgetPayload: Codable {
  let updatedAt: Int64
  let defaultBoardId: Int?
  let boards: [WidgetBoard]
  let cards: [WidgetCard]
}

enum WidgetDataStore {
  static let appGroupId = "group.com.example.nextdeck"
  static let payloadKey = "nextdeck_widget_payload"

  static func load() -> WidgetPayload? {
    let defaults = UserDefaults(suiteName: appGroupId)
    if let data = defaults?.data(forKey: payloadKey) {
      return try? JSONDecoder().decode(WidgetPayload.self, from: data)
    }
    guard let raw = defaults?.string(forKey: payloadKey) else { return nil }
    guard let data = raw.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(WidgetPayload.self, from: data)
  }

}
