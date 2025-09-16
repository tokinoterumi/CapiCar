import SwiftUI

// MARK: - App Color Palette

extension Color {
    // Primary brand color: Beautiful Teal
    static let primaryTeal = Color(red: 0.2, green: 0.6, blue: 0.6)
    
    // Destructive action color
    static let destructiveRed = Color.red
}


// MARK: - Primary Button Style

/// A custom ButtonStyle that defines the visual appearance and interaction of the primary action buttons.
/// This approach is highly reusable and follows SwiftUI best practices.
struct PrimaryButtonStyle: ButtonStyle {
    
    /// The main color theme for the button.
    var color: Color = .primaryTeal // Default to our brand's primary color
    
    /// A flag to indicate if the button is in a loading state.
    var isLoading: Bool = false
    
    /// Defines if this is a secondary (outline/text-only) or primary (filled) button.
    var isSecondary: Bool = false
    
    /// Defines if this is a destructive (red) button.
    var isDestructive: Bool = false

    @Environment(\.isEnabled) private var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            // Show a ProgressView if the button is in a loading state.
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: isSecondary ? color : .white))
                    .scaleEffect(0.8)
            } else {
                configuration.label
            }
        }
        .font(.headline.weight(.semibold))
        .foregroundColor(
            !isEnabled || isLoading ? .white : // Disabled/loading text stays white
            isSecondary ? (isDestructive ? .destructiveRed : color) : .white // Normal text color based on type
        )
        .padding(.vertical, 14) // Vertical padding for comfortable height
        .padding(.horizontal, 24) // Horizontal padding for minimum width based on content
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    !isEnabled || isLoading ? Color.gray : // Disabled/loading state
                    isSecondary ? Color.clear : // Secondary buttons have clear background
                    (isDestructive ? Color.destructiveRed : color) // Destructive or primary fill
                )
        )
        .overlay( // For secondary buttons, add a border
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    !isEnabled || isLoading ? Color.gray : // Disabled/loading border
                    isSecondary ? (isDestructive ? .destructiveRed : color) : Color.clear, 
                    lineWidth: isSecondary ? 2 : 0
                )
        )
        // Animate the scale of the button when it's pressed.
        .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
        .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
        .animation(.easeOut(duration: 0.2), value: isLoading)
        .accessibilityAddTraits(.isButton) // Indicate it's a button for accessibility
    }
}


// MARK: - Primary Button View

/// A reusable primary action button view.
/// It simplifies the process of creating a styled button by wrapping the ButtonStyle.
struct PrimaryButton: View {
    
    let title: String
    var color: Color = .primaryTeal // Default to brand color
    var isLoading: Bool = false
    var isDisabled: Bool = false
    var isSecondary: Bool = false // For secondary button style
    var isDestructive: Bool = false // For destructive button style
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(PrimaryButtonStyle(
            color: color,
            isLoading: isLoading,
            isSecondary: isSecondary,
            isDestructive: isDestructive
        ))
        .disabled(isDisabled || isLoading)
    }
}


// MARK: - Preview

struct PrimaryButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            Text("Primary Button (Filled)")
                .font(.caption)
            PrimaryButton(title: "Start Shift", action: {})
            PrimaryButton(title: "Loading...", isLoading: true, action: {})
            PrimaryButton(title: "Disabled", isDisabled: true, action: {})
            
            Divider()
            
            Text("Secondary Button (Outline)")
                .font(.caption)
            PrimaryButton(title: "Edit", color: .primaryTeal, isSecondary: true, action: {}) // Secondary style
            PrimaryButton(title: "Disabled Secondary", isDisabled: true, isSecondary: true, action: {})
            
            Divider()

            Text("Destructive Button")
                .font(.caption)
            PrimaryButton(title: "Cancel Task", color: .destructiveRed, isDestructive: true, action: {}) // Destructive style
            PrimaryButton(title: "Report Issue", isSecondary: true, isDestructive: true, action: {})

            Divider()

            Text("Custom Color Primary")
                .font(.caption)
            PrimaryButton(title: "Custom Action", color: .purple, action: {})
        }
        .padding()
        .previewLayout(.sizeThatFits)
        .navigationTitle("Button Examples") // For preview in a NavigationStack context
    }
}
