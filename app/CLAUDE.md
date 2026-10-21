# Boulder Bay — iOS app

- **The Xcode project is generated.** `project.yml` (XcodeGen) is the source of truth; `BoulderBay.xcodeproj` is gitignored. Add sources, targets, SPM packages and Info.plist keys to `project.yml`, then run `xcodegen generate`. Never hand-edit the `.xcodeproj`.
- **Views are covered by snapshot tests, view models by unit tests.** `GymPinView` and `SelectedGymCard` have reference PNGs under `BoulderBayTests/Features/Map/__Snapshots__/`. A deliberate visual change means re-recording: delete the affected PNGs, run the tests twice (the first run records and fails), and look at the new images before committing. Never re-record to silence a failure you haven't looked at. `MapView` itself isn't snapshot-tested — MapKit tiles don't render in snapshots.
