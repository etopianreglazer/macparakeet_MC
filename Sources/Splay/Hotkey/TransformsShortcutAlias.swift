import SplayCore

/// SwiftUI also defines a `KeyboardShortcut` type (used by `.keyboardShortcut`
/// view modifiers). The Transforms feature uses SplayCore's storage-
/// shaped `KeyboardShortcut` — bind a stable alias so SwiftUI files don't
/// need to fully qualify every reference.
typealias TransformShortcut = SplayCore.KeyboardShortcut
