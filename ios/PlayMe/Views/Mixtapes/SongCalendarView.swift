import SwiftUI

/// Locket-style calendar of songs, one cell per day. Defaults to "You"
/// (every song you sent, by the day you sent it); a scope selector lets
/// you switch to a friend to see every song they sent you. Tapping a day
/// opens a full-screen carousel of that day's songs.
///
/// Layout:
///   * Fixed top bar: scope selector + global streak / unique-song pills.
///   * Scrollable calendar: a "first song" banner pinned at the very top
///     (reachable by scrolling up), then month sections ascending so the
///     newest month sits at the bottom — where the view auto-scrolls on
///     appear, mirroring Locket.
struct SongCalendarView: View {
    @Bindable var appState: AppState
    /// Parent owns the day carousel presentation, so a day tap hands the
    /// day's song groups up (sender, note, and recipients travel with
    /// each song).
    var onOpenDay: ([DaySongGroup]) -> Void
    /// Opens the search/send sheet when the user taps the "+" on today.
    var onSendSong: () -> Void

    /// `nil` = "You" scope (songs you sent). Otherwise a friend's id
    /// (songs that friend sent you).
    @State private var selectedFriendId: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let weekdaySymbols = ["S", "M", "T", "W", "T", "F", "S"]
    private static let bottomAnchorId = "calendar-bottom"

    /// Local day key for "today", used to mark the current cell with the
    /// glowing send affordance.
    private var todayString: String { AppState.localDayString(for: Date()) }

    var body: some View {
        VStack(spacing: 0) {
            scopeSelector
            weekdayHeader
            calendarScroll
            statsFooter
        }
        .task {
            await appState.loadCalendarHistory()
        }
    }

    // MARK: - Derived data

    private var songsByDay: [String: [DaySongGroup]] {
        appState.calendarSongsByDay(friendId: selectedFriendId)
    }

    private var selectedFriend: AppUser? {
        guard let id = selectedFriendId else { return nil }
        return appState.friends.first(where: { $0.id == id })
            ?? appState.calendarReceivedShares.first(where: { $0.sender.id == id })?.sender
    }

    private var scopeTitle: String {
        guard let friend = selectedFriend else { return "You" }
        return friend.firstName.isEmpty ? "@\(friend.username)" : friend.firstName
    }

    /// Earliest day (in the active scope) that has a song, used as the
    /// first month of the calendar.
    private var earliestDate: Date? {
        let dates = songsByDay.values.flatMap { $0 }.flatMap(\.shares).map(\.timestamp)
        return dates.min()
    }

    // MARK: - Scope selector (centered)

    private var scopeSelector: some View {
        Menu {
            Picker("Scope", selection: $selectedFriendId) {
                Text("You").tag(String?.none)
                ForEach(appState.friends) { friend in
                    Text(friend.firstName.isEmpty ? "@\(friend.username)" : friend.firstName)
                        .tag(Optional(friend.id))
                }
            }
        } label: {
            HStack(spacing: 7) {
                Text(scopeTitle)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            // Keep the label at its intrinsic width so the name never gets
            // momentarily compressed/clipped while the tab/selection
            // re-lays out around it. Suppress the implicit resize animation
            // too, otherwise the title visibly clips mid-resize when the
            // selected person changes, then snaps to the correct width.
            .fixedSize(horizontal: true, vertical: false)
            .transaction { $0.animation = nil }
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.10))
                    .overlay(
                        Capsule().stroke(AppAccentGradient.button.opacity(0.5), lineWidth: 1)
                    )
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    // MARK: - Stats footer (centered, bottom)

    private var statsFooter: some View {
        HStack(spacing: 10) {
            statPill(
                icon: "music.note",
                text: appState.uniqueSongsSentCount == 1 ? "1 song" : "\(appState.uniqueSongsSentCount) songs"
            )
            statPill(
                icon: "flame.fill",
                text: "\(appState.effectiveSendDayStreak)d streak"
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private func statPill(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppAccentGradient.button)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    // MARK: - Calendar scroll

    @ViewBuilder
    private var calendarScroll: some View {
        if appState.isLoadingCalendarHistory && !appState.didLoadCalendarHistory {
            VStack {
                Spacer()
                ProgressView().tint(.white)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if earliestDate == nil {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 24) {
                        firstSongBanner
                        ForEach(months, id: \.key) { month in
                            monthSection(month)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomAnchorId)
                    }
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
                .refreshable { await appState.loadCalendarHistory(force: true) }
                .onAppear {
                    // Land on the newest month, matching Locket. Scrolling
                    // up from here reveals older months and the first-song
                    // banner.
                    DispatchQueue.main.async {
                        proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "calendar")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.15))
            Text(selectedFriendId == nil ? "No songs sent yet" : "No songs from \(scopeTitle) yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
            Text(selectedFriendId == nil
                 ? "Send a song to start your calendar"
                 : "When they send you songs, they'll show up here")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.25))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity)
    }

    private var firstSongBanner: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 18))
                .foregroundStyle(AppAccentGradient.button)
            if let earliest = earliestDate {
                Text(selectedFriendId == nil
                     ? "Your first song was sent on"
                     : "First song from \(scopeTitle) on")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                Text(Self.bannerDateFormatter.string(from: earliest))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            if selectedFriendId == nil, let top = appState.topPersonBetween() {
                let name = top.friend.firstName.isEmpty ? "@\(top.friend.username)" : top.friend.firstName
                Text("Top person: \(name) · \(top.total) song\(top.total == 1 ? "" : "s") between you")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    // MARK: - Month sections

    private struct MonthBucket: Identifiable {
        let key: String
        let title: String
        let leadingBlanks: Int
        let days: [DayCell]
        var id: String { key }
    }

    private struct DayCell: Identifiable {
        let dayNumber: Int
        let dayString: String
        /// Unique songs that day (each group may carry multiple shares
        /// when the same song went to several people).
        let songs: [DaySongGroup]
        var id: String { dayString }
    }

    /// All months from the earliest song month through the current month,
    /// ascending.
    private var months: [MonthBucket] {
        guard let earliest = earliestDate else { return [] }
        let cal = Calendar.current
        let byDay = songsByDay

        let startComps = cal.dateComponents([.year, .month], from: earliest)
        guard let startMonth = cal.date(from: startComps) else { return [] }
        let now = Date()

        var buckets: [MonthBucket] = []
        var cursor = startMonth
        var guardCounter = 0
        while cursor <= now && guardCounter < 600 {
            guardCounter += 1
            let comps = cal.dateComponents([.year, .month], from: cursor)
            guard let firstOfMonth = cal.date(from: comps),
                  let range = cal.range(of: .day, in: .month, for: cursor) else {
                break
            }
            let firstWeekday = cal.component(.weekday, from: firstOfMonth)
            let leadingBlanks = (firstWeekday - cal.firstWeekday + 7) % 7

            var days: [DayCell] = []
            for day in range {
                var dc = comps
                dc.day = day
                guard let date = cal.date(from: dc) else { continue }
                let dayString = AppState.localDayString(for: date)
                days.append(DayCell(dayNumber: day, dayString: dayString, songs: byDay[dayString] ?? []))
            }

            buckets.append(MonthBucket(
                key: "\(comps.year ?? 0)-\(comps.month ?? 0)",
                title: Self.monthTitleFormatter.string(from: firstOfMonth),
                leadingBlanks: leadingBlanks,
                days: days
            ))

            guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return buckets
    }

    private func monthSection(_ month: MonthBucket) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(month.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<month.leadingBlanks, id: \.self) { idx in
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .id("blank-\(month.key)-\(idx)")
                }
                ForEach(month.days) { day in
                    dayCell(day)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// An empty current day in the "You" scope gets a glowing "+" to send a
    /// song right now. Once a song has landed today the "+" disappears and
    /// the cell behaves like any other day (artwork opens the carousel).
    /// (Friend scopes show their sends only, so no send affordance.)
    private func showsSendButton(_ day: DayCell) -> Bool {
        selectedFriendId == nil && day.dayString == todayString && day.songs.isEmpty
    }

    @ViewBuilder
    private func dayCell(_ day: DayCell) -> some View {
        if showsSendButton(day) {
            todaySendCell(day)
        } else if day.songs.isEmpty {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    Text("\(day.dayNumber)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.2))
                        .padding(4)
                }
        } else {
            Button {
                openDay(day)
            } label: {
                ZStack {
                    // Stacked offset cards behind the front art hint at
                    // multiple songs that day (Locket-style).
                    if day.songs.count > 2 {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.12))
                            .aspectRatio(1, contentMode: .fit)
                            .scaleEffect(0.86)
                            .offset(x: 5, y: -5)
                    }
                    if day.songs.count > 1 {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.18))
                            .aspectRatio(1, contentMode: .fit)
                            .scaleEffect(0.93)
                            .offset(x: 3, y: -3)
                    }
                    AlbumArtSquare(
                        url: day.songs.first?.song.albumArtURL,
                        cornerRadius: 8,
                        showsPlaceholderProgress: false,
                        showsShadow: false,
                        targetDecodeSide: 60
                    )
                    if day.songs.count > 1 {
                        Text("\(day.songs.count)")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.6)))
                            .padding(4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                }
                // AlbumArtSquare is a `Color.clear` with a
                // non-hit-testable image overlay, so a single-song day
                // (no stacked backing rectangles) has no tappable pixels
                // without an explicit content shape.
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Today's empty cell in "You" scope: a glowing gradient "+" to send a
    /// song now. Only used while today has no songs (see `showsSendButton`).
    private func todaySendCell(_ day: DayCell) -> some View {
        Button {
            onSendSong()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.06))
                GlowingPlusBadge(size: 26, glow: 12)
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Send a song today")
    }

    private func openDay(_ day: DayCell) {
        guard !day.songs.isEmpty else { return }
        if let first = day.songs.first?.song {
            AudioPlayerService.shared.play(song: first)
        }
        onOpenDay(day.songs)
    }

    // MARK: - Formatters

    private static let bannerDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        return f
    }()

    private static let monthTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f
    }()
}

/// Pulsing gradient "+" used to mark today on the calendar as a one-tap
/// send affordance — Locket's glowing add button, recolored to RIFF's
/// lilac → pink → peach palette instead of yellow.
private struct GlowingPlusBadge: View {
    var size: CGFloat = 26
    var glow: CGFloat = 12
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(AppAccentGradient.button)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "plus")
                    .font(.system(size: size * 0.55, weight: .heavy))
                    .foregroundStyle(.black.opacity(0.75))
            )
            .shadow(color: AppAccentGradient.pink.opacity(0.9), radius: pulse ? glow : glow * 0.5)
            .shadow(color: AppAccentGradient.lilac.opacity(0.8), radius: pulse ? glow * 1.6 : glow * 0.85)
            .scaleEffect(pulse ? 1.08 : 0.95)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}
