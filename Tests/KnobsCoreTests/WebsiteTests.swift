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

    /// The site's demo quotes commands for display as the app does, character for character.
    @Test func websiteQuotingMatchesTheApp() throws {
        let script = try String(contentsOf: websiteScript, encoding: .utf8)
        let pattern = try #require(script.firstMatch(of: /const SHELL_SAFE = \/\^\[(.*?)\]\+\$\/;/))
        let safeOnWebsite = Self.characters(inJavaScriptClass: String(pattern.1))
        let printable = (0x21...0x7E).compactMap { Unicode.Scalar($0).map(Character.init) }
        // Each character is tried in the middle of a word, apart from the rule about a leading `=`.
        let differing = printable.filter { character in
            let word = "a\(character)a"
            return (ShellQuoting.quote(word) == word) != safeOnWebsite.contains(character)
        }
        #expect(differing.isEmpty, "quoted differently on the website: \(differing)")
        // The app quotes a leading `=` even though `=` is safe elsewhere; the site must too.
        #expect(ShellQuoting.quote("=ls") != "=ls")
        #expect(script.contains(#"!text.startsWith("=")"#))
    }

    /// Expands a regular expression character class body such as `a-c_\/-` into its characters.
    private static func characters(inJavaScriptClass body: String) -> Set<Character> {
        var characters: Set<Character> = []
        let items = Array(body)
        var index = 0
        while index < items.count {
            var character = items[index]
            if character == "\\", index + 1 < items.count {
                index += 1
                character = items[index]
            }
            if index + 2 < items.count, items[index + 1] == "-",
                let low = character.unicodeScalars.first?.value, let high = items[index + 2].unicodeScalars.first?.value
            {
                for scalar in (low...high).compactMap(Unicode.Scalar.init) { characters.insert(Character(scalar)) }
                index += 3
            } else {
                characters.insert(character)
                index += 1
            }
        }
        return characters
    }
}
