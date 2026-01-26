import SwiftUI
import WidgetKit
import AppIntents

struct NextDeckEntry: TimelineEntry {
  let date: Date
  let configuration: NextDeckWidgetIntent
  let payload: WidgetPayload?
}

struct NextDeckProvider: AppIntentTimelineProvider {
  typealias Intent = NextDeckWidgetIntent
  typealias Entry = NextDeckEntry

  func placeholder(in context: Context) -> NextDeckEntry {
    NextDeckEntry(date: Date(), configuration: NextDeckWidgetIntent(), payload: nil)
  }

  func snapshot(for configuration: NextDeckWidgetIntent, in context: Context) async -> NextDeckEntry {
    NextDeckEntry(date: Date(), configuration: configuration, payload: WidgetDataStore.load())
  }

  func timeline(for configuration: NextDeckWidgetIntent, in context: Context) async -> Timeline<NextDeckEntry> {
    let entry = NextDeckEntry(date: Date(), configuration: configuration, payload: WidgetDataStore.load())
    let next = Date().addingTimeInterval(60 * 15)
    return Timeline(entries: [entry], policy: .after(next))
  }
}

struct NextDeckWidget: Widget {
  let kind: String = "NextDeckWidget"

  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: kind, intent: NextDeckWidgetIntent.self, provider: NextDeckProvider()) { entry in
      NextDeckWidgetView(entry: entry)
    }
    .configurationDisplayName(String(localized: "widget.displayName"))
    .description(String(localized: "widget.description"))
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

struct NewCardEntry: TimelineEntry {
  let date: Date
  let configuration: NewCardWidgetIntent
  let payload: WidgetPayload?
}

struct NewCardProvider: AppIntentTimelineProvider {
  typealias Intent = NewCardWidgetIntent
  typealias Entry = NewCardEntry

  func placeholder(in context: Context) -> NewCardEntry {
    NewCardEntry(date: Date(), configuration: NewCardWidgetIntent(), payload: nil)
  }

  func snapshot(for configuration: NewCardWidgetIntent, in context: Context) async -> NewCardEntry {
    NewCardEntry(date: Date(), configuration: configuration, payload: WidgetDataStore.load())
  }

  func timeline(for configuration: NewCardWidgetIntent, in context: Context) async -> Timeline<NewCardEntry> {
    let entry = NewCardEntry(date: Date(), configuration: configuration, payload: WidgetDataStore.load())
    let next = Date().addingTimeInterval(60 * 15)
    return Timeline(entries: [entry], policy: .after(next))
  }
}

struct NewCardWidget: Widget {
  let kind: String = "NewCardWidget"

  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: kind, intent: NewCardWidgetIntent.self, provider: NewCardProvider()) { entry in
      NewCardWidgetView(entry: entry)
    }
    .configurationDisplayName(String(localized: "newcard.displayName"))
    .description(String(localized: "newcard.description"))
    .supportedFamilies([.systemSmall])
  }
}

struct UpcomingLargeEntry: TimelineEntry {
  let date: Date
  let configuration: UpcomingLargeWidgetIntent
  let payload: WidgetPayload?
}

struct UpcomingLargeProvider: AppIntentTimelineProvider {
  typealias Intent = UpcomingLargeWidgetIntent
  typealias Entry = UpcomingLargeEntry

  func placeholder(in context: Context) -> UpcomingLargeEntry {
    UpcomingLargeEntry(date: Date(), configuration: UpcomingLargeWidgetIntent(), payload: nil)
  }

  func snapshot(for configuration: UpcomingLargeWidgetIntent, in context: Context) async -> UpcomingLargeEntry {
    UpcomingLargeEntry(date: Date(), configuration: configuration, payload: WidgetDataStore.load())
  }

  func timeline(for configuration: UpcomingLargeWidgetIntent, in context: Context) async -> Timeline<UpcomingLargeEntry> {
    let entry = UpcomingLargeEntry(date: Date(), configuration: configuration, payload: WidgetDataStore.load())
    let next = Date().addingTimeInterval(60 * 15)
    return Timeline(entries: [entry], policy: .after(next))
  }
}

struct UpcomingLargeWidget: Widget {
  let kind: String = "UpcomingLargeWidget"

  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: kind, intent: UpcomingLargeWidgetIntent.self, provider: UpcomingLargeProvider()) { entry in
      UpcomingLargeWidgetView(entry: entry)
    }
    .configurationDisplayName(String(localized: "upcomingLarge.displayName"))
    .description(String(localized: "upcomingLarge.description"))
    .supportedFamilies([.systemLarge])
  }
}

struct UpcomingLockEntry: TimelineEntry {
  let date: Date
  let configuration: UpcomingLockWidgetIntent
  let payload: WidgetPayload?
}

struct UpcomingLockProvider: AppIntentTimelineProvider {
  typealias Intent = UpcomingLockWidgetIntent
  typealias Entry = UpcomingLockEntry

  func placeholder(in context: Context) -> UpcomingLockEntry {
    UpcomingLockEntry(date: Date(), configuration: UpcomingLockWidgetIntent(), payload: nil)
  }

  func snapshot(for configuration: UpcomingLockWidgetIntent, in context: Context) async -> UpcomingLockEntry {
    UpcomingLockEntry(date: Date(), configuration: configuration, payload: WidgetDataStore.load())
  }

  func timeline(for configuration: UpcomingLockWidgetIntent, in context: Context) async -> Timeline<UpcomingLockEntry> {
    let entry = UpcomingLockEntry(date: Date(), configuration: configuration, payload: WidgetDataStore.load())
    let next = Date().addingTimeInterval(60 * 15)
    return Timeline(entries: [entry], policy: .after(next))
  }
}

struct UpcomingLockWidget: Widget {
  let kind: String = "UpcomingLockWidget"

  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: kind, intent: UpcomingLockWidgetIntent.self, provider: UpcomingLockProvider()) { entry in
      UpcomingLockWidgetView(entry: entry)
    }
    .configurationDisplayName(String(localized: "upcomingLock.displayName"))
    .description(String(localized: "upcomingLock.description"))
    .supportedFamilies([.accessoryRectangular])
  }
}


struct NextDeckWidgetView: View {
  let entry: NextDeckEntry

  @Environment(\.widgetFamily) var family

  var body: some View {
    let payload = entry.payload
    let board = resolvedBoard(from: payload)
    let cards = filteredCards(from: payload, boardId: board?.id)
    let boardTitle = titleText(board: board)
    let quickAddUrl = entry.configuration.viewMode == .board
      ? deepLink(action: "quick-add", boardId: board?.id)
      : nil
    let displayCards = cards.prefix(maxCardsForFamily())

    ZStack {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(boardTitle)
            .font(.headline)
            .lineLimit(1)
          Spacer()
          if let url = quickAddUrl {
            Link(destination: url) {
              Image(systemName: "plus.circle.fill")
                .font(.title3)
            }
          }
        }
        if displayCards.isEmpty {
          Text(String(localized: "widget.noCards"))
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(displayCards) { card in
              if let url = deepLink(
                action: "card",
                boardId: card.boardId,
                cardId: card.id,
                stackId: card.columnId,
                edit: true
              ) {
                Link(destination: url) {
                  CardRow(card: card)
                }
              } else {
                CardRow(card: card)
              }
            }
          }
        }
        Spacer(minLength: 0)
        Text(filterLabel())
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .padding(12)
    }
    .containerBackground(.background, for: .widget)
  }

  private func resolvedBoard(from payload: WidgetPayload?) -> WidgetBoard? {
    guard entry.configuration.viewMode == .board else { return nil }
    guard let payload else { return nil }
    if let selected = entry.configuration.board,
       let board = payload.boards.first(where: { $0.id == selected.id }) {
      return board
    }
    if let defaultId = payload.defaultBoardId,
       let board = payload.boards.first(where: { $0.id == defaultId }) {
      return board
    }
    return payload.boards.first
  }

  private func filteredCards(from payload: WidgetPayload?, boardId: Int?) -> [WidgetCard] {
    guard let payload else { return [] }
    var cards = payload.cards
    if entry.configuration.viewMode == .board, let boardId {
      cards = cards.filter { $0.boardId == boardId }
    }
    switch entry.configuration.viewMode {
    case .upcoming:
      cards = cards.filter { $0.due != nil }
    case .board:
      switch entry.configuration.filter {
      case .assigned:
        cards = cards.filter { $0.assignedToMe }
      case .dueSoon:
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let soonMs = nowMs + Int64(24 * 60 * 60 * 1000)
        cards = cards.filter { card in
          guard let due = card.due else { return false }
          return due <= soonMs
        }
      case .all:
        break
      }
    }
    let sorted = cards.sorted(by: sortCards(_:_:))
    if entry.configuration.viewMode == .upcoming {
      return Array(sorted.prefix(3))
    }
    return sorted
  }

  private func sortCards(_ a: WidgetCard, _ b: WidgetCard) -> Bool {
    switch (a.due, b.due) {
    case let (lhs?, rhs?):
      return lhs < rhs
    case (.some, .none):
      return true
    case (.none, .some):
      return false
    default:
      return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
    }
  }

  private func maxCardsForFamily() -> Int {
    if entry.configuration.viewMode == .upcoming {
      return family == .systemSmall ? 2 : 3
    }
    return family == .systemSmall ? 2 : 5
  }

  private func deepLink(action: String, boardId: Int?, cardId: Int? = nil, stackId: Int? = nil, edit: Bool = false) -> URL? {
    var components = URLComponents()
    components.scheme = "nextdeck"
    components.host = action
    var items: [URLQueryItem] = []
    if let boardId { items.append(URLQueryItem(name: "board", value: "\(boardId)")) }
    if let cardId { items.append(URLQueryItem(name: "card", value: "\(cardId)")) }
    if let stackId { items.append(URLQueryItem(name: "stack", value: "\(stackId)")) }
    if edit { items.append(URLQueryItem(name: "edit", value: "1")) }
    if !items.isEmpty {
      components.queryItems = items
    }
    return components.url
  }

  private func filterLabel() -> String {
    switch entry.configuration.viewMode {
    case .upcoming:
      return String(localized: "view.upcoming.subtitle")
    case .board:
      switch entry.configuration.filter {
      case .assigned:
        return String(localized: "filter.assigned")
      case .dueSoon:
        return String(localized: "filter.dueSoon")
      case .all:
        return String(localized: "filter.all")
      }
    }
  }

  private func titleText(board: WidgetBoard?) -> String {
    if entry.configuration.viewMode == .upcoming {
      return String(localized: "view.upcoming.title")
    }
    return board?.title ?? String(localized: "widget.defaultTitle")
  }
}

struct CardRow: View {
  let card: WidgetCard

  var body: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(card.due != nil ? Color.red : Color.blue)
        .frame(width: 6, height: 6)
      Text(card.title)
        .font(.caption)
        .lineLimit(1)
    }
  }
}

struct NewCardWidgetView: View {
  let entry: NewCardEntry

  var body: some View {
    let payload = entry.payload
    let board = resolvedBoard(from: payload)
    let boardTitle = board?.title ?? String(localized: "newcard.noBoard")
    let quickAddUrl = deepLink(action: "quick-add", boardId: board?.id)

    ZStack {
      VStack(alignment: .leading, spacing: 8) {
        Text(String(localized: "newcard.header"))
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(boardTitle)
          .font(.headline)
          .lineLimit(1)
        Spacer(minLength: 0)
        if let url = quickAddUrl {
          Link(destination: url) {
            HStack(spacing: 6) {
              Image(systemName: "plus.circle.fill")
              Text(String(localized: "newcard.button"))
            }
          }
          .buttonStyle(.borderedProminent)
        } else {
          Text(String(localized: "newcard.missingBoard"))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .padding(12)
    }
    .containerBackground(.background, for: .widget)
  }

  private func resolvedBoard(from payload: WidgetPayload?) -> WidgetBoard? {
    guard let payload else { return nil }
    if let selected = entry.configuration.board,
       let board = payload.boards.first(where: { $0.id == selected.id }) {
      return board
    }
    if let defaultId = payload.defaultBoardId,
       let board = payload.boards.first(where: { $0.id == defaultId }) {
      return board
    }
    return payload.boards.first
  }

  private func deepLink(action: String, boardId: Int?) -> URL? {
    var components = URLComponents()
    components.scheme = "nextdeck"
    components.host = action
    if let boardId {
      components.queryItems = [URLQueryItem(name: "board", value: "\(boardId)")]
    }
    return components.url
  }
}

struct UpcomingLargeWidgetView: View {
  let entry: UpcomingLargeEntry

  var body: some View {
    let cards = upcomingCards(from: entry.payload)
    let left = Array(cards.enumerated().filter { $0.offset % 2 == 0 }.map { $0.element })
    let right = Array(cards.enumerated().filter { $0.offset % 2 == 1 }.map { $0.element })

    ZStack {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(String(localized: "upcomingLarge.header"))
            .font(.headline)
          Spacer()
          Text(assignmentLabel())
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if cards.isEmpty {
          Text(String(localized: "widget.noCards"))
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          HStack(alignment: .top, spacing: 12) {
            cardColumn(left)
            cardColumn(right)
          }
        }
        Spacer(minLength: 0)
      }
      .padding(12)
    }
    .containerBackground(.background, for: .widget)
  }

  private func upcomingCards(from payload: WidgetPayload?) -> [WidgetCard] {
    guard let payload else { return [] }
    let filtered = payload.cards.filter { card in
      guard card.due != nil else { return false }
      switch entry.configuration.assignment {
      case .assigned:
        return card.assignedToMe
      case .all:
        return true
      }
    }
    let sorted = filtered.sorted(by: sortCards(_:_:))
    return Array(sorted.prefix(16))
  }

  private func cardColumn(_ cards: [WidgetCard]) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(cards) { card in
        if let url = deepLink(
          action: "card",
          boardId: card.boardId,
          cardId: card.id,
          stackId: card.columnId,
          edit: true
        ) {
          Link(destination: url) {
            UpcomingRow(card: card)
          }
        } else {
          UpcomingRow(card: card)
        }
      }
    }
  }

  private func assignmentLabel() -> String {
    switch entry.configuration.assignment {
    case .assigned:
      return String(localized: "assignment.assigned")
    case .all:
      return String(localized: "assignment.all")
    }
  }

  private func sortCards(_ a: WidgetCard, _ b: WidgetCard) -> Bool {
    switch (a.due, b.due) {
    case let (lhs?, rhs?):
      return lhs < rhs
    case (.some, .none):
      return true
    case (.none, .some):
      return false
    default:
      return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
    }
  }

  private func deepLink(action: String, boardId: Int?, cardId: Int? = nil, stackId: Int? = nil, edit: Bool = false) -> URL? {
    var components = URLComponents()
    components.scheme = "nextdeck"
    components.host = action
    var items: [URLQueryItem] = []
    if let boardId { items.append(URLQueryItem(name: "board", value: "\(boardId)")) }
    if let cardId { items.append(URLQueryItem(name: "card", value: "\(cardId)")) }
    if let stackId { items.append(URLQueryItem(name: "stack", value: "\(stackId)")) }
    if edit { items.append(URLQueryItem(name: "edit", value: "1")) }
    if !items.isEmpty {
      components.queryItems = items
    }
    return components.url
  }
}

struct UpcomingRow: View {
  let card: WidgetCard

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(card.title)
        .font(.caption)
        .lineLimit(1)
      if let due = card.due {
        Text(formatDue(due))
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func formatDue(_ due: Int64) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(due) / 1000)
    return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
  }
}

struct UpcomingLockWidgetView: View {
  let entry: UpcomingLockEntry

  var body: some View {
    let cards = upcomingCards(from: entry.payload)

    ZStack {
      VStack(alignment: .leading, spacing: 4) {
        if cards.isEmpty {
          Text(String(localized: "widget.noCards"))
            .font(.caption2)
            .foregroundStyle(.secondary)
        } else {
          ForEach(cards) { card in
            if let url = deepLink(
              action: "card",
              boardId: card.boardId,
              cardId: card.id,
              stackId: card.columnId,
              edit: true
            ) {
              Link(destination: url) {
                UpcomingLockRow(card: card)
              }
            } else {
              UpcomingLockRow(card: card)
            }
          }
        }
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 4)
    }
    .containerBackground(.background, for: .widget)
  }

  private func upcomingCards(from payload: WidgetPayload?) -> [WidgetCard] {
    guard let payload else { return [] }
    let filtered = payload.cards.filter { card in
      guard card.due != nil else { return false }
      switch entry.configuration.assignment {
      case .assigned:
        return card.assignedToMe
      case .all:
        return true
      }
    }
    let sorted = filtered.sorted(by: sortCards(_:_:))
    return Array(sorted.prefix(3))
  }

  private func sortCards(_ a: WidgetCard, _ b: WidgetCard) -> Bool {
    switch (a.due, b.due) {
    case let (lhs?, rhs?):
      return lhs < rhs
    case (.some, .none):
      return true
    case (.none, .some):
      return false
    default:
      return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
    }
  }

  private func deepLink(action: String, boardId: Int?, cardId: Int? = nil, stackId: Int? = nil, edit: Bool = false) -> URL? {
    var components = URLComponents()
    components.scheme = "nextdeck"
    components.host = action
    var items: [URLQueryItem] = []
    if let boardId { items.append(URLQueryItem(name: "board", value: "\(boardId)")) }
    if let cardId { items.append(URLQueryItem(name: "card", value: "\(cardId)")) }
    if let stackId { items.append(URLQueryItem(name: "stack", value: "\(stackId)")) }
    if edit { items.append(URLQueryItem(name: "edit", value: "1")) }
    if !items.isEmpty {
      components.queryItems = items
    }
    return components.url
  }
}

struct UpcomingLockRow: View {
  let card: WidgetCard

  var body: some View {
    HStack(spacing: 6) {
      Text(card.title)
        .font(.caption)
        .lineLimit(1)
      Spacer(minLength: 4)
      if let due = card.due {
        Text(formatDue(due))
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func formatDue(_ due: Int64) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(due) / 1000)
    if Calendar.current.isDateInToday(date) {
      return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
    }
    return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .none)
  }
}
