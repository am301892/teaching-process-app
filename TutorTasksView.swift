//
//  TutorTasksView.swift
//  HolisticTaskManager
//
//  Created by Aleksandra Maksimowska
//
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct TutorTasksView: View {
    @StateObject private var viewModel = TutorTasksViewModel()
    @State private var showNewTask = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                Picker("Task Filter", selection: $viewModel.selectedView) {
                    Text("Pending").tag("pending")
                    Text("Completed").tag("completed")
                    Text("Archived").tag("archived")
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                if viewModel.isLoading {
                    ProgressView()
                        .padding()
                } else if viewModel.filteredTasks.isEmpty {
                    Text(viewModel.emptyStateMessage)
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.filteredTasks) { task in
                            TaskRow(viewModel: viewModel, task: task)
                                .padding(.horizontal)
                        }
                    }
                }
            }
            .navigationTitle("Tasks")
            .toolbar {
                Button(action: { showNewTask = true }) {
                    Image(systemName: "plus")
                }
            }
            .sheet(isPresented: $showNewTask) {
                NewTaskView()
            }
            .onAppear {
                viewModel.startListening()
            }
            .onDisappear {
                viewModel.stopListening()
            }
        }
    }
}

class TutorTasksViewModel: ObservableObject {
    @Published var tasks: [Task] = []
    @Published var selectedView = "pending"
    @Published var isLoading = false
    
    private var listeners: [ListenerRegistration] = []
    private let db = Firestore.firestore()
    
    var filteredTasks: [Task] {
        switch selectedView {
        case "pending":
            return tasks.filter { !$0.isArchived && !$0.isCompleted }
        case "completed":
            return tasks.filter { !$0.isArchived && $0.isCompleted }
        case "archived":
            return tasks.filter { $0.isArchived }
        default:
            return []
        }
    }
    
    var emptyStateMessage: String {
        switch selectedView {
        case "pending":
            return "No pending tasks"
        case "completed":
            return "No completed tasks"
        case "archived":
            return "No archived tasks"
        default:
            return "No tasks found"
        }
    }
    
    func startListening() {
        guard let tutorId = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        
        // Clear existing listeners
        stopListening()
        
        // Listen for tasks
        let tasksListener = db.collection("tasks")
            .whereField("tutor_id", isEqualTo: tutorId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self, let documents = snapshot?.documents else {
                    self?.isLoading = false
                    return
                }
                
                var updatedTasks: [Task] = []
                
                for document in documents {
                    let data = document.data()
                    let task = Task(
                        id: document.documentID,
                        title: data["title"] as? String ?? "",
                        description: data["description"] as? String ?? "",
                        additionalInfo: data["additional_info"] as? String ?? "",
                        dueDate: (data["due_date"] as? Timestamp)?.dateValue() ?? Date(),
                        isArchived: data["is_archived"] as? Bool ?? false,
                        studentIds: data["student_ids"] as? [String] ?? [],
                        createdAt: (data["created_at"] as? Timestamp)?.dateValue() ?? Date()
                    )
                    updatedTasks.append(task)
                    self.setupCompletionListener(for: task)
                }
                
                DispatchQueue.main.async {
                    self.tasks = updatedTasks.sorted { $0.dueDate < $1.dueDate }
                    self.isLoading = false
                }
            }
        
        listeners.append(tasksListener)
    }
    
    private func setupCompletionListener(for task: Task) {
        for studentId in task.studentIds {
            let listener = db.collection("task_completions")
                .whereField("task_id", isEqualTo: task.id)
                .whereField("student_id", isEqualTo: studentId)
                .addSnapshotListener { [weak self, weak task] snapshot, error in
                    guard let task = task else { return }
                    
                    if let document = snapshot?.documents.first {
                        let status = document.data()["status"] as? String ?? "pending"
                        DispatchQueue.main.async {
                            task.updateStudentStatus(studentId: studentId, status: status)
                            // Trigger view update
                            self?.objectWillChange.send()
                        }
                    }
                }
            listeners.append(listener)
        }
    }
    
    func stopListening() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }
    
    func archiveTask(_ task: Task) {
        db.collection("tasks").document(task.id).updateData([
            "is_archived": true
        ])
    }
}

class Task: Identifiable, ObservableObject {
    let id: String
    let title: String
    let description: String
    let additionalInfo: String
    let dueDate: Date
    let isArchived: Bool
    let studentIds: [String]
    let createdAt: Date
    
    @Published private var studentStatuses: [String: String] = [:]
    
    var isCompleted: Bool {
        !studentIds.isEmpty && studentIds.allSatisfy { studentStatuses[$0] == "completed" }
    }
    
    init(id: String, title: String, description: String, additionalInfo: String,
         dueDate: Date, isArchived: Bool, studentIds: [String], createdAt: Date) {
        self.id = id
        self.title = title
        self.description = description
        self.additionalInfo = additionalInfo
        self.dueDate = dueDate
        self.isArchived = isArchived
        self.studentIds = studentIds
        self.createdAt = createdAt
    }
    
    func updateStudentStatus(studentId: String, status: String) {
        studentStatuses[studentId] = status
    }
    
    func getStudentStatus(_ studentId: String) -> String {
        return studentStatuses[studentId] ?? "pending"
    }
}

struct TaskRow: View {
    @ObservedObject var viewModel: TutorTasksViewModel
    @ObservedObject var task: Task
    @State private var showDetails = false
    
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
                
                if !task.isArchived {
                    Button(action: { viewModel.archiveTask(task) }) {
                        Image(systemName: "archivebox")
                            .foregroundColor(.gray)
                    }
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
                
                ForEach(task.studentIds, id: \.self) { studentId in
                    StudentProgressRow(
                        studentId: studentId,
                        status: task.getStudentStatus(studentId)
                    )
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showDetails.toggle()
        }
    }
}

struct StudentProgressRow: View {
    let studentId: String
    let status: String
    @State private var studentName = ""
    private let db = Firestore.firestore()
    
    var body: some View {
        HStack {
            Text(studentName.isEmpty ? "Loading..." : studentName)
                .font(.subheadline)
            
            Spacer()
            
            Text(status.capitalized)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.2))
                .foregroundColor(statusColor)
                .cornerRadius(4)
        }
        .onAppear {
            fetchStudentName()
        }
    }
    
    private var statusColor: Color {
        switch status {
        case "completed":
            return .green
        case "pending":
            return .orange
        default:
            return .gray
        }
    }
    
    private func fetchStudentName() {
        db.collection("students")
            .document(studentId)
            .getDocument { document, error in
                if let data = document?.data() {
                    DispatchQueue.main.async {
                        studentName = data["name"] as? String ?? "Unknown"
                    }
                }
            }
    }
}

#Preview {
    TutorTasksView()
}
