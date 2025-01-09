//
//  ParentPeopleView.swift
//  HolisticTaskManager
//
//  Created by Aleksandra Maksimowska
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// Model representing a child user in the system
// Contains both student document data and associated user account information
struct Child: Identifiable {
    let id: String           // Student document ID
    let userId: String       // Associated user document ID
    let name: String
    let schoolType: String
    let grade: Int
    let email: String
    let phoneNumber: String
    
    // Connection status with parent/guardian
    let guardianRole: String // "primary_parent", "secondary_parent", "guardian"
    let connectionStatus: String // "active", "pending"
}

extension Child: Equatable {
    static func == (lhs: Child, rhs: Child) -> Bool {
        return lhs.id == rhs.id &&
        lhs.userId == rhs.userId &&
        lhs.name == rhs.name &&
        lhs.schoolType == rhs.schoolType &&
        lhs.grade == rhs.grade &&
        lhs.email == rhs.email &&
        lhs.phoneNumber == rhs.phoneNumber &&
        lhs.guardianRole == rhs.guardianRole &&
        lhs.connectionStatus == rhs.connectionStatus
    }
}

// Model representing a tutor in the system
// Contains basic tutor information and connection status
struct Tutor: Identifiable {
    let id: String
    let email: String
    let phoneNumber: String
    let status: String // "active" or "pending"
    var connectedChildren: [Child] // Pole dla połączonych dzieci
}

// Main view for parent users to manage their children and tutors
// Provides functionality to add children and connect with tutors
struct ParentPeopleView: View {
    @StateObject private var appStore = AppStore.shared
    @State private var children: [Child] = []
    @State private var showAddChildSheet = false
    @State private var searchTutorText = ""
    @State private var showSearchAlert = false
    @State private var alertMessage = ""
    @State private var foundTutor: Tutor?
    @State private var showSelectChildrenSheet = false
    @State private var selectedChildren: Set<String> = []
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Children management section
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Text("Children")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Spacer()
                            
                            Button(action: {
                                showAddChildSheet = true
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(Color(hexString: "0D085B"))
                                    .font(.title2)
                            }
                        }
                        
                        if appStore.children.isEmpty {
                            Text("No children added yet")
                                .foregroundColor(.gray)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(10)
                        } else {
                            ForEach(appStore.children) { child in
                                NavigationLink(destination: EditChildView(child: child)) {
                                    ChildCard(child: child)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(15)
                    .shadow(radius: 2)
                    
                    // Tutors section
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Tutors")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        HStack {
                            TextField("Search tutor by phone number", text: $searchTutorText)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numberPad)
                            
                            Button(action: searchTutor) {
                                Image(systemName: "magnifyingglass.circle.fill")
                                    .foregroundColor(Color(hexString: "0D085B"))
                                    .font(.title2)
                            }
                        }
                        
                        if !appStore.tutors.filter({ $0.status == "active" }).isEmpty {
                            Text("Active")
                                .font(.headline)
                                .padding(.top)
                            
                            ForEach(appStore.tutors.filter { $0.status == "active" }) { tutor in
                                TutorCard(tutor: tutor)
                            }
                        }
                        
                        if !appStore.tutors.filter({ $0.status == "pending" }).isEmpty {
                            Text("Pending Invitations")
                                .font(.headline)
                                .padding(.top)
                            
                            ForEach(appStore.tutors.filter { $0.status == "pending" }) { tutor in
                                TutorCard(tutor: tutor)
                            }
                        }
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(15)
                    .shadow(radius: 2)
                }
                .padding()
                .padding(.bottom, 90)
            }
            .navigationTitle("People")
            .sheet(isPresented: $showAddChildSheet) {
                AddChildView(onChildAdded: {
                    appStore.triggerRefresh()
                })
            }
            .sheet(isPresented: $showSelectChildrenSheet) {
                SelectChildrenSheet(
                    children: appStore.children,
                    selectedChildren: $selectedChildren
                ) { selectedChildrenIds in
                    sendInvitationToTutor(selectedChildrenIds: selectedChildrenIds)
                }
            }
            .alert(alertMessage, isPresented: $showSearchAlert) {
                Button("OK", role: .cancel) {}
            }
        }
    }
    
    private func searchTutor() {
        guard !searchTutorText.isEmpty else {
            alertMessage = "Please enter a phone number"
            showSearchAlert = true
            return
        }
        
        let db = Firestore.firestore()
        db.collection("users")
            .whereField("phoneNumber", isEqualTo: searchTutorText)
            .whereField("role", isEqualTo: "tutor")
            .getDocuments { (snapshot: QuerySnapshot?, error: Error?) in
                if let error = error {
                    alertMessage = "Error: \(error.localizedDescription)"
                    showSearchAlert = true
                    return
                }
                
                guard let documents = snapshot?.documents,
                      !documents.isEmpty else {
                    alertMessage = "No tutor found with this phone number"
                    showSearchAlert = true
                    return
                }
                
                let document = documents[0]
                let tutorId = document.documentID
                
                if appStore.tutors.contains(where: { $0.id == tutorId }) {
                    alertMessage = "This tutor is already in your connections"
                    showSearchAlert = true
                    return
                }
                
                foundTutor = Tutor(
                    id: tutorId,
                    email: document.data()["email"] as? String ?? "",
                    phoneNumber: document.data()["phoneNumber"] as? String ?? "",
                    status: "pending",
                    connectedChildren: []
                )
                
                showSelectChildrenSheet = true
            }
    }
    
    
    // Sends connection invitations to tutor for selected children
    // Creates connection documents and notifications in a single batch
    private func sendInvitationToTutor(selectedChildrenIds: Set<String>) {
        guard let tutor = foundTutor,
              let parentId = Auth.auth().currentUser?.uid else { return }
        
        let db = Firestore.firestore()
        let batch = db.batch() // Use batch for atomic operation
        
        // Create connection documents for each selected child
        for childId in selectedChildrenIds {
            let connectionRef = db.collection("tutor_student_connections").document()
            let connectionData: [String: Any] = [
                "tutor_id": tutor.id,
                "parent_id": parentId,
                "student_id": childId,
                "status": "pending",
                "created_at": FieldValue.serverTimestamp(),
                "updated_at": FieldValue.serverTimestamp()
            ]
            
            batch.setData(connectionData, forDocument: connectionRef)
            
            // Create notification for tutor
            let notificationRef = db.collection("notifications").document()
            let notificationData: [String: Any] = [
                "user_id": tutor.id,
                "title": "New Connection Request",
                "content": "A parent wants to connect with you",
                "type": "connection_request",
                "is_read": false,
                "created_at": FieldValue.serverTimestamp()
            ]
            
            batch.setData(notificationData, forDocument: notificationRef)
        }
        
        // Commit all changes
        batch.commit { error in
            if let error = error {
                self.alertMessage = "Error creating connection: \(error.localizedDescription)"
                self.showSearchAlert = true
                return
            }
            
            // Update local state after successful commit
            appStore.tutors.append(tutor)
            
            // Clear search state
            self.searchTutorText = ""
            self.foundTutor = nil
            
            self.alertMessage = "Invitation sent successfully"
            self.showSearchAlert = true
        }
    }
}

// Card view for displaying child information
struct ChildCard: View {
    let child: Child
    @State private var showEditSheet = false
    
    var body: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(child.name)
                        .font(.headline)
                    
                    Text("\(child.schoolType) - Grade \(child.grade)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    Text(child.email)
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Text(child.phoneNumber)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Pokazujemy przycisk edycji tylko dla primary i secondary parent
                if child.guardianRole == "primary_parent" || child.guardianRole == "secondary_parent" {
                    Button(action: {
                        showEditSheet = true
                    }) {
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                    }
                }
                
                // Display connection status badge if not active
                if child.connectionStatus != "active" {
                    Text(child.connectionStatus.capitalized)
                        .font(.caption)
                        .padding(5)
                        .background(child.connectionStatus == "pending" ? Color.orange.opacity(0.2) : Color.gray.opacity(0.2))
                        .foregroundColor(child.connectionStatus == "pending" ? .orange : .gray)
                        .cornerRadius(5)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
        .sheet(isPresented: $showEditSheet) {
            EditChildView(child: child)
        }
    }
}

// Card view for displaying tutor information
struct TutorCard: View {
    let tutor: Tutor
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Informacje o tutorze
            VStack(alignment: .leading, spacing: 5) {
                Text(tutor.email)
                    .font(.headline)
                Text(tutor.phoneNumber)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            // Sekcja dzieci
            if !tutor.connectedChildren.isEmpty {
                Divider()
                
                Text("Connected children:")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                ForEach(tutor.connectedChildren) { child in
                    Text(child.name)
                        .font(.subheadline)
                }
            }
            
            HStack {
                Spacer()
                
                // Status "pending" jeśli potrzebny
                if tutor.status == "pending" {
                    Text("Pending")
                        .font(.caption)
                        .padding(5)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(5)
                }
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}

// Sheet view for selecting children when connecting with a tutor
// Allows multiple selection and handles completion through callback
struct SelectChildrenSheet: View {
    @Environment(\.dismiss) var dismiss
    let children: [Child]
    @Binding var selectedChildren: Set<String>
    let onComplete: (Set<String>) -> Void
    
    var body: some View {
        NavigationView {
            List(children) { child in
                Button(action: {
                    // Toggle child selection
                    if selectedChildren.contains(child.id) {
                        selectedChildren.remove(child.id)
                    } else {
                        selectedChildren.insert(child.id)
                    }
                }) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(child.name)
                                .foregroundColor(.primary)
                            Text("\(child.schoolType) - Grade \(child.grade)")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        // Show checkmark for selected children
                        if selectedChildren.contains(child.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color(hexString: "0D085B"))
                        }
                    }
                }
            }
            .navigationTitle("Select Children")
            .navigationBarItems(
                leading: Button("Cancel") {
                    dismiss()
                },
                trailing: Button("Send Invitation") {
                    onComplete(selectedChildren)
                    dismiss()
                }
                    .disabled(selectedChildren.isEmpty)
            )
        }
    }
}

// View for adding new children or connecting with existing ones
// Supports two modes: creating new accounts and connecting existing accounts
struct AddChildView: View {
    @Environment(\.dismiss) var dismiss
    @State private var isLoading = false
    private let db = Firestore.firestore()
    var onChildAdded: (() -> Void)? // Callback for refreshing parent view
    
    // Shared state
    @State private var additionMode = "new" // "new" or "existing"
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    // State for new child creation
    @State private var childEmail = ""
    @State private var childPassword = ""
    @State private var childName = ""
    @State private var phoneNumber = ""
    @State private var selectedSchoolType = "primary"
    @State private var selectedGrade = 1
    
    // State for existing child connection
    @State private var existingChildPhone = ""
    @State private var existingChildPassword = ""
    
    var body: some View {
        NavigationView {
            if isLoading {
                ProgressView()
            } else {
                Form {
                    // Mode selection segment control
                    Picker("Addition Mode", selection: $additionMode) {
                        Text("Create New Account").tag("new")
                        Text("Connect Existing").tag("existing")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.vertical)
                    
                    if additionMode == "new" {
                        // Form for creating new child account
                        Section(header: Text("Child Account Details")) {
                            TextField("Email", text: $childEmail)
                                .textContentType(.emailAddress)
                                .autocapitalization(.none)
                            
                            SecureField("Password", text: $childPassword)
                                .textContentType(.newPassword)
                            
                            TextField("Full Name", text: $childName)
                            
                            TextField("Phone Number", text: $phoneNumber)
                                .keyboardType(.numberPad)
                        }
                        
                        Section(header: Text("School Information")) {
                            Picker("School Type", selection: $selectedSchoolType) {
                                Text("Primary").tag("primary")
                                Text("High School").tag("high_school")
                                Text("Technical").tag("technical")
                                Text("Vocational").tag("vocational")
                            }
                            
                            Picker("Grade", selection: $selectedGrade) {
                                ForEach(1...8, id: \.self) { grade in
                                    Text("\(grade)").tag(grade)
                                }
                            }
                        }
                    } else {
                        // Form for connecting existing child account
                        Section(header: Text("Connect with Existing Child")) {
                            TextField("Child's Phone Number", text: $existingChildPhone)
                                .keyboardType(.numberPad)
                            
                            SecureField("Child's Account Password", text: $existingChildPassword)
                        }
                    }
                }
                .navigationTitle("Add Child")
                .navigationBarItems(
                    leading: Button("Cancel") {
                        dismiss()
                    },
                    trailing: Button("Add") {
                        if additionMode == "new" {
                            createNewChild()
                        } else {
                            connectExistingChild()
                        }
                    }
                        .disabled(isFormInvalid)
                )
                .alert(alertMessage, isPresented: $showAlert) {
                    Button("OK", role: .cancel) {}
                }
            }
        }
    }
    
    // Form validation logic
    private var isFormInvalid: Bool {
        if additionMode == "new" {
            return childEmail.isEmpty || childPassword.isEmpty ||
            childName.isEmpty || phoneNumber.isEmpty
        } else {
            return existingChildPhone.isEmpty || existingChildPassword.isEmpty
        }
    }
    
    // Handles creation of new child account and connection
    private func createNewChild() {
        isLoading = true // Rozpoczęcie ładowania

        guard let parentId = Auth.auth().currentUser?.uid else {
            isLoading = false // Dodaj tutaj
            return
        }

        ConnectionManager.shared.createNewChildAccount(
            email: childEmail,
            password: childPassword,
            name: childName,
            phoneNumber: phoneNumber,
            schoolType: selectedSchoolType,
            grade: selectedGrade,
            parentId: parentId,
            parentEmail: Auth.auth().currentUser?.email ?? "",
            parentPassword: childPassword
        ) { result in 
            
            DispatchQueue.main.async {
                self.isLoading = false // Upewnij się, że to się wykonuje
                
                switch result {
                case .success:
                    self.onChildAdded?()
                    self.dismiss()
                case .failure(let error):
                    self.alertMessage = error.localizedDescription
                    self.showAlert = true
                }
            }
        }
    }
    
    // Handles connection with existing child account
    private func connectExistingChild() {
        guard let guardianId = Auth.auth().currentUser?.uid else { return }
        
        ConnectionManager.shared.connectExistingChild(
            phoneNumber: existingChildPhone,
            password: existingChildPassword,
            guardianId: guardianId
        ) { result in
            switch result {
            case .success:
                DispatchQueue.main.async {
                    self.onChildAdded?()
                    self.dismiss()
                }
            case .failure(let error):
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }


    
    
    // Preview provider for SwiftUI canvas
    #Preview {
        ParentPeopleView()
    }
}
