import Foundation

/// The parts of GitHub's "latest release" API response that matter for update checks.
public struct GitHubRelease: Equatable {
    public let version: SemanticVersion
    public let page: URL

    /// Decodes `GET /repos/{owner}/{repo}/releases/latest`. Nil if the tag isn't a version.
    public static func decode(_ data: Data) throws -> GitHubRelease? {
        struct Payload: Decodable {
            let tag_name: String
            let html_url: URL
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return SemanticVersion(payload.tag_name).map { GitHubRelease(version: $0, page: payload.html_url) }
    }
}
