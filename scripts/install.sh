#!/bin/zsh
# Build hantap, install it as ~/Applications/hantap.app and start it at login.
# Extra arguments are passed to `hantap run`, e.g.:
#   zsh scripts/install.sh --hold-ms 0 --fallback activate
set -euo pipefail
cd "${0:A:h}/.."

LABEL=dev.hantap.agent
APP=~/Applications/hantap.app
EXE=$APP/Contents/MacOS/hantap
PLIST=~/Library/LaunchAgents/$LABEL.plist
LOG=~/Library/Logs/hantap.log

swift build -c release
[[ -f Resources/AppIcon.icns ]] || swift scripts/make-icon.swift .

# Stop the running agent first; it restores CapsLock on SIGTERM.
launchctl bootout gui/$UID/$LABEL 2>/dev/null || true

rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources ~/Library/LaunchAgents ~/Library/Logs ~/.local/bin
cp .build/release/hantap $EXE
cp Resources/AppIcon.icns $APP/Contents/Resources/
cat > $APP/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.hantap</string>
  <key>CFBundleName</key><string>hantap</string>
  <key>CFBundleExecutable</key><string>hantap</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF
codesign --force --sign - --identifier dev.hantap $APP
ln -sf $EXE ~/.local/bin/hantap

args_xml=""
for a in "$@"; do args_xml+="    <string>${a}</string>"$'\n'; done
cat > $PLIST <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$EXE</string>
    <string>run</string>
${args_xml}  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardErrorPath</key><string>$LOG</string>
  <key>StandardOutPath</key><string>$LOG</string>
</dict>
</plist>
EOF

launchctl bootstrap gui/$UID $PLIST

cat <<EOF

hantap installed and started.
  app:  $APP
  log:  tail -f $LOG

Allow hantap in System Settings > Privacy & Security > Accessibility
(and Input Monitoring if it asks). CapsLock keeps its normal behaviour until
then. After every reinstall the ad-hoc signature changes: if CapsLock stops
switching, remove hantap from Accessibility and add it again.
EOF
