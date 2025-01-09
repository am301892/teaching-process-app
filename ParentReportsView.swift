//
//  ParentReportsView.swift
//  HolisticTaskManager
//
//  Created by Aleksandra Maksimowska
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// Main view for displaying progress reports to parents
// Organizes reports by student and displays them in collapsible sections
struct ParentReportsView: View {
    @StateObject private var viewModel = ParentReportsViewModel()
    
    var body: some View {
        NavigationView {
            ScrollView {
                // Show placeholder when no reports are available
                if viewModel.studentReports.isEmpty {
                    VStack(spacing: 20) {
                        Text("No reports available")
                            .foregroundColor(.gray)
                            .padding()
                    }
                } else {
                    // Display reports grouped by student name
                    LazyVStack(spacing: 20) {
                        ForEach(viewModel.studentReports.keys.sorted(), id: \.self) { studentName in
                            if let reports = viewModel.studentReports[studentName] {
                                StudentReportsSection(studentName: studentName, reports: reports)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Progress Reports")
            .onAppear {
                viewModel.fetchReports()
            }
            .onDisappear {
                // Clean up Firebase listeners when view disappears
                viewModel.stopListening()
            }
        }
    }
}

// Section view for displaying all reports for a single student
// Includes student name header and list of report cards
struct StudentReportsSection: View {
    let studentName: String
    let reports: [Report]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(studentName)
                .font(.title2)
                .fontWeight(.bold)
            
            ForEach(reports) { report in
                ReportCard(report: report)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}

// ViewModel responsible for managing progress report data
// Handles Firebase data fetching and real-time updates
class ParentReportsViewModel: ObservableObject {
    // Dictionary mapping student names to their respective reports
    @Published var studentReports: [String: [Report]] = [:]
    
    // Store Firebase listeners to properly clean them up later
    private var listeners: [String: ListenerRegistration] = [:]
    
    // Fetches reports for all children connected to the parent
    // This includes both direct family connections and tutor-student connections
    func fetchReports() {
        guard let parentId = Auth.auth().currentUser?.uid else { return }
        
        print("Starting fetch for parent: \(parentId)")
        let db = Firestore.firestore()
        
        // Step 1: Fetch family connections to get directly connected children
        db.collection("family_connections")
            .whereField("guardian_id", isEqualTo: parentId)
            .whereField("status", isEqualTo: "active")
            .getDocuments { [weak self] snapshot, error in
                print("=== DEBUGGING FAMILY CONNECTIONS ===")
                
                if let error = error {
                    print("Error fetching family connections: \(error)")
                    return
                }
                
                guard let familyDocs = snapshot?.documents else {
                    print("No family connections found")
                    return
                }
                
                // Step 2: Also fetch tutor connections to get children connected through tutors
                db.collection("tutor_student_connections")
                    .whereField("parent_id", isEqualTo: parentId)
                    .whereField("status", isEqualTo: "active")
                    .getDocuments { tutorSnapshot, tutorError in
                        print("=== DEBUGGING TUTOR CONNECTIONS ===")
                        
                        // Create a set to store unique student IDs
                        var studentIds = Set<String>()
                        
                        // Collect student IDs from family connections
                        familyDocs.forEach { doc in
                            if let studentId = doc.data()["student_id"] as? String {
                                studentIds.insert(studentId)
                                print("Added student ID from family: \(studentId)")
                            }
                        }
                        
                        // Collect student IDs from tutor connections
                        tutorSnapshot?.documents.forEach { doc in
                            if let studentId = doc.data()["student_id"] as? String {
                                studentIds.insert(studentId)
                                print("Added student ID from tutor: \(studentId)")
                            }
                        }
                        
                        print("Total unique student IDs: \(studentIds.count)")
                        
                        // Clean up any existing listeners before setting up new ones
                        self?.listeners.values.forEach { $0.remove() }
                        self?.listeners.removeAll()
                        
                        // Step 3: Set up real-time listeners for each student's reports
                        for studentId in studentIds {
                            print("Processing student ID: \(studentId)")
                            
                            // Create a listener for progress reports collection
                            let listener = db.collection("progress_reports")
                                .whereField("student_id", isEqualTo: studentId)
                                .order(by: "created_at", descending: true)
                                .addSnapshotListener { reportSnapshot, reportError in
                                    if let reportError = reportError {
                                        print("Error fetching reports for \(studentId): \(reportError)")
                                        return
                                    }
                                    
                                    guard let reportDocs = reportSnapshot?.documents else { return }
                                    print("Found \(reportDocs.count) reports for student \(studentId)")
                                    
                                    if !reportDocs.isEmpty {
                                        // Fetch student name to use as key in studentReports dictionary
                                        db.collection("students")
                                            .document(studentId)
                                            .getDocument { studentSnapshot, studentError in
                                                let studentName = studentSnapshot?.data()?["name"] as? String ?? "Unknown Student"
                                                
                                                // Convert Firestore documents to Report objects
                                                let reports = reportDocs.compactMap { document -> Report? in
                                                    let data = document.data()
                                                    return Report(
                                                        id: document.documentID,
                                                        tutorId: data["tutor_id"] as? String ?? "",
                                                        studentId: data["student_id"] as? String ?? "",
                                                        date: (data["date"] as? Timestamp)?.dateValue() ?? Date(),
                                                        duration: data["duration"] as? Int ?? 0,
                                                        topic: data["topic"] as? String ?? "",
                                                        preparation: data["preparation"] as? Int ?? 0,
                                                        engagement: data["engagement"] as? Int ?? 0,
                                                        recommendations: data["recommendations"] as? String ?? "",
                                                        createdAt: (data["created_at"] as? Timestamp)?.dateValue() ?? Date()
                                                    )
                                                }
                                                
                                                // Update UI on main thread
                                                DispatchQueue.main.async {
                                                    self?.studentReports[studentName] = reports
                                                }
                                            }
                                    }
                                }
                            
                            // Store listener for cleanup
                            self?.listeners[studentId] = listener
                        }
                    }
            }
    }
    
    // Removes all Firebase listeners to prevent memory leaks
    // Called when view disappears or when we need to reset listeners
    func stopListening() {
        listeners.values.forEach { $0.remove() }
        listeners.removeAll()
    }
}
