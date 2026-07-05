import SwiftUI

struct StackLockSheet: View {
    @ObservedObject var store: ScheduleStore
    @ObservedObject var statusModel: StatusViewModel
    var body: some View { Text("Stack a lock").padding() }
}
