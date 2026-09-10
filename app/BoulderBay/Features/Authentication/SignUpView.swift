import SwiftUI

struct SignUpView: View {
    @Bindable var model: AuthenticationViewModel

    var body: some View {
        AuthScreen(model: model) {
            TextField("Name", text: $model.name)
                .textContentType(.name)
                .textFieldStyle(AuthTextFieldStyle())
            TextField("Email", text: $model.email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(AuthTextFieldStyle())
            SecureField("Password", text: $model.password)
                .textContentType(.newPassword)
                .textFieldStyle(AuthTextFieldStyle())
                .submitLabel(.go)
                .onSubmit { Task { await model.submit() } }
        }
    }
}

#Preview {
    SignUpView(model: AuthenticationViewModel(auth: MockAuthService(), mode: .signUp))
}
