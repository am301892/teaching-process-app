//
//  ChatView.swift
//  HolisticTaskManager
//
//  Created by Aleksandra Maksimowska
//
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFirestoreSwift
import Foundation

// Models
struct ChatMessage: Identifiable {
    let id: String
    let senderId: String
    let content: String
    let timestamp: Date
    let isRead: Bool
}

struct ChatContact: Identifiable {
    let id: String
    let name: String
    let role: String // "parent", "tutor", "student"
    let lastMessage: String?
    let lastMessageTimestamp: Date?
    let unreadCount: Int
}

struct ChatListView: View {
    @State private var contacts: [ChatContact] = []
    
    var body: some View {
        NavigationView {
            List(contacts) { contact in
                NavigationLink(destination: ChatDetailView(contact: contact)) {
                    ChatContactRow(contact: contact)
                }
            }
            .navigationTitle("Messages")
            .onAppear {
                fetchContacts()
            }
        }
    }
    
    private func fetchContacts() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        
        db.collection("users").document(currentUserId).getDocument { userSnapshot, error in
            guard let currentUserData = userSnapshot?.data(),
                  let currentUserRole = currentUserData["role"] as? String else { return }
            
            switch currentUserRole {
            case "parent":
                    // Najpierw pobierz dzieci rodzica
                    db.collection("family_connections")
                        .whereField("guardian_id", isEqualTo: currentUserId)
                        .whereField("status", isEqualTo: "active")
                        .addSnapshotListener { snapshot, error in
                            guard let documents = snapshot?.documents else { return }
                            
                            let studentIds = documents.compactMap { doc -> String? in
                                doc.data()["student_id"] as? String
                            }
                            
                            guard !studentIds.isEmpty else { return }
                            
                            // Pobierz połączenia z tutorami dla tych dzieci
                            db.collection("tutor_student_connections")
                                .whereField("student_id", in: studentIds)
                                .whereField("status", isEqualTo: "active")
                                .addSnapshotListener { tutorSnapshot, error in
                                    guard let tutorDocs = tutorSnapshot?.documents else { return }
                                    
                                    let group = DispatchGroup()
                                    var newContacts: [ChatContact] = []
                                    var processedTutorIds = Set<String>()
                                    
                                    for doc in tutorDocs {
                                        let tutorId = doc["tutor_id"] as? String ?? ""
                                        let studentId = doc["student_id"] as? String ?? ""
                                        
                                        if !processedTutorIds.contains(tutorId) {
                                            processedTutorIds.insert(tutorId)
                                            
                                            group.enter()
                                            // Pobierz dane tutora
                                            db.collection("users").document(tutorId).getDocument { tutorDoc, error in
                                                defer { group.leave() }
                                                guard let tutorData = tutorDoc?.data() else { return }
                                                
                                                // Pobierz dane studenta dla opisu
                                                group.enter()
                                                db.collection("students").document(studentId).getDocument { studentDoc, error in
                                                    defer { group.leave() }
                                                    let studentName = studentDoc?.data()?["name"] as? String ?? ""
                                                    
                                                    let chatId = [currentUserId, tutorId].sorted().joined(separator: "_")
                                                    group.enter()
                                                    fetchLastMessage(chatId: chatId) { lastMessage, timestamp in
                                                        defer { group.leave() }
                                                        
                                                        let contact = ChatContact(
                                                            id: tutorId,
                                                            name: "\(tutorData["name"] as? String ?? "Unknown") (Tutor of \(studentName))",
                                                            role: "tutor",
                                                            lastMessage: lastMessage,
                                                            lastMessageTimestamp: timestamp,
                                                            unreadCount: 0
                                                        )
                                                        newContacts.append(contact)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    
                                    group.notify(queue: .main) {
                                        contacts = newContacts.sorted { ($0.lastMessageTimestamp ?? Date.distantPast) > ($1.lastMessageTimestamp ?? Date.distantPast) }
                                    }
                                }
                        }

                case "tutor":
                    // Dla tutora: pobierz zarówno rodziców jak i uczniów z aktywnych połączeń
                    db.collection("tutor_student_connections")
                        .whereField("tutor_id", isEqualTo: currentUserId)
                        .whereField("status", isEqualTo: "active")
                        .addSnapshotListener { snapshot, error in
                            guard let documents = snapshot?.documents else { return }
                            
                            let group = DispatchGroup()
                            var newContacts: [ChatContact] = []
                            var processedParentIds = Set<String>()
                            var processedStudentIds = Set<String>()
                            
                            for document in documents {
                                let studentId = document.data()["student_id"] as? String ?? ""
                                
                                if !processedStudentIds.contains(studentId) {
                                    processedStudentIds.insert(studentId)
                                    
                                    // Pobierz wszystkich rodziców dla tego studenta
                                    group.enter()
                                    db.collection("family_connections")
                                        .whereField("student_id", isEqualTo: studentId)
                                        .whereField("status", isEqualTo: "active")
                                        .getDocuments { familySnapshot, familyError in
                                            defer { group.leave() }
                                            
                                            guard let familyDocs = familySnapshot?.documents else { return }
                                            
                                            // Pobierz dane studenta
                                            group.enter()
                                            db.collection("students").document(studentId).getDocument { studentDoc, error in
                                                defer { group.leave() }
                                                let studentName = studentDoc?.data()?["name"] as? String ?? ""
                                                
                                                // Dla każdego rodzica
                                                for familyDoc in familyDocs {
                                                    let parentId = familyDoc.data()["guardian_id"] as? String ?? ""
                                                    let guardianRole = familyDoc.data()["role"] as? String ?? ""
                                                    
                                                    if !processedParentIds.contains(parentId) {
                                                        processedParentIds.insert(parentId)
                                                        
                                                        group.enter()
                                                        db.collection("users").document(parentId).getDocument { parentDoc, error in
                                                            defer { group.leave() }
                                                            guard let parentData = parentDoc?.data() else { return }
                                                            
                                                            let chatId = [currentUserId, parentId].sorted().joined(separator: "_")
                                                            group.enter()
                                                            fetchLastMessage(chatId: chatId) { lastMessage, timestamp in
                                                                defer { group.leave() }
                                                                
                                                                let contact = ChatContact(
                                                                    id: parentId,
                                                                    name: "\(parentData["name"] as? String ?? "Unknown") (\(guardianRole == "primary_parent" ? "Parent1" : "Parent2") of \(studentName))",
                                                                    role: "parent",
                                                                    lastMessage: lastMessage,
                                                                    lastMessageTimestamp: timestamp,
                                                                    unreadCount: 0
                                                                )
                                                                newContacts.append(contact)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    
                                    // Dodaj też studenta do kontaktów
                                    group.enter()
                                    db.collection("students").document(studentId).getDocument { studentDoc, error in
                                        defer { group.leave() }
                                        guard let studentData = studentDoc?.data() else { return }
                                        
                                        let chatId = [currentUserId, studentId].sorted().joined(separator: "_")
                                        group.enter()
                                        fetchLastMessage(chatId: chatId) { lastMessage, timestamp in
                                            defer { group.leave() }
                                            
                                            let contact = ChatContact(
                                                id: studentId,
                                                name: "\(studentData["name"] as? String ?? "") (Student)",
                                                role: "student",
                                                lastMessage: lastMessage,
                                                lastMessageTimestamp: timestamp,
                                                unreadCount: 0
                                            )
                                            newContacts.append(contact)
                                        }
                                    }
                                }
                            }
                            
                            group.notify(queue: .main) {
                                contacts = newContacts.sorted { ($0.lastMessageTimestamp ?? Date.distantPast) > ($1.lastMessageTimestamp ?? Date.distantPast) }
                            }
                        }
                        
                
            case "student":
                // Dla ucznia: pobierz tutorów z aktywnych połączeń
                db.collection("tutor_student_connections")
                    .whereField("student_id", isEqualTo: currentUserId)
                    .whereField("status", isEqualTo: "active")
                    .addSnapshotListener { snapshot, error in
                        guard let documents = snapshot?.documents else { return }
                        
                        let group = DispatchGroup()
                        var newContacts: [ChatContact] = []
                        
                        for document in documents {
                            let data = document.data()
                            let tutorId = data["tutor_id"] as? String ?? ""
                            
                            group.enter()
                            db.collection("users").document(tutorId).getDocument { tutorDoc, error in
                                defer { group.leave() }
                                
                                guard let tutorData = tutorDoc?.data() else { return }
                                
                                group.enter()
                                let chatId = [currentUserId, tutorId].sorted().joined(separator: "_")
                                fetchLastMessage(chatId: chatId) { lastMessage, timestamp in
                                    defer { group.leave() }
                                    
                                    let contact = ChatContact(
                                        id: tutorId,
                                        name: "\(tutorData["name"] as? String ?? "Unknown") (Tutor of \(userSnapshot?.data()?["name"] as? String ?? ""))",
                                        role: "tutor",
                                        lastMessage: lastMessage,
                                        lastMessageTimestamp: timestamp,
                                        unreadCount: 0
                                    )
                                    newContacts.append(contact)
                                }
                            }
                        }
                        
                        group.notify(queue: .main) {
                            contacts = newContacts.sorted { ($0.lastMessageTimestamp ?? Date.distantPast) > ($1.lastMessageTimestamp ?? Date.distantPast) }
                        }
                    }
                
            default:
                break
            }
        }
    }
    
    private func fetchLastMessage(chatId: String, completion: @escaping (String?, Date?) -> Void) {
        let db = Firestore.firestore()
        db.collection("chats")
            .document(chatId)
            .collection("messages")
            .order(by: "timestamp", descending: true)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                guard let snapshot = snapshot,
                      let document = snapshot.documents.first else {
                    completion(nil, nil)
                    return
                }
                
                let data = document.data()
                let message = data["content"] as? String
                let timestamp = (data["timestamp"] as? Timestamp)?.dateValue()
                completion(message, timestamp)
            }
    }
}

// MARK: - Subviews
struct ChatContactRow: View {
    let contact: ChatContact // To powinien być parametr przekazywany do widoku
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(contact.name)
                    .font(.headline)
                if let lastMessage = contact.lastMessage {
                    Text(lastMessage)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                if let timestamp = contact.lastMessageTimestamp {
                    Text(timestamp.formatted(date: .numeric, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                if contact.unreadCount > 0 {
                    Text("\(contact.unreadCount)")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.blue)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct ChatDetailView: View {
    let contact: ChatContact
    @State private var messageText = ""
    @State private var messages: [ChatMessage] = []
    @State private var isLoading = false
    
    private var displayName: String {
        contact.name
//        let roleText = contact.role.capitalized
//        return "\(contact.name) (\(roleText))"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _ in
                    if let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            HStack {
                TextField("Message", text: $messageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .disabled(isLoading)
                
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(messageText.isEmpty ? .gray : Color(hexString: "0D085B"))
                }
                .disabled(messageText.isEmpty || isLoading)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(displayName)
                    .font(.headline)
            }
        }
        .onAppear {
            startMessagesListener()
        }
    }
    
    private func startMessagesListener() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        let db = Firestore.firestore()
        let chatId = [currentUserId, contact.id].sorted().joined(separator: "_")
        
        db.collection("chats")
            .document(chatId)
            .collection("messages")
            .order(by: "timestamp")
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                messages = documents.map { doc -> ChatMessage in
                    let data = doc.data()
                    return ChatMessage(
                        id: doc.documentID,
                        senderId: data["sender_id"] as? String ?? "",
                        content: data["content"] as? String ?? "",
                        timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date(),
                        isRead: data["is_read"] as? Bool ?? false
                    )
                }
            }
    }
    
    private func sendMessage() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              !messageText.isEmpty else { return }
        
        isLoading = true
        let db = Firestore.firestore()
        let chatId = [currentUserId, contact.id].sorted().joined(separator: "_")
        let chatRef = db.collection("chats").document(chatId)
        
        chatRef.getDocument { document, error in
            if let error = error {
                print("Error checking chat: \(error)")
                isLoading = false
                return
            }
            
            let batch = db.batch()
            
            if document == nil || !document!.exists {
                let chatData: [String: Any] = [
                    "participants": [currentUserId, contact.id],
                    "created_at": FieldValue.serverTimestamp(),
                    "updated_at": FieldValue.serverTimestamp(),
                    "last_message": messageText,
                    "last_message_timestamp": FieldValue.serverTimestamp()
                ]
                batch.setData(chatData, forDocument: chatRef)
            } else {
                batch.updateData([
                    "updated_at": FieldValue.serverTimestamp(),
                    "last_message": messageText,
                    "last_message_timestamp": FieldValue.serverTimestamp()
                ], forDocument: chatRef)
            }
            
            let messageRef = chatRef.collection("messages").document()
            let messageData: [String: Any] = [
                "sender_id": currentUserId,
                "content": messageText,
                "timestamp": FieldValue.serverTimestamp(),
                "is_read": false
            ]
            batch.setData(messageData, forDocument: messageRef)
            
            batch.commit { error in
                isLoading = false
                if let error = error {
                    print("Error sending message: \(error)")
                    return
                }
                messageText = ""
            }
        }
    }
}
    
    struct MessageBubble: View {
        let message: ChatMessage
        @State private var currentUserId = Auth.auth().currentUser?.uid
        
        private var isFromCurrentUser: Bool {
            message.senderId == currentUserId
        }
        
        var body: some View {
            HStack {
                if isFromCurrentUser { Spacer() }
                
                VStack(alignment: isFromCurrentUser ? .trailing : .leading) {
                    Text(message.content)
                        .padding(10)
                        .background(isFromCurrentUser ? Color(hexString: "0D085B") : Color(.systemGray5))
                        .foregroundColor(isFromCurrentUser ? .white : .black)
                        .cornerRadius(15)
                    
                    Text(message.timestamp.formatted(date: .numeric, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                
                if !isFromCurrentUser { Spacer() }
            }
        }
    }


#Preview(){
    ChatListView()
}
