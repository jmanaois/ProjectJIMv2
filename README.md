# ProjectJIM

ProjectJIM is a workout-focused app for a paired iPhone and Apple Watch for strength training.

## Included

- SwiftUI iPhone and watchOS apps
- HealthKit workout session and live heart-rate display on Apple Watch
- Core Motion sampling and an arm-exercise state-machine rep detector for curls, rows, and shoulder presses
- WatchConnectivity routine sync and live rep/set events
- Codable on-device workout history on iPhone
- Generated completion tone with Bluetooth routing and Watch haptic fallback
- Manual rep correction and explicit set completion

## Run

1. Open `ProjectJIM.xcodeproj` in Xcode.
2. Select your development team for both targets.
3. Change the example bundle identifiers if needed.
4. Run `ProjectJIM` on a paired iPhone and `ProjectJIM Watch App` on its Apple Watch.
5. Accept Health and Motion permissions when prompted.

Motion and WatchConnectivity behavior must be tested on physical devices. The simulator is useful for UI work but doesn't provide representative wrist motion or pairing behavior.

## Detector status

`CycleRepDetector` is an MVP signal-processing detector, not a production classifier. It calibrates a neutral wrist pitch and recognizes an away-and-return cycle. Thresholds differ by supported arm exercise and are intentionally centralized in `ExerciseKind`. Collect labeled physical-device recordings before tuning thresholds or replacing it with a Core ML activity classifier.
