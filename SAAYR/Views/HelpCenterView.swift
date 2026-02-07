//
//  HelpCenterView.swift
//  SAAYR
//
//  Created by Awais Raza on 08/02/2026.
//

import SwiftUI


struct HelpCenterView: View {
    let faqs: [FAQ]
    @EnvironmentObject var languageManager: LanguageManager
    @Environment(\.dismiss) var dismiss
    @State private var expandedFAQ: String?

    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        VStack(alignment: languageManager.currentLanguage == .english ? .leading : .trailing, spacing: 16) {
                            Text(languageManager.text("support.faq"))
                                .font(.system(size: 27, weight: .bold))
                                .padding(.horizontal)

                            ForEach(faqs) { faq in
                                FAQItem(
                                    faq: faq,
                                    isExpanded: expandedFAQ == faq.id
                                ) {
                                    withAnimation {
                                        expandedFAQ = expandedFAQ == faq.id ? nil : faq.id
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }

                        Spacer(minLength: 50)
                    }
                    .padding(.top, 20)
                }
            }
//            .navigationTitle(languageManager.text("support.faq"))
//            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: languageManager.currentLanguage == .english ? "chevron.left" : "chevron.right")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            }
        }
        .environment(\.layoutDirection, languageManager.currentLanguage == .arabic ? .rightToLeft : .leftToRight)
    }
}


struct FAQItem: View {
    let faq: FAQ
    let isExpanded: Bool
    let action: () -> Void
    @EnvironmentObject var languageManager: LanguageManager
    
    var body: some View {
        VStack(alignment: languageManager.currentLanguage == .english ? .leading : .trailing, spacing: 12) {
            Button(action: action) {
                HStack {
                    Text(languageManager.currentLanguage == .english ? faq.question : faq.questionAr)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(languageManager.currentLanguage == .english ? .leading : .trailing)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            
            if isExpanded {
                Text(languageManager.currentLanguage == .english ? faq.answer : faq.answerAr)
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(languageManager.currentLanguage == .english ? .leading : .trailing)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
    }
}
