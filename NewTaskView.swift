//
//  NewTaskView.swift
//  HolisticTaskManager
//
//  Created by Aleksandra Maksimowska
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct NewTaskView: View {
    @Environment(\.dismiss) var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var additionalInfo = ""
    @State private var dueDate = Date()
    @State private var selectedStudentIds = Set<String>()
    @State private var students: [Student] = []
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    private let minimumDate = Date()
    private let db = Firestore.firestore()
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Task Details")) {
                    TextField("Title", text: $title)
                    
                    TextField("Description", text: $description)
                    
                    TextField("Additional Info (e.g. links)", text: $additionalInfo)
                    
                    DatePicker("Due Date",
                              selection: $dueDate,
                              in: minimumDate...,
                              displayedComponents: [.date, .hourAndMinute])
                }
                
                Section(header: Text("Assign Students")) {
                    if students.isEmpty {
                        Text("No active students")
                            .foregroundColor(.gray)
                    } else {
                        ForEach(students) { student in
                            StudentSelectionRow(
                                student: student,
                                isSelected: selectedStudentIds.contains(student.id),
                                onToggle: { selected in
                                    if selected {
                                        selectedStudentIds.insert(student.id)
                                    } else {
                                        selectedStudentIds.remove(student.id)
                                    }
                                }
                            )
                        }
                    }
                }
            }
            .navigationTitle("New Task")
            .navigationBarItems(
                leading: Button("Cancel") {
                    dismiss()
                },
                trailing: Button("Create") {
                    createTask()
                }
                .disabled(isFormInvalid)
            )
            .alert(alertMessage, isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            }
            .onAppear {
                fetchStudents()
            }
        }
    }
    
    private var isFormInvalid: Bool {
        title.isEmpty || description.isEmpty || selectedStudentIds.isEmpty
    }
    
    private func fetchStudents() {
        guard let tutorId = Auth.auth().currentUser?.uid else { return }
        
        db.collection("tutor_student_connections")
            .whereField("tutor_id", isEqualTo: tutorId)
            .whereField("status", isEqualTo: "active")
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else {
                    print("Error fetching students: \(error?.localizedDescription ?? "unknown error")")
                    return
                }
                
                let studentIds = documents.compactMap { $0.data()["student_id"] as? String }
                
                for studentId in studentIds {
                    db.collection("students")
                        .document(studentId)
                        .getDocument { document, error in
                            if let error = error {
                                print("Error fetching student details: \(error.localizedDescription)")
                                return
                            }
                            
                            guard let data = document?.data() else { return }
                            
                            let student = Student(
                                id: studentId,
                                name: data["name"] as? String ?? "",
                                schoolType: data["school_type"] as? String ?? "",
                                grade: data["grade"] as? Int ?? 0,
                                parentEmail: "" // Not needed for this view
                            )
                            
                            DispatchQueue.main.async {
                                if !self.students.contains(where: { $0.id == student.id }) {
                                    self.students.append(student)
                                }
                            }
                        }
                }
            }
    }
    
    private func createTask() {
        guard let tutorId = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        
        let taskData: [String: Any] = [
            "tutor_id": tutorId,
            "student_ids": Array(selectedStudentIds),
            "title": title,
            "description": description,
            "additional_info": additionalInfo,
            "due_date": Timestamp(date: dueDate),
            "status": "pending",
            "is_archived": false,
            "created_at": FieldValue.serverTimestamp()
        ]
        
        db.collection("tasks").addDocument(data: taskData) { error in
            isLoading = false
            
            if let error = error {
                alertMessage = "Error creating task: \(error.localizedDescription)"
                showAlert = true
                return
            }
            
            // Create notifications for students
            let batch = db.batch()
            
            for studentId in selectedStudentIds {
                let notificationRef = db.collection("notifications").document()
                let notificationData: [String: Any] = [
                    "user_id": studentId,
                    "type": "new_task",
                    "title": "New Task Assigned",
                    "content": "You have been assigned a new task: \(title)",
                    "is_read": false,
                    "created_at": FieldValue.serverTimestamp()
                ]
                
                batch.setData(notificationData, forDocument: notificationRef)
            }
            
            batch.commit { error in
                if let error = error {
                    print("Error creating notifications: \(error.localizedDescription)")
                }
                
                dismiss()
            }
        }
    }
}

struct StudentSelectionRow: View {
    let student: Student
    let isSelected: Bool
    let onToggle: (Bool) -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(student.name)
                    .font(.headline)
                Text("\(student.schoolType) - Grade \(student.grade)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color(hexString: "0D085B"))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle(!isSelected)
        }
    }
}

#Preview {
    NewTaskView()
}
