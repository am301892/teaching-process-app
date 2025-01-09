//
//  StudentTasksView.swift
//  HolisticTaskManager
//
//  Created by Aleksandra Maksimowska
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct StudentTasksView: View {
    @State private var tasks: [TaskWithCompletion] = []
    @State private var showCompleted = false
    @State private var isLoading = false
    @State private var listeners: [ListenerRegistration] = []
    
    private let db = Firestore.firestore()
    
    var filteredTasks: [TaskWithCompletion] {
        tasks.filter { $0.status == (showCompleted ? "completed" : "pending") }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("Task Filter", selection: $showCompleted) {
                    Text("To Do").tag(false)
                    Text("Completed").tag(true)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                ScrollView {
                    if isLoading {
                        ProgressView()
                            .padding()
                    } else if filteredTasks.isEmpty {
                        Text(showCompleted ? "No completed tasks" : "No tasks to do")
                            .foregroundColor(.gray)
                            .padding()
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredTasks) { task in
                                StudentTaskRow(task: task, onComplete: { completeTask(task) })
                                    .padding(.horizontal)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tasks")
            .onAppear {
                setupListeners()
            }
            .onDisappear {
                // Cleanup listeners
                listeners.forEach { $0.remove() }
                listeners.removeAll()
            }
        }
    }
    
    private func setupListeners() {
        guard let studentId = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        
        // Listen for tasks
        let tasksListener = db.collection("tasks")
            .whereField("student_ids", arrayContains: studentId)
            .whereField("is_archived", isEqualTo: false)  // Tylko niezarchiwizowane
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else {
                    print("Error fetching tasks: \(error?.localizedDescription ?? "unknown error")")
                    return
                }
                
                var newTasks: [String: TaskWithCompletion] = [:]
                
                for document in documents {
                    let data = document.data()
                    let taskId = document.documentID
                    
                    // Listen for task completion status
                    let completionListener = db.collection("task_completions")
                        .whereField("task_id", isEqualTo: taskId)
                        .whereField("student_id", isEqualTo: studentId)
                        .addSnapshotListener { completionSnapshot, completionError in
                            let isCompleted = !(completionSnapshot?.documents.isEmpty ?? true)
                            let completedAt = completionSnapshot?.documents.first?.data()["completed_at"] as? Timestamp
                            
                            let task = TaskWithCompletion(
                                id: taskId,
                                title: data["title"] as? String ?? "",
                                description: data["description"] as? String ?? "",
                                additionalInfo: data["additional_info"] as? String ?? "",
                                dueDate: (data["due_date"] as? Timestamp)?.dateValue() ?? Date(),
                                status: isCompleted ? "completed" : "pending",
                                completedAt: completedAt?.dateValue(),
                                createdAt: (data["created_at"] as? Timestamp)?.dateValue() ?? Date()
                            )
                            
                            newTasks[taskId] = task
                            
                            DispatchQueue.main.async {
                                self.tasks = Array(newTasks.values)
                                    .sorted { $0.dueDate < $1.dueDate }
                                isLoading = false
                            }
                        }
                    
                    self.listeners.append(completionListener)
                }
            }
        
        listeners.append(tasksListener)
    }
    
    private func completeTask(_ task: TaskWithCompletion) {
        guard let studentId = Auth.auth().currentUser?.uid else { return }
        
        let completionData: [String: Any] = [
            "task_id": task.id,
            "student_id": studentId,
            "status": "completed",
            "completed_at": FieldValue.serverTimestamp(),
            "created_at": FieldValue.serverTimestamp()
        ]
        
        db.collection("task_completions").addDocument(data: completionData) { error in
            if let error = error {
                print("Error completing task: \(error.localizedDescription)")
            }
        }
    }
}


struct StudentTaskRow: View {
    let task: TaskWithCompletion
    let onComplete: () -> Void
    @State private var showDetails = false
    @State private var showCompleteAlert = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(task.title)
                        .font(.headline)
                    Text(task.dueDate.formatted(date: .numeric, time: .shortened))
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                if task.status == "pending" {
                    Button(action: { showCompleteAlert = true }) {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.green)
                    }
                    .alert("Complete Task", isPresented: $showCompleteAlert) {
                        Button("Cancel", role: .cancel) { }
                        Button("Complete", role: .none) {
                            onComplete()
                        }
                    } message: {
                        Text("Mark this task as completed?")
                    }
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            
            if showDetails {
                Text(task.description)
                    .font(.body)
                    .padding(.vertical, 4)
                
                if !task.additionalInfo.isEmpty {
                    Text(task.additionalInfo)
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                
                if let completedAt = task.completedAt {
                    Text("Completed: \(completedAt.formatted(date: .numeric, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showDetails.toggle()
        }
    }
}

struct TaskWithCompletion: Identifiable {
    let id: String
    let title: String
    let description: String
    let additionalInfo: String
    let dueDate: Date
    let status: String
    let completedAt: Date?
    let createdAt: Date
}

#Preview{
    StudentTasksView()
}
