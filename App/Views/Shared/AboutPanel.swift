import AppKit

/// The standard About window, with a line about what Knobs is, the license and a link to the source.
enum AboutPanel {
    /// Working repository address (DEC-010); the website uses the same one.
    static let repositoryURL = URL(string: "https://github.com/deva0x/knobs")!

    @MainActor static func show() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 6
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]
        let credits = NSMutableAttributedString(
            string: "Command-line tools, as Mac windows.\nThe tools themselves belong to their authors.\n",
            attributes: body)
        var link = body
        link[.link] = repositoryURL
        link[.foregroundColor] = NSColor.linkColor
        credits.append(NSAttributedString(string: "Source code on GitHub", attributes: link))
        credits.append(NSAttributedString(string: " · MIT License", attributes: body))

        NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApplication.shared.activate()
    }
}
