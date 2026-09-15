// Package elisa_ui is the optional Go host face of elisa-ui's stable C ABI.
//
// It is deliberately small: the linked Elisa component owns retained widgets,
// callbacks, and all framework state. Go owns only scalar event values and
// copies text into the borrowed call boundary. Stateful calls must be made on
// one UI-owner OS thread (typically a goroutine locked with
// runtime.LockOSThread); this package does not add a scheduler or mutex.
package elisa_ui

/*
#cgo CFLAGS: -I${SRCDIR}/../../..
#include "include/elisa_ui.h"

_Static_assert(sizeof(elisa_ui_event) == 24, "elisa_ui_event layout changed");
_Static_assert(offsetof(elisa_ui_event, code) == 20, "elisa_ui_event code offset changed");

enum {
	elisa_go_abi_version = ELISA_UI_ABI_VERSION,
	elisa_go_abi_version_major = ELISA_UI_ABI_VERSION_MAJOR,
	elisa_go_abi_version_minor = ELISA_UI_ABI_VERSION_MINOR,
	elisa_go_abi_version_patch = ELISA_UI_ABI_VERSION_PATCH,
	elisa_go_event_none = ELISA_UI_EVENT_NONE,
	elisa_go_event_quit = ELISA_UI_EVENT_QUIT,
	elisa_go_event_pointer_move = ELISA_UI_EVENT_POINTER_MOVE,
	elisa_go_event_pointer_down = ELISA_UI_EVENT_POINTER_DOWN,
	elisa_go_event_pointer_up = ELISA_UI_EVENT_POINTER_UP,
	elisa_go_event_pointer_leave = ELISA_UI_EVENT_POINTER_LEAVE,
	elisa_go_event_key_down = ELISA_UI_EVENT_KEY_DOWN,
	elisa_go_event_key_up = ELISA_UI_EVENT_KEY_UP,
	elisa_go_event_resize = ELISA_UI_EVENT_RESIZE,
	elisa_go_event_scroll = ELISA_UI_EVENT_SCROLL,
	elisa_go_event_gamepad_button = ELISA_UI_EVENT_GAMEPAD_BUTTON,
	elisa_go_event_gamepad_axis = ELISA_UI_EVENT_GAMEPAD_AXIS,
	elisa_go_event_focus_gained = ELISA_UI_EVENT_FOCUS_GAINED,
	elisa_go_event_focus_lost = ELISA_UI_EVENT_FOCUS_LOST
};
*/
import "C"

import (
	"runtime"
	"unsafe"
)

// Event mirrors elisa_ui_event. Only fields selected by Kind carry meaning;
// the Elisa boundary validates and normalizes hostile values.
type Event struct {
	Kind int32
	X    float32
	Y    float32
	DX   float32
	DY   float32
	Code int32
}

// Stable event wire ordinals.
const (
	EventNone          int32 = C.elisa_go_event_none
	EventQuit          int32 = C.elisa_go_event_quit
	EventPointerMove   int32 = C.elisa_go_event_pointer_move
	EventPointerDown   int32 = C.elisa_go_event_pointer_down
	EventPointerUp     int32 = C.elisa_go_event_pointer_up
	EventPointerLeave  int32 = C.elisa_go_event_pointer_leave
	EventKeyDown       int32 = C.elisa_go_event_key_down
	EventKeyUp         int32 = C.elisa_go_event_key_up
	EventResize        int32 = C.elisa_go_event_resize
	EventScroll        int32 = C.elisa_go_event_scroll
	EventGamepadButton int32 = C.elisa_go_event_gamepad_button
	EventGamepadAxis   int32 = C.elisa_go_event_gamepad_axis
	EventFocusGained   int32 = C.elisa_go_event_focus_gained
	EventFocusLost     int32 = C.elisa_go_event_focus_lost
)

// ABI version components are kept as Go constants for callers that want to
// reject a major mismatch before making stateful calls.
const (
	ABIVersionMajor uint32 = C.elisa_go_abi_version_major
	ABIVersionMinor uint32 = C.elisa_go_abi_version_minor
	ABIVersionPatch uint32 = C.elisa_go_abi_version_patch
)

// WidgetHandle is an opaque generation-scoped retained-widget token received
// by an application callback. Do not persist it across a tree reset/rebuild.
type WidgetHandle uint64

// InvalidWidgetHandle is the callback sentinel for an invalid target.
const InvalidWidgetHandle WidgetHandle = 0

// Valid reports whether a callback supplied a nonzero widget token.
func (handle WidgetHandle) Valid() bool {
	return handle != InvalidWidgetHandle
}

// ABIVersion returns the packed version reported by the linked Elisa
// implementation. The result is 0 only when the linked boundary is absent or
// otherwise invalid.
func ABIVersion() uint32 {
	return uint32(C.elisa_ui_abi_version())
}

// ExpectedABIVersion returns the version this binding was compiled against.
func ExpectedABIVersion() uint32 {
	return uint32(C.elisa_go_abi_version)
}

// DispatchEvent delivers one scalar event to the linked Elisa application.
// Calls are synchronous and must be serialized by the caller on the UI owner.
func DispatchEvent(event Event) {
	C.elisa_ui_dispatch_event(
		C.int32_t(event.Kind),
		C.float(event.X),
		C.float(event.Y),
		C.float(event.DX),
		C.float(event.DY),
		C.int32_t(event.Code),
	)
}

// DispatchTextInput copies committed UTF-8 text through the borrowed C
// boundary. The framework applies its bounded length and malformed-input
// policy before invoking the application callback.
func DispatchTextInput(text string) {
	bytes := []byte(text)
	if len(bytes) == 0 {
		C.elisa_ui_dispatch_text_input(nil, 0)
		return
	}
	C.elisa_ui_dispatch_text_input(
		(*C.char)(unsafe.Pointer(&bytes[0])),
		C.size_t(len(bytes)),
	)
	runtime.KeepAlive(bytes)
}

// DispatchTextEditing delivers live UTF-8 IME composition text. Selection
// offsets are Unicode-scalar positions and are clamped by Elisa.
func DispatchTextEditing(text string, selectedStart, selectedLength int32) {
	bytes := []byte(text)
	if len(bytes) == 0 {
		C.elisa_ui_dispatch_text_editing(nil, 0, C.int32_t(selectedStart), C.int32_t(selectedLength))
		return
	}
	C.elisa_ui_dispatch_text_editing(
		(*C.char)(unsafe.Pointer(&bytes[0])),
		C.size_t(len(bytes)),
		C.int32_t(selectedStart),
		C.int32_t(selectedLength),
	)
	runtime.KeepAlive(bytes)
}

// SetViewport sets the logical viewport. Negative or non-finite extents are
// normalized by Elisa according to the C ABI contract.
func SetViewport(width, height float32) {
	C.elisa_ui_set_viewport(C.float(width), C.float(height))
}

// Viewport returns the normalized logical viewport from the linked framework.
func Viewport() (width, height float32) {
	return float32(C.elisa_ui_viewport_width()), float32(C.elisa_ui_viewport_height())
}
