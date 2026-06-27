# /run — Build and Launch Stripie on Simulator

Build and launch Stripie on the iPhone 16 Pro simulator.

## Steps

1. Use `mcp__xcodebuildmcp__build_run_sim_name_proj` with:
   - scheme: `Stripie`
   - simulatorName: `iPhone 16 Pro`

2. Once launched, take a screenshot with `mcp__xcodebuildmcp__simulator_screenshot`.

3. Verify the golden path:
   - Tab bar shows Charge / Transactions / Reader
   - Charge screen shows $0.00 with keypad
   - Reader tab shows connection state

4. Report any console errors visible in the build output.
