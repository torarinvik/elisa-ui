// Package elisa_ui is the optional Go host face of elisa-ui's stable C ABI.
//
// It is deliberately small: the linked Elisa component owns retained widgets,
// callbacks, and all framework state. Go owns scalar values and opaque widget
// identities, and borrows bounded immutable string prefixes for synchronous
// calls. Stateful calls must be made on one UI-owner OS thread (typically a
// goroutine locked with runtime.LockOSThread); this package adds no scheduler
// or mutex.
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
	elisa_go_max_text_bytes = ELISA_UI_MAX_TEXT_BYTES,
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
	elisa_go_event_focus_lost = ELISA_UI_EVENT_FOCUS_LOST,
	elisa_go_event_pointer_cancel = ELISA_UI_EVENT_POINTER_CANCEL,
	elisa_go_event_contact_began = ELISA_UI_EVENT_CONTACT_BEGAN,
	elisa_go_event_contact_moved = ELISA_UI_EVENT_CONTACT_MOVED,
	elisa_go_event_contact_ended = ELISA_UI_EVENT_CONTACT_ENDED,
	elisa_go_event_contact_cancelled = ELISA_UI_EVENT_CONTACT_CANCELLED
};
*/
import "C"

import (
	"runtime"
	"unicode/utf8"
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
	EventNone             int32 = C.elisa_go_event_none
	EventQuit             int32 = C.elisa_go_event_quit
	EventPointerMove      int32 = C.elisa_go_event_pointer_move
	EventPointerDown      int32 = C.elisa_go_event_pointer_down
	EventPointerUp        int32 = C.elisa_go_event_pointer_up
	EventPointerLeave     int32 = C.elisa_go_event_pointer_leave
	EventKeyDown          int32 = C.elisa_go_event_key_down
	EventKeyUp            int32 = C.elisa_go_event_key_up
	EventResize           int32 = C.elisa_go_event_resize
	EventScroll           int32 = C.elisa_go_event_scroll
	EventGamepadButton    int32 = C.elisa_go_event_gamepad_button
	EventGamepadAxis      int32 = C.elisa_go_event_gamepad_axis
	EventFocusGained      int32 = C.elisa_go_event_focus_gained
	EventFocusLost        int32 = C.elisa_go_event_focus_lost
	EventPointerCancel    int32 = C.elisa_go_event_pointer_cancel
	EventContactBegan     int32 = C.elisa_go_event_contact_began
	EventContactMoved     int32 = C.elisa_go_event_contact_moved
	EventContactEnded     int32 = C.elisa_go_event_contact_ended
	EventContactCancelled int32 = C.elisa_go_event_contact_cancelled
)

const (
	ContactFinger   int32 = 0
	ContactStylus   int32 = 1
	ContactIndirect int32 = 2
	ContactUnknown  int32 = 3
)

// ABI version components are kept as Go constants for callers that want to
// reject a major mismatch before making stateful calls.
const (
	ABIVersionMajor uint32 = C.elisa_go_abi_version_major
	ABIVersionMinor uint32 = C.elisa_go_abi_version_minor
	ABIVersionPatch uint32 = C.elisa_go_abi_version_patch
)

// MaxTextBytes is the shared C/Elisa cap for one committed-text or IME call.
const MaxTextBytes int = C.elisa_go_max_text_bytes

// WidgetHandle is an opaque generation-scoped retained-widget token received
// by an application callback. Do not persist it across a tree reset/rebuild.
type WidgetHandle uint64

// InvalidWidgetHandle is the callback sentinel for an invalid target.
const InvalidWidgetHandle WidgetHandle = 0

// Valid reports whether a callback supplied a nonzero widget token.
func (handle WidgetHandle) Valid() bool {
	return handle != InvalidWidgetHandle
}

// WidgetParent distinguishes a valid root insertion point from an invalid
// widget token. Construct values with RootWidgetParent or ParentWidget.
type WidgetParent struct {
	token uint64
	valid bool
}

// RootWidgetParent selects the root of the retained tree.
func RootWidgetParent() WidgetParent {
	return WidgetParent{valid: true}
}

// ParentWidget selects a live-or-stale token as a parent. Elisa validates its
// generation and container kind when the builder is called.
func ParentWidget(handle WidgetHandle) WidgetParent {
	return WidgetParent{token: uint64(handle), valid: handle.Valid()}
}

// ColorRgba packs channels as 0xRRGGBBAA, the representation used by the C ABI.
type ColorRgba uint32

func RGBA(red, green, blue, alpha uint8) ColorRgba {
	return ColorRgba(uint32(red)<<24 | uint32(green)<<16 | uint32(blue)<<8 | uint32(alpha))
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

// ResetWidgetTree destroys the current retained tree and invalidates all of
// its widget tokens.
func ResetWidgetTree() {
	C.elisa_ui_widget_tree_reset()
}

func widgetResult(token C.elisa_ui_widget_handle) (WidgetHandle, bool) {
	if token == 0 {
		return InvalidWidgetHandle, false
	}
	return WidgetHandle(token), true
}

// NewColumn creates a retained vertical container beneath the root or a live
// container. Colors use packed RGBA bytes.
func NewColumn(parent WidgetParent, padding, spacing float32, color ColorRgba) (WidgetHandle, bool) {
	if !parent.valid {
		return InvalidWidgetHandle, false
	}
	token := C.elisa_ui_widget_column(
		C.elisa_ui_widget_handle(parent.token), C.float(padding), C.float(spacing), C.uint32_t(color),
	)
	return widgetResult(token)
}

func NewRow(parent WidgetParent, padding, spacing float32, color ColorRgba) (WidgetHandle, bool) {
	if !parent.valid {
		return InvalidWidgetHandle, false
	}
	token := C.elisa_ui_widget_row(
		C.elisa_ui_widget_handle(parent.token), C.float(padding), C.float(spacing), C.uint32_t(color),
	)
	return widgetResult(token)
}

// NewLabel copies a bounded valid UTF-8 prefix into retained Elisa storage.
func NewLabel(parent WidgetParent, text string, size float32, color ColorRgba) (WidgetHandle, bool) {
	if !parent.valid {
		return InvalidWidgetHandle, false
	}
	bounded := validTextPrefix(text)
	var pointer *C.char
	if len(bounded) != 0 {
		pointer = (*C.char)(unsafe.Pointer(unsafe.StringData(bounded)))
	}
	token := C.elisa_ui_widget_label(
		C.elisa_ui_widget_handle(parent.token), pointer, C.size_t(len(bounded)), C.float(size), C.uint32_t(color),
	)
	runtime.KeepAlive(bounded)
	return widgetResult(token)
}

// NewTextField creates an editable field with a counted UTF-8 initial value.
// Compose a separate label when a visible field caption is needed.
func NewTextField(parent WidgetParent, initial string, minWidth, minHeight, size float32, ink, fill ColorRgba) (WidgetHandle, bool) {
	if !parent.valid {
		return InvalidWidgetHandle, false
	}
	bounded := validTextPrefix(initial)
	var pointer *C.char
	if len(bounded) != 0 {
		pointer = (*C.char)(unsafe.Pointer(unsafe.StringData(bounded)))
	}
	token := C.elisa_ui_widget_text_field(
		C.elisa_ui_widget_handle(parent.token), pointer, C.size_t(len(bounded)),
		C.float(minWidth), C.float(minHeight), C.float(size), C.uint32_t(ink), C.uint32_t(fill),
	)
	runtime.KeepAlive(bounded)
	return widgetResult(token)
}

func NewButton(parent WidgetParent, minWidth, minHeight float32, color, hover, press ColorRgba) (WidgetHandle, bool) {
	if !parent.valid {
		return InvalidWidgetHandle, false
	}
	token := C.elisa_ui_widget_button(
		C.elisa_ui_widget_handle(parent.token), C.float(minWidth), C.float(minHeight),
		C.uint32_t(color), C.uint32_t(hover), C.uint32_t(press),
	)
	return widgetResult(token)
}

// NewRadioButton creates a radio control. Radio grouping policy belongs to the caller.
func NewRadioButton(parent WidgetParent, minWidth, minHeight float32, color, hover, press ColorRgba) (WidgetHandle, bool) {
	if !parent.valid {
		return InvalidWidgetHandle, false
	}
	token := C.elisa_ui_widget_radio_button(
		C.elisa_ui_widget_handle(parent.token), C.float(minWidth), C.float(minHeight),
		C.uint32_t(color), C.uint32_t(hover), C.uint32_t(press),
	)
	return widgetResult(token)
}

// NewCheckBox creates a check box beneath a live container.
func NewCheckBox(parent WidgetParent, minWidth, minHeight float32, color, hover, press ColorRgba) (WidgetHandle, bool) {
	if !parent.valid {
		return InvalidWidgetHandle, false
	}
	token := C.elisa_ui_widget_check_box(
		C.elisa_ui_widget_handle(parent.token), C.float(minWidth), C.float(minHeight),
		C.uint32_t(color), C.uint32_t(hover), C.uint32_t(press),
	)
	return widgetResult(token)
}

// NewSlider creates an interactive slider whose value is normalized to [0, 1].
func NewSlider(parent WidgetParent, minWidth, minHeight, value float32, track, fill, thumb ColorRgba) (WidgetHandle, bool) {
	if !parent.valid {
		return InvalidWidgetHandle, false
	}
	token := C.elisa_ui_widget_slider(
		C.elisa_ui_widget_handle(parent.token), C.float(minWidth), C.float(minHeight), C.float(value),
		C.uint32_t(track), C.uint32_t(fill), C.uint32_t(thumb),
	)
	return widgetResult(token)
}

// NewProgressBar creates a non-interactive normalized progress indicator.
func NewProgressBar(parent WidgetParent, minWidth, minHeight, value float32, track, fill ColorRgba) (WidgetHandle, bool) {
	if !parent.valid {
		return InvalidWidgetHandle, false
	}
	token := C.elisa_ui_widget_progress_bar(
		C.elisa_ui_widget_handle(parent.token), C.float(minWidth), C.float(minHeight), C.float(value),
		C.uint32_t(track), C.uint32_t(fill),
	)
	return widgetResult(token)
}

// SetWidgetText copies a bounded valid UTF-8 prefix into Elisa-owned retained
// storage before returning. Embedded NUL remains ordinary counted text.
func SetWidgetText(widget WidgetHandle, text string, size float32, color ColorRgba) bool {
	if !widget.Valid() {
		return false
	}
	bounded := validTextPrefix(text)
	var pointer *C.char
	if len(bounded) != 0 {
		pointer = (*C.char)(unsafe.Pointer(unsafe.StringData(bounded)))
	}
	accepted := C.elisa_ui_widget_set_text(
		C.elisa_ui_widget_handle(widget), pointer, C.size_t(len(bounded)), C.float(size), C.uint32_t(color),
	) == 1
	runtime.KeepAlive(bounded)
	return accepted
}

func SetWidgetEnabled(widget WidgetHandle, enabled bool) bool {
	if !widget.Valid() {
		return false
	}
	var value C.int32_t
	if enabled {
		value = 1
	}
	return C.elisa_ui_widget_set_enabled(C.elisa_ui_widget_handle(widget), value) == 1
}

func SetWidgetVisible(widget WidgetHandle, visible bool) bool {
	if !widget.Valid() {
		return false
	}
	var value C.int32_t
	if visible {
		value = 1
	}
	return C.elisa_ui_widget_set_visible(C.elisa_ui_widget_handle(widget), value) == 1
}

// SetWidgetSelected applies to radio buttons and check boxes only.
func SetWidgetSelected(widget WidgetHandle, selected bool) bool {
	if !widget.Valid() {
		return false
	}
	var value C.int32_t
	if selected {
		value = 1
	}
	return C.elisa_ui_widget_set_selected(C.elisa_ui_widget_handle(widget), value) == 1
}

// WidgetSelected returns false for stale or non-selection controls.
func WidgetSelected(widget WidgetHandle) bool {
	if !widget.Valid() {
		return false
	}
	return C.elisa_ui_widget_selected(C.elisa_ui_widget_handle(widget)) == 1
}

// SetWidgetValue applies to sliders and progress bars; Elisa normalizes to [0, 1].
func SetWidgetValue(widget WidgetHandle, value float32) bool {
	if !widget.Valid() {
		return false
	}
	return C.elisa_ui_widget_set_value(C.elisa_ui_widget_handle(widget), C.float(value)) == 1
}

// WidgetValue returns zero for stale or unsupported handles.
func WidgetValue(widget WidgetHandle) float32 {
	if !widget.Valid() {
		return 0
	}
	return float32(C.elisa_ui_widget_value(C.elisa_ui_widget_handle(widget)))
}

// RequestTextFocus requests focus for a live text field.
func RequestTextFocus(widget WidgetHandle) bool {
	if !widget.Valid() {
		return false
	}
	return C.elisa_ui_widget_request_text_focus(C.elisa_ui_widget_handle(widget)) == 1
}

// WidgetTextLength returns the UTF-8 byte length, or false for stale/non-text handles.
func WidgetTextLength(widget WidgetHandle) (int, bool) {
	if !widget.Valid() {
		return 0, false
	}
	length := int32(C.elisa_ui_widget_text_length(C.elisa_ui_widget_handle(widget)))
	if length < 0 {
		return 0, false
	}
	return int(length), true
}

// CopyWidgetText copies a UTF-8-safe prefix into caller-owned storage. The C
// boundary does not retain the byte-slice pointer.
func CopyWidgetText(widget WidgetHandle, destination []byte) (int, bool) {
	if !widget.Valid() {
		return 0, false
	}
	if _, ok := WidgetTextLength(widget); !ok {
		return 0, false
	}
	var pointer *C.char
	if len(destination) != 0 {
		pointer = (*C.char)(unsafe.Pointer(&destination[0]))
	}
	copied := int(C.elisa_ui_widget_copy_text(
		C.elisa_ui_widget_handle(widget), pointer, C.size_t(len(destination)),
	))
	runtime.KeepAlive(destination)
	return copied, true
}

// WidgetText reads the complete bounded field value as a Go string.
func WidgetText(widget WidgetHandle) (string, bool) {
	length, ok := WidgetTextLength(widget)
	if !ok {
		return "", false
	}
	bytes := make([]byte, length)
	copied, ok := CopyWidgetText(widget, bytes)
	if !ok || copied != length || !utf8.Valid(bytes) {
		return "", false
	}
	return string(bytes), true
}

// ActivateWidget runs the retained control's callback synchronously.
func ActivateWidget(widget WidgetHandle) bool {
	if !widget.Valid() {
		return false
	}
	return C.elisa_ui_widget_activate(C.elisa_ui_widget_handle(widget)) == 1
}

func WidgetIsLive(widget WidgetHandle) bool {
	if !widget.Valid() {
		return false
	}
	return C.elisa_ui_widget_is_valid(C.elisa_ui_widget_handle(widget)) == 1
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

// DispatchTextInput borrows at most MaxTextBytes of a valid UTF-8 prefix from
// text for the duration of the synchronous C call. The Elisa boundary copies
// that prefix into its fixed staging slot before invoking the app callback.
func DispatchTextInput(text string) {
	bounded := validTextPrefix(text)
	if len(bounded) == 0 {
		C.elisa_ui_dispatch_text_input(nil, 0)
		return
	}
	C.elisa_ui_dispatch_text_input(
		(*C.char)(unsafe.Pointer(unsafe.StringData(bounded))),
		C.size_t(len(bounded)),
	)
	runtime.KeepAlive(bounded)
}

// DispatchTextEditing delivers live UTF-8 IME composition text. Selection
// offsets are Unicode-scalar positions and are clamped by Elisa.
func DispatchTextEditing(text string, selectedStart, selectedLength int32) {
	bounded := validTextPrefix(text)
	if len(bounded) == 0 {
		C.elisa_ui_dispatch_text_editing(nil, 0, C.int32_t(selectedStart), C.int32_t(selectedLength))
		return
	}
	C.elisa_ui_dispatch_text_editing(
		(*C.char)(unsafe.Pointer(unsafe.StringData(bounded))),
		C.size_t(len(bounded)),
		C.int32_t(selectedStart),
		C.int32_t(selectedLength),
	)
	runtime.KeepAlive(bounded)
}

// validTextPrefix bounds the scan and borrowed extent before crossing cgo. It
// stops at malformed UTF-8 or a rune that would cross the byte cap; slicing a
// string does not allocate or copy its backing bytes.
func validTextPrefix(text string) string {
	limit := len(text)
	if limit > MaxTextBytes {
		limit = MaxTextBytes
	}
	for offset := 0; offset < limit; {
		r, size := utf8.DecodeRuneInString(text[offset:limit])
		if r == utf8.RuneError && size == 1 && text[offset] >= utf8.RuneSelf {
			return text[:offset]
		}
		offset += size
	}
	return text[:limit]
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
