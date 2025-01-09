//
//  AppStore.swift
//  HolisticTaskManager
//
//  Created by Aleksandra Maksimowska
//plik do zarzadzania stanem

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

class AppStore: ObservableObject {
    // User state
    @Published var currentUser: UserProfile?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    
    // Data refresh
    private var refreshTrigger = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()
    
    // Shared data
    @Published var children: [Child] = []
    @Published var tutors: [Tutor] = []
    @Published var tasks: [Task] = []
    
    static let shared = AppStore()
    private let db = Firestore.firestore()
    
    private init() {
        setupAuthStateListener()
        setupRefreshTrigger()
    }
    
    struct UserProfile: Codable {
        let id: String
        var email: String
        var phoneNumber: String
        var role: String
        var name: String
    }
    
    private func setupAuthStateListener() {
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            if let user = user {
                self?.fetchUserProfile(userId: user.uid)
            } else {
                DispatchQueue.main.async {
                    self?.currentUser = nil
                    self?.isAuthenticated = false
                    self?.children = []
                    self?.tutors = []
                    self?.tasks = []
                    self?.isLoading = false
                }
            }
        }
    }
    
    private func setupRefreshTrigger() {
        refreshTrigger
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshData()
            }
            .store(in: &cancellables)
    }
    
    func refreshData() {
        guard let user = currentUser else {
            isLoading = false
            return
        }
        
        switch user.role {
        case "parent":
            fetchChildren()
            fetchTutors()
        case "tutor":
            fetchStudents()
            fetchTasks()
        case "student":
            fetchTasks()
        default:
            isLoading = false
            break
        }
    }
    
    func triggerRefresh() {
        DispatchQueue.main.async { [weak self] in
            self?.isLoading = false  // Upewnij się, że stan ładowania jest resetowany
            self?.refreshTrigger.send()
        }
    }
    
    private func fetchUserProfile(userId: String) {
        isLoading = true
        db.collection("users").document(userId).getDocument { [weak self] document, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error fetching user profile: \(error)")
                    self?.isLoading = false
                    return
                }
                
                guard let self = self,
                      let data = document?.data() else {
                    self?.isLoading = false
                    return
                }
                
                self.currentUser = UserProfile(
                    id: userId,
                    email: data["email"] as? String ?? "",
                    phoneNumber: data["phoneNumber"] as? String ?? "",
                    role: data["role"] as? String ?? "",
                    name: data["name"] as? String ?? ""
                )
                
                self.isAuthenticated = true
                self.isLoading = false
                self.triggerRefresh()
            }
        }
    }
    
    // Phone number validation
    func isPhoneNumberAvailable(_ phoneNumber: String, completion: @escaping (Bool) -> Void) {
        db.collection("users")
            .whereField("phoneNumber", isEqualTo: phoneNumber)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error checking phone number: \(error)")
                    completion(false)
                    return
                }
                
                completion(snapshot?.documents.isEmpty ?? true)
            }
    }
    
    //email validation
    func isEmailAvailable(_ email: String, completion: @escaping (Bool) -> Void) {
        db.collection("users")
            .whereField("email", isEqualTo: email)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error checking email: \(error)")
                    completion(false)
                    return
                }
                
                completion(snapshot?.documents.isEmpty ?? true)
            }
    }
    
    // User profile update
    func updateUserProfile(
        name: String? = nil,
        phoneNumber: String? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let userId = currentUser?.id else {
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])))
            return
        }
        
        var updates: [String: Any] = [:]
        
        // Add name if provided
        if let name = name {
            updates["name"] = name
        }
        
        // Validate phone if changed
        if let newPhone = phoneNumber, newPhone != currentUser?.phoneNumber {
            isPhoneNumberAvailable(newPhone) { [weak self] isAvailable in
                if !isAvailable {
                    completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Phone number already in use"])))
                    return
                }
                
                updates["phoneNumber"] = newPhone
                self?.performUpdate(updates: updates, completion: completion)
            }
            return
        }
        
        // If no phone change, just update name if provided
        performUpdate(updates: updates, completion: completion)
    }
    
    private func performUpdate(updates: [String: Any], completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = currentUser?.id else { return }
        
        db.collection("users").document(userId).updateData(updates) { [weak self] error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            // Update local state
            if let name = updates["name"] as? String {
                self?.currentUser?.name = name
            }
            if let phoneNumber = updates["phoneNumber"] as? String {
                self?.currentUser?.phoneNumber = phoneNumber
            }
            
            completion(.success(()))
        }
    }
    
    
    
    // MARK: - Parent Methods
    private func fetchChildren() {
        guard let userId = currentUser?.id else { return }
        isLoading = true
        
        db.collection("family_connections")
            .whereField("guardian_id", isEqualTo: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self,
                      let documents = snapshot?.documents else {
                    self?.isLoading = false
                    return
                }
                
                let group = DispatchGroup()
                var newChildren: [Child] = []
                
                for document in documents {
                    let connectionData = document.data()
                    guard let studentId = connectionData["student_id"] as? String,
                          let guardianRole = connectionData["role"] as? String,
                          let connectionStatus = connectionData["status"] as? String else {
                        continue
                    }
                    
                    group.enter()
                    self.fetchChildDetails(studentId: studentId, guardianRole: guardianRole, connectionStatus: connectionStatus) { child in
                        if let child = child {
                            newChildren.append(child)
                        }
                        group.leave()
                    }
                }
                
                group.notify(queue: .main) {
                    self.children = newChildren.sorted { $0.name < $1.name }
                    self.isLoading = false
                }
            }
    }
    
    private func fetchChildDetails(studentId: String, guardianRole: String, connectionStatus: String, completion: @escaping (Child?) -> Void) {
        db.collection("students")
            .document(studentId)
            .getDocument { [weak self] studentDoc, error in
                guard let studentData = studentDoc?.data() else {
                    completion(nil)
                    return
                }
                
                self?.db.collection("users")
                    .document(studentId)
                    .getDocument { userDoc, error in
                        guard let userData = userDoc?.data() else {
                            completion(nil)
                            return
                        }
                        
                        let child = Child(
                            id: studentDoc?.documentID ?? "",
                            userId: studentId,
                            name: studentData["name"] as? String ?? "",
                            schoolType: studentData["school_type"] as? String ?? "",
                            grade: studentData["grade"] as? Int ?? 0,
                            email: userData["email"] as? String ?? "",
                            phoneNumber: userData["phoneNumber"] as? String ?? "",
                            guardianRole: guardianRole,
                            connectionStatus: connectionStatus
                        )
                        
                        completion(child)
                    }
            }
    }
    
    private func fetchTutors() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        db.collection("family_connections")
            .whereField("guardian_id", isEqualTo: userId)
            .whereField("status", isEqualTo: "active")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self,
                      let documents = snapshot?.documents else { return }
                
                let studentIds = documents.compactMap { doc -> String? in
                    doc.data()["student_id"] as? String
                }
                
                guard !studentIds.isEmpty else { return }
                
                db.collection("tutor_student_connections")
                    .whereField("student_id", in: studentIds)
                    .addSnapshotListener { [weak self] snapshot, error in
                        guard let self = self,
                              let documents = snapshot?.documents else { return }
                        
                        var uniqueTutors: [String: (status: String, studentIds: Set<String>)] = [:]
                        
                        // First pass: collect all student IDs for each tutor
                        for document in documents {
                            let data = document.data()
                            let tutorId = data["tutor_id"] as? String ?? ""
                            let status = data["status"] as? String ?? "active"
                            let studentId = data["student_id"] as? String ?? ""
                            let currentParentId = data["parent_id"] as? String ?? ""
                            
                            if var tutorData = uniqueTutors[tutorId] {
                                tutorData.studentIds.insert(studentId)
                                if status == "pending" && currentParentId == userId {
                                    tutorData.status = "pending"
                                }
                                uniqueTutors[tutorId] = tutorData
                            } else {
                                uniqueTutors[tutorId] = (status: status, studentIds: [studentId])
                            }
                        }
                        
                        let group = DispatchGroup()
                        var newTutors: [Tutor] = []
                        
                        for (tutorId, tutorData) in uniqueTutors {
                            group.enter()
                            
                            // Fetch tutor details
                            self.db.collection("users").document(tutorId).getDocument { document, error in
                                guard let document = document,
                                      let userData = document.data() else {
                                    group.leave()
                                    return
                                }
                                
                                // Fetch connected children details
                                let childrenGroup = DispatchGroup()
                                var connectedChildren: [Child] = []
                                
                                for studentId in tutorData.studentIds {
                                    childrenGroup.enter()
                                    
                                    // Fetch student details
                                    self.db.collection("students").document(studentId).getDocument { studentDoc, error in
                                        guard let studentData = studentDoc?.data() else {
                                            childrenGroup.leave()
                                            return
                                        }
                                        
                                        // Fetch user details for the student
                                        self.db.collection("users").document(studentId).getDocument { userDoc, error in
                                            defer { childrenGroup.leave() }
                                            guard let userData = userDoc?.data() else { return }
                                            
                                            let child = Child(
                                                id: studentId,
                                                userId: studentId,
                                                name: studentData["name"] as? String ?? "",
                                                schoolType: studentData["school_type"] as? String ?? "",
                                                grade: studentData["grade"] as? Int ?? 0,
                                                email: userData["email"] as? String ?? "",
                                                phoneNumber: userData["phoneNumber"] as? String ?? "",
                                                guardianRole: "student",
                                                connectionStatus: tutorData.status
                                            )
                                            connectedChildren.append(child)
                                        }
                                    }
                                }
                                
                                childrenGroup.notify(queue: .main) {
                                    let tutor = Tutor(
                                        id: tutorId,
                                        email: userData["email"] as? String ?? "",
                                        phoneNumber: userData["phoneNumber"] as? String ?? "",
                                        status: tutorData.status,
                                        connectedChildren: connectedChildren
                                    )
                                    newTutors.append(tutor)
                                    group.leave()
                                }
                            }
                        }
                        
                        group.notify(queue: .main) {
                            self.tutors = newTutors
                        }
                    }
            }
    }
    
    // Dodajemy wywołanie fetchTutors w refreshData
    
    // }
    
    private func fetchTutorsForStudents(studentIds: [String]) {
        db.collection("tutor_student_connections")
            .whereField("student_id", in: studentIds)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                // Śledź unikalnych korepetytorów i ich najnowszy status
                var uniqueTutors: [String: (Tutor, String)] = [:]
                
                for document in documents {
                    let data = document.data()
                    let tutorId = data["tutor_id"] as? String ?? ""
                    let status = data["status"] as? String ?? "active"
                    let currentParentId = data["parent_id"] as? String ?? ""
                    
                    if status == "pending" && currentParentId == self?.currentUser?.id {
                        uniqueTutors[tutorId]?.1 = "pending"
                    } else if !uniqueTutors.keys.contains(tutorId) {
                        uniqueTutors[tutorId] = (Tutor(id: tutorId, email: "", phoneNumber: "", status: status, connectedChildren: []), status)
                    }
                }
                
                // Resetuj listę korepetytorów
                self?.tutors.removeAll()
                
                // Pobierz pełne szczegóły dla każdego unikalnego korepetytora
                for (tutorId, (_, status)) in uniqueTutors {
                    self?.db.collection("users").document(tutorId).getDocument { document, error in
                        if let document = document, document.exists,
                           let data = document.data() {
                            let tutor = Tutor(
                                id: document.documentID,
                                email: data["email"] as? String ?? "",
                                phoneNumber: data["phoneNumber"] as? String ?? "",
                                status: status,
                                connectedChildren: []
                            )
                            
                            DispatchQueue.main.async {
                                if !(self?.tutors.contains(where: { $0.id == tutor.id }) ?? false) {
                                    self?.tutors.append(tutor)
                                }
                            }
                        }
                    }
                }
            }
    }
    
    private func fetchStudents() {
        // Implementation will be added in next step
    }
    
    private func fetchTasks() {
        // Implementation will be added in next step
    }
    
    
}
