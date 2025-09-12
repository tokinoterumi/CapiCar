import SwiftUI

struct ContentView: View {
    var body: some View {
        // The ContentView is the root of the entire application.
        // Its primary job is to decide which main screen to show.
        // In a more complex app, it might check for an authentication
        // token and show either a LoginView or the DashboardView.
        
        // For our CapiCar MVP, we will directly show the main dashboard.
        DashboardView()
    }
}

// The preview for ContentView now simply shows our entire Dashboard.
#Preview {
    ContentView()
}
