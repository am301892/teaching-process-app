//
//  RaportViewModel.swift
//  HolisticTaskManager
//
//  Created by Aleksandra Maksimowska
//

import FirebaseFirestore
import FirebaseAuth

class ReportViewModel: ObservableObject {
    // Published właściwość, która automatycznie odświeża UI gdy się zmienia
    @Published var reports: [Report] = []
    
    // Przechowujemy referencję do listenera, żeby móc go później wyłączyć
    private var listener: ListenerRegistration?
    
    // Przechowujemy ID aktualnego studenta, żeby móc porównać czy się zmieniło
    private var currentStudentId: String?
    
    // Dodajemy inicjalizator
    init() {
        // Możemy tu dodać początkową konfigurację jeśli potrzebna
    }
    
    func startListening(for studentId: String) {
        // Sprawdzamy czy już nasłuchujemy tego samego studenta
        guard currentStudentId != studentId else { return }
        
        // Aktualizujemy currentStudentId
        currentStudentId = studentId
        
        // Upewniamy się, że mamy ID zalogowanego tutora
        guard let tutorId = Auth.auth().currentUser?.uid else {
            print("Brak zalogowanego tutora")
            return
        }
        
        // Usuwamy istniejący listener jeśli istnieje
        stopListening()
        
        print("Rozpoczynam nasłuchiwanie raportów dla studenta: \(studentId)")
        
        let db = Firestore.firestore()
        
        // Tworzymy query do kolekcji progress_reports
        let query = db.collection("progress_reports")
            .whereField("tutor_id", isEqualTo: tutorId)
            .whereField("student_id", isEqualTo: studentId)
            .order(by: "created_at", descending: true)
        
        // Ustawiamy nasłuchiwanie w czasie rzeczywistym
        listener = query.addSnapshotListener { [weak self] snapshot, error in
            // Sprawdzamy czy nie wystąpił błąd
            if let error = error {
                print("Błąd podczas nasłuchiwania raportów: \(error.localizedDescription)")
                return
            }
            
            // Sprawdzamy czy mamy dokumenty
            guard let documents = snapshot?.documents else {
                print("Brak dokumentów w snapshot")
                return
            }
            
            print("Otrzymano \(documents.count) raportów")
            
            // Mapujemy dokumenty na obiekty Report
            let newReports = documents.compactMap { document -> Report? in
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
            
            // Aktualizujemy reports na głównym wątku
            DispatchQueue.main.async {
                self?.reports = newReports
                print("Zaktualizowano listę raportów, liczba raportów: \(newReports.count)")
            }
        }
    }
    
    func stopListening() {
        print("Zatrzymuję nasłuchiwanie raportów")
        listener?.remove()
        listener = nil
        currentStudentId = nil
    }
    
    deinit {
        stopListening()
    }
}
