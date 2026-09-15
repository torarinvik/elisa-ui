// elisa_ui is the optional cgo wrapper for include/elisa_ui.h.
//
// Stateful entry points are single-threaded and synchronous. Callers should
// keep the UI goroutine locked to its OS thread with runtime.LockOSThread and
// serialize all calls there. The Go wrapper never retains C or Go pointers
// across a call: text is copied into a temporary byte slice, and callback
// records remain owned by the linked Elisa boundary.
package elisa_ui
