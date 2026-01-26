import SwiftUI
import WidgetKit

@main
struct NextDeckWidgetBundle: WidgetBundle {
  var body: some Widget {
    NextDeckWidget()
    NewCardWidget()
    UpcomingLargeWidget()
    UpcomingLockWidget()
  }
}
