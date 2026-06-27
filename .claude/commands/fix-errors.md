# /fix-errors — Diagnose and Fix Build Errors (ultrathink)

Systematically diagnose and resolve Swift build errors in Stripie.

## Process

1. Run the build using `mcp__xcodebuildmcp__build_sim_name_proj`.

2. Parse the structured JSON error output. Group errors by file.

3. For each error, think deeply about the root cause:
   - Swift 6 concurrency isolation violations → fix the isolation, don't suppress
   - Missing imports → add correct import, check SPM dependency is added
   - Type mismatches → check Codable key strategies (camelCase ↔ snake_case)
   - Protocol conformance gaps → implement missing methods, don't stub with `fatalError`

4. Fix one file at a time. Rebuild after each file to avoid fixing phantom errors.

5. **Never:**
   - Delete DerivedData
   - Use `@preconcurrency import` unless as an absolute last resort with explanation
   - Silence warnings with `// swiftlint:disable` or `#warning`
   - Use `try!` or `as!` to make errors go away

6. After all errors resolve, run `/test` to verify no regressions.
