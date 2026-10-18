import Foundation
import KnobsCore
import Testing

/// The website shows real tasks. These keep it from drifting away from the manifests the app ships.
@Suite struct WebsiteTests {
    @Test func demoTaskIsTheRealShrinkAVideoTask() throws {
        let page = try String(contentsOf: websitePage, encoding: .utf8)
        let demo = try #require(
            page.firstMatch(of: /<script type="application\/json" id="demo-task">(.*?)<\/script>/.dotMatchesNewlines()))
        let demoTask = try JSONSerialization.jsonObject(with: Data(demo.1.utf8)) as? NSDictionary

        let manifest =
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: manifestsDirectory.appending(path: "ffmpeg.json"))) as? [String: Any]
        let tasks = manifest?["tasks"] as? [NSDictionary] ?? []
        let realTask = try #require(tasks.first { $0["id"] as? String == "shrink-video" })

        #expect(demoTask == realTask, "Copy the Shrink a video task from Manifests/ffmpeg.json into #demo-task.")
    }

    @Test func galleryListsOnlyRealToolsAndTasks() throws {
        let page = try String(contentsOf: websitePage, encoding: .utf8)
        let catalog = ManifestLoader.loadCatalog(in: manifestsDirectory)
        let cards = page.matches(
            of:
                /<h3>([^<]+)<\/h3>\s*<p class="strip-what">.*?<ul class="strip-tasks">(.*?)<\/ul>\s*<code class="strip-brew">brew install ([^<]+)<\/code>/
                .dotMatchesNewlines())
        #expect(cards.count == catalog.manifests.count)

        for card in cards {
            let name = String(card.1)
            let manifest = try #require(catalog.manifests.first { $0.name == name }, "No manifest is named \(name).")
            #expect(String(card.3) == manifest.brewFormula, "\(name)'s brew formula")
            let titles = card.2.matches(of: /<li>([^<]+)<\/li>/).map { String($0.1) }
            let unknown = titles.filter { title in !manifest.tasks.contains { $0.title == title } }
            #expect(unknown.isEmpty, "\(name) has no tasks named \(unknown)")
        }
    }
}
