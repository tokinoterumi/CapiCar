import SwiftUI

struct NetworkSettingsView: View {
    @State private var apiURL: String = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""

    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("API Configuration")
                    .font(.headline)

                Text("Current URL: \(APIService.shared.currentBaseURL)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Update API URL")
                    .font(.subheadline)
                    .fontWeight(.medium)

                TextField("http://your-ip:3000/api", text: $apiURL)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .keyboardType(.URL)

            }

            Button("Update URL") {
                updateAPIURL()
            }
            .buttonStyle(.borderedProminent)
            .disabled(apiURL.trimmingCharacters(in: .whitespaces).isEmpty)

            Button("Reset to Auto-Detect") {
                resetToAutoDetect()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .alert("API URL Updated", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            // Pre-populate with current URL if it's a manual override
            if let savedURL = UserDefaults.standard.string(forKey: "api_base_url"), !savedURL.isEmpty {
                apiURL = savedURL
            }
        }
    }

    private func updateAPIURL() {
        let trimmedURL = apiURL.trimmingCharacters(in: .whitespaces)
        guard !trimmedURL.isEmpty else { return }

        // Basic validation
        guard trimmedURL.hasPrefix("http://") || trimmedURL.hasPrefix("https://") else {
            alertMessage = "URL must start with http:// or https://"
            showingAlert = true
            return
        }

        APIService.shared.updateBaseURL(trimmedURL)
        alertMessage = "API URL updated to:\n\(trimmedURL)\n\nRestart the app to apply changes."
        showingAlert = true
    }

    private func resetToAutoDetect() {
        UserDefaults.standard.removeObject(forKey: "api_base_url")
        apiURL = ""
        alertMessage = "Reset to auto-detection. Restart the app to apply changes."
        showingAlert = true
    }
}

#Preview {
    NetworkSettingsView()
}
