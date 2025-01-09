//
//  RatingSliderView.swift
//  HolisticTaskManager
//
//  Created by Aleksandra Maksimowska
//

import SwiftUI

struct RatingSliderView: View {
    let title: String
    @Binding var value: Int
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value)/5")
                    .foregroundColor(color)
            }
            
            HStack {
                ForEach(1...5, id: \.self) { index in
                    Rectangle()
                        .fill(index <= value ? color : Color(.systemGray5))
                        .frame(height: 8)
                        .cornerRadius(4)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let width = UIScreen.main.bounds.width - 40 // Adjusting for padding
                        let segmentWidth = width / 5
                        let location = gesture.location.x
                        let newValue = min(max(Int(location / segmentWidth) + 1, 1), 5)
                        if newValue != value {
                            value = newValue
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
            )
        }
    }
}
