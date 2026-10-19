#!/bin/zsh
# MusicDeck.app 빌드. 실행: ./build.sh && open MusicDeck.app
set -e
cd "$(dirname "$0")"
swift build -c release
rm -rf MusicDeck.app
mkdir -p MusicDeck.app/Contents/MacOS
cp .build/release/MusicDeck MusicDeck.app/Contents/MacOS/
cp Info.plist MusicDeck.app/Contents/
codesign -s - --force MusicDeck.app
echo "built MusicDeck.app"
