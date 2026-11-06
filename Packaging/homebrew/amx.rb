# The cask for HenryQW/homebrew-tap. The release workflow fills in the version, the SHA-256 and the release certificate
# (CERT in website/public/install.sh) and commits it to the tap as Casks/amx.rb.
cask "amx" do
  version "@VERSION@"
  sha256 "@SHA256@"

  url "https://github.com/HenryQW/Activity-Monitor-X/releases/download/v#{version}/AMX-#{version}.dmg"
  name "Activity Monitor X"
  desc "Records the CPU, memory, disk, energy, network and GPU history of every process"
  homepage "https://amx.henry.wang/"

  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Activity Monitor X.app"
  binary "#{appdir}/Activity Monitor X.app/Contents/MacOS/amx"

  # Activity Monitor X has no Developer ID, so macOS blocks a quarantined copy. The helper records as root: as in
  # install.sh, it goes to a root-owned folder outside the app, and the copy is checked after it is made (D92). The
  # property list comes from this cask, not from the app, because it says what root runs.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/Activity Monitor X.app"]
    run "/bin/sh", args: ["-c", <<~'SH', "sh", "{{appdir}}/Activity Monitor X.app"], sudo: true
      set -eu
      LABEL="com.henryqw.activitymonitorx.daemon"
      PLIST="/Library/LaunchDaemons/$LABEL.plist"
      mkdir -p /Library/PrivilegedHelperTools
      # A new name first: a copy that fails the check never replaces the helper that runs.
      install -m 755 -o root -g wheel "$1/Contents/MacOS/amxd" /Library/PrivilegedHelperTools/amxd.new
      if ! codesign --verify --strict -R="identifier \"$LABEL\" and certificate leaf = H\"@CERT_SHA1@\"" \
          /Library/PrivilegedHelperTools/amxd.new; then
          rm -f /Library/PrivilegedHelperTools/amxd.new
          echo "The helper is not signed by Activity Monitor X. It is not installed." >&2
          exit 1
      fi
      mv -f /Library/PrivilegedHelperTools/amxd.new /Library/PrivilegedHelperTools/amxd
      cat > "$PLIST" <<EOF
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
      	<key>Label</key>
      	<string>$LABEL</string>
      	<key>ProgramArguments</key>
      	<array>
      		<string>/Library/PrivilegedHelperTools/amxd</string>
      	</array>
      	<key>MachServices</key>
      	<dict>
      		<key>$LABEL</key>
      		<true/>
      	</dict>
      	<key>RunAtLoad</key>
      	<true/>
      	<key>KeepAlive</key>
      	<true/>
      	<key>ProcessType</key>
      	<string>Background</string>
      </dict>
      </plist>
      EOF
      chown root:wheel "$PLIST"
      chmod 644 "$PLIST"
      launchctl bootout "system/$LABEL" 2>/dev/null || true
      # bootout returns before the old helper exits; a bootstrap before that fails (EIO).
      while launchctl print "system/$LABEL" >/dev/null 2>&1; do sleep 0.2; done
      launchctl bootstrap system "$PLIST"
    SH
  end

  uninstall launchctl: "com.henryqw.activitymonitorx.daemon",
            delete:    [
              "/Library/LaunchDaemons/com.henryqw.activitymonitorx.daemon.plist",
              "/Library/PrivilegedHelperTools/amxd",
            ]

  zap trash: [
    "~/Library/Application Support/ActivityMonitorX",
    "~/Library/Preferences/com.henryqw.activitymonitorx.plist",
  ]

  caveats <<~EOS
    The history database stays after an uninstall, also with --zap. To remove it, run:
      sudo rm -rf "/Library/Application Support/ActivityMonitorX"
  EOS
end
