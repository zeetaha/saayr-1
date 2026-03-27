//
//  TicketDetailView.swift
//  SAAYR
//
//  Created by Awais Raza on 08/02/2026.
//


import SwiftUI
import Kingfisher


struct TicketDetailView: View {
    let ticket: Ticket
    @EnvironmentObject var languageManager: LanguageManager
    @Environment(\.dismiss) var dismiss
    
    @State private var messages: [MessageItem]
    @State private var inputText = ""
    @State private var isLoading: Bool = false
    @State private var headerTime: String
    @State private var ticketImages: [String] = []
    @State private var selectedImageURL: URL?
    @State private var showingFullImage: Bool = false
    @State private var pollingTask: Task<Void, Never>? = nil
    

    init(ticket: Ticket) {
        self.ticket = ticket
        _messages = State(initialValue: [
            MessageItem(text: ticket.message, isUser: true, time: ticket.timeAgo),
        ])
        _headerTime = State(initialValue: ticket.timeAgo)
    }

    var body: some View {
        NavigationView{
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 12) {
                    if isLoading {
                        ProgressView()
                            .padding()
                    }

                    messagesView
                    inputBar
                }
            }
            
            .navigationTitle("Ticket Details")
            .navigationBarTitleDisplayMode(.large)
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
        }
        .onAppear {
            fetchTicketDetails()
            startPolling()
        }
        .onDisappear {
            stopPolling()
        }
        .environment(
            \.layoutDirection,
            languageManager.currentLanguage == .arabic ? .rightToLeft : .leftToRight
        )
    }

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    headerCard

                    ForEach(messages) { msg in
                        MessageBubble(msg: msg)
                            .id(msg.id)
                    }
                }
                .padding(.top, 10)
            }
            .onChange(of: messages.count) { _ in
                if let last = messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ticket.title)
                .font(.system(size: 20, weight: .bold))
            
            Text(ticket.desc)
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            // Ticket images
            if !ticketImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ticketImages, id: \.self) { img in
                            if let url = fullImageUrl(from: img) {
                                KFImage.url(url)
                                    .placeholder {
                                        ProgressView()
                                            .frame(width: 120, height: 80)
                                    }
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 80)
                                    .clipped()
                                    .cornerRadius(8)
                                    .onTapGesture {
                                        selectedImageURL = url
                                        showingFullImage = true
                                    }
                            }
                        }
                    }
                }
            }

            Text("Created: \(headerTime)")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(UIColor.systemBackground))
        )
        .sheet(isPresented: $showingFullImage) {
            if let url = selectedImageURL {
                FullScreenImageView(url: url)
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Type your message...", text: $inputText)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(UIColor.systemBackground))
                )

            Button(action: sendMessage) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.8), Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "arrow.up")
                            .foregroundColor(.white)
                    )
            }
        }
        .padding()
    }

    func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // optimistic UI update
        messages.append(
            MessageItem(text: trimmed, isUser: true, time: currentTime())
        )
        inputText = ""

        // send reply to API
        let endpoint = WebService.myTickets + "/\(ticket.id)/reply"
        let params: [String: Any] = [
            "message": trimmed,
            "image_url": ""
        ]

        ServiceModel.shared.postRequest(endpoint: endpoint, parameters: params) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(_):
                    // refresh details to get authoritative messages from server
                    fetchTicketDetails()
                case .failure(let error):
                    print("Reply API error:", error.localizedDescription)
                }
            }
        }
    }

    func currentTime() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
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


    // Fetch ticket details and messages from API
    func fetchTicketDetails() {
        isLoading = true
        let endpoint = WebService.myTickets + "/\(ticket.id)"
        ServiceModel.shared.getRequest(endpoint: endpoint) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            if let created = json["created_at"] as? String {
                                    headerTime = formatMessageTime(created)
                                } else {
                                    headerTime = ""
                                }
                            

                            // Top-level ticket images
                            if let imagesArray = json["images"] as? [[String: Any]] {
                                var topImgs: [String] = []
                                for i in imagesArray {
                                    if let url = i["image_url"] as? String {
                                        topImgs.append(url)
                                    }
                                }
                                ticketImages = topImgs
                            }

                            if let messagesArray = json["messages"] as? [[String: Any]] {
                                var loaded: [MessageItem] = []

                                for m in messagesArray {
                                    // 1️⃣ Message text
                                    let text = (m["message"] as? String) ?? ""

                                    // 2️⃣ Determine if message is from current user
                                    let isUser: Bool
                                    if let senderType = m["sender_type"] as? String {
                                        isUser = senderType.lowercased() == "user"
                                    } else {
                                        isUser = false
                                    }

                                    // 3️⃣ Format message time
                                    var timeText = ""
                                    if let createdAt = m["created_at"] as? String {
                                        timeText = formatMessageTime(createdAt)
                                    }

                                    // 4️⃣ Extract message images if any
                                    var msgImgs: [String] = []
                                    if let imgs = m["images"] as? [[String: Any]] {
                                        for im in imgs {
                                            if let url = im["image_url"] as? String {
                                                msgImgs.append(url)
                                            }
                                        }
                                    }

                                    // 5️⃣ Append to array
                                    loaded.append(MessageItem(text: text, isUser: isUser, time: timeText, images: msgImgs))
                                }

                                messages = loaded
                            }

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

    // Start polling ticket details periodically (every 5 seconds)
    private func startPolling(intervalSeconds: UInt64 = 5) {
        stopPolling()
        pollingTask = Task {
            let nanos = intervalSeconds * 1_000_000_000
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: nanos)
                } catch {
                    break
                }

                if Task.isCancelled { break }

                await MainActor.run {
                    fetchTicketDetails()
                }
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}



#Preview {
    TicketDetailView(
        ticket: Ticket(
            id: "1",
            title: "Check-in Issue", desc: "description",
            message: "I couldn't check in at the venue.",
            timeAgo: "10 min ago",
            status: .open
        )
    )
    .environmentObject(LanguageManager())
}
