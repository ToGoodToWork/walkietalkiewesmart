# iOS App

The Xcode project lands in **Milestone 2**. Planned configuration:

- Bundle ID: `com.adrian.walkietalkie` (changeable later in Xcode)
- App display name: `WalkieTalk`
- Minimum target: iOS 17
- Language: Swift 5.9+, SwiftUI, async/await throughout
- Signing: free personal team (7-day provisioning fine for dev)
- Build configs:
  - `Config/Debug.xcconfig` → `API_BASE_URL=http://localhost:3000`
  - `Config/Release.xcconfig` → `API_BASE_URL=https://api.walkiehost.duckdns.org`
- App reads `API_BASE_URL` from `Info.plist`

See `claude-code-prompt.md` §8 for the screen list and §14 for iOS-specific
implementation notes.
