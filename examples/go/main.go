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
	"strings"
	"unsafe"

	ui "github.com/torarinvik/elisa-ui/bindings/go/elisa_ui"
)

var (
	eventCount          int
	textCount           int
	editingCount        int
	lastStart           int32
	lastLength          int32
	boundedTextCount    int
	invalidPrefixCount  int
	embeddedNulCount    int
	boundedEditingCount int
	validWidgetCount    int
	invalidWidgetCount  int
	lastWidget          ui.WidgetHandle
	lastWidgetEvent     int32
)

//export elisa_ui_on_init
func elisa_ui_on_init() {}

//export elisa_ui_on_frame
func elisa_ui_on_frame() {}

//export elisa_ui_on_widget_event
func elisa_ui_on_widget_event(widget C.uint64_t, event C.int32_t) {
	// The token remains opaque to the binding; only its validity is observable.
	lastWidget = ui.WidgetHandle(widget)
	lastWidgetEvent = int32(event)
	if lastWidget.Valid() {
		validWidgetCount++
	} else {
		invalidWidgetCount++
	}
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
	if len(value) == ui.MaxTextBytes-1 && allX(value) {
		boundedTextCount++
	}
	if string(value) == "ok" {
		invalidPrefixCount++
	}
	if string(value) == "A\x00B" {
		embeddedNulCount++
	}
}

//export elisa_ui_on_text_editing
func elisa_ui_on_text_editing(text *C.char, length C.size_t, start C.int32_t, selected C.int32_t) {
	var value []byte
	if text != nil && length != 0 {
		value = C.GoBytes(unsafe.Pointer(text), C.int(length))
		if string(value) == "é 👋" {
			editingCount++
		}
	}
	lastStart = int32(start)
	lastLength = int32(selected)
	if len(value) == ui.MaxTextBytes-1 && allX(value) && int32(start) == 1000 && int32(selected) == 23 {
		boundedEditingCount++
	}
}

func allX(value []byte) bool {
	for _, item := range value {
		if item != 'x' {
			return false
		}
	}
	return len(value) == ui.MaxTextBytes-1
}

func main() {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	failures := 0
	if ui.ABIVersion() != ui.ExpectedABIVersion() || ui.ABIVersion() == 0 {
		fmt.Fprintln(os.Stderr, "Go host: ABI version mismatch")
		failures++
	}
	if ui.InvalidWidgetHandle.Valid() || !ui.WidgetHandle(1).Valid() {
		fmt.Fprintln(os.Stderr, "Go host: widget handle validity sentinel was incorrect")
		failures++
	}
	elisa_ui_on_widget_event(0, 0)
	elisa_ui_on_widget_event(1, 0)
	if invalidWidgetCount != 1 || validWidgetCount != 1 {
		fmt.Fprintln(os.Stderr, "Go host: widget callback did not preserve opaque-handle validity")
		failures++
	}
	validWidgetCount = 0
	invalidWidgetCount = 0
	ui.ResetWidgetTree()
	root, rootOK := ui.NewColumn(ui.RootWidgetParent(), 8, 4, ui.RGBA(32, 32, 40, 255))
	row, rowOK := ui.NewRow(ui.ParentWidget(root), 0, 8, ui.RGBA(32, 32, 40, 255))
	label, labelOK := ui.NewLabel(ui.ParentWidget(row), "Status", 16, ui.RGBA(255, 255, 255, 255))
	button, buttonOK := ui.NewButton(ui.ParentWidget(row), 120, 36,
		ui.RGBA(48, 48, 56, 255), ui.RGBA(64, 64, 72, 255), ui.RGBA(80, 80, 88, 255))
	checkbox, checkboxOK := ui.NewCheckBox(ui.ParentWidget(row), 24, 24,
		ui.RGBA(48, 48, 56, 255), ui.RGBA(64, 64, 72, 255), ui.RGBA(80, 80, 88, 255))
	radio, radioOK := ui.NewRadioButton(ui.ParentWidget(row), 24, 24,
		ui.RGBA(48, 48, 56, 255), ui.RGBA(64, 64, 72, 255), ui.RGBA(80, 80, 88, 255))
	slider, sliderOK := ui.NewSlider(ui.ParentWidget(row), 160, 24, 0.25,
		ui.RGBA(48, 48, 56, 255), ui.RGBA(64, 64, 72, 255), ui.RGBA(80, 80, 88, 255))
	progress, progressOK := ui.NewProgressBar(ui.ParentWidget(row), 160, 12, 0.5,
		ui.RGBA(48, 48, 56, 255), ui.RGBA(64, 64, 72, 255))
	field, fieldOK := ui.NewTextField(ui.ParentWidget(row), "Hi é", 180, 32, 16,
		ui.RGBA(255, 255, 255, 255), ui.RGBA(32, 32, 40, 255))
	fieldPrefix := make([]byte, 4)
	fieldCopied, fieldCopyOK := ui.CopyWidgetText(field, fieldPrefix)
	fieldText, fieldTextOK := ui.WidgetText(field)
	fieldLength, fieldLengthOK := ui.WidgetTextLength(field)
	if !rootOK || !rowOK || !labelOK || !buttonOK || !ui.WidgetIsLive(label) ||
		!checkboxOK || !radioOK || !sliderOK || !progressOK || !fieldOK ||
		!ui.SetWidgetText(button, "Run", 16, ui.RGBA(255, 255, 255, 255)) ||
		!ui.SetWidgetEnabled(button, false) || ui.ActivateWidget(button) ||
		!ui.SetWidgetEnabled(button, true) || !ui.SetWidgetVisible(button, true) ||
		!ui.SetWidgetSelected(checkbox, true) || !ui.WidgetSelected(checkbox) ||
		!ui.SetWidgetSelected(radio, true) || !ui.WidgetSelected(radio) ||
		ui.SetWidgetSelected(button, true) ||
		!ui.SetWidgetValue(slider, 1.25) || ui.WidgetValue(slider) != 1 ||
		!ui.SetWidgetValue(progress, 0.75) || ui.WidgetValue(progress) != 0.75 ||
		ui.SetWidgetValue(button, 0.5) ||
		!ui.RequestTextFocus(field) || !fieldLengthOK || fieldLength != 5 ||
		!fieldCopyOK || fieldCopied != 3 || string(fieldPrefix[:3]) != "Hi " ||
		!fieldTextOK || fieldText != "Hi é" ||
		ui.RequestTextFocus(button) ||
		!ui.ActivateWidget(button) || validWidgetCount != 1 || lastWidget != button || lastWidgetEvent != 0 {
		fmt.Fprintln(os.Stderr, "Go host: retained-control create/use/callback path failed")
		failures++
	}
	ui.ResetWidgetTree()
	if ui.WidgetIsLive(button) || ui.SetWidgetEnabled(button, true) ||
		ui.SetWidgetSelected(checkbox, false) || ui.SetWidgetValue(slider, 0.5) ||
		ui.RequestTextFocus(field) ||
		func() bool { _, ok := ui.WidgetTextLength(field); return ok }() ||
		ui.ActivateWidget(button) {
		fmt.Fprintln(os.Stderr, "Go host: tree reset did not reject a stale handle")
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

	// The cap bisects the following two-byte rune. Only the valid, bounded
	// prefix may cross cgo; the megabyte tail is borrowed from the source string
	// and is never copied into a temporary Go byte slice.
	largeText := strings.Repeat("x", ui.MaxTextBytes-1) + "é" + strings.Repeat("y", 1<<20)
	ui.DispatchTextInput(largeText)
	if boundedTextCount != 1 {
		fmt.Fprintln(os.Stderr, "Go host: oversized UTF-8 input was not bounded at a rune boundary")
		failures++
	}
	ui.DispatchTextEditing(largeText, 1000, 1000)
	if boundedEditingCount != 1 {
		fmt.Fprintln(os.Stderr, "Go host: oversized IME input or selection was not bounded")
		failures++
	}
	ui.DispatchTextInput("ok" + string([]byte{0xff}) + "discard")
	if invalidPrefixCount != 1 {
		fmt.Fprintln(os.Stderr, "Go host: malformed UTF-8 was not truncated to its valid prefix")
		failures++
	}
	ui.DispatchTextInput("A\x00B")
	if embeddedNulCount != 1 {
		fmt.Fprintln(os.Stderr, "Go host: counted UTF-8 text lost its embedded NUL")
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
