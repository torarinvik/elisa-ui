//go:build cgo

// This small host demonstrates the optional Go binding against the same C ABI
// used by the C and Rust examples. It is a host-driven app: the linked Elisa
// bridge invokes these callbacks synchronously on the caller's UI thread.
package main

/*
#include <stddef.h>
#include <stdint.h>

// cgo cannot export a Go callback with the header's const-qualified pointer
// declaration. Keep this local mirror layout-only; the binding package itself
// includes and builds against include/elisa_ui.h.
typedef struct elisa_ui_event {
    int32_t kind;
    float x;
    float y;
    float dx;
    float dy;
	int32_t code;
} elisa_ui_event;
_Static_assert(sizeof(elisa_ui_event) == 24, "elisa_ui_event layout changed");
_Static_assert(offsetof(elisa_ui_event, code) == 20, "elisa_ui_event code offset changed");
*/
import "C"

import (
	"fmt"
	"os"
	"runtime"
	"unsafe"

	ui "github.com/torarinvik/elisa-ui/bindings/go/elisa_ui"
)

var (
	eventCount   int
	textCount    int
	editingCount int
	lastStart    int32
	lastLength   int32
)

//export elisa_ui_on_init
func elisa_ui_on_init() {}

//export elisa_ui_on_frame
func elisa_ui_on_frame() {}

//export elisa_ui_on_widget_event
func elisa_ui_on_widget_event(widget C.uint64_t, event C.int32_t) {
	// The token remains opaque to the binding; only its validity is observable.
	_ = ui.WidgetHandle(widget).Valid()
	_ = event
}

//export elisa_ui_on_event
func elisa_ui_on_event(event *C.elisa_ui_event) {
	if event != nil && int32(event.kind) == ui.EventPointerDown &&
		float32(event.x) == 12.5 && float32(event.y) == 34.25 && int32(event.code) == 2 {
		eventCount++
	}
}

//export elisa_ui_on_text_input
func elisa_ui_on_text_input(text *C.char, length C.size_t) {
	if text == nil || length == 0 {
		return
	}
	value := C.GoBytes(unsafe.Pointer(text), C.int(length))
	if string(value) == "Hé 👋" {
		textCount++
	}
}

//export elisa_ui_on_text_editing
func elisa_ui_on_text_editing(text *C.char, length C.size_t, start C.int32_t, selected C.int32_t) {
	if text != nil && length != 0 {
		value := C.GoBytes(unsafe.Pointer(text), C.int(length))
		if string(value) == "é 👋" {
			editingCount++
		}
	}
	lastStart = int32(start)
	lastLength = int32(selected)
}

func main() {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	failures := 0
	if ui.ABIVersion() != ui.ExpectedABIVersion() || ui.ABIVersion() == 0 {
		fmt.Fprintln(os.Stderr, "Go host: ABI version mismatch")
		failures++
	}

	ui.DispatchEvent(ui.Event{Kind: ui.EventPointerDown, X: 12.5, Y: 34.25, Code: 2})
	if eventCount != 1 {
		fmt.Fprintln(os.Stderr, "Go host: pointer event did not survive")
		failures++
	}

	ui.DispatchTextInput("Hé 👋")
	if textCount != 1 {
		fmt.Fprintln(os.Stderr, "Go host: UTF-8 text did not survive")
		failures++
	}

	ui.DispatchTextEditing("é 👋", 99, 99)
	if editingCount != 1 || lastStart != 3 || lastLength != 0 {
		fmt.Fprintln(os.Stderr, "Go host: UTF-8 IME composition did not survive")
		failures++
	}

	ui.SetViewport(800, 600)
	width, height := ui.Viewport()
	if width != 800 || height != 600 {
		fmt.Fprintln(os.Stderr, "Go host: viewport did not survive")
		failures++
	}
	ui.SetViewport(-10, -20)
	width, height = ui.Viewport()
	if width != 0 || height != 0 {
		fmt.Fprintln(os.Stderr, "Go host: negative viewport was not normalized")
		failures++
	}

	if failures != 0 {
		os.Exit(1)
	}
	fmt.Println("go: Go example passed")
}
