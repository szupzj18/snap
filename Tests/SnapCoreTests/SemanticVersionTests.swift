import XCTest
@testable import SnapCore

final class SemanticVersionTests: XCTestCase {
    private func v(_ string: String) -> SemanticVersion { SemanticVersion(string)! }

    func testParsesTagsAndShortForms() {
        XCTAssertEqual(v("v0.2.0").numbers, [0, 2, 0])
        XCTAssertEqual(v("1.4").numbers, [1, 4, 0])
        XCTAssertEqual(v("2").description, "2.0.0")
        XCTAssertEqual(v("0.3.0-beta.2").prerelease, "beta.2")
    }

    func testRejectsGarbage() {
        XCTAssertNil(SemanticVersion("latest"))
        XCTAssertNil(SemanticVersion("1.2.3.4"))
        XCTAssertNil(SemanticVersion("1.x"))
        XCTAssertNil(SemanticVersion(""))
    }

    func testOrdering() {
        XCTAssertLessThan(v("0.1.0"), v("0.2.0"))
        XCTAssertLessThan(v("0.9.0"), v("0.10.0"))
        XCTAssertLessThan(v("1.0.0-beta.2"), v("1.0.0"))
        XCTAssertLessThan(v("1.0.0-beta.2"), v("1.0.0-beta.10"))
        XCTAssertEqual(v("v1.2"), v("1.2.0"))
        XCTAssertFalse(v("1.0.0") < v("1.0.0-rc.1"))
    }
}

final class GitHubReleaseTests: XCTestCase {
    func testDecodesLatestRelease() throws {
        let json = #"{"tag_name": "v0.2.0", "html_url": "https://github.com/szupzj18/snap/releases/tag/v0.2.0", "draft": false, "assets": []}"#
        let release = try XCTUnwrap(GitHubRelease.decode(Data(json.utf8)))
        XCTAssertEqual(release.version, SemanticVersion("0.2.0"))
        XCTAssertEqual(release.page.absoluteString, "https://github.com/szupzj18/snap/releases/tag/v0.2.0")
    }

    func testNonVersionTagIsIgnored() throws {
        let json = #"{"tag_name": "nightly", "html_url": "https://example.com"}"#
        XCTAssertNil(try GitHubRelease.decode(Data(json.utf8)))
    }
}
