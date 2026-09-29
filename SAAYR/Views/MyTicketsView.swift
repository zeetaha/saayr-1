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
    @State private var filter: TicketFilter = .open

    /// The two tabs a player filters by. Each card still shows its own
    /// status (New / Open / In Progress / Resolved).
    enum TicketFilter: CaseIterable {
        case open, resolved

        func matches(_ status: TicketStatus) -> Bool {
            switch self {
            case .open:     return status != .resolved
            case .resolved: return status == .resolved
            }
        }
    }

    /// Unread replies first, then by last message, newest first.
    private var shownTickets: [Ticket] {
        tickets
            .filter { filter.matches($0.status) }
            .sorted { a, b in
                if a.hasUnread != b.hasUnread { return a.hasUnread }
                return (a.lastActivity ?? .distantPast) > (b.lastActivity ?? .distantPast)
            }
    }

    private func unread(in tab: TicketFilter) -> Int {
        tickets.filter { tab.matches($0.status) && $0.hasUnread }.count
    }

    private func title(for tab: TicketFilter) -> String {
        let english = languageManager.currentLanguage == .english
        let name: String
        switch tab {
        case .open:     name = english ? "Open" : "مفتوحة"
        case .resolved: name = english ? "Resolved" : "محلولة"
        }
        let count = unread(in: tab)
        return count > 0 ? "\(name) (\(count))" : name
    }

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
                            Picker("", selection: $filter) {
                                ForEach(TicketFilter.allCases, id: \.self) { tab in
                                    Text(title(for: tab)).tag(tab)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal)

                            if shownTickets.isEmpty {
                                Text(filter == .open
                                     ? (languageManager.currentLanguage == .english ? "No open tickets" : "لا توجد تذاكر مفتوحة")
                                     : (languageManager.currentLanguage == .english ? "No resolved tickets" : "لا توجد تذاكر محلولة"))
                                    .font(.system(size: 15))
                                    .foregroundColor(.secondary)
                                    .padding(.top, 40)
                            }

                            ForEach(shownTickets) { ticket in
                                Button {
                                    selectedTicket = ticket  // Trigger fullScreenCover
                                    // The detail screen marks it read; clear
                                    // the chip now rather than on the re-fetch.
                                    if let i = tickets.firstIndex(where: { $0.id == ticket.id }) {
                                        tickets[i].unreadCount = 0
                                    }
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
            // Back from a ticket: pick up a reply sent or a status change.
            .onChange(of: selectedTicket) { ticket in
                if ticket == nil { fetchTickets(showSpinner: false) }
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
    
    
    /// Server timestamps come with or without fractional seconds and
    /// sometimes without a zone (treated as UTC).
    func parseServerDate(_ isoDateString: String) -> Date? {
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

        return date
    }

    func formatMessageTime(_ parsedDate: Date) -> String {
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
    func fetchTickets(showSpinner: Bool = true) {
        if showSpinner { isLoading = true }
        // Everything in one page, so the tabs, their unread counts and the
        // sort are worked out over all tickets and not just the first 20.
        let params: [String: Any] = ["page": page, "page_size": 100]
        ServiceModel.shared.getRequest(endpoint: WebService.myTickets, parameters: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let ticketsArray = json["tickets"] as? [[String: Any]] {
                            var loaded: [Ticket] = []

                            for t in ticketsArray {
                                let idVal = t["id"]
                                let idStr = "\(idVal ?? "0")"
                                let subject = t["subject"] as? String ?? ""
                                let description = t["description"] as? String ?? ""

                                // Last message from either side; a ticket with
                                // no replies yet falls back to when it was made.
                                let lastRaw = (t["last_message_at"] as? String) ?? (t["created_at"] as? String) ?? ""
                                let lastActivity = parseServerDate(lastRaw)
                                let timeStr = lastActivity.map(formatMessageTime) ?? lastRaw

                                let status = TicketStatus(server: t["status"] as? String)

                                var unread = t["unread_count"] as? Int ?? 0
                                if unread == 0, t["has_unread"] as? Bool == true { unread = 1 }

                                let ticket = Ticket(id: idStr, title: subject, desc: description, message: description,
                                                    timeAgo: timeStr, status: status,
                                                    unreadCount: unread, lastActivity: lastActivity)
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
                        .font(.system(size: 16, weight: ticket.hasUnread ? .bold : .semibold))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    StatusBadge(status: ticket.status)
                }

                if ticket.hasUnread {
                    HStack(spacing: 5) {
                        Circle().fill(Color.red).frame(width: 7, height: 7)
                        Text(ticket.unreadCount > 1 ? "\(ticket.unreadCount) new replies" : "New reply")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.red.opacity(0.1)))
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
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.red.opacity(ticket.hasUnread ? 0.35 : 0), lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
    }

    func iconBackgroundColor(for status: TicketStatus) -> Color {
        switch status {
        case .new: return Color.purple
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
