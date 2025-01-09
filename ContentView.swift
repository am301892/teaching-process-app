//
//  ContentView.swift
//  HolisticTaskManager
//
//  Created by Aleksandra Maksimowska 
//

import SwiftUI
import FirebaseAuth


struct ContentView: View {
    @StateObject private var appStore = AppStore.shared
    
    var body: some View {
        Group {
            if appStore.isLoading {
                ProgressView()
            } else if appStore.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
    }
}



#Preview {
    ContentView()
}
