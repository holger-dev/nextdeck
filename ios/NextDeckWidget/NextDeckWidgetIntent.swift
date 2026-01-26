import AppIntents
import WidgetKit

enum CardFilterOption: String, AppEnum {
  case all
  case assigned
  case dueSoon

  static var typeDisplayRepresentation: TypeDisplayRepresentation {
    TypeDisplayRepresentation(name: LocalizedStringResource("filter.title"))
  }

  static var caseDisplayRepresentations: [CardFilterOption: DisplayRepresentation] {
    [
      .all: DisplayRepresentation(title: LocalizedStringResource("filter.all")),
      .assigned: DisplayRepresentation(title: LocalizedStringResource("filter.assigned")),
      .dueSoon: DisplayRepresentation(title: LocalizedStringResource("filter.dueSoon"))
    ]
  }
}

enum AssignmentFilterOption: String, AppEnum {
  case assigned
  case all

  static var typeDisplayRepresentation: TypeDisplayRepresentation {
    TypeDisplayRepresentation(name: LocalizedStringResource("assignment.title"))
  }

  static var caseDisplayRepresentations: [AssignmentFilterOption: DisplayRepresentation] {
    [
      .assigned: DisplayRepresentation(title: LocalizedStringResource("assignment.assigned")),
      .all: DisplayRepresentation(title: LocalizedStringResource("assignment.all"))
    ]
  }
}

enum WidgetViewMode: String, AppEnum {
  case board
  case upcoming

  static var typeDisplayRepresentation: TypeDisplayRepresentation {
    TypeDisplayRepresentation(name: LocalizedStringResource("view.title"))
  }

  static var caseDisplayRepresentations: [WidgetViewMode: DisplayRepresentation] {
    [
      .board: DisplayRepresentation(title: LocalizedStringResource("view.board")),
      .upcoming: DisplayRepresentation(title: LocalizedStringResource("view.upcoming"))
    ]
  }
}

struct BoardEntity: AppEntity {
  static var typeDisplayRepresentation: TypeDisplayRepresentation {
    TypeDisplayRepresentation(name: LocalizedStringResource("board.title"))
  }

  static var defaultQuery = BoardQuery()

  let id: Int
  let title: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(title)")
  }
}

struct BoardQuery: EntityQuery {
  typealias Entity = BoardEntity

  func entities(for identifiers: [BoardEntity.ID]) async throws -> [BoardEntity] {
    let boards = WidgetDataStore.load()?.boards ?? []
    return boards
      .filter { identifiers.contains($0.id) }
      .map { BoardEntity(id: $0.id, title: $0.title) }
  }

  func suggestedEntities() async throws -> [BoardEntity] {
    let boards = WidgetDataStore.load()?.boards ?? []
    return boards.map { BoardEntity(id: $0.id, title: $0.title) }
  }
}

struct NextDeckWidgetIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "Next Deck Widget"
  static var description = IntentDescription(LocalizedStringResource("widget.intentDescription"))
  static var isWidgetConfiguration = true

  @Parameter(title: LocalizedStringResource("parameter.view"), default: .board)
  var viewMode: WidgetViewMode

  @Parameter(title: LocalizedStringResource("parameter.board"))
  var board: BoardEntity?

  @Parameter(title: LocalizedStringResource("parameter.filter"), default: .all)
  var filter: CardFilterOption

  static var parameterSummary: some ParameterSummary {
    Summary("Show \(\.$viewMode) for \(\.$board) with \(\.$filter)")
  }

  func perform() async throws -> some IntentResult {
    .result()
  }
}

struct NewCardWidgetIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "newcard.widgetTitle"
  static var description = IntentDescription(LocalizedStringResource("newcard.intentDescription"))
  static var isWidgetConfiguration = true

  @Parameter(title: LocalizedStringResource("parameter.board"))
  var board: BoardEntity?

  static var parameterSummary: some ParameterSummary {
    Summary("Create card in \(\.$board)")
  }

  func perform() async throws -> some IntentResult {
    .result()
  }
}

struct UpcomingLargeWidgetIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "upcomingLarge.widgetTitle"
  static var description = IntentDescription(LocalizedStringResource("upcomingLarge.intentDescription"))
  static var isWidgetConfiguration = true

  @Parameter(title: LocalizedStringResource("parameter.assignment"), default: .assigned)
  var assignment: AssignmentFilterOption

  static var parameterSummary: some ParameterSummary {
    Summary("Show \(\.$assignment) cards")
  }

  func perform() async throws -> some IntentResult {
    .result()
  }
}

struct UpcomingLockWidgetIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "upcomingLock.widgetTitle"
  static var description = IntentDescription(LocalizedStringResource("upcomingLock.intentDescription"))
  static var isWidgetConfiguration = true

  @Parameter(title: LocalizedStringResource("parameter.assignment"), default: .assigned)
  var assignment: AssignmentFilterOption

  static var parameterSummary: some ParameterSummary {
    Summary("Show \(\.$assignment) cards")
  }

  func perform() async throws -> some IntentResult {
    .result()
  }
}
