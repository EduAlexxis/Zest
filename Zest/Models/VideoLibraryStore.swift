import Foundation
import SwiftUI
import Combine

final class VideoLibraryStore: ObservableObject {
    let objectWillChange = PassthroughSubject<Void, Never>()
    
    @AppStorage("videoLibraryItemsJSON") private var libraryItemsData: Data?
    @AppStorage("videoLibraryBookmarksData") private var libraryBookmarksBlob: Data?

    var items: [VideoLibraryItem] {
        get {
            if let data = libraryItemsData,
               let decoded = try? JSONDecoder().decode([VideoLibraryItem].self, from: data) {
                return decoded
            }

            if let oldBlob = libraryBookmarksBlob,
               let oldBookmarks = try? PropertyListDecoder().decode([Data].self, from: oldBlob) {
                let migrated = oldBookmarks.map { VideoLibraryItem(id: UUID(), bookmark: $0, customName: nil, isFavorite: false) }
                if let encoded = try? JSONEncoder().encode(migrated) {
                    DispatchQueue.main.async {
                        self.libraryItemsData = encoded
                        self.libraryBookmarksBlob = nil
                    }
                }
                return migrated
            }
            return []
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                libraryItemsData = encoded
                objectWillChange.send()
            }
        }
    }

    func append(_ data: Data) -> VideoLibraryItem {
        var arr = items
        let newItem = VideoLibraryItem(id: UUID(), bookmark: data, customName: nil, isFavorite: false)
        arr.append(newItem)
        items = arr
        return newItem
    }

    func update(_ item: VideoLibraryItem) {
        var arr = items
        if let idx = arr.firstIndex(where: { $0.id == item.id }) {
            arr[idx] = item
            items = arr
        }
    }

    func remove(id: UUID) {
        var arr = items
        arr.removeAll(where: { $0.id == id })
        items = arr
    }
}
