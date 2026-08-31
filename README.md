# Matix the Math Club - iOS (Swift)

This is an EXACT 1:1 copy of the club web app. The real app.html is bundled
into the app and runs in a native Swift shell (WKWebView), so every page,
feature and pixel matches the original: login, workspace, AI, learn, games
hub, chat, ideas, points, notifications, roles, video calls, all of it.

## Open it

Open "Matix the Math Club.xcodeproj" in Xcode 15+, pick iPhone or simulator (iOS 17+), press Run.
Set your signing team under Signing & Capabilities if Xcode asks.

## How it works

- WebShell.swift hosts the bundled app.html in WKWebView with persistent
  storage, so sign-ins survive relaunches.
- Camera/microphone requests (video calls) are granted natively; the system
  asks once with the usage strings in the project.
- JS dialogs, file uploads and popup links are all wired to native handlers.
- Talks to your Firebase Realtime Database directly, exactly like the website.

## Updating the app when the HTML changes

Replace app.html inside the "Matix the Math Club" folder with the new file
and rebuild. Nothing else to change.

## app.html lives in the project root

The whole web app is the single file `app.html` in the root of this project.
That is the file you edit. Run `node sync-app.js` after editing to copy it into
the platform shell folder. (Android does this automatically through Gradle.)
