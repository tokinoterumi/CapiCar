import SwiftUI

struct LoginView: View {
    @StateObject private var viewModel = StaffLoginViewModel()
    
    var body: some View {
        VStack(spacing: 36) {
            // MARK: - App Logo & Title
            VStack(spacing: 16) {
                // App icon
                Image("AppIcon") // Make sure you have this image in your assets
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                
                VStack(spacing: 8) {
                    Text("CapiCar for YOS")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Warehouse Fulfillment System")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top)

            Spacer()
            
            // MARK: - Login Form
            VStack(spacing: 24) {
                TextField("Username", text: $viewModel.username)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .textContentType(.username)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                
                SecureField("Password", text: $viewModel.password)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .textContentType(.password)
            }
            .padding(.horizontal)
            
            // MARK: - Login Button
            // NOTE: Using a standard Button here. Replace with your 'PrimaryButton' if available.
            Button(action: {
                viewModel.performLogin()
            }) {
                HStack {
                    Spacer()
                    if viewModel.isLoggingIn {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Login")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                    Spacer()
                }
                .padding()
                .background(viewModel.canLogin ? Color.primaryTeal : Color.gray)
                .cornerRadius(50)
            }
            .frame(maxWidth: 120)
            .disabled(!viewModel.canLogin)
            .padding(.horizontal)
            
            Spacer()
            Spacer()
        }
        .padding()
        .alert("Login Error", isPresented: $viewModel.showErrorAlert) {
            Button("OK") { }
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        }
    }
}

#if DEBUG
struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
    }
}
#endif
