//
//  StudentModels.swift
//  HolisticTaskManager
//
//  Created by Aleksandra Maksimowska 
//
import Foundation
import SwiftUI

struct Student: Identifiable {
    let id: String
    let name: String
    let schoolType: String
    let grade: Int
    let parentEmail: String
}

struct Report: Identifiable {
    let id: String
    let tutorId: String
    let studentId: String
    let date: Date
    let duration: Int // in minutes
    let topic: String
    let preparation: Int // 1-5
    let engagement: Int // 1-5
    let recommendations: String
    let createdAt: Date
}

extension Student: Equatable {
    static func == (lhs: Student, rhs: Student) -> Bool {
        return lhs.id == rhs.id
    }
}
