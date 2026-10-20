#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
# Convert the existing brand asset to Apple's opaque 1024px icon packaging format.
sips -z 1024 1024 Resources/Assets.xcassets/ReviceIcon.imageset/image.png --out /tmp/revice-icon.png >/dev/null
sips -s format jpeg /tmp/revice-icon.png --out /tmp/revice-icon.jpg >/dev/null
sips -s format png /tmp/revice-icon.jpg --out Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png >/dev/null
"${XCODEGEN:-xcodegen}" generate --spec project.yml
