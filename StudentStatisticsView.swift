//
//  StudentStatisticsView.swift
//  HolisticTaskManager
//
//  Created by Aleksandra Maksimowska
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Charts

struct StudentStatisticsView: View {
    @State private var statistics = Statistics(
        totalTasks: 0,
        completedTasks: 0,
        completionRate: 0,
        nextDeadline: nil,
        monthlyData: []
    )
    @State private var isLoading = true
    
    private let db = Firestore.firestore()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                gridView
                chartView
            }
        }
        .navigationTitle("Statistics")
        .onAppear {
            setupListeners()
        }
        .onDisappear {
            listeners.forEach { $0.remove() }
            listeners.removeAll()
        }
    }
    
    var gridView: some View {
        VStack(spacing: 16) {
            // Next Deadline Card - full width
            StatCard(
                title: "Next Deadline",
                value: statistics.nextDeadline?.formatted(date: .numeric, time: .shortened) ?? "No tasks to do",
                color: Color(hexString: "0D085B").opacity(0.1)
            )
            
            // Stats Grid - two columns
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                StatCard(
                    title: "Total Tasks",
                    value: "\(statistics.totalTasks)",
                    color: Color(hexString: "0D085B").opacity(0.1)
                )
                StatCard(
                    title: "Completed",
                    value: "\(statistics.completedTasks)",
                    color: Color(hexString: "0D085B").opacity(0.1)
                )
            }
        }
        .padding()
    }
    
    var chartView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weekly Activity")
                .font(.headline)
                .padding(.horizontal)
            
            if statistics.monthlyData.isEmpty {
                Text("No data available")
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
            } else {
                Chart {
                    ForEach(statistics.monthlyData) { data in
                        BarMark(
                            x: .value("Day", data.dayName),
                            y: .value("Tasks", data.tasks)
                        )
                        .foregroundStyle(Color(hexString: "0D085B"))
                    }
                }
                .chartXAxis {
                    AxisMarks(position: .bottom) { _ in
                        AxisValueLabel()
                            .font(.caption)
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel()
                            .font(.caption)
                    }
                }
                .frame(height: 200)
                .padding()
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(10)
        .shadow(radius: 1)
    }
    
    @State private var listeners: [ListenerRegistration] = []
    
    private func setupListeners() {
        guard let studentId = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        
        // Nasłuchuj zmian w task_completions
        let completionsListener = db.collection("task_completions")
            .whereField("student_id", isEqualTo: studentId)
            .addSnapshotListener { completionSnapshot, error in
                let completedTaskIds = Set(completionSnapshot?.documents.map { $0.data()["task_id"] as? String ?? "" } ?? [])
                let completionsData = completionSnapshot?.documents.reduce(into: [String: Date]()) { dict, doc in
                    let taskId = doc.data()["task_id"] as? String ?? ""
                    let completedAt = (doc.data()["completed_at"] as? Timestamp)?.dateValue()
                    if let completedAt = completedAt {
                        dict[taskId] = completedAt
                    }
                } ?? [:]
                
                // Nasłuchuj zmian w tasks
                let tasksListener = db.collection("tasks")
                    .whereField("student_ids", arrayContains: studentId)
                    .addSnapshotListener { snapshot, error in
                        guard let documents = snapshot?.documents else {
                            isLoading = false
                            return
                        }
                        
                        let allTasks = documents.map { doc -> TaskData in
                            let data = doc.data()
                            let isCompleted = completedTaskIds.contains(doc.documentID)
                            
                            return TaskData(
                                id: doc.documentID,
                                dueDate: (data["due_date"] as? Timestamp)?.dateValue() ?? Date(),
                                isCompleted: isCompleted,
                                isArchived: data["is_archived"] as? Bool ?? false,
                                completedAt: completionsData[doc.documentID]
                            )
                        }
                        
                        // Filtruj aktywne (nie zarchiwizowane) zadania
                        let activeTasks = allTasks.filter { !$0.isArchived }
                        
                        let total = activeTasks.count
                        let completed = activeTasks.filter { $0.isCompleted }.count
                        
                        let nextDeadline = activeTasks
                            .filter { !$0.isCompleted && $0.dueDate > Date() }
                            .sorted { $0.dueDate < $1.dueDate }
                            .first?.dueDate
                        
                        // Dane tygodniowe
                        let calendar = Calendar.current
                        let now = Date()
                        let weekAgo = calendar.date(byAdding: .day, value: -6, to: now)!
                        
                        var dailyTasks: [DailyData] = []
                        
                        for dayOffset in 0...6 {
                            let date = calendar.date(byAdding: .day, value: dayOffset, to: weekAgo)!
                            
                            // Licz zadania ukończone w danym dniu
                            let completedTasksForDay = activeTasks.filter {
                                $0.isCompleted &&
                                $0.completedAt != nil &&
                                calendar.isDate($0.completedAt!, inSameDayAs: date)
                            }.count
                            
                            dailyTasks.append(DailyData(date: date, tasks: completedTasksForDay))
                        }
                        
                        DispatchQueue.main.async {
                            self.statistics = Statistics(
                                totalTasks: total,
                                completedTasks: completed,
                                completionRate: total > 0 ? (completed * 100) / total : 0,
                                nextDeadline: nextDeadline,
                                monthlyData: dailyTasks
                            )
                            isLoading = false
                        }
                    }
                
                self.listeners.append(tasksListener)
            }
        
        self.listeners.append(completionsListener)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.gray)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color)
        .cornerRadius(10)
    }
}

struct Statistics {
    var totalTasks: Int
    var completedTasks: Int
    var completionRate: Int
    var nextDeadline: Date?
    var monthlyData: [DailyData]
}

struct DailyData: Identifiable {
    var id = UUID()
    var date: Date
    var tasks: Int
    
    var dayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E" // Skrócona nazwa dnia (Mon, Tue, etc.)
        return formatter.string(from: date)
    }
}

struct TaskData {
    let id: String
    let dueDate: Date
    let isCompleted: Bool
    let isArchived: Bool
    let completedAt: Date?
}

#Preview{
    StudentStatisticsView()
}
