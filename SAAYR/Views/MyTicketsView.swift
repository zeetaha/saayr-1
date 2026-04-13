//
//  MyTicketsView.swift
//  SAAYR
//
//  Created by Awais Raza on 08/02/2026.
//

import SwiftUI

struct MyTicketsView: View {
    @EnvironmentObject var languageManager: LanguageManager
    @Environment(\.dismiss) var dismiss

    @State private var tickets: [Ticket] = [
        // will be loaded from API
    ]
    
    @State private var selectedTicket: Ticket? = nil  // For fullScreenCover
    @State private var isLoading: Bool = false
    @State private var page: Int = 1
    @State private var showSubmitTicket: Bool = false

    var body: some View {
        NavigationView{
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 18) {
                        Text("My Support Tickets")
                            .font(.system(size: 28, weight: .bold))
                            .padding(.top, 20)
                        
                        if isLoading {
                            ProgressView()
                                .padding()
                        } else if tickets.isEmpty {
                            VStack(spacing: 20) {
                                Image(systemName: "ticket.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(Color.purple)
                                    .padding(.top, 40)

                                Text("No tickets yet")
                                    .font(.system(size: 22, weight: .semibold))
                                    .multilineTextAlignment(.center)

                                Text("You don’t have any support requests yet. Submit a ticket and our team will help you with any issue.")
                                    .font(.system(size: 15))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 30)

                                Button(action: { showSubmitTicket = true }) {
                                    Text("Submit a Ticket")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                        .background(Color.purple)
                                        .cornerRadius(14)
                                }
                                .padding(.horizontal, 40)
                            }
                            .padding(.vertical, 40)
                        } else {
                            ForEach(tickets) { ticket in
                                Button {
                                    selectedTicket = ticket  // Trigger fullScreenCover
                                } label: {
                                    TicketCard(ticket: ticket)
                                        .padding(.horizontal)
                                }
                            }
                        }
                        
                    }
                }
            }
            
            .navigationTitle("My Tickets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(
                            systemName: languageManager.currentLanguage == .english
                            ? "chevron.left"
                            : "chevron.right"
                        )
                        .font(.system(size: 17, weight: .semibold))
                    }
                }
            }
            // Full screen presentation for ticket details
            .fullScreenCover(item: $selectedTicket) { ticket in
                TicketDetailView(ticket: ticket)
                    .environmentObject(languageManager)
            }
            .fullScreenCover(isPresented: $showSubmitTicket) {
                SubmitTicketView()
                    .environmentObject(languageManager)
            }
            .onChange(of: showSubmitTicket) { isPresented in
                if !isPresented {
                    fetchTickets()
                }
            }
            .onAppear {
                fetchTickets()
            }
        }
        .environment(
            \.layoutDirection,
            languageManager.currentLanguage == .arabic ? .rightToLeft : .leftToRight
        )
    }
    
    
    func formatMessageTime(_ isoDateString: String) -> String {
        var date: Date?

        // 1️⃣ Try ISO8601 (fractional seconds optional)
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        isoFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        date = isoFormatter.date(from: isoDateString)

        if date == nil {
            // fallback without fractional seconds
            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            fallback.timeZone = TimeZone(secondsFromGMT: 0)
            date = fallback.date(from: isoDateString)
        }

        if date == nil {
            // fallback for timezone-less ISO string
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            fmt.timeZone = TimeZone(secondsFromGMT: 0) // treat as UTC
            date = fmt.date(from: isoDateString)
        }

        guard let parsedDate = date else {
            return isoDateString
        }

        let now = Date()
        let diff = now.timeIntervalSince(parsedDate)

        if diff >= 0 && diff < 3600 {
            // Less than 1 hour ago
            let minutes = Int(diff / 60)
            return minutes <= 1 ? "now" : "\(minutes) min ago"
        } else if diff < 0 {
            // Future timestamp: show as full date
            let fmt = DateFormatter()
            fmt.dateFormat = "d MMM h:mm a"
            fmt.locale = Locale(identifier: "en_US_POSIX")
            return fmt.string(from: parsedDate)
        } else {
            // Older than 1 hour: show full date
            let fmt = DateFormatter()
            fmt.dateFormat = "d MMM h:mm a"
            fmt.locale = Locale(identifier: "en_US_POSIX")
            return fmt.string(from: parsedDate)
        }
    }
    func fetchTickets() {
        isLoading = true
        let params: [String: Any] = ["page": page, "page_size": 20]
        ServiceModel.shared.getRequest(endpoint: WebService.myTickets, parameters: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let ticketsArray = json["tickets"] as? [[String: Any]] {
                            var loaded: [Ticket] = []
                            let iso = ISO8601DateFormatter()
                            let out = DateFormatter()
                            out.dateFormat = "MMM dd, HH:mm"

                            for t in ticketsArray {
                                let idVal = t["id"]
                                let idStr = "\(idVal ?? "0")"
                                let subject = t["subject"] as? String ?? ""
                                let description = t["description"] as? String ?? ""
                                let statusStr = (t["status"] as? String ?? "open").lowercased()
                                let createdAt = t["created_at"] as? String ?? ""
                                var timeStr = createdAt
                                timeStr = formatMessageTime(timeStr)

                                let status: TicketStatus
                                if statusStr.contains("resolve") { status = .resolved }
                                else if statusStr.contains("progress") || statusStr.contains("in_progress") { status = .inProgress }
                                else { status = .open }

                                let ticket = Ticket(id: idStr, title: subject, desc: description, message: description, timeAgo: timeStr, status: status)
                                loaded.append(ticket)
                            }
                            tickets = loaded
                        }
                    } catch {
                        print("Parsing error:", error.localizedDescription)
                    }
                case .failure(let error):
                    print("API error:", error.localizedDescription)
                }
            }
        }
    }
}

struct TicketCard: View {
    let ticket: Ticket
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconBackgroundColor(for: ticket.status))
                    .frame(width: 48, height: 48)
                Image(systemName: ticket.status == .resolved ? "checkmark" : "exclamationmark.triangle")
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(ticket.title)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    StatusBadge(status: ticket.status)
                }
                
                Text(ticket.message)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                
                Text(ticket.timeAgo)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(UIColor.systemBackground)))
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
    }

    func iconBackgroundColor(for status: TicketStatus) -> Color {
        switch status {
        case .inProgress: return Color.orange
        case .resolved: return Color.green
        case .open: return Color.blue
        }
    }
}

#Preview {
    MyTicketsView()
        .environmentObject(LanguageManager())
}
