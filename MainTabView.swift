//
//  MainTabView.swift
//  HolisticTaskManager
//
//  Created by Aleksandra Maksimowska
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var userRole: String
    
    
    init(userRole: String = "") {
        _userRole = State(initialValue: userRole)
    }
    
    var body: some View {
        Group {
            if userRole.isEmpty {
                ProgressView()
            } else {
                TabView(selection: $selectedTab) {
                    if userRole == "student" {
                        // Student Tabs
                        StudentStatisticsView()  // Statystyki
                            .tabItem {
                                Image(systemName: "chart.bar.fill")
                                Text("Statistics")
                            }
                            .tag(0)
                        
                        ChatListView()  // Czat
                            .tabItem {
                                Image(systemName: "message.fill")
                                Text("Chat")
                            }
                            .tag(1)
                        
                        StudentTasksView()  // Zadania
                            .tabItem {
                                Image(systemName: "checkmark.square.fill")
                                Text("Tasks")
                            }
                            .tag(2)
                        
                        ProfileView(selectedTab: $selectedTab)
                            .tabItem {
                                Image(systemName: "person.fill")
                                Text("Profile")
                            }
                            .tag(3)
                            
                    } else if userRole == "tutor" {
                        // Tutor Tabs
                        TutorPeopleView() // Uczniowie
                            .tabItem {
                                Image(systemName: "person.2.fill")
                                Text("People")
                            }
                            .tag(0)
                        
                        ChatListView()  // Czat
                            .tabItem {
                                Image(systemName: "message.fill")
                                Text("Chat")
                            }
                            .tag(1)
                        
                        TutorTasksView()  // Zadania
                            .tabItem {
                                Image(systemName: "checkmark.square.fill")
                                Text("Tasks")
                            }
                            .tag(2)
                        
                        ProfileView(selectedTab: $selectedTab)
                            .tabItem {
                                Image(systemName: "person.fill")
                                Text("Profile")
                            }
                            .tag(3)
                            
                    } else if userRole == "parent" {
                        // Parent Tabs
                        ParentPeopleView()  // Dzieci
                            .tabItem {
                                Image(systemName: "person.3.fill")
                                Text("People")
                            }
                            .tag(0)
                        
                        ChatListView() // Czat
                            .tabItem {
                                Image(systemName: "message.fill")
                                Text("Messages")
                            }
                            .tag(1)
                        
                        ParentReportsView() //raporty
                            .tabItem {
                                Image(systemName: "list.bullet.rectangle")
                                Text("Reports")
                            }
                            .tag(2)
                        
                        ProfileView(selectedTab: $selectedTab)
                            .tabItem {
                                Image(systemName: "person.fill")
                                Text("Profile")
                            }
                            .tag(3)
                    }
                }
                .accentColor(Color(hexString: "0D085B"))
            }
        }
        .onAppear {
            if userRole.isEmpty {
                fetchUserRole()
            }
        }
    }
    
    private func fetchUserRole() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let db = Firestore.firestore()
        db.collection("users").document(userId).getDocument { document, error in
            if let document = document, document.exists {
                self.userRole = document.data()?["role"] as? String ?? ""
            }
        }
    }
}

#Preview {
    MainTabView(userRole: "student")
}
   
