import SwiftUI

// MARK: - App Color Palette

extension Color {
    
    static let primaryTeal = Color(red: 0.2, green: 0.6, blue: 0.6)
    
    static let destructiveRed = Color.red
}


// MARK: - Primary Button Style

struct PrimaryButtonStyle: ButtonStyle {
    
    var color: Color = .primaryTeal
    var isLoading: Bool = false
    var isSecondary: Bool = false
    var isDestructive: Bool = false

    @Environment(\.isEnabled) private var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {

            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: isSecondary ? color : .white))
                    .scaleEffect(0.8)
            } else {
                configuration.label
            }
        }
        .font(.headline.weight(.semibold))
        .padding(.vertical, 14)
        .padding(.horizontal, 24)

        .background(

            ZStack {

                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        isSecondary ? Color.clear : (isDestructive ? Color.destructiveRed : color)
                    )
                
            
                if isSecondary {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isDestructive ? .destructiveRed : color,
                            lineWidth: 2
                        )
                }
            }
        )
        .foregroundColor(
            isSecondary ? (isDestructive ? .destructiveRed : color) : .white
        )

        .opacity(!isEnabled || isLoading ? 0.6 : 1.0)
        .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
        .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
        .animation(.easeOut(duration: 0.2), value: isLoading)
        .accessibilityAddTraits(.isButton)
    }
}


// MARK: - Primary Button View

/// 一個封裝了 `PrimaryButtonStyle` 的便捷視圖，簡化按鈕的創建。
struct PrimaryButton: View {
    
    let title: String
    var color: Color = .primaryTeal
    var isLoading: Bool = false
    var isDisabled: Bool = false
    var isSecondary: Bool = false
    var isDestructive: Bool = false
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
        ScrollView {
            VStack(spacing: 20) {
                Text("Primary Button (Filled)")
                    .font(.caption)
                PrimaryButton(title: "Start Shift", action: {})
                PrimaryButton(title: "Loading...", isLoading: true, action: {})
                PrimaryButton(title: "Disabled", isDisabled: true, action: {})
                
                Divider()
                
                Text("Secondary Button (Outline)")
                    .font(.caption)
                PrimaryButton(title: "Edit", color: .primaryTeal, isSecondary: true, action: {})
                PrimaryButton(title: "Disabled Secondary", isDisabled: true, isSecondary: true, action: {})
                
                Divider()

                Text("Destructive Button")
                    .font(.caption)
                PrimaryButton(title: "Cancel Task", isDestructive: true, action: {})
                PrimaryButton(title: "Report Issue", isSecondary: true, isDestructive: true, action: {})

            }
            .padding()
        }
        .previewLayout(.sizeThatFits)
        .navigationTitle("Button Examples")
    }
}
