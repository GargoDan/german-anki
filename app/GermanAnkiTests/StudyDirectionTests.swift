import XCTest
@testable import GermanAnki

final class StudyDirectionTests: XCTestCase {

    func testDefaultDirectionShowsGermanFirst() {
        XCTAssertFalse(StudyDirection.deToTranslation.showsTranslationFirst)
        XCTAssertTrue(StudyDirection.translationToDe.showsTranslationFirst)
    }

    func testShortLabelsReflectTranslationLanguage() {
        XCTAssertEqual(StudyDirection.deToTranslation.shortLabel(.en), "DE → EN")
        XCTAssertEqual(StudyDirection.translationToDe.shortLabel(.en), "EN → DE")
        XCTAssertEqual(StudyDirection.deToTranslation.shortLabel(.ru), "DE → RU")
        XCTAssertEqual(StudyDirection.translationToDe.shortLabel(.ru), "RU → DE")
    }

    func testRawValuesAreStableForPersistence() {
        // These strings are persisted in UserDefaults; changing them silently
        // resets every user's chosen direction, so pin them.
        XCTAssertEqual(StudyDirection.deToTranslation.rawValue, "deToTranslation")
        XCTAssertEqual(StudyDirection.translationToDe.rawValue, "translationToDe")
    }
}
