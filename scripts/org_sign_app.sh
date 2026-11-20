#!/bin/bash
# Signs Undertone.app inside-out (no --deep): nested code first (Sparkle XPCs, helpers, frameworks,
# dylibs), the app last. Entitlements, flags and hardened runtime of every item are kept.
#
#   scripts/org_sign_app.sh <Undertone.app> <identity>
#
#   identity   name of a code signing certificate in the keychain (e.g. "Undertone Signing")
#              or "-" for ad-hoc
set -euo pipefail

APP="$1"
IDENTITY="$2"
[ -d "$APP/Contents" ] || { echo "Keine App: $APP" >&2; exit 1; }

sign() {
    # Nested items keep their own identifier; the app gets its Info.plist bundle id.
    local target="$1" keep_identifier="$2"
    local metadata="entitlements,flags,runtime"
    [ "$keep_identifier" = "1" ] && metadata="identifier,$metadata"
    codesign --force --timestamp=none --sign "$IDENTITY" --preserve-metadata="$metadata" "$target"
}

# Nested code, deepest paths first.
nested=$(
    find "$APP/Contents/Frameworks" "$APP/Contents/PlugIns" "$APP/Contents/XPCServices" \
        \( -name "*.xpc" -o -name "*.app" -o -name "*.framework" -o -name "*.dylib" -o -name "*.appex" \) \
        -print 2>/dev/null
    # Bare helper executables inside frameworks (e.g. Sparkle's Autoupdate).
    find "$APP/Contents/Frameworks" -type f -perm +111 -path "*.framework/Versions/*" 2>/dev/null \
        | while read -r file; do
            relative="${file#"$APP/Contents/Frameworks/"}"
            case "$relative" in (*.app/*|*.xpc/*) continue ;; esac
            base="$(basename "$file")"
            framework_binary="$(basename "$(dirname "$(dirname "$(dirname "$file")")")" .framework)"
            # The framework's main binary is signed together with the framework itself.
            [ "$base" = "$framework_binary" ] && continue
            file "$file" | grep -q "Mach-O" && echo "$file"
        done
)

echo "$nested" | awk 'NF { print gsub("/", "/"), $0 }' | sort -rn | cut -d' ' -f2- | while read -r item; do
    [ -e "$item" ] || continue
    # Skip framework symlinks (Versions/Current, top-level aliases).
    [ -L "$item" ] && continue
    sign "$item" 1
done

sign "$APP" 0
codesign --verify --deep --strict "$APP"
