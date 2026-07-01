import Foundation

struct GitHubRelease: Codable, Identifiable {
    let id: Int
    let tagName: String
    let name: String?
    let body: String?
    let htmlUrl: String
    let publishedAt: String
    let prerelease: Bool
    let draft: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case publishedAt = "published_at"
        case prerelease
        case draft
    }
}

final class UpdateChecker {
    static let shared = UpdateChecker()
    private init() {}

    private let releasesURL = URL(string: "https://api.github.com/repos/EduAlexxis/Zest/releases")!

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    func fetchReleases(completion: @escaping (Result<[GitHubRelease], Error>) -> Void) {
        URLSession.shared.dataTask(with: releasesURL) { data, _, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data else {
                DispatchQueue.main.async { completion(.failure(URLError(.badServerResponse))) }
                return
            }
            do {
                let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
                DispatchQueue.main.async { completion(.success(releases.filter { !$0.draft })) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }

    func isNewer(_ remote: String, than local: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(separator: ".").compactMap { Int($0) }
        }
        let remoteParts = parts(remote)
        let localParts = parts(local)
        for i in 0..<max(remoteParts.count, localParts.count) {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r != l { return r > l }
        }
        return false
    }
}
