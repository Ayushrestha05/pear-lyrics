#!/bin/sh
set -eu

cd "$(dirname "$0")"

if kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -q 'org.user.pearlyrics'; then
    kpackagetool6 --type Plasma/Applet --upgrade package
else
    kpackagetool6 --type Plasma/Applet --install package
fi

echo "Pear Lyrics installed. Restart Plasma or re-add the widget to apply changes."
