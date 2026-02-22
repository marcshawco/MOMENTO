import SwiftUI

struct EmptyShelfView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Your Collection is Empty", systemImage: "cube.transparent")
        } description: {
            Text("Tap the + button to scan your first collectible and create a 3D digital twin.")
        }
    }
}

#Preview {
    EmptyShelfView()
}
