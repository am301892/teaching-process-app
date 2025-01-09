//
//  SectionHeaderView.swift
//  HolisticTaskManager
//
//  Created by Aleksandra Maksimowska
//

import SwiftUI

struct SectionHeaderView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 24, weight: .bold)) // Adjust the font size and weight
            .foregroundColor(Color(hexString: "0D085B")) // Use the darkest color from your theme
            .padding(.vertical, 5)
            .padding(.leading, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}



//#Preview {
//    SectionHeaderView()
//}
