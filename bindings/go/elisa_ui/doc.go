// elisa_ui is the optional cgo wrapper for include/elisa_ui.h.
//
// Stateful entry points are single-threaded and synchronous. Callers should
// keep the UI goroutine locked to its OS thread with runtime.LockOSThread and
// serialize all calls there. Text calls borrow at most ELISA_UI_MAX_TEXT_BYTES
// from immutable Go string storage; the Elisa boundary copies that prefix into
// its fixed staging slot synchronously. No pointer is retained after a call,
// and callback records remain owned by the linked Elisa boundary.
package elisa_ui
