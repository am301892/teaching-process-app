//
//  TutorPeopleView.swift
//  HolisticTaskManager
//
//  Created by Aleksandra Maksimowska
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct TutorPeopleView: View {
    @State private var pendingConnections: [Connection] = []
    @State private var activeStudents: [Student] = []
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    struct Connection: Identifiable {
        let id: String
        let parentId: String
        let studentId: String
        let studentName: String
        let schoolType: String
        let grade: Int
        let parentEmail: String
    }
    

    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Pending Connections Section
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Pending Invitations")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        if pendingConnections.isEmpty {
                            Text("No pending invitations")
                                .foregroundColor(.gray)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(10)
                        } else {
                            ForEach(pendingConnections) { connection in
                                ConnectionRequestCard(
                                    connection: connection,
                                    onAccept: { acceptConnection(connection) },
                                    onDecline: { declineConnection(connection) }
                                )
                            }
                        }
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(15)
                    .shadow(radius: 2)
                    
                    // Active Students Section
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Active Students")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        if activeStudents.isEmpty {
                            Text("No active students yet")
                                .foregroundColor(.gray)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(10)
                        } else {
                            ForEach(activeStudents) { student in
                                StudentCard(student: student)
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
            .alert(alertMessage, isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            }
            .onAppear {
                fetchPendingConnections()
                fetchActiveStudents()
            }
        }
    }
    
    private func fetchPendingConnections() {
        guard let tutorId = Auth.auth().currentUser?.uid else { return }
        print("Fetching pending connections for tutor: \(tutorId)")
        
        let db = Firestore.firestore()
        
        db.collection("tutor_student_connections")
            .whereField("tutor_id", isEqualTo: tutorId)
            .whereField("status", isEqualTo: "pending")
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error fetching connections: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("No documents found")
                    return
                }
                
                print("Found \(documents.count) pending connections")
                
                // Tworzymy Set do śledzenia już dodanych studentId
                var processedStudentIds = Set<String>()
                pendingConnections.removeAll()
                
                for document in documents {
                    let data = document.data()
                    let parentId = data["parent_id"] as? String ?? ""
                    let studentId = data["student_id"] as? String ?? ""
                    
                    // Sprawdzamy czy ten student już został przetworzony
                    if processedStudentIds.contains(studentId) {
                        continue // Pomijamy duplikat
                    }
                    
                    processedStudentIds.insert(studentId) // Dodajemy studentId do przetworzonych
                    
                    print("Processing connection - Parent: \(parentId), Student: \(studentId)")
                    
                    // Fetch student details
                    db.collection("students")
                        .document(studentId)
                        .getDocument { studentSnapshot, error in
                            if let error = error {
                                print("Error fetching student: \(error.localizedDescription)")
                                return
                            }
                            
                            guard let studentData = studentSnapshot?.data() else {
                                print("No student data found")
                                return
                            }
                            
                            // Fetch parent details
                            db.collection("users")
                                .document(parentId)
                                .getDocument { parentSnapshot, error in
                                    if let error = error {
                                        print("Error fetching parent: \(error.localizedDescription)")
                                        return
                                    }
                                    
                                    guard let parentData = parentSnapshot?.data() else {
                                        print("No parent data found")
                                        return
                                    }
                                    
                                    let connection = Connection(
                                        id: document.documentID,
                                        parentId: parentId,
                                        studentId: studentId,
                                        studentName: studentData["name"] as? String ?? "",
                                        schoolType: studentData["school_type"] as? String ?? "",
                                        grade: studentData["grade"] as? Int ?? 0,
                                        parentEmail: parentData["email"] as? String ?? ""
                                    )
                                    
                                    DispatchQueue.main.async {
                                        // Dodatkowe sprawdzenie przed dodaniem do tablicy
                                        if !pendingConnections.contains(where: { $0.studentId == studentId }) {
                                            pendingConnections.append(connection)
                                            print("Added connection for student: \(connection.studentName)")
                                        }
                                    }
                                }
                        }
                }
            }
    }
    
    private func fetchActiveStudents() {
        guard let tutorId = Auth.auth().currentUser?.uid else { return }
        
        let db = Firestore.firestore()
        db.collection("tutor_student_connections")
            .whereField("tutor_id", isEqualTo: tutorId)
            .whereField("status", isEqualTo: "active")
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error fetching active students: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("No active students found")
                    return
                }
                
                // Create a set to store unique student IDs
                var processedStudentIds = Set<String>()
                activeStudents.removeAll()
                
                for document in documents {
                    let data = document.data()
                    let studentId = data["student_id"] as? String ?? ""
                    let parentId = data["parent_id"] as? String ?? ""
                    
                    // Skip if we've already processed this student
                    if processedStudentIds.contains(studentId) {
                        continue
                    }
                    processedStudentIds.insert(studentId)
                    
                    // Fetch student details
                    db.collection("students")
                        .document(studentId)
                        .getDocument { studentSnapshot, error in
                            if let error = error {
                                print("Error fetching student details: \(error.localizedDescription)")
                                return
                            }
                            
                            guard let studentData = studentSnapshot?.data() else {
                                print("No student data found")
                                return
                            }
                            
                            // Fetch parent details
                            db.collection("users")
                                .document(parentId)
                                .getDocument { parentSnapshot, error in
                                    if let error = error {
                                        print("Error fetching parent details: \(error.localizedDescription)")
                                        return
                                    }
                                    
                                    guard let parentData = parentSnapshot?.data() else {
                                        print("No parent data found")
                                        return
                                    }
                                    
                                    let student = Student(
                                        id: studentId,
                                        name: studentData["name"] as? String ?? "",
                                        schoolType: studentData["school_type"] as? String ?? "",
                                        grade: studentData["grade"] as? Int ?? 0,
                                        parentEmail: parentData["email"] as? String ?? ""
                                    )
                                    
                                    DispatchQueue.main.async {
                                        // Only add if not already in the list
                                        if !activeStudents.contains(where: { $0.id == student.id }) {
                                            activeStudents.append(student)
                                            print("Added active student: \(student.name)")
                                        }
                                    }
                                }
                        }
                }
            }
    }
    
    private func acceptConnection(_ connection: Connection) {
        let db = Firestore.firestore()
        db.collection("tutor_student_connections").document(connection.id).updateData([
            "status": "active",
            "updated_at": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                alertMessage = "Error accepting connection: \(error.localizedDescription)"
                showAlert = true
                return
            }
            
            // Create notification for parent
            let notificationData: [String: Any] = [
                "user_id": connection.parentId,
                "title": "Connection Accepted",
                "content": "Tutor has accepted your connection request",
                "type": "connection_accepted",
                "is_read": false,
                "created_at": FieldValue.serverTimestamp()
            ]
            
            db.collection("notifications").addDocument(data: notificationData)
        }
    }
    
    private func declineConnection(_ connection: Connection) {
        let db = Firestore.firestore()
        db.collection("tutor_student_connections").document(connection.id).delete { error in
            if let error = error {
                alertMessage = "Error declining connection: \(error.localizedDescription)"
                showAlert = true
                return
            }
            
            // Create notification for parent
            let notificationData: [String: Any] = [
                "user_id": connection.parentId,
                "title": "Connection Declined",
                "content": "Tutor has declined your connection request",
                "type": "connection_declined",
                "is_read": false,
                "created_at": FieldValue.serverTimestamp()
            ]
            
            db.collection("notifications").addDocument(data: notificationData)
        }
    }
}

struct ConnectionRequestCard: View {
    let connection: TutorPeopleView.Connection
    let onAccept: () -> Void
    let onDecline: () -> Void
    
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(connection.studentName)
                        .font(.headline)
                    Text("\(connection.schoolType) - Grade \(connection.grade)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Text("Parent: \(connection.parentEmail)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer()
            }
            
            HStack {
                Button(action: onDecline) {
                    Text("Decline")
                        .foregroundColor(.red)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
                
                Button(action: onAccept) {
                    Text("Accept")
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color(hexString: "0D085B"))
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}

struct StudentCard: View {
    let student: Student
    @State private var parentEmails: [String] = []
    
    var body: some View {
        NavigationLink(destination: StudentDetailView(student: student)) {
            VStack(alignment: .leading, spacing: 5) {
                Text(student.name)
                    .font(.headline)
                
                Text("\(student.schoolType) - Grade \(student.grade)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Parents:")
                        .font(.caption)
                        .foregroundColor(.gray)
                    ForEach(parentEmails, id: \.self) { email in
                        Text(email)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
            .onAppear {
                fetchParentEmails(for: student.id)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
    
    private func fetchParentEmails(for studentId: String) {
        let db = Firestore.firestore()
        db.collection("family_connections")
            .whereField("student_id", isEqualTo: studentId)
            .getDocuments { snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                let parentIds = documents.compactMap { doc -> String? in
                    doc.data()["guardian_id"] as? String
                }
                
                for parentId in parentIds {
                    db.collection("users").document(parentId).getDocument { document, error in
                        if let email = document?.data()?["email"] as? String {
                            DispatchQueue.main.async {
                                parentEmails.append(email)
                            }
                        }
                    }
                }
            }
    }
}

#Preview {
    TutorPeopleView()
}
