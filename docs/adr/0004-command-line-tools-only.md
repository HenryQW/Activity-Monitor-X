# Build with Command Line Tools only, no Xcode project

The project builds with SwiftPM and `make` on Command Line Tools, so contributors and agents need no Xcode. Cost: the SwiftUI macro plugin is missing, so `@State`, `@Entry` and `#Preview` do not compile; views use `State(initialValue:)` by hand, and there are no previews or asset catalogs. Tests need the plugin path that `make test` passes. Do not "fix" the hand-written state by adding macros.
