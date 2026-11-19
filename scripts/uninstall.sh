#!/bin/zsh
# Stop hantap, restore CapsLock and remove what install.sh added.
set -uo pipefail

LABEL=dev.hantap.agent
APP=~/Applications/hantap.app

launchctl bootout gui/$UID/$LABEL 2>/dev/null
# In case the agent died without restoring the mapping.
[[ -x $APP/Contents/MacOS/hantap ]] && $APP/Contents/MacOS/hantap restore-keys

rm -rf $APP ~/Library/LaunchAgents/$LABEL.plist
[[ -L ~/.local/bin/hantap ]] && rm ~/.local/bin/hantap

echo "hantap removed; CapsLock is back to the macOS setting."
echo "You can also remove hantap from Privacy & Security > Accessibility."
