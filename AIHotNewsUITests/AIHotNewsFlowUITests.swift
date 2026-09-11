import XCTest

final class AIHotNewsFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-session", UUID().uuidString,
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] + extraArguments
        app.launch()
        return app
    }

    @MainActor
    private func articleRow(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "开源模型发布全新推理能力")).firstMatch
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

#if os(macOS)
    @MainActor
    func testMacFeedFiltersRemainAccessibleAfterSearch() throws {
        let app = launch()
        let modelsChip = app.buttons["模型"]
        XCTAssertTrue(modelsChip.waitForExistence(timeout: 15))
        modelsChip.click()
        XCTAssertTrue(modelsChip.isSelected)
        app.radioButtons["7 天"].click()
        app.radioButtons["公开池"].click()
        XCTAssertTrue(app.buttons["公开池不是全站历史"].waitForExistence(timeout: 5))

        let search = app.searchFields.firstMatch
        search.click()
        search.typeText("model")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "没有找到符合条件的条目"))
            .firstMatch.waitForExistence(timeout: 10))
        search.buttons["取消"].click()
        XCTAssertTrue(modelsChip.isSelected)
        app.buttons["全部类型"].click()
        XCTAssertFalse(modelsChip.isSelected)
        XCTAssertTrue(app.buttons["公开池不是全站历史"].exists)
        capture("28-mac-feed-filters-search")
    }
#endif

    @MainActor
    func testCategoryChipSelectionAndPoolNotice() throws {
        let app = launch()
        XCTAssertTrue(articleRow(app).waitForExistence(timeout: 15))
        let modelsChip = app.buttons["模型"]
        XCTAssertTrue(modelsChip.waitForExistence(timeout: 5))
        XCTAssertFalse(modelsChip.isSelected)
        modelsChip.tap()
        XCTAssertTrue(modelsChip.isSelected)
        app.buttons["全部类型"].tap()
        XCTAssertFalse(modelsChip.isSelected)

        let pool = app.segmentedControls.buttons["公开池"]
        XCTAssertTrue(pool.waitForExistence(timeout: 5))
        pool.tap()
        let notice = app.buttons["公开池不是全站历史"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        notice.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "公开池是最近 7 天可见动态"))
            .firstMatch.waitForExistence(timeout: 5))
        capture("20-category-pool-notice")
    }

    @MainActor
    func testSearchTooShortShowsValidation() throws {
        let app = launch()
        XCTAssertTrue(articleRow(app).waitForExistence(timeout: 15))
        app.buttons["搜索资讯"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        if app.buttons["Continue"].waitForExistence(timeout: 2) { app.buttons["Continue"].tap() }
        search.typeText("a")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "搜索请输入 2–200 个字"))
            .firstMatch.waitForExistence(timeout: 10))
        capture("21-search-too-short")
    }

    @MainActor
    func testReadMarkingAndClearAll() throws {
        let app = launch()
        let article = articleRow(app)
        XCTAssertTrue(article.waitForExistence(timeout: 15))
        article.tap()
        XCTAssertTrue(app.buttons["收藏资讯"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["已读"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(article.waitForExistence(timeout: 5))

        app.tabBars.buttons["我的"].tap()
        let counter = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "1 条已读")).firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "清除已读标记")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["清除全部已读标记？"].waitForExistence(timeout: 5))
        app.buttons["清除已读标记"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "0 条已读"))
            .firstMatch.waitForExistence(timeout: 5))
        capture("22-clear-read-marks")
    }

    @MainActor
    func testRemoveBookmarkWithConfirmation() throws {
        let app = launch()
        let article = articleRow(app)
        XCTAssertTrue(article.waitForExistence(timeout: 15))
        article.tap()
        XCTAssertTrue(app.buttons["收藏资讯"].waitForExistence(timeout: 5))
        app.buttons["收藏资讯"].tap()
        XCTAssertTrue(app.buttons["取消收藏"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.tabBars.buttons["我的"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "条目收藏")).firstMatch.tap()
        let saved = articleRow(app)
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.swipeLeft()
        app.buttons["取消收藏"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["取消这份收藏？"].waitForExistence(timeout: 5))
        app.buttons["取消收藏"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["还没有收藏"].waitForExistence(timeout: 5))
        capture("23-bookmark-removed")
    }

    @MainActor
    func testDailyDeepLinkAndArchiveEntry() throws {
        let app = launch()
        XCTAssertTrue(articleRow(app).waitForExistence(timeout: 15))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        app.open(try XCTUnwrap(URL(string: "aihotnews://daily/\(today)")))
        XCTAssertTrue(app.staticTexts["今日 AI 研究与产品进展"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["每日速览"].exists)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["往期日报"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["往期日报"].waitForExistence(timeout: 10))
        let entry = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "今日 AI 研究与产品进展")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        XCTAssertTrue(app.staticTexts["模型进展"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["开发者工具更新"].exists)
        capture("24-daily-archive-detail")
    }

    @MainActor
    func testItemAndStoryDeepLinks() throws {
        let app = launch()
        XCTAssertTrue(articleRow(app).waitForExistence(timeout: 15))
        app.open(try XCTUnwrap(URL(string: "aihotnews://item/ui-article")))
        XCTAssertTrue(app.buttons["收藏资讯"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["内容摘要"].exists)

        // XCUIApplication.open 会重启 App，内存态丢失；先收藏事件让深链走本机书签分支
        XCTAssertTrue(app.tabBars.buttons["热点"].waitForExistence(timeout: 15))
        app.tabBars.buttons["热点"].tap()
        let topic = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "第 1 名")).firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 15))
        topic.tap()
        XCTAssertTrue(app.buttons["收藏事件"].waitForExistence(timeout: 15))
        app.buttons["收藏事件"].tap()

        app.open(try XCTUnwrap(URL(string: "aihotnews://story/ui-story")))
        XCTAssertTrue(app.staticTexts["开源推理模型持续演进"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "仅你设备上的副本"))
            .firstMatch.exists)
        capture("25-story-deep-link")
    }

    @MainActor
    func testInvalidDeepLinkShowsAlert() throws {
        let app = launch()
        XCTAssertTrue(articleRow(app).waitForExistence(timeout: 15))
        app.open(try XCTUnwrap(URL(string: "aihotnews://unknown")))
        let alert = app.alerts["无法打开链接"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["好"].tap()
        XCTAssertFalse(alert.exists)
    }

    @MainActor
    func testHotExplanationDismissalPersists() throws {
        let app = launch()
        app.tabBars.buttons["热点"].tap()
        let explanation = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "多源同时报道")).firstMatch
        let close = app.buttons["关闭热点说明"]
        if close.waitForExistence(timeout: 10) {
            XCTAssertTrue(explanation.exists)
            close.tap()
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: explanation)
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        }
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["热点"].waitForExistence(timeout: 15))
        app.tabBars.buttons["热点"].tap()
        XCTAssertFalse(app.buttons["关闭热点说明"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "第 1 名"))
            .firstMatch.waitForExistence(timeout: 10))
        capture("26-hot-explanation-dismissed")
    }

    @MainActor
    func testClearCacheKeepsBookmarks() throws {
        let app = launch()
        let article = articleRow(app)
        XCTAssertTrue(article.waitForExistence(timeout: 15))
        article.tap()
        XCTAssertTrue(app.buttons["收藏资讯"].waitForExistence(timeout: 5))
        app.buttons["收藏资讯"].tap()
        XCTAssertTrue(app.buttons["取消收藏"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.tabBars.buttons["我的"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "设置")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "清除网络缓存")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["清除本机网络缓存？"].waitForExistence(timeout: 5))
        app.buttons["清除缓存"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(identifier: "cacheStatus")
            .firstMatch.waitForExistence(timeout: 10))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "条目收藏")).firstMatch.tap()
        XCTAssertTrue(articleRow(app).waitForExistence(timeout: 5))
        capture("27-cache-cleared-bookmarks-kept")
    }
}
