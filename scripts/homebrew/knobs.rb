# Homebrew cask for Knobs (DEC-025). scripts/release.sh fills in @VERSION@ and @SHA256@ and writes the result to
# dist/homebrew/knobs.rb, which goes to the deva0x/homebrew-knobs tap as Casks/knobs.rb once the GitHub release
# holds the DMG.
cask "knobs" do
  version "@VERSION@"
  sha256 "@SHA256@"

  url "https://github.com/deva0x/knobs/releases/download/v#{version}/Knobs-#{version}.dmg",
      verified: "github.com/deva0x/knobs/"
  name "Knobs"
  desc "Windows for command-line tools such as ffmpeg, yt-dlp and pandoc"
  homepage "https://knobs.pages.dev/"

  livecheck do
    url "https://knobs.pages.dev/appcast.xml"
    strategy :sparkle
  end

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Knobs.app"

  zap trash: [
    "~/Library/Application Support/Knobs",
    "~/Library/Caches/io.github.deva0x.Knobs",
    "~/Library/HTTPStorages/io.github.deva0x.Knobs",
    "~/Library/Preferences/io.github.deva0x.Knobs.plist",
    "~/Library/Saved Application State/io.github.deva0x.Knobs.savedState",
  ]
end
