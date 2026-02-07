import SwiftUI

struct SupportView: View {
    @EnvironmentObject var languageManager: LanguageManager
    @Environment(\.dismiss) var dismiss
    @State private var expandedFAQ: String?
    @State private var showHelpCenter: Bool = false
    @State private var showSubmitTicket: Bool = false
    @State private var showMyTickets: Bool = false
    
    let faqs = [
        FAQ(
            id: "1",
            question: "How do I earn XP?",
            questionAr: "كيف أكسب نقاط الخبرة؟",
            answer: "You earn XP by checking in at locations, making purchases at partner merchants, and completing challenges. Every 1 SAR spent = 1 XP (2x at partner locations).",
            answerAr: "تكسب نقاط الخبرة من خلال تسجيل الحضور في المواقع، والشراء من التجار الشركاء، وإكمال التحديات. كل 1 ريال منفق = 1 نقطة خبرة (2x في المواقع الشريكة)."
        ),
        FAQ(
            id: "2",
            question: "What are Points used for?",
            questionAr: "ما هي استخدامات النقاط؟",
            answer: "Points are used for leaderboard rankings and weekly prize pool competitions. Every 100 XP = 1 Point.",
            answerAr: "تستخدم النقاط لترتيب لوحة المتصدرين ومسابقات جوائز الأسبوع. كل 100 نقطة خبرة = 1 نقطة."
        ),
        FAQ(
            id: "3",
            question: "How does my pet evolve?",
            questionAr: "كيف يتطور حيواني الأليف؟",
            answer: "Your pet evolves through 5 stages (Egg → Hatchling → Juvenile → Adult → Legendary) based on your level progression. Each evolution unlocks new rewards!",
            answerAr: "يتطور حيوانك الأليف عبر 5 مراحل (بيضة ← فرخ ← يافع ← بالغ ← أسطوري) بناءً على تقدم مستواك. كل تطور يفتح مكافآت جديدة!"
        ),
        FAQ(
            id: "4",
            question: "What is PVP Battle Arena?",
            questionAr: "ما هي ساحة المعركة PVP؟",
            answer: "PVP Battle Arena lets you compete against other players in real-time challenges. Entry costs 5 SAR, and the winner takes the prize!",
            answerAr: "تتيح لك ساحة المعركة PVP المنافسة ضد لاعبين آخرين في تحديات فورية. تكلفة الدخول 5 ريال، والفائز يأخذ الجائزة!"
        ),
        FAQ(
            id: "5",
            question: "How do check-in streaks work?",
            questionAr: "كيف تعمل سلاسل تسجيل الحضور؟",
            answer: "Check in at any location once per day to maintain your streak. Longer streaks unlock bonus rewards and achievements!",
            answerAr: "سجل حضورك في أي موقع مرة واحدة يوميًا للحفاظ على سلسلتك. السلاسل الأطول تفتح مكافآت وإنجازات إضافية!"
        )
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Contact Cards
                        VStack(spacing: 12) {
//                            ContactCard(
//                                icon: "envelope.fill",
//                                title: "Email Us",
//                                titleAr: "راسلنا عبر البريد الإلكتروني",
//                                subtitle: "zeeshan@saayr.sa",
//                                gradient: [Color.blue, Color.cyan]
//                            )
//                            
                            ContactCard(
                                icon: "info.circle.fill",
                                title: "Help Center",
                                titleAr: "مركز المساعدة",
                                subtitle: "Frequently Asked Questions",
                                gradient: [Color.blue, Color.cyan]
                            )
                            .onTapGesture {
                                showHelpCenter = true
                            }

                            ContactCard(
                                icon: "envelope.fill",
                                title: "Submit Ticket",
                                titleAr: "إرسال تذكرة",
                                subtitle: "Frequently Asked Questions",
                                gradient: [Color.purple.opacity(0.7), Color.indigo.opacity(0.9)]
                            )
                            .onTapGesture {
                                showSubmitTicket = true
                            }

                            ContactCard(
                                icon: "list.bullet",
                                title: "My Tickets",
                                titleAr: "تذاكري",
                                subtitle: "View your support tickets",
                                gradient: [Color.yellow.opacity(0.7), Color.orange.opacity(0.9)]
                            )
                            .onTapGesture {
                                showMyTickets = true
                            }

//                            ContactCard(
//                                icon: "phone.fill",
//                                title: "Call Us",
//                                titleAr: "اتصل بنا",
//                                subtitle: "+966 11 234 5678",
//                                gradient: [Color.green, Color.teal]
//                            )
//                            
//                            ContactCard(
//                                icon: "bubble.left.and.bubble.right.fill",
//                                title: "Live Chat",
//                                titleAr: "الدردشة المباشرة",
//                                subtitle: "Available 24/7",
//                                gradient: [Color.purple, Color.pink]
//                            )
                        }
                        .padding(.horizontal)
                        
                        // (Moved FAQ Section to HelpCenterView presented fullscreen)
                        
                        Spacer(minLength: 50)
                    }
                    .padding(.top, 20)
                }
            }
            .navigationTitle(languageManager.text("support.title"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: languageManager.currentLanguage == .english ? "chevron.left" : "chevron.right")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showHelpCenter) {
            HelpCenterView(faqs: faqs)
                .environmentObject(languageManager)
        }
        .fullScreenCover(isPresented: $showSubmitTicket) {
            SubmitTicketView()
                .environmentObject(languageManager)
        }
        .fullScreenCover(isPresented: $showMyTickets) {
            MyTicketsView()
                .environmentObject(languageManager)
        }
        .environment(\.layoutDirection, languageManager.currentLanguage == .arabic ? .rightToLeft : .leftToRight)
    }
}




struct Ticket: Identifiable, Hashable {
    let id: String
    let title: String
    let message: String
    let timeAgo: String
    let status: TicketStatus
}


enum TicketStatus {
    case inProgress, resolved, open
}



struct StatusBadge: View {
    let status: TicketStatus
    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(badgeColor)
            .cornerRadius(12)
    }

    var label: String {
        switch status {
        case .inProgress: return "In Progress"
        case .resolved: return "Resolved"
        case .open: return "Open"
        }
    }

    var badgeColor: Color {
        switch status {
        case .inProgress: return Color.orange
        case .resolved: return Color.green
        case .open: return Color.blue
        }
    }
}

struct MessageItem: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let time: String
}


struct FAQ: Identifiable {
    let id: String
    let question: String
    let questionAr: String
    let answer: String
    let answerAr: String
}

struct ContactCard: View {
    let icon: String
    let title: String
    let titleAr: String
    let subtitle: String
    let gradient: [Color]
    @EnvironmentObject var languageManager: LanguageManager
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(.white)
            }
            
            var textAlignment: HorizontalAlignment {
                languageManager.currentLanguage == .english ? .leading : .trailing
            }

            VStack(alignment: textAlignment, spacing: 4) {
                Text(languageManager.currentLanguage == .english ? title : titleAr)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
    }
}

#Preview {
    SupportView()
        .environmentObject(LanguageManager())
}
