//
//  NewReportView.swift
//  HolisticTaskManager
//
//  Created by Aleksandra Maksimowska
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct NewReportView: View {
    let student: Student
    @Binding var isPresented: Bool
    var onReportCreated: (() -> Void)? // callback
    
    @State private var date = Date()
    @State private var duration = 60
    @State private var topic = ""
    @State private var preparation = 3
    @State private var engagement = 3
    @State private var recommendations = ""
    @State private var isLoading = false
    
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    private let durations = [45, 60, 90, 120]
    private let darkColor = Color(hexString: "0D085B")
    
    var body: some View {
        NavigationView {
            ZStack { //for loader to show up properly
                Form {
                    Section(header: Text("Lesson Details")) {
                        DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: [.date])
                        
                        Picker("Duration", selection: $duration) {
                            ForEach(durations, id: \.self) { mins in
                                Text("\(mins) min").tag(mins)
                            }
                        }
                        
                        TextField("Topic/Section", text: $topic)
                    }
                    
                    Section(header: Text("Student Assessment")) {
                        RatingSliderView(
                            title: "Preparation",
                            value: $preparation,
                            color: darkColor
                        )
                        .padding(.vertical, 8)
                        
                        RatingSliderView(
                            title: "Engagement",
                            value: $engagement,
                            color: darkColor
                        )
                        .padding(.vertical, 8)
                    }
                    
                    Section(header: Text("Additional Information")) {
                        TextEditor(text: $recommendations)
                            .frame(height: 100)
                    }
                }
                .navigationTitle("New Report")
                .navigationBarItems(
                    leading: Button("Cancel") {
                        isPresented = false
                    },
                    trailing: Button("Save") {
                        saveReport()
                    }
                    .disabled(topic.isEmpty || isLoading)
                )
                .alert(alertMessage, isPresented: $showAlert) {
                    Button("OK", role: .cancel) {}
                }
                
                // Loader
                if isLoading {
                    Color.black.opacity(0.2)
                        .edgesIgnoringSafeArea(.all)
                    
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: darkColor))
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
    
    private func saveReport() {
        guard let tutorId = Auth.auth().currentUser?.uid else { return }
        isLoading = true // showing loader
        
        let db = Firestore.firestore()
        
        let reportData: [String: Any] = [
            "tutor_id": tutorId,
            "student_id": student.id,
            "date": Timestamp(date: date),
            "duration": duration,
            "topic": topic,
            "preparation": preparation,
            "engagement": engagement,
            "recommendations": recommendations,
            "created_at": FieldValue.serverTimestamp()
        ]
        
        db.collection("progress_reports").addDocument(data: reportData) { error in
            if let error = error {
                isLoading = false
                alertMessage = "Error saving report: \(error.localizedDescription)"
                showAlert = true
                return
            }
            
            // Create notification for parent
            let notificationData: [String: Any] = [
                "user_id": student.parentEmail,
                "title": "New Progress Report",
                "content": "A new progress report has been added for \(student.name)",
                "type": "new_report",
                "is_read": false,
                "created_at": FieldValue.serverTimestamp()
            ]
            
            db.collection("notifications").addDocument(data: notificationData) { error in
                DispatchQueue.main.async {
                    isLoading = false
                    if let error = error {
                        alertMessage = "Error creating notification: \(error.localizedDescription)"
                        showAlert = true
                        return
                    }
                    
                    onReportCreated?() // Wywołanie callback'a po utworzeniu raportu
                    isPresented = false
                }
            }
        }
    }
}
