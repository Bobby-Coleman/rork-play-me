import SwiftUI
import UIKit

/// SwiftUI bridge for the UIKit-backed chat scroll container. Replaces the
/// previous `ScrollView { LazyVStack { ... } }` so we get production-grade
/// scroll behavior — reliable "stick to bottom" while images/text/reactions
/// settle in, smooth recycling for long threads, and content-offset
/// preservation when prepending older pages — while keeping every bubble
/// rendered by the existing SwiftUI view (`ChatBubbleRow`) via
/// `UIHostingConfiguration`.
///
/// The look of every bubble, song card, quoted reply chip, and "Read"
/// indicator stays in SwiftUI. Only the scroll container, recycling, and
/// pinning behavior moves to UIKit.
struct ChatMessagesCollectionView: UIViewControllerRepresentable {
    let messages: [ChatMessage]
    let currentUID: String
    let friendName: String
    let mostRecentReadMessageId: String?
    let highlightedMessageId: String?
    let showEarlierLoader: Bool
    let isLoadingEarlier: Bool

    let onLongPressMessage: (ChatMessage, CGRect) -> Void
    let onTapSong: (ChatMessage) -> Void
    let onTapArtist: (Song) -> Void
    let onTapQuotedReply: (String) -> Void
    let onReachedTop: () -> Void

    /// Imperative scroll instructions dispatched from SwiftUI state. The
    /// binding is cleared back to nil by the bridge once the action has
    /// been applied so subsequent state changes can re-fire the same
    /// action (e.g. two quoted-reply taps to the same parent).
    @Binding var pendingScrollAction: ChatScrollAction?

    func makeUIViewController(context: Context) -> ChatMessagesViewController {
        let vc = ChatMessagesViewController()
        vc.delegateProxy = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: ChatMessagesViewController, context: Context) {
        context.coordinator.parent = self
        vc.update(
            messages: messages,
            currentUID: currentUID,
            friendName: friendName,
            mostRecentReadMessageId: mostRecentReadMessageId,
            highlightedMessageId: highlightedMessageId,
            showEarlierLoader: showEarlierLoader,
            isLoadingEarlier: isLoadingEarlier
        )
        if let action = pendingScrollAction {
            vc.applyScrollAction(action)
            DispatchQueue.main.async {
                self.pendingScrollAction = nil
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: ChatMessagesViewControllerDelegate {
        var parent: ChatMessagesCollectionView
        init(_ parent: ChatMessagesCollectionView) { self.parent = parent }

        func didLongPressMessage(_ message: ChatMessage, sourceFrame: CGRect) {
            parent.onLongPressMessage(message, sourceFrame)
        }
        func didTapSong(_ message: ChatMessage) { parent.onTapSong(message) }
        func didTapArtist(_ song: Song) { parent.onTapArtist(song) }
        func didTapQuotedReply(parentMessageId: String) { parent.onTapQuotedReply(parentMessageId) }
        func didReachTopOfList() { parent.onReachedTop() }
    }
}

/// Imperative scroll request from SwiftUI to the UIKit controller.
enum ChatScrollAction: Equatable {
    /// Scroll to the newest message at the bottom of the list.
    case toBottom(animated: Bool)
    /// Scroll a specific message into the centered position. Used by the
    /// quoted-reply "jump to parent" interaction.
    case toMessage(id: String, animated: Bool)
}

// MARK: - Controller delegate

protocol ChatMessagesViewControllerDelegate: AnyObject {
    func didLongPressMessage(_ message: ChatMessage, sourceFrame: CGRect)
    func didTapSong(_ message: ChatMessage)
    func didTapArtist(_ song: Song)
    func didTapQuotedReply(parentMessageId: String)
    func didReachTopOfList()
}

// MARK: - Diffable data source types

/// Section identifier. Marked `nonisolated` because this target sets
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which would otherwise
/// make this enum's `Hashable` conformance main-actor-isolated and fail
/// the diffable data source's `Sendable` requirement on its section /
/// item type parameters.
nonisolated enum ChatListSection: Hashable, Sendable { case main }

/// Row identifiers for the diffable data source. The loader row is a
/// constant; message rows are keyed by `ChatMessage.id`. State that
/// changes per render (reactions, "Read" line, highlight ring) is pulled
/// live from the controller's properties at cell-configure time, so we
/// only need ids in the snapshot.
nonisolated enum ChatListItem: Hashable, Sendable {
    case earlierLoader
    case message(String)
}

// MARK: - View Controller

/// UIKit owner of the chat's collection view. Holds the diffable data
/// source, the cell registration, and all of the imperative behavior
/// (sticky-bottom, prepend-preserving offset, async content-size
/// re-pinning) that SwiftUI's ScrollView is unreliable at.
///
/// Cell content is still rendered by SwiftUI via `UIHostingConfiguration`,
/// so the bubble look — gradient, song cards, quoted reply chips, "Read"
/// line — is unchanged from before this refactor.
final class ChatMessagesViewController: UIViewController, UICollectionViewDelegate {
    weak var delegateProxy: ChatMessagesViewControllerDelegate?

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<ChatListSection, ChatListItem>!

    /// Local mirror of the data the SwiftUI parent has handed us. Used by
    /// the cell registration to render each row without taking a strong
    /// dependency on the bridge struct itself.
    private var messagesById: [String: ChatMessage] = [:]
    private var orderedMessageIds: [String] = []
    private var currentUID: String = ""
    private var friendName: String = ""
    private var mostRecentReadMessageId: String?
    private var highlightedMessageId: String?
    private var showEarlierLoader: Bool = false
    private var isLoadingEarlier: Bool = false

    /// True when the bottom of the list is currently in view (within the
    /// stickiness threshold). New messages cause a re-pin to bottom only
    /// while this is true, so a user reading older messages isn't yanked
    /// down by an incoming send/receive.
    private var stickyBottom: Bool = true
    private static let stickyBottomThreshold: CGFloat = 80

    /// Latches once the first non-empty data has been applied. Used to
    /// suppress a redundant "scroll to bottom" before any rows exist.
    private var hasReceivedInitialData: Bool = false

    /// KVO token for `contentSize` so we can re-pin to bottom while async
    /// content (image loads, reaction badges popping in, text shaping)
    /// resolves after the initial layout pass.
    private var contentSizeObservation: NSKeyValueObservation?

    /// Suppresses the next top-of-list trigger after we've just prepended
    /// older content — otherwise scrolling back up after a successful
    /// prepend immediately re-fires the load-earlier callback.
    private var ignoreNextTopReached: Bool = false

    /// Last known bounds height of the collection view. Used to detect
    /// keyboard-show/hide-driven frame changes from the SwiftUI parent
    /// so we can re-pin to bottom while the user is sticky (the
    /// keyboard appearing would otherwise leave the newest message
    /// hidden behind the keyboard until the user manually scrolls).
    private var lastBoundsHeight: CGFloat = 0

    private var messageCellRegistration: UICollectionView.CellRegistration<UICollectionViewCell, String>!
    private var loaderCellRegistration: UICollectionView.CellRegistration<UICollectionViewCell, Bool>!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureCollectionView()
        configureDataSource()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let h = collectionView.bounds.height
        // SwiftUI re-sizes our container when the keyboard appears (or
        // hides) by adjusting the safe area. That doesn't fire the
        // contentSize observer or any scroll delegate, so without this
        // hook a user pinned to the bottom would see their newest
        // message disappear behind the keyboard until they manually
        // scrolled. We only react to height deltas — width changes
        // (rotation) don't require a re-pin.
        if abs(h - lastBoundsHeight) > 0.5 {
            let wasStickyBottom = stickyBottom
            lastBoundsHeight = h
            if wasStickyBottom && hasReceivedInitialData {
                scrollToBottom(animated: false)
            }
        }
    }

    private func configureCollectionView() {
        var listConfig = UICollectionLayoutListConfiguration(appearance: .plain)
        listConfig.backgroundColor = .black
        listConfig.showsSeparators = false
        let layout = UICollectionViewCompositionalLayout.list(using: listConfig)

        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .black
        cv.alwaysBounceVertical = true
        cv.delegate = self
        cv.showsVerticalScrollIndicator = false
        cv.keyboardDismissMode = .interactive
        cv.contentInsetAdjustmentBehavior = .always
        cv.allowsSelection = false
        view.addSubview(cv)
        NSLayoutConstraint.activate([
            cv.topAnchor.constraint(equalTo: view.topAnchor),
            cv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        self.collectionView = cv

        // Watch contentSize so async content (e.g. AsyncImage decoding,
        // a reaction badge popping in, the "Read" line transitioning)
        // re-pins us to the bottom while we're stickyBottom. This is
        // what SwiftUI doesn't have a reliable equivalent for.
        contentSizeObservation = cv.observe(\.contentSize, options: [.old, .new]) { [weak self] cv, change in
            guard let self else { return }
            guard let oldSize = change.oldValue, let newSize = change.newValue else { return }
            // Only react to height growth; width changes during rotation
            // would otherwise trigger spurious bottom-pins.
            guard newSize.height != oldSize.height else { return }
            if self.stickyBottom {
                self.scrollToBottom(animated: false)
            }
        }

        // Tap-to-dismiss-keyboard on background space, mirroring
        // `appKeyboardDismiss()` from the SwiftUI side. Set cancelsTouchesInView
        // to false so taps inside bubbles still register.
        let tapToDismiss = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap))
        tapToDismiss.cancelsTouchesInView = false
        cv.addGestureRecognizer(tapToDismiss)
    }

    private func configureDataSource() {
        messageCellRegistration = UICollectionView.CellRegistration<UICollectionViewCell, String> { [weak self] cell, _, messageId in
            guard let self else { return }
            guard let message = self.messagesById[messageId] else {
                cell.contentConfiguration = nil
                return
            }
            let isMe = message.senderId == self.currentUID
            let isMostRecentRead = (message.id == self.mostRecentReadMessageId)
            let isHighlighted = (message.id == self.highlightedMessageId)
            cell.backgroundConfiguration = .clear()

            cell.contentConfiguration = UIHostingConfiguration {
                ChatBubbleRow(
                    message: message,
                    isMe: isMe,
                    isHighlighted: isHighlighted,
                    isMostRecentRead: isMostRecentRead,
                    currentUID: self.currentUID,
                    friendName: self.friendName,
                    onTapSong: { [weak self] message in self?.delegateProxy?.didTapSong(message) },
                    onTapArtist: { [weak self] song in self?.delegateProxy?.didTapArtist(song) },
                    onTapQuotedReply: { [weak self] parentId in self?.delegateProxy?.didTapQuotedReply(parentMessageId: parentId) },
                    onLongPress: { [weak self] frameInWindow in
                        self?.delegateProxy?.didLongPressMessage(message, sourceFrame: frameInWindow)
                    }
                )
            }
            .margins(.horizontal, 16)
            .margins(.vertical, 4)
        }

        loaderCellRegistration = UICollectionView.CellRegistration<UICollectionViewCell, Bool> { cell, _, isLoading in
            cell.backgroundConfiguration = .clear()
            cell.contentConfiguration = UIHostingConfiguration {
                ChatEarlierLoaderRow(isLoading: isLoading)
            }
            .margins(.all, 0)
        }

        dataSource = UICollectionViewDiffableDataSource<ChatListSection, ChatListItem>(
            collectionView: collectionView
        ) { [weak self] cv, indexPath, item in
            guard let self else { return UICollectionViewCell() }
            switch item {
            case .earlierLoader:
                return cv.dequeueConfiguredReusableCell(using: self.loaderCellRegistration, for: indexPath, item: self.isLoadingEarlier)
            case .message(let id):
                return cv.dequeueConfiguredReusableCell(using: self.messageCellRegistration, for: indexPath, item: id)
            }
        }
    }

    // MARK: - Update from SwiftUI

    func update(
        messages: [ChatMessage],
        currentUID: String,
        friendName: String,
        mostRecentReadMessageId: String?,
        highlightedMessageId: String?,
        showEarlierLoader: Bool,
        isLoadingEarlier: Bool
    ) {
        let previousFirstMessageId = self.orderedMessageIds.first
        let previousReadId = self.mostRecentReadMessageId
        let previousHighlightId = self.highlightedMessageId
        let previousMessages = self.messagesById
        let previousLoaderVisible = self.showEarlierLoader
        let previousIsLoadingEarlier = self.isLoadingEarlier

        self.currentUID = currentUID
        self.friendName = friendName
        self.mostRecentReadMessageId = mostRecentReadMessageId
        self.highlightedMessageId = highlightedMessageId
        self.showEarlierLoader = showEarlierLoader
        self.isLoadingEarlier = isLoadingEarlier

        var byId: [String: ChatMessage] = [:]
        var ordered: [String] = []
        for m in messages {
            byId[m.id] = m
            ordered.append(m.id)
        }
        self.messagesById = byId
        self.orderedMessageIds = ordered

        // Detect prepend (older pages just landed). We anchor the
        // previously-topmost visible message back to the top after the
        // snapshot applies so the user's reading position doesn't
        // jump when older content lands above.
        let didPrepend: Bool
        if let prevFirst = previousFirstMessageId,
           let newIndexOfPrev = ordered.firstIndex(of: prevFirst),
           newIndexOfPrev > 0 {
            didPrepend = true
        } else {
            didPrepend = false
        }
        let pivotForPrepend: String? = didPrepend ? previousFirstMessageId : nil

        var snapshot = NSDiffableDataSourceSnapshot<ChatListSection, ChatListItem>()
        snapshot.appendSections([.main])
        if showEarlierLoader {
            snapshot.appendItems([.earlierLoader], toSection: .main)
        }
        snapshot.appendItems(ordered.map { .message($0) }, toSection: .main)

        // Reconfigure rows whose visible state has changed even if the
        // message id list is identical. Without this, edits to
        // reactions, the "Read" indicator moving forward, or the
        // highlight ring lighting up after a quoted-reply tap wouldn't
        // re-render in the affected cell.
        var idsNeedingReconfigure: [ChatListItem] = []
        for id in ordered {
            let prevMsg = previousMessages[id]
            let newMsg = byId[id]
            if prevMsg != newMsg {
                idsNeedingReconfigure.append(.message(id))
                continue
            }
            // The "Read" line moves under different ids over time.
            let wasRead = (previousReadId == id)
            let isRead = (mostRecentReadMessageId == id)
            if wasRead != isRead {
                idsNeedingReconfigure.append(.message(id))
                continue
            }
            // Quoted-reply tap briefly highlights the parent bubble.
            let wasHighlight = (previousHighlightId == id)
            let isHighlight = (highlightedMessageId == id)
            if wasHighlight != isHighlight {
                idsNeedingReconfigure.append(.message(id))
                continue
            }
        }
        if !idsNeedingReconfigure.isEmpty {
            snapshot.reconfigureItems(idsNeedingReconfigure)
        }
        if showEarlierLoader && (!previousLoaderVisible || previousIsLoadingEarlier != isLoadingEarlier) {
            snapshot.reconfigureItems([.earlierLoader])
        }

        // Detect a fresh append at the bottom — only this case should
        // auto-scroll to bottom, and only if we were already sticky.
        let lastNewId = ordered.last
        let lastPrevId = previousMessages.isEmpty ? nil : self.lastOrderedId(from: previousMessages)
        let didAppend = lastNewId != nil && lastNewId != lastPrevId && previousMessages[lastNewId ?? ""] == nil

        // First non-empty snapshot is a "scroll to bottom" no matter
        // what — we want to land on the newest message.
        let isFirstNonEmpty = !hasReceivedInitialData && !ordered.isEmpty
        if !ordered.isEmpty { hasReceivedInitialData = true }

        let shouldPinToBottomAfter = isFirstNonEmpty || (didAppend && stickyBottom)

        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self else { return }
            if let pivot = pivotForPrepend {
                self.ignoreNextTopReached = true
                self.scrollMessageToTop(id: pivot, animated: false)
            } else if shouldPinToBottomAfter {
                self.scrollToBottom(animated: false)
            }
        }
    }

    private func lastOrderedId(from byId: [String: ChatMessage]) -> String? {
        byId.values.sorted { $0.timestamp < $1.timestamp }.last?.id
    }

    // MARK: - Imperative scrolling

    func applyScrollAction(_ action: ChatScrollAction) {
        switch action {
        case .toBottom(let animated):
            scrollToBottom(animated: animated)
            stickyBottom = true
        case .toMessage(let id, let animated):
            scrollMessageToCenter(id: id, animated: animated)
        }
    }

    private func scrollToBottom(animated: Bool) {
        guard let lastId = orderedMessageIds.last else { return }
        guard let indexPath = dataSource.indexPath(for: .message(lastId)) else { return }
        collectionView.scrollToItem(at: indexPath, at: .bottom, animated: animated)
    }

    private func scrollMessageToCenter(id: String, animated: Bool) {
        guard let indexPath = dataSource.indexPath(for: .message(id)) else { return }
        collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: animated)
    }

    private func scrollMessageToTop(id: String, animated: Bool) {
        guard let indexPath = dataSource.indexPath(for: .message(id)) else { return }
        collectionView.scrollToItem(at: indexPath, at: .top, animated: animated)
    }

    // MARK: - UICollectionViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        recomputeStickyBottom()
        checkTopReached()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // Reset the prepend-suppression latch the moment the user
        // actively pulls the scroll, so subsequent organic top-reaches
        // page in further history.
        ignoreNextTopReached = false
    }

    private func recomputeStickyBottom() {
        let offset = collectionView.contentOffset.y
        let contentH = collectionView.contentSize.height
        let frameH = collectionView.bounds.height
        let bottomInset = collectionView.adjustedContentInset.bottom
        guard contentH > 0 else { stickyBottom = true; return }
        let distanceFromBottom = (contentH - offset) - frameH + bottomInset
        stickyBottom = distanceFromBottom <= Self.stickyBottomThreshold
    }

    private func checkTopReached() {
        guard showEarlierLoader, !ignoreNextTopReached else { return }
        let offset = collectionView.contentOffset.y
        let topInset = collectionView.adjustedContentInset.top
        if offset <= -topInset + 40 {
            delegateProxy?.didReachTopOfList()
        }
    }

    @objc private func handleBackgroundTap(_ recognizer: UITapGestureRecognizer) {
        let location = recognizer.location(in: collectionView)
        if collectionView.indexPathForItem(at: location) == nil {
            UIApplication.pm_dismissKeyboard()
        }
    }

    deinit {
        contentSizeObservation?.invalidate()
    }
}

// MARK: - Earlier-page loader row (SwiftUI)

/// Top-of-list "Loading earlier…" sentinel. Identical visually to the
/// previous SwiftUI implementation so the transition to UIKit container
/// is invisible to the user.
private struct ChatEarlierLoaderRow: View {
    let isLoading: Bool
    var body: some View {
        HStack {
            Spacer()
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.4))
            }
            Spacer()
        }
        .frame(height: 28)
        .padding(.horizontal, 16)
    }
}
