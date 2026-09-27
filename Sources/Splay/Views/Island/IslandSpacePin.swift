import AppKit
import Darwin
import SplayCore

/// Keeps the island fixed behind the camera while the user swipes between
/// desktops (owner, 2026-09-27).
///
/// A `.canJoinAllSpaces` window is drawn into every Space, so a three-finger
/// swipe slides it along with the desktop. There is no public way to stop that.
/// Notch apps (boring.notch, Atoll) put their window in a private WindowServer
/// Space that sits above every desktop at the highest absolute level, where the
/// menu bar lives, so desktop transitions no longer move it.
///
/// **Private API.** The CGS symbols are looked up at runtime; if any is missing
/// (a future macOS), `pin` does nothing and the island keeps today's
/// behaviour. Fine for Developer ID distribution; not App Store-safe.
///
/// WindowServer can silently drop a window from the space after `orderOut`,
/// `orderFrontRegardless` or a `collectionBehavior` change while still listing
/// it (Atoll PR #857), so callers re-`pin` after every re-order.
@MainActor
final class IslandSpacePin {
    private typealias ConnectionFn = @convention(c) () -> UInt32
    private typealias SpaceCreateFn = @convention(c) (UInt32, Int, CFDictionary?) -> UInt64
    private typealias SpaceLevelFn = @convention(c) (UInt32, UInt64, Int) -> Void
    private typealias SpacesFn = @convention(c) (UInt32, CFArray) -> Void
    private typealias WindowsSpacesFn = @convention(c) (UInt32, CFArray, CFArray) -> Void
    private typealias SpaceDestroyFn = @convention(c) (UInt32, UInt64) -> Void

    private struct API {
        let connection: ConnectionFn
        let create: SpaceCreateFn
        let setLevel: SpaceLevelFn
        let show: SpacesFn
        let hide: SpacesFn
        let add: WindowsSpacesFn
        let remove: WindowsSpacesFn
        let destroy: SpaceDestroyFn

        static func load() -> API? {
            let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
            func sym<T>(_ names: String..., as _: T.Type) -> T? {
                for name in names {
                    if let raw = dlsym(handle ?? UnsafeMutableRawPointer(bitPattern: -2), name) {
                        return unsafeBitCast(raw, to: T.self)
                    }
                }
                return nil
            }
            guard
                let connection = sym("SLSMainConnectionID", "_CGSDefaultConnection", as: ConnectionFn.self),
                let create = sym("SLSSpaceCreate", "CGSSpaceCreate", as: SpaceCreateFn.self),
                let setLevel = sym("SLSSpaceSetAbsoluteLevel", "CGSSpaceSetAbsoluteLevel", as: SpaceLevelFn.self),
                let show = sym("SLSShowSpaces", "CGSShowSpaces", as: SpacesFn.self),
                let hide = sym("SLSHideSpaces", "CGSHideSpaces", as: SpacesFn.self),
                let add = sym("SLSAddWindowsToSpaces", "CGSAddWindowsToSpaces", as: WindowsSpacesFn.self),
                let remove = sym("SLSRemoveWindowsFromSpaces", "CGSRemoveWindowsFromSpaces", as: WindowsSpacesFn.self),
                let destroy = sym("SLSSpaceDestroy", "CGSSpaceDestroy", as: SpaceDestroyFn.self)
            else { return nil }
            return API(connection: connection, create: create, setLevel: setLevel, show: show,
                       hide: hide, add: add, remove: remove, destroy: destroy)
        }
    }

    /// Above every desktop and full-screen Space (the value boring.notch uses).
    private static let absoluteLevel = Int(Int32.max)

    private let api: API?
    private var space: UInt64?

    init() {
        api = AppFeatures.islandPinnedAcrossSpaces ? API.load() : nil
        guard let api else {
            if AppFeatures.islandPinnedAcrossSpaces {
                AudioCaptureDiagnostics.append("splay_island space_pin unavailable")
            }
            return
        }
        let cid = api.connection()
        // Flag 1: a user-invisible space. Any other value and Finder draws the
        // desktop icons into it.
        let created = api.create(cid, 1, nil)
        guard created != 0 else {
            AudioCaptureDiagnostics.append("splay_island space_pin create_failed")
            return
        }
        api.setLevel(cid, created, Self.absoluteLevel)
        api.show(cid, [NSNumber(value: created)] as CFArray)
        space = created
        AudioCaptureDiagnostics.append("splay_island space_pin created space=\(created)")
    }

    /// Put `window` in the pinned space. Idempotent; call after every re-order.
    func pin(_ window: NSWindow) {
        guard let api, let space, window.windowNumber > 0 else { return }
        api.add(api.connection(), [NSNumber(value: window.windowNumber)] as CFArray,
                [NSNumber(value: space)] as CFArray)
    }

    func unpin(_ window: NSWindow) {
        guard let api, let space, window.windowNumber > 0 else { return }
        api.remove(api.connection(), [NSNumber(value: window.windowNumber)] as CFArray,
                   [NSNumber(value: space)] as CFArray)
    }

    func destroy() {
        guard let api, let space else { return }
        let cid = api.connection()
        api.hide(cid, [NSNumber(value: space)] as CFArray)
        api.destroy(cid, space)
        self.space = nil
    }
}
