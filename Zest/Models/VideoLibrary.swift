import Foundation




struct VideoLibraryItem: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    let bookmark: Data
    var customName: String?
    var isFavorite: Bool
}
