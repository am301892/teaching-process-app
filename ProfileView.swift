//
//  ProfileView.swift
//  HolisticTaskManager
//
//  Created by Aleksandra Maksimowska
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ProfileView: View {
    @Binding var selectedTab: Int
    @StateObject private var appStore = AppStore.shared
    @State private var showLoginView = false
    @State private var showEditProfile = false  // New state for edit sheet
    
    private var canEditProfile: Bool {
            guard let role = appStore.currentUser?.role else { return false }
            return role == "parent" || role == "tutor"
        }
    
    var body: some View {
        NavigationView {
            VStack {
                if let profile = appStore.currentUser {
                    VStack(spacing: 10) {
                        // Profile Header
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Hello \(profile.name)")
                                    .font(.title)
                                    .fontWeight(.bold)
                                
                                Text(profile.email)
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            // Add Edit Button
                            if canEditProfile {
                                Button(action: {
                                    showEditProfile = true
                                }) {
                                    Image(systemName: "pencil.circle.fill")
                                        .foregroundColor(Color(hexString: "0D085B"))
                                        .font(.title2)
                                }
                            }
                        }
                        
                        // Role Section
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Role")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                Text(profile.role.capitalized)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(5)
                        
                        // Phone Number with Copy Button
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Phone Number")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                Text(profile.phoneNumber)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                UIPasteboard.general.string = profile.phoneNumber
                            }) {
                                Text("Copy")
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(Color(hexString: "0D085B"))
                                    .foregroundColor(.white)
                                    .cornerRadius(5)
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(5)
                        
                        // Customer Support Button
                        Button(action: {
                            // TO DO: Add customer support action here
                        }) {
                            HStack {
                                Image(systemName: "questionmark.circle")
                                Text("Customer Support")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .foregroundColor(.primary)
                            .cornerRadius(5)
                        }
                        
                        Spacer()
                        
                        // Logout Button
                        Button(action: {
                            do {
                                try Auth.auth().signOut()
                                showLoginView = true
                            } catch {
                                print("Error signing out: \(error.localizedDescription)")
                            }
                        }) {
                            Text("Log Out")
                                .frame(minWidth: 0, maxWidth: .infinity)
                                .padding()
                                .background(Color(hexString: "0D085B"))
                                .foregroundColor(.white)
                                .cornerRadius(5)
                        }
                    }
                    .padding()
                } else {
                    ProgressView()
                }
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileView()
            }
            .fullScreenCover(isPresented: $showLoginView) {
                LoginView()
            }
        }
    }
}

// Add EditProfileView definition here
struct EditProfileView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var appStore = AppStore.shared
    
    @State private var name: String = ""
    @State private var phoneNumber: String = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isLoading = false
    
    private func isValidPhoneNumber(_ phone: String) -> Bool {
        let phoneRegex = "^[0-9]{9}$" // Dokładnie 9 cyfr
        let phoneTest = NSPredicate(format: "SELF MATCHES %@", phoneRegex)
        return phoneTest.evaluate(with: phone)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Form {
                    Section(header: Text("Personal Information")) {
                        TextField("Name", text: $name)
                        TextField("Phone Number", text: $phoneNumber)
                            .keyboardType(.phonePad)
                            .onChange(of: phoneNumber) { newValue in
                                // Usuwamy wszystkie nie-cyfry
                                phoneNumber = newValue.filter { $0.isNumber }
                                // Ograniczamy długość do 9 cyfr
                                if phoneNumber.count > 9 {
                                    phoneNumber = String(phoneNumber.prefix(9))
                                }
                            }
                    }
                }
                .navigationTitle("Edit Profile")
                .navigationBarItems(
                    leading: Button("Cancel") {
                        dismiss()
                    },
                    trailing: Button("Save") {
                        saveChanges()
                    }
                    .disabled(isLoading || !hasChanges)
                )
                .onAppear {
                    if let currentUser = appStore.currentUser {
                        name = currentUser.name
                        phoneNumber = currentUser.phoneNumber
                    }
                }
                .alert(alertMessage, isPresented: $showAlert) {
                    Button("OK", role: .cancel) { }
                }
                
                if isLoading {
                    Color.black.opacity(0.2)
                        .edgesIgnoringSafeArea(.all)
                    
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(hexString: "0D085B")))
                        .scaleEffect(1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white)
                                .frame(width: 80, height: 80)
                        )
                }
            }
        }
    }
    
    private var hasChanges: Bool {
        guard let currentUser = appStore.currentUser else { return false }
        return name != currentUser.name ||
               phoneNumber != currentUser.phoneNumber
    }
    
    private func saveChanges() {
        // Sprawdzamy numer telefonu jeśli został zmieniony
        if phoneNumber != appStore.currentUser?.phoneNumber {
            if !isValidPhoneNumber(phoneNumber) {
                alertMessage = "Phone number must be exactly 9 digits"
                showAlert = true
                return
            }
        }
        
        isLoading = true
        
        // Jeśli numer telefonu się zmienił, sprawdź jego dostępność
        if phoneNumber != appStore.currentUser?.phoneNumber {
            appStore.isPhoneNumberAvailable(phoneNumber) { isAvailable in
                if !isAvailable {
                    DispatchQueue.main.async {
                        isLoading = false
                        alertMessage = "This phone number is already in use"
                        showAlert = true
                    }
                    return
                }
                // Jeśli numer jest dostępny, wykonaj aktualizację
                updateProfile()
            }
        } else {
            // Jeśli tylko nazwa się zmieniła, wykonaj aktualizację
            updateProfile()
        }
    }
    
    private func updateProfile() {
        appStore.updateUserProfile(
            name: name != appStore.currentUser?.name ? name : nil,
            phoneNumber: phoneNumber != appStore.currentUser?.phoneNumber ? phoneNumber : nil
        ) { result in
            isLoading = false
            
            switch result {
            case .success:
                dismiss()
            case .failure(let error):
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }
}

#Preview {
    ProfileView(selectedTab: .constant(4))
}
