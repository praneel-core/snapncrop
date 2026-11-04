import Foundation

/// Last few screenshots, kept in memory only (cleared when the app quits) so the menu can
/// offer "click to copy again". Same idea as the recent-dictations list in talk-to-me-man.
final class RecentCaptures {
    struct Item { let date: Date; let png: Data; let width: Int; let height: Int; let savedAs: URL? }

    static let shared = RecentCaptures()
    private(set) var items: [Item] = []      // newest first
    private let limit = 5

    func add(png: Data, width: Int, height: Int, savedAs: URL?) {
        items.insert(Item(date: Date(), png: png, width: width, height: height, savedAs: savedAs), at: 0)
        if items.count > limit { items.removeLast(items.count - limit) }
    }
}
