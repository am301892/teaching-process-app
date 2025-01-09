//
//  ConnectionManager.swift
//  HolisticTaskManager
//
//  Created by Aleksandra Maksimowska
//

import Firebase
import FirebaseFirestore
import FirebaseAuth

enum ConnectionError: Error {
    case userNotFound
    case invalidPassword
    case childAlreadyConnected
    case invalidRole
    case databaseError
    case phoneNumberExists
    case emailExists
    case authError
    case unknownError
    
    var localizedDescription: String {
        switch self {
        case .userNotFound:
            return "User not found"
        case .invalidPassword:
            return "Invalid password"
        case .childAlreadyConnected:
            return "Child is already connected with this guardian"
        case .invalidRole:
            return "Invalid user role"
        case .databaseError:
            return "Database error occurred"
        case .phoneNumberExists:
            return "Please verify your data - p"
        case .emailExists:
            return "Please verify your data - e"
        case .authError:
            return "Authentication error occurred"
        case .unknownError:
            return "Unknown error occurred"
        }
    }
}

class ConnectionManager {
    static let shared = ConnectionManager()
    private let db = Firestore.firestore()
    
    // Zmienna do przechowywania użytkownika-rodzica
    private var parentUser: User?
    
    // Metoda do zapisywania referencji do użytkownika-rodzica
    private func saveParentUser() {
        parentUser = Auth.auth().currentUser
    }
    
    // Metoda do przywracania użytkownika-rodzica
    private func restoreParentUser(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let parent = parentUser else {
            completion(.failure(ConnectionError.authError))
            return
        }
        
        Auth.auth().updateCurrentUser(parent) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    
    // Dodana funkcja pomocnicza do tworzenia dokumentów dziecka
    private func setupChildDocuments(
        childId: String,
        name: String,
        email: String,
        phoneNumber: String,
        schoolType: String,
        grade: Int,
        parentId: String,
        batch: WriteBatch,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // Tworzenie dokumentu użytkownika
        let userRef = db.collection("users").document(childId)
        let userData: [String: Any] = [
            "email": email,
            "phoneNumber": phoneNumber,
            "role": "student",
            "name": name,
            "created_at": FieldValue.serverTimestamp(),
            "created_by": parentId
        ]
        batch.setData(userData, forDocument: userRef)
        
        // Tworzenie dokumentu studenta
        let studentRef = db.collection("students").document(childId)
        let studentData: [String: Any] = [
            "user_id": childId,
            "name": name,
            "school_type": schoolType,
            "grade": grade,
            "created_at": FieldValue.serverTimestamp()
        ]
        batch.setData(studentData, forDocument: studentRef)
        
        // Tworzenie połączenia rodzinnego
        let connectionRef = db.collection("family_connections").document()
        let connectionData: [String: Any] = [
            "student_id": childId,
            "guardian_id": parentId,
            "role": "primary_parent",
            "status": "active",
            "created_at": FieldValue.serverTimestamp()
        ]
        batch.setData(connectionData, forDocument: connectionRef)
        
        // Commit batch
        batch.commit { error in
            if let error = error {
                completion(.failure(error))
                return
            }
            completion(.success(()))
        }
    }
    
    func createNewChildAccount(
        email: String,
        password: String,
        name: String,
        phoneNumber: String,
        schoolType: String,
        grade: Int,
        parentId: String,
        parentEmail: String,
        parentPassword: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        // Rozpocznij ładowanie
        DispatchQueue.main.async {
            AppStore.shared.isLoading = true
        }
        
        // Zapisz referencję do użytkownika-rodzica przed jakimikolwiek operacjami
        saveParentUser()
        
        // Sprawdź dostępność numeru telefonu
        AppStore.shared.isPhoneNumberAvailable(phoneNumber) { [weak self] isPhoneAvailable in
            guard let self = self else { return }
            
            if !isPhoneAvailable {
                DispatchQueue.main.async {
                    AppStore.shared.isLoading = false
                    completion(.failure(ConnectionError.phoneNumberExists))
                }
                return
            }
            
            AppStore.shared.isEmailAvailable(email) { [weak self] isEmailAvailable in
                guard let self = self else { return }
                
                if !isEmailAvailable {
                    DispatchQueue.main.async {
                        AppStore.shared.isLoading = false
                        completion(.failure(ConnectionError.userNotFound)) // lub nowy typ błędu
                    }
                    return
                }
                
                // Utwórz konto dla dziecka - 2. instancja auth
                let secondaryAuth = Auth.auth()
                secondaryAuth.createUser(withEmail: email, password: password) { [weak self] authResult, authError in
                    guard let self = self else { return }
                    
                    if let authError = authError {
                        self.restoreParentUser { _ in
                            DispatchQueue.main.async {
                                AppStore.shared.isLoading = false
                                completion(.failure(authError))
                            }
                        }
                        return
                    }
                    
                    guard let childId = authResult?.user.uid else {
                        self.restoreParentUser { _ in
                            DispatchQueue.main.async {
                                AppStore.shared.isLoading = false
                                completion(.failure(ConnectionError.authError))
                            }
                        }
                        return
                    }
                    
                    // Utwórz batch dla operacji Firestore
                    let batch = self.db.batch()
                    
                    // Skonfiguruj dokumenty dziecka
                    self.setupChildDocuments(
                        childId: childId,
                        name: name,
                        email: email,
                        phoneNumber: phoneNumber,
                        schoolType: schoolType,
                        grade: grade,
                        parentId: parentId,
                        batch: batch
                    ) { [weak self] result in
                        guard let self = self else { return }
                        
                        switch result {
                        case .success:
                            // Przywróć sesję rodzica
                            self.restoreParentUser { restoreResult in
                                DispatchQueue.main.async {
                                    AppStore.shared.isLoading = false
                                    switch restoreResult {
                                    case .success:
                                        AppStore.shared.triggerRefresh()
                                        completion(.success(childId))
                                    case .failure(let error):
                                        AppStore.shared.isLoading = false
                                        completion(.failure(error))
                                    }
                                }
                            }
                        case .failure(let error):
                            self.restoreParentUser { _ in
                                DispatchQueue.main.async {
                                    AppStore.shared.isLoading = false
                                    AppStore.shared.triggerRefresh()
                                    completion(.failure(error))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    func connectExistingChild(
        phoneNumber: String,
        password: String,
        guardianId: String,
        guardianRole: String = "secondary_parent",
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        DispatchQueue.main.async {
            AppStore.shared.isLoading = true
        }
        
        // Zapisz referencję do użytkownika-rodzica
        saveParentUser()
        
        db.collection("users")
            .whereField("phoneNumber", isEqualTo: phoneNumber)
            .whereField("role", isEqualTo: "student")
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    self.restoreParentUser { _ in
                        DispatchQueue.main.async {
                            AppStore.shared.isLoading = false
                            completion(.failure(error))
                        }
                    }
                    return
                }
                
                guard let document = snapshot?.documents.first,
                      let email = document.data()["email"] as? String else {
                    self.restoreParentUser { _ in
                        DispatchQueue.main.async {
                            AppStore.shared.isLoading = false
                            completion(.failure(ConnectionError.userNotFound))
                        }
                    }
                    return
                }
                
                // Zweryfikuj kredencjały dziecka
                Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
                    guard let self = self else { return }
                    
                    if error != nil {
                        self.restoreParentUser { _ in
                            DispatchQueue.main.async {
                                AppStore.shared.isLoading = false
                                completion(.failure(ConnectionError.invalidPassword))
                            }
                        }
                        return
                    }
                    
                    let childUserId = document.documentID
                    
                    // Sprawdź czy połączenie już istnieje
                    self.checkExistingConnection(childUserId: childUserId, guardianId: guardianId) { [weak self] connectionExists in
                        guard let self = self else { return }
                        
                        if connectionExists {
                            self.restoreParentUser { _ in
                                DispatchQueue.main.async {
                                    AppStore.shared.isLoading = false
                                    completion(.failure(ConnectionError.childAlreadyConnected))
                                }
                            }
                            return
                        }
                        
                        // Utwórz nowe połączenie
                        self.createFamilyConnection(
                            childUserId: childUserId,
                            guardianId: guardianId,
                            guardianRole: guardianRole
                        ) { [weak self] result in
                            guard let self = self else { return }
                            
                            self.restoreParentUser { restoreResult in
                                DispatchQueue.main.async {
                                    AppStore.shared.isLoading = false
                                    switch restoreResult {
                                    case .success:
                                        AppStore.shared.triggerRefresh()
                                        completion(.success(childUserId))
                                    case .failure(let error):
                                        completion(.failure(error))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        
    }
    private func checkExistingConnection(childUserId: String, guardianId: String, completion: @escaping (Bool) -> Void) {
        db.collection("family_connections")
            .whereField("student_id", isEqualTo: childUserId)
            .whereField("guardian_id", isEqualTo: guardianId)
            .getDocuments { snapshot, _ in
                let exists = !(snapshot?.documents.isEmpty ?? true)
                completion(exists)
            }
    }

    private func createFamilyConnection(
        childUserId: String,
        guardianId: String,
        guardianRole: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let connectionData: [String: Any] = [
            "student_id": childUserId,
            "guardian_id": guardianId,
            "role": guardianRole,
            "status": "active",
            "created_at": FieldValue.serverTimestamp()
        ]
        
        db.collection("family_connections").addDocument(data: connectionData) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
}
