//
//  LoginView.swift
//  HolisticTaskManager
//
//  Created by Aleksandra Maksimowska
//

import Foundation
import Firebase
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct LoginView: View {
    // State dla logowania
    @State private var loginEmail = ""
    @State private var loginPassword = ""
    
    // State dla rejestracji
    @State private var registerEmail = ""
    @State private var registerPassword = ""
    @State private var phoneNumber = ""
    @State private var role = "parent"
    @State private var name = ""
    
    @State private var isLoginMode = true
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isUserLoggedIn = false
    
    @StateObject private var appStore = AppStore.shared
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    var body: some View {
        NavigationView {
            VStack {
                Spacer()
                VStack(spacing: 0){
                    Image("Learning-cuate")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 300, height: 300)
                    Text("Image by Freepik")
                        .font(.system(size: 8))
                }
                Picker(selection: $isLoginMode, label: Text("Picker here")) {
                    Text("Login")
                        .tag(true)
                    Text("Register")
                        .tag(false)
                }.pickerStyle(SegmentedPickerStyle())
                    .padding()
                
                if isLoginMode {
                    // Pola logowania
                    TextField("Email", text: $loginEmail)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(5)
                    
                    SecureField("Password", text: $loginPassword)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(5)
                } else {
                    // Pola rejestracji
                    Group {
                        TextField("Email", text: $registerEmail)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                        
                        SecureField("Password", text: $registerPassword)
                        
                        TextField("Name", text: $name)
                        
                        TextField("Phone Number", text: $phoneNumber)
                            .keyboardType(.phonePad)
                        
                        Picker("Role", selection: $role) {
                            Text("Parent").tag("parent")
                            Text("Tutor").tag("tutor")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    .padding(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                Button(action: handleAction) {
                    Text(isLoginMode ? "Log In" : "Create Account")
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .padding()
                        .background(Color(hexString: "0D085B"))
                        .foregroundColor(.white)
                        .cornerRadius(5)
                }
                .disabled(isLoginMode ?
                          (loginEmail.isEmpty || loginPassword.isEmpty) :
                            (registerEmail.isEmpty || registerPassword.isEmpty || phoneNumber.isEmpty || name.isEmpty))
                .padding()
                
                if showAlert {
                    Text(alertMessage)
                        .foregroundColor(.red)
                        .padding()
                }
                
                Spacer()
            }
            .padding()
        }
    }
    
    private func handleAction() {
        if isLoginMode {
            loginUser()
        } else {
            createNewAccount()
        }
    }
    
    private func loginUser() {
        Auth.auth().signIn(withEmail: loginEmail, password: loginPassword) { result, error in
            if let error = error as NSError? {
                switch error.code {
                case AuthErrorCode.wrongPassword.rawValue:
                    alertMessage = "Incorrect data"
                case AuthErrorCode.invalidEmail.rawValue:
                    alertMessage = "Please enter a valid email address"
                case AuthErrorCode.userNotFound.rawValue:
                    alertMessage = "Account not found"
                default:
                    alertMessage = "Failed to login: \(error.localizedDescription)"
                }
                showAlert = true
                return
            }
            isUserLoggedIn = true
        }
    }
    
    private func createNewAccount() {
        // 1. Walidacja emaila
        if !isValidEmail(registerEmail) {
            alertMessage = "Please enter a valid email address"
            showAlert = true
            return
        }

        // 2. Walidacja numeru telefonu
        let phoneNumberRegex = try? NSRegularExpression(pattern: "^[0-9]{9}$")
        let phoneNumberValid = phoneNumberRegex?.firstMatch(
            in: phoneNumber,
            range: NSRange(location: 0, length: phoneNumber.count)
        ) != nil
        
        if !phoneNumberValid {
            alertMessage = "Please enter a valid 9-digit phone number"
            showAlert = true
            return
        }

        // 3. Sprawdź czy konto już istnieje w Auth i Firestore
        Auth.auth().fetchSignInMethods(forEmail: registerEmail) { [self] methods, error in
            if let error = error {
                alertMessage = "Error checking email: \(error.localizedDescription)"
                showAlert = true
                return
            }
            
            if let methods = methods, !methods.isEmpty {
                alertMessage = "This email is already registered"
                showAlert = true
                return
            }
            
            // 4. Sprawdź dostępność numeru telefonu
            appStore.isPhoneNumberAvailable(phoneNumber) { [self] isPhoneAvailable in
                if !isPhoneAvailable {
                    alertMessage = "This phone number is already registered"
                    showAlert = true
                    return
                }
                
                // 5. Utwórz konto w Firebase Auth
                Auth.auth().createUser(withEmail: registerEmail, password: registerPassword) { [self] result, error in
                    if let error = error {
                        alertMessage = "Failed to create account: \(error.localizedDescription)"
                        showAlert = true
                        return
                    }
                    
                    guard let userId = result?.user.uid else {
                        alertMessage = "Failed to get user ID"
                        showAlert = true
                        return
                    }
                    
                    // 6. Zapisz dane użytkownika w Firestore
                    let db = Firestore.firestore()
                    let userData: [String: Any] = [
                        "email": registerEmail,
                        "phoneNumber": phoneNumber,
                        "role": role,
                        "name": name,
                        "createdAt": FieldValue.serverTimestamp()
                    ]
                    
                    db.collection("users").document(userId).setData(userData) { [self] error in
                        if let error = error {
                            alertMessage = "Failed to save user data: \(error.localizedDescription)"
                            showAlert = true
                            return
                        }
                        
                        isUserLoggedIn = true
                        appStore.triggerRefresh()
                    }
                }
            }
        }
    }
}
    #Preview{
        LoginView()
    }
