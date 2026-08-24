//
//  BossWaitlistView.swift
//  SAAYR
//
//  Who's signed up for a boss that hasn't started yet. The list is live: the
//  stream sends the current membership on connect and then pushes each join
//  and leave, so the count moves while the player watches it.
//

import SwiftUI
import Combine

// MARK: - Model

/// One person in the queue, with the moment they joined reconstructed from the
/// payload's `joined_seconds_ago`. Storing the instant rather than the elapsed
/// count is what lets "just now" become "4m ago" while the screen stays open.
struct WaitlistRow: Identifiable {
    let member: WaitlistMember
    let joinedAt: Date

    var id: String { member.id }

    init(member: WaitlistMember, receivedAt: Date = Date()) {
        self.member = member
        self.joinedAt = receivedAt.addingTimeInterval(-TimeInterval(member.joined_seconds_ago))
    }

    func elapsedText(now: Date, isEnglish: Bool) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(joinedAt)))
        switch seconds {
        case ..<60:
            return isEnglish ? "just now" : "الآن"
        case ..<3_600:
            let m = seconds / 60
            return isEnglish ? "\(m)m ago" : "قبل \(m) د"
        case ..<86_400:
            let h = seconds / 3_600
            return isEnglish ? "\(h)h ago" : "قبل \(h) س"
        default:
            let d = seconds / 86_400
            return isEnglish ? "\(d)d ago" : "قبل \(d) ي"
        }
    }
}

@MainActor
final class BossWaitlistModel: ObservableObject {

    @Published var rows: [WaitlistRow] = []
    @Published var total: Int = 0
    @Published var isOnWaitlist: Bool = false
    @Published var isToggling = false
    /// The last failed join, until it's shown. Held as the error rather than a
    /// string because the wording depends on the language the view knows.
    @Published var joinError: BossAPIError?
    /// Set when the stream reports the boss went live — the screen uses it to
    /// hand the player straight to the battle.
    @Published var didGoLive = false
    @Published var isConnected = false

    private let bossID: Int
    private var stream: EventSource?
    /// The REST snapshot is only for the case where the stream never opens.
    /// Requested once, so a flapping connection can't spam it.
    private var didRequestFallback = false

    init(bossID: Int, initiallyJoined: Bool, interestedCount: Int?) {
        self.bossID = bossID
        self.isOnWaitlist = initiallyJoined
        self.total = interestedCount ?? 0
    }

    // MARK: Stream

    func start() {
        guard stream == nil, let source = BossAPI.shared.waitlistStream(bossID: bossID) else { return }

        source.onOpen = { [weak self] in
            self?.isConnected = true
        }

        source.onMessage = { [weak self] message in
            self?.handle(message)
        }

        source.onError = { [weak self] _, willRetry in
            guard let self else { return }
            self.isConnected = false
            // Only fall back to REST if the stream never delivered anything —
            // a mid-session drop will be repaired by the next snapshot.
            if self.rows.isEmpty && !self.didRequestFallback {
                self.didRequestFallback = true
                self.loadFallbackSnapshot()
            }
            _ = willRetry
        }

        stream = source
        source.connect()
    }

    func stop() {
        stream?.close()
        stream = nil
        isConnected = false
    }

    private func handle(_ message: SSEMessage) {
        switch message.event {
        case "snapshot":
            guard let event = message.decode(WaitlistSnapshotEvent.self) else { return }
            total = event.total
            rows = event.members.map { WaitlistRow(member: $0) }
            // The snapshot is authoritative about whether the player is in it.
            if event.members.contains(where: \.is_you) { isOnWaitlist = true }

        case "joined":
            guard let event = message.decode(WaitlistJoinedEvent.self) else { return }
            total = event.total
            let row = WaitlistRow(member: event.member)
            // Newest first, matching where the count is going.
            rows.insert(row, at: 0)
            if event.is_you { isOnWaitlist = true }

        case "left":
            guard let event = message.decode(WaitlistLeftEvent.self) else { return }
            total = event.total
            // The leave event carries only a display name, so remove the
            // oldest match — the one most likely to have been there longest.
            if let index = rows.lastIndex(where: { $0.member.display_name == event.display_name }) {
                rows.remove(at: index)
            }

        case "ended":
            let event = message.decode(WaitlistEndedEvent.self)
            stop()
            if event?.didGoLive == true { didGoLive = true }

        default:
            break
        }
    }

    private func loadFallbackSnapshot() {
        BossAPI.shared.fetchWaitlist(bossID: bossID, page: 1, pageSize: 50) { [weak self] response in
            guard let self, let response else { return }
            self.total = response.total
            self.rows = response.members.map { WaitlistRow(member: $0) }
            if response.members.contains(where: \.is_you) { self.isOnWaitlist = true }
        }
    }

    // MARK: Actions

    /// Join only — there is deliberately no leave path. The button used to
    /// toggle, which meant a second tap silently dropped the player off the
    /// waitlist when they meant to confirm.
    func join() {
        guard !isToggling, !isOnWaitlist else { return }
        isToggling = true
        // Cleared up front so a retry doesn't leave the previous reason on
        // screen next to a request that's still in flight.
        joinError = nil

        BossAPI.shared.toggleWaitlist(bossID: bossID, join: true) { [weak self] result in
            guard let self else { return }
            self.isToggling = false

            switch result {
            case .success(let response):
                self.isOnWaitlist = response.joined
                self.total = response.interested_count
                // The row for the player arrives on the stream; nothing is
                // inserted here, or it would appear twice.
            case .failure(let error):
                // A 400 here is usually a reason, not a fault — "joining opens
                // in 2m 17s" is something the player can act on, so it has to
                // reach them instead of dying in a log line.
                self.joinError = error
            }
        }
    }
}

// MARK: - Screen

struct BossWaitlistView: View {

    let bossName: String
    let startsAt: Date?
    let imageURL: String?
    let isEnglish: Bool
    let onClose: () -> Void
    /// Called when the boss goes live while the player is on this screen.
    let onGoLive: () -> Void

    @StateObject private var model: BossWaitlistModel
    /// Drives the "2m ago" column. A slow tick is enough — the strings only
    /// change once a minute.
    @State private var now = Date()
    /// Set from `model.joinError`; the toast modifier clears it when it goes.
    @State private var toast: ToastContent?
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    init(
        bossID: Int,
        bossName: String,
        startsAt: Date?,
        imageURL: String?,
        initiallyJoined: Bool,
        interestedCount: Int?,
        isEnglish: Bool,
        onClose: @escaping () -> Void,
        onGoLive: @escaping () -> Void
    ) {
        self.bossName = bossName
        self.startsAt = startsAt
        self.imageURL = imageURL
        self.isEnglish = isEnglish
        self.onClose = onClose
        self.onGoLive = onGoLive
        _model = StateObject(wrappedValue: BossWaitlistModel(
            bossID: bossID,
            initiallyJoined: initiallyJoined,
            interestedCount: interestedCount
        ))
    }

    var body: some View {
        ZStack {
            Color(hex: "#0B0E14").ignoresSafeArea()

            VStack(spacing: 0) {
                header
                joinCard
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)
                membersList
            }
        }
        .topToast($toast)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onReceive(clock) { now = $0 }
        .onChange(of: model.didGoLive) { didGoLive in
            if didGoLive { onGoLive() }
        }
        // onReceive rather than onChange: BossAPIError wraps an Error and so
        // can't be Equatable. Formatting happens here because the wording
        // depends on `isEnglish`, which the model doesn't have.
        .onReceive(model.$joinError) { error in
            guard let error else { return }
            toast = .error(error.displayMessage(isEnglish: isEnglish))
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            if let startsAt {
                Text(Self.slot(startsAt, isEnglish: isEnglish))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: "#60A5FA"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(hex: "#60A5FA").opacity(0.15)))
            }

            Text(bossName)
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(BossStyle.textPrimary)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(BossStyle.textDim)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .accessibilityLabel(isEnglish ? "Close" : "إغلاق")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    /// "FRI 8:00 PM" — the slot, not a countdown; the countdown lives on the
    /// card below.
    private static func slot(_ date: Date, isEnglish: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: isEnglish ? "en" : "ar")
        formatter.dateFormat = "EEE h:mm a"
        return formatter.string(from: date).uppercased()
    }

    // MARK: Join card

    private var joinCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                BossAvatar(imageURL: imageURL, size: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(isEnglish ? "Waitlist open" : "قائمة الانتظار مفتوحة")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(BossStyle.textPrimary)

                    Text("\(model.total.formatted()) \(isEnglish ? "joined" : "منضم")")
                        .font(.system(size: 12))
                        .foregroundColor(BossStyle.textDim)
                }

                Spacer(minLength: 0)

                if let startsAt {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(isEnglish ? "starts in" : "يبدأ خلال")
                            .font(.system(size: 9))
                            .foregroundColor(BossStyle.textDim)
                        BossCountdownText(deadline: startsAt)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(BossStyle.ember)
                    }
                }
            }

            Button(action: model.join) {
                HStack(spacing: 6) {
                    if model.isToggling {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "#1A1206")))
                    } else {
                        Text(model.isOnWaitlist
                             ? (isEnglish ? "✓ Joined" : "✓ انضممت")
                             : (isEnglish ? "Join" : "انضم"))
                            .font(.system(size: 14, weight: .bold))
                    }
                }
                .foregroundColor(model.isOnWaitlist ? BossStyle.textPrimary : Color(hex: "#1A1206"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(model.isOnWaitlist ? Color.white.opacity(0.10) : BossStyle.gold)
                )
            }
            .buttonStyle(.plain)
            // Inert once joined: the state is shown, but there's nothing left
            // to tap, so the player can't leave by accident.
            .disabled(model.isToggling || model.isOnWaitlist)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(BossStyle.surface))
    }

    // MARK: Members

    private var membersList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(isEnglish ? "WHO'S IN" : "من انضم")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                Text("— \(model.total.formatted())")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                if !model.isConnected {
                    // Says the list may be behind, without implying failure —
                    // the client reconnects on its own.
                    Text(isEnglish ? "reconnecting…" : "…جارٍ إعادة الاتصال")
                        .font(.system(size: 10))
                        .foregroundColor(BossStyle.textDim)
                }
            }
            .foregroundColor(BossStyle.textDim)
            .padding(.horizontal, 16)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.rows) { row in
                        memberRow(row)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }

    private func memberRow(_ row: WaitlistRow) -> some View {
        let isYou = row.member.is_you

        return HStack(spacing: 10) {
            Text(row.member.initial.uppercased())
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(isYou ? BossStyle.gold : BossStyle.ember))

            VStack(alignment: .leading, spacing: 2) {
                Text(isYou ? (isEnglish ? "You" : "أنت") : row.member.display_name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(BossStyle.textPrimary)
                Text("\(isEnglish ? "Level" : "المستوى") \(row.member.level)")
                    .font(.system(size: 11))
                    .foregroundColor(BossStyle.textDim)
            }

            Spacer(minLength: 0)

            Text(row.elapsedText(now: now, isEnglish: isEnglish))
                .font(.system(size: 11))
                .foregroundColor(BossStyle.textDim)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isYou ? BossStyle.gold.opacity(0.14) : BossStyle.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isYou ? BossStyle.gold.opacity(0.6) : .clear, lineWidth: 1)
        )
    }
}
