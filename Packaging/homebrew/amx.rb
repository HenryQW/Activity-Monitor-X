# The cask for HenryQW/homebrew-tap. The release workflow fills in the version and the SHA-256 and commits it to the tap
# as Casks/amx.rb.
cask "amx" do
  version "@VERSION@"
  sha256 "@SHA256@"

  url "https://github.com/HenryQW/amx/releases/download/v#{version}/AMX-#{version}.dmg"
  name "Activity Monitor X"
  desc "Records the CPU, memory, disk, energy, network and GPU history of every process"
  homepage "https://amx.henry.wang/"

  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Activity Monitor X.app"
  binary "#{appdir}/Activity Monitor X.app/Contents/MacOS/amx"

  zap trash: [
    "~/Library/Application Support/ActivityMonitorX",
    "~/Library/Preferences/com.henryqw.activitymonitorx.plist",
  ]

  caveats <<~EOS
    Activity Monitor X has no Developer ID signature, so macOS blocks it at first. To open it, run:
      xattr -dr com.apple.quarantine "/Applications/Activity Monitor X.app"
    Run it again after each upgrade.

    At its first launch, the app registers its helper, which records the history as root.
    To start the recording, turn on Activity Monitor X in
    System Settings > General > Login Items & Extensions, under Allow in the Background.

    Before you uninstall Activity Monitor X, quit it and turn it off there. The helper then stops.
  EOS
end
