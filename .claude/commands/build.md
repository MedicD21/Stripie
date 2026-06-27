# /build — Build Stripie for Simulator

Build the Stripie iOS app for the iPhone 16 Pro simulator using XcodeBuildMCP.

## Steps

1. Use `mcp__xcodebuildmcp__build_sim_name_proj` with:
   - scheme: `Stripie`
   - simulatorName: `iPhone 16 Pro`
   - project path: the `.xcodeproj` in the repo root

2. If the build fails, read the structured JSON error output carefully. Fix one error at a time. Do NOT delete DerivedData.

3. After a successful build, confirm by reporting the build number and any warnings.

## Notes

- Swift 6 strict concurrency — all warnings are errors. Fix isolation issues at the root.
- Never use `Task { @MainActor in }` to paper over a Sendable violation.
- If SPM packages are missing, remind the user to add `stripe-terminal-ios` via Xcode → File → Add Package Dependencies.
