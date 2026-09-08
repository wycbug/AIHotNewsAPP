import XCTest

final class AIHotNewsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testReadingNavigationAndOfflineBookmarks() throws {
        let app = XCUIApplication()
        let session = UUID().uuidString
        app.launchArguments = ["--ui-test-session", session, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let article = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "开源模型发布全新推理能力")).firstMatch
        XCTAssertTrue(article.waitForExistence(timeout: 15))
        capture("01-feed", app)
        article.tap()
        XCTAssertTrue(app.buttons["收藏资讯"].waitForExistence(timeout: 5))
        app.buttons["收藏资讯"].tap()
        XCTAssertTrue(app.buttons["取消收藏"].exists)
        capture("02-article", app)
        app.tabBars.buttons["热点"].tap()
        let topic = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "第 1 名")).firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 10))
        topic.tap()
        XCTAssertTrue(app.staticTexts["开源推理模型持续演进"].waitForExistence(timeout: 10))
        app.buttons["收藏事件"].tap()
        capture("03-story", app)
        app.tabBars.buttons["日报"].tap()
        XCTAssertTrue(app.staticTexts["今日 AI 研究与产品进展"].waitForExistence(timeout: 10))
        app.buttons["收藏日报"].tap()
        capture("04-daily", app)
        app.buttons["往期日报"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["往期日报"].waitForExistence(timeout: 10))

        app.terminate()
        app.launchArguments += ["--ui-offline"]
        app.launch()
        XCTAssertTrue(article.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "离线")).firstMatch.waitForExistence(timeout: 10))
        app.tabBars.buttons["我的"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "条目收藏")).firstMatch.tap()
        XCTAssertTrue(article.waitForExistence(timeout: 5))
        article.tap()
        XCTAssertTrue(app.staticTexts["内容摘要"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["取消收藏"].exists)
        capture("05-offline-bookmark", app)
    }

    @MainActor
    func testSearchEmptyStateAndAppearance() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-session", UUID().uuidString, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        app.buttons["搜索资讯"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        if app.buttons["Continue"].waitForExistence(timeout: 2) { app.buttons["Continue"].tap() }
        search.typeText("zzzz")
        XCTAssertTrue(app.staticTexts["没有找到符合条件的条目"].waitForExistence(timeout: 10))
        capture("06-search-empty", app)
        app.buttons.matching(NSPredicate(format: "label IN %@", ["取消", "关闭", "Close", "Cancel"])).firstMatch.tap()
        app.tabBars.buttons["我的"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "设置")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        capture("07-settings", app)
    }

    @MainActor
    func testSearchDeepLinkReturnsToFeedAndReopensSameQuery() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-session", UUID().uuidString, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let article = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "开源模型发布全新推理能力")).firstMatch
        XCTAssertTrue(article.waitForExistence(timeout: 10))
        article.tap()
        XCTAssertTrue(app.buttons["收藏资讯"].waitForExistence(timeout: 5))

        let emptySearchURL = try XCTUnwrap(URL(string: "aihotnews://search?q=zzzz"))
        app.open(emptySearchURL)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["没有找到符合条件的条目"].waitForExistence(timeout: 10))
        XCTAssertEqual(search.value as? String, "zzzz")
        XCTAssertTrue(search.isHittable)
        XCTAssertFalse(app.buttons["收藏资讯"].exists)

        app.open(try XCTUnwrap(URL(string: "aihotnews://my")))
        XCTAssertTrue(app.staticTexts["本机资料库"].waitForExistence(timeout: 5))
        app.open(emptySearchURL)
        XCTAssertTrue(app.staticTexts["没有找到符合条件的条目"].waitForExistence(timeout: 10))
        XCTAssertEqual(search.value as? String, "zzzz")
        XCTAssertTrue(search.isHittable)

        var matchingURL = URLComponents()
        matchingURL.scheme = "aihotnews"
        matchingURL.host = "search"
        matchingURL.queryItems = [URLQueryItem(name: "q", value: "开源")]
        app.open(try XCTUnwrap(matchingURL.url))
        XCTAssertTrue(article.waitForExistence(timeout: 10))
        XCTAssertEqual(search.value as? String, "开源")
        capture("12-search-deep-link", app)
    }

    @MainActor
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testLargeTypeInDarkMode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-session", UUID().uuidString, "-appearance", "dark",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let article = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "开源模型发布全新推理能力")).firstMatch
        for _ in 0..<5 {
            if article.waitForExistence(timeout: 1) { break }
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(article.waitForExistence(timeout: 10))
        capture("08-large-type-dark-feed", app)
        article.tap()
        XCTAssertTrue(app.buttons["收藏资讯"].waitForExistence(timeout: 5))
        capture("09-large-type-dark-detail", app)
    }

    @MainActor
    func testTabletThreeColumnNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-session", UUID().uuidString]
        app.launch()
        let article = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "开源模型发布全新推理能力")).firstMatch
        XCTAssertTrue(article.waitForExistence(timeout: 10))
        article.tap()
        XCTAssertTrue(app.buttons["收藏资讯"].waitForExistence(timeout: 5))
        capture("10-adaptive-navigation", app)
#if os(iOS)
        XCUIDevice.shared.orientation = .landscapeLeft
        app.buttons["收藏资讯"].tap()
        XCTAssertTrue(app.buttons["取消收藏"].waitForExistence(timeout: 5))
        capture("11-landscape-navigation", app)
        XCUIDevice.shared.orientation = .portrait
#endif
    }
}
