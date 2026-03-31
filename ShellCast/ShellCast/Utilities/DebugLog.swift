import Foundation

/// Debug-only logging. Compiles to nothing in release builds.
@inline(__always)
func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}
