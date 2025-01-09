//
//  EditChildView.swift
//  HolisticTaskManager
//
//  Created by Aleksandra Maksimowska
//
import SwiftUI
import Foundation
import Firebase
import FirebaseAuth

struct EditChildView: View {
    @Environment(\.dismiss) var dismiss
    let child: Child
    @State private var name: String = ""
    @State private var phoneNumber: String = ""
    @State private var schoolType: String = "primary"
    @State private var grade: Int = 1
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Form {
                    Section(header: Text("Personal Information")) {
                        TextField("Name", text: $name)
                        TextField("Phone Number", text: $phoneNumber)
                            .keyboardType(.phonePad)
                    }
                    
                    Section(header: Text("School Information")) {
                        Picker("School Type", selection: $schoolType) {
                            Text("Primary").tag("primary")
                            Text("High School").tag("high_school")
                            Text("Technical").tag("technical")
                            Text("Vocational").tag("vocational")
                        }
                        
                        Picker("Grade", selection: $grade) {
                            ForEach(1...8, id: \.self) { grade in
                                Text("\(grade)").tag(grade)
                            }
                        }
                    }
                }
                .navigationTitle("Edit Child Profile")
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
                    loadChildData()
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
    
    private func loadChildData() {
        name = child.name
        phoneNumber = child.phoneNumber
        schoolType = child.schoolType
        grade = child.grade
    }
    
    private var hasChanges: Bool {
        name != child.name ||
        phoneNumber != child.phoneNumber ||
        schoolType != child.schoolType ||
        grade != child.grade
    }
    
    private func isValidPhoneNumber(_ phone: String) -> Bool {
        let phoneRegex = "^[0-9]{9}$" // Dokładnie 9 cyfr
        let phoneTest = NSPredicate(format: "SELF MATCHES %@", phoneRegex)
        return phoneTest.evaluate(with: phone)
    }

    private func saveChanges() {
        // Najpierw sprawdzamy numer telefonu
        if !isValidPhoneNumber(phoneNumber) {
            alertMessage = "Phone number must be exactly 9 digits"
            showAlert = true
            return
        }

        isLoading = true
        let db = Firestore.firestore()
        
        print("Starting update for child - userId/documentId: \(child.userId)")
        print("New values - name: \(name), phone: \(phoneNumber), school: \(schoolType), grade: \(grade)")

        // Sprawdzamy dostępność numeru telefonu, jeśli został zmieniony
        if phoneNumber != child.phoneNumber {
            AppStore.shared.isPhoneNumberAvailable(phoneNumber) { isAvailable in
                if !isAvailable {
                    DispatchQueue.main.async {
                        isLoading = false
                        alertMessage = "This phone number is already in use"
                        showAlert = true
                    }
                    return
                }
                // Jeśli numer jest dostępny, kontynuujemy z aktualizacją
                self.performUpdate(db: db)
            }
        } else {
            // Jeśli numer telefonu nie został zmieniony, po prostu aktualizujemy
            performUpdate(db: db)
        }
    }

    private func performUpdate(db: Firestore) {
        // Aktualizacja w tabeli users
        db.collection("users").document(child.userId).updateData([
            "name": name,
            "phoneNumber": phoneNumber
        ]) { error in
            if let error = error {
                isLoading = false
                print("Error updating user data: \(error.localizedDescription)")
                alertMessage = "Error updating user data: \(error.localizedDescription)"
                showAlert = true
                return
            }
            
            print("Successfully updated user data")
            
            // Aktualizacja w tabeli students - używamy tego samego ID
            db.collection("students").document(child.userId).updateData([
                "name": name,
                "school_type": schoolType,
                "grade": grade
            ]) { error in
                isLoading = false
                
                if let error = error {
                    print("Error updating student data: \(error.localizedDescription)")
                    alertMessage = "Error updating student data: \(error.localizedDescription)"
                    showAlert = true
                    return
                }
                
                print("Successfully updated student data")
                AppStore.shared.triggerRefresh()
                dismiss()
            }
        }
    }
}
