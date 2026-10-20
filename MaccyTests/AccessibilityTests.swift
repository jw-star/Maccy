import XCTest
import Defaults
@testable import Maccy

@MainActor
class AccessibilityTests: XCTestCase {
  private let savedPasteByDefault = Defaults[.pasteByDefault]

  override func tearDown() {
    Defaults[.pasteByDefault] = savedPasteByDefault
    super.tearDown()
  }

  func testCheckPromptsWhenAccessibilityIsDenied() {
    var prompted = false

    let allowed = Accessibility.check(allowed: false) {
      prompted = true
    }

    XCTAssertFalse(allowed)
    XCTAssertTrue(prompted)
  }

  func testCheckDoesNotPromptWhenAccessibilityIsGranted() {
    var prompted = false

    let allowed = Accessibility.check(allowed: true) {
      prompted = true
    }

    XCTAssertTrue(allowed)
    XCTAssertFalse(prompted)
  }

  func testEnablingPasteByDefaultWithoutPermissionRevertsAndPrompts() {
    Defaults[.pasteByDefault] = true
    var prompted = false
    var openedSettings = false

    GeneralSettingsPane.updatePasteByDefault(true, openAccessibilitySettings: {
      openedSettings = true
    }) {
      Accessibility.check(allowed: false) {
        prompted = true
      }
    }

    XCTAssertTrue(prompted)
    XCTAssertTrue(openedSettings)
    XCTAssertFalse(Defaults[.pasteByDefault])
  }

  func testEnablingPasteByDefaultWithPermissionStaysOn() {
    Defaults[.pasteByDefault] = false
    var prompted = false
    var openedSettings = false

    GeneralSettingsPane.updatePasteByDefault(true, openAccessibilitySettings: {
      openedSettings = true
    }) {
      Accessibility.check(allowed: true) {
        prompted = true
      }
    }

    XCTAssertFalse(prompted)
    XCTAssertFalse(openedSettings)
    XCTAssertTrue(Defaults[.pasteByDefault])
  }

  func testDisablingPasteByDefaultDoesNotCheckAccessibility() {
    Defaults[.pasteByDefault] = true
    var checked = false
    var openedSettings = false

    GeneralSettingsPane.updatePasteByDefault(false, openAccessibilitySettings: {
      openedSettings = true
    }) {
      checked = true
      return false
    }

    XCTAssertFalse(checked)
    XCTAssertFalse(openedSettings)
    XCTAssertFalse(Defaults[.pasteByDefault])
  }

  func testOpenSystemSettingsUsesCurrentPrivacyURL() {
    var opened: [String] = []

    Accessibility.openSystemSettings { url in
      opened.append(url.absoluteString)
      return true
    }

    XCTAssertEqual(opened, [
      "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
    ])
  }

  func testOpenSystemSettingsFallsBackWhenCurrentURLFails() {
    var opened: [String] = []

    Accessibility.openSystemSettings { url in
      opened.append(url.absoluteString)
      return false
    }

    XCTAssertEqual(opened, [
      "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
      "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    ])
  }
}
