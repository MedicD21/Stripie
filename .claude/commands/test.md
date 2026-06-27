# /test — Run Stripie Test Suite

Run all unit tests for the Stripie target using XcodeBuildMCP.

## Steps

1. Use `mcp__xcodebuildmcp__test_sim_name_proj` with:
   - scheme: `Stripie`
   - simulatorName: `iPhone 16 Pro`

2. Report: total tests run, passed, failed. For any failure, show the test name and failure message.

3. Coverage target is 80%+ for: networking, payment flow logic, transaction mapping.

## Framework

Tests use **Swift Testing** (`import Testing`, `@Suite`, `@Test`, `#expect`).
Do not add XCTest assertions to Swift Testing suites — they use different assertion styles.
