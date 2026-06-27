# /new-view <ViewName> — Scaffold a SwiftUI View + ViewModel

Scaffold a new feature view following Stripie's MVVM conventions.

## Instructions

Given `$ARGUMENTS` as the view name (e.g. `RefundView`):

1. Infer the feature name from the view name (e.g. `Refund`).

2. Create these files:
   - `Stripie/Features/<Feature>/Models/<Feature>State.swift` — enums/structs for UI state
   - `Stripie/Features/<Feature>/ViewModels/<ViewName>Model.swift` — `@Observable @MainActor final class`
   - `Stripie/Features/<Feature>/Views/<ViewName>.swift` — SwiftUI view + `#Preview`

3. Follow these rules exactly:
   - ViewModel: `@Observable @MainActor final class`, injected dependencies via `init`
   - View: receives ViewModel via `init`, stores in `@State`
   - No `ObservableObject`, no `@Published`, no `NavigationView`
   - Every view must end with a `#Preview` block
   - Views must be ≤100 lines; extract subviews if longer
   - Use `Logger` for any async operations, never `print()`

4. After creating files, remind the user to add them to the Xcode project.
