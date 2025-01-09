//
//  StudentDetailView.swift
//  HolisticTaskManager
//
//  Created by Aleksandra Maksimowska
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct StudentDetailView: View {
    let student: Student
    @StateObject private var reportViewModel = ReportViewModel()
    @State private var showNewReportSheet = false
    @State private var isLoading = false
    
    var body: some View {
        ZStack { // ZStack fior loader
            ScrollView {
                VStack(spacing: 20) {
                    // Student Info Card
                    VStack(alignment: .leading, spacing: 10) {
                        Text(student.name)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("\(student.schoolType) - Grade \(student.grade)")
                            .foregroundColor(.gray)
                        
                        Text("Parent: \(student.parentEmail)")
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                    
                    // Reports Section
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Text("Progress Reports")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Spacer()
                            
                            Button(action: {
                                showNewReportSheet = true
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(Color(hexString: "0D085B"))
                                    .font(.title2)
                            }
                        }
                        
                        if reportViewModel.reports.isEmpty {
                            Text("No reports yet")
                                .foregroundColor(.gray)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(10)
                        } else {
                            ForEach(reportViewModel.reports) { report in
                                ReportCard(report: report)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Student Details")
            .sheet(isPresented: $showNewReportSheet) {
                NewReportView(
                    student: student,
                    isPresented: $showNewReportSheet,
                    onReportCreated: { // add callback
                        isLoading = true // show loader
                        // moemnt for saving report
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            reportViewModel.startListening(for: student.id)
                            isLoading = false // hide loader
                        }
                    }
                )
            }
            .onAppear {
                isLoading = true
                reportViewModel.startListening(for: student.id)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    isLoading = false
                }
            }
            .onDisappear {
                reportViewModel.stopListening()
            }
            
            // Loader
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
    
//    private func fetchReports() {
//        guard let tutorId = Auth.auth().currentUser?.uid else { return }
//        
//        let db = Firestore.firestore()
//        db.collection("progress_reports")
//            .whereField("tutor_id", isEqualTo: tutorId)
//            .whereField("student_id", isEqualTo: student.id)
//            .order(by: "created_at", descending: true)
//            .addSnapshotListener { snapshot, error in
//                guard let documents = snapshot?.documents else { return }
//                
//                reports = documents.compactMap { document -> Report? in
//                    let data = document.data()
//                    
//                    return Report(
//                        id: document.documentID,
//                        tutorId: data["tutor_id"] as? String ?? "",
//                        studentId: data["student_id"] as? String ?? "",
//                        date: (data["date"] as? Timestamp)?.dateValue() ?? Date(),
//                        duration: data["duration"] as? Int ?? 0,
//                        topic: data["topic"] as? String ?? "",
//                        preparation: data["preparation"] as? Int ?? 0,
//                        engagement: data["engagement"] as? Int ?? 0,
//                        recommendations: data["recommendations"] as? String ?? "",
//                        createdAt: (data["created_at"] as? Timestamp)?.dateValue() ?? Date()
//                    )
//                }
//            }
//    }

struct ReportCard: View {
    let report: Report
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(report.date.formatted(date: .numeric, time: .omitted))
                    .font(.headline)
                
                Spacer()
                
                Text("\(report.duration) min")
                    .foregroundColor(.gray)
            }
            
            Text(report.topic)
                .font(.subheadline)
            
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Preparation")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("\(report.preparation)/5")
                }
                
                VStack(alignment: .leading) {
                    Text("Engagement")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("\(report.engagement)/5")
                }
            }
            
            if !report.recommendations.isEmpty {
                Text("Recommendations:")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text(report.recommendations)
                    .font(.subheadline)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}



