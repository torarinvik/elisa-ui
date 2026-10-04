//! Minimal Rust host/app example for elisa-ui's stable C boundary.
//!
//! It implements the application callbacks and drives the typed host calls
//! through the safe wrapper in `bindings/rust/elisa_ui.rs`. This example is
//! voluntary: a Rust application that chose another framework never links it.

#[path = "../../bindings/rust/elisa_ui.rs"]
mod elisa_ui;

use core::ffi::c_char;
use elisa_ui::{event_kind, ColorRgba, Event, WidgetHandle, WidgetParent};
use std::sync::atomic::{AtomicI32, AtomicU64, AtomicUsize, Ordering};

static EVENT_COUNT: AtomicUsize = AtomicUsize::new(0);
static TEXT_OK: AtomicUsize = AtomicUsize::new(0);
static EDITING_OK: AtomicUsize = AtomicUsize::new(0);
static EDITING_START: AtomicI32 = AtomicI32::new(-1);
static EDITING_LENGTH: AtomicI32 = AtomicI32::new(-1);
static WIDGET_EVENT_COUNT: AtomicUsize = AtomicUsize::new(0);
static LAST_WIDGET: AtomicU64 = AtomicU64::new(0);
static LAST_WIDGET_EVENT: AtomicI32 = AtomicI32::new(-1);

#[no_mangle]
pub extern "C" fn elisa_ui_on_init() {}

#[no_mangle]
pub extern "C" fn elisa_ui_on_frame() {}

#[no_mangle]
pub extern "C" fn elisa_ui_on_widget_event(widget: u64, event: i32) {
    LAST_WIDGET.store(widget, Ordering::SeqCst);
    LAST_WIDGET_EVENT.store(event, Ordering::SeqCst);
    WIDGET_EVENT_COUNT.fetch_add(1, Ordering::SeqCst);
}

#[no_mangle]
pub extern "C" fn elisa_ui_on_event(event: *const Event) {
    if event.is_null() {
        return;
    }
    // SAFETY: the callee borrows a valid record for the call.
    let event = unsafe { *event };
    if event.kind == event_kind::POINTER_DOWN
        && event.x == 12.5
        && event.y == 34.25
        && event.code == 2
    {
        EVENT_COUNT.fetch_add(1, Ordering::SeqCst);
    }
}

#[no_mangle]
pub extern "C" fn elisa_ui_on_text_input(text: *const c_char, length: usize) {
    // SAFETY: the pointer/length pair is borrowed for the call.
    if let Some(value) = unsafe { elisa_ui::borrowed_str(text, length) } {
        if value == "Hé 👋" {
            TEXT_OK.fetch_add(1, Ordering::SeqCst);
        }
    }
}

#[no_mangle]
pub extern "C" fn elisa_ui_on_text_editing(
    text: *const c_char,
    length: usize,
    selected_start: i32,
    selected_length: i32,
) {
    // SAFETY: as `elisa_ui_on_text_input`.
    if let Some(value) = unsafe { elisa_ui::borrowed_str(text, length) } {
        if value == "é 👋" {
            EDITING_OK.fetch_add(1, Ordering::SeqCst);
        }
    }
    EDITING_START.store(selected_start, Ordering::SeqCst);
    EDITING_LENGTH.store(selected_length, Ordering::SeqCst);
}

fn main() {
    let mut failures = 0;

    if elisa_ui::abi_version() == 0 {
        eprintln!("Rust host: ABI version was zero");
        failures += 1;
    }

    elisa_ui::widget_tree_reset();
    let root = elisa_ui::widget_column(
        WidgetParent::Root,
        8.0,
        4.0,
        ColorRgba::new(32, 32, 40, 255),
    )
    .expect("root column should be created");
    let row = elisa_ui::widget_row(
        WidgetParent::Widget(root),
        0.0,
        8.0,
        ColorRgba::new(32, 32, 40, 255),
    )
    .expect("row should be created under the column");
    let label = elisa_ui::widget_label(
        WidgetParent::Widget(row),
        "Status",
        16.0,
        ColorRgba::new(255, 255, 255, 255),
    )
    .expect("label should be created under the row");
    let button = elisa_ui::widget_button(
        WidgetParent::Widget(row),
        120.0,
        36.0,
        ColorRgba::new(48, 48, 56, 255),
        ColorRgba::new(64, 64, 72, 255),
        ColorRgba::new(80, 80, 88, 255),
    )
    .expect("button should be created under a live parent");
    let checkbox = elisa_ui::widget_check_box(
        WidgetParent::Widget(row),
        24.0,
        24.0,
        ColorRgba::new(48, 48, 56, 255),
        ColorRgba::new(64, 64, 72, 255),
        ColorRgba::new(80, 80, 88, 255),
    )
    .expect("check box should be created under a live parent");
    let radio = elisa_ui::widget_radio_button(
        WidgetParent::Widget(row),
        24.0,
        24.0,
        ColorRgba::new(48, 48, 56, 255),
        ColorRgba::new(64, 64, 72, 255),
        ColorRgba::new(80, 80, 88, 255),
    )
    .expect("radio button should be created under a live parent");
    let slider = elisa_ui::widget_slider(
        WidgetParent::Widget(row),
        160.0,
        24.0,
        0.25,
        ColorRgba::new(48, 48, 56, 255),
        ColorRgba::new(64, 64, 72, 255),
        ColorRgba::new(80, 80, 88, 255),
    )
    .expect("slider should be created under a live parent");
    let progress = elisa_ui::widget_progress_bar(
        WidgetParent::Widget(row),
        160.0,
        12.0,
        0.5,
        ColorRgba::new(48, 48, 56, 255),
        ColorRgba::new(64, 64, 72, 255),
    )
    .expect("progress bar should be created under a live parent");
    let field = elisa_ui::widget_text_field(
        WidgetParent::Widget(row),
        "Hi é",
        180.0,
        32.0,
        16.0,
        ColorRgba::new(255, 255, 255, 255),
        ColorRgba::new(32, 32, 40, 255),
    )
    .expect("text field should be created under a live parent");
    let mut text_prefix = [0; 4];
    if !elisa_ui::widget_is_live(label)
        || !elisa_ui::widget_set_text(button, "Run", 16.0, ColorRgba::new(255, 255, 255, 255))
        || !elisa_ui::widget_set_enabled(button, true)
        || !elisa_ui::widget_set_visible(button, true)
        || !elisa_ui::widget_set_selected(checkbox, true)
        || !elisa_ui::widget_selected(checkbox)
        || !elisa_ui::widget_set_selected(radio, true)
        || !elisa_ui::widget_selected(radio)
        || elisa_ui::widget_set_selected(button, true)
        || !elisa_ui::widget_set_value(slider, 1.25)
        || elisa_ui::widget_value(slider) != 1.0
        || !elisa_ui::widget_set_value(progress, 0.75)
        || elisa_ui::widget_value(progress) != 0.75
        || elisa_ui::widget_set_value(button, 0.5)
        || !elisa_ui::widget_request_text_focus(field)
        || elisa_ui::widget_text_length(field) != Some(5)
        || elisa_ui::widget_copy_text(field, &mut text_prefix) != Some(3)
        || &text_prefix[..3] != b"Hi "
        || elisa_ui::widget_text(field).as_deref() != Some("Hi é")
        || elisa_ui::widget_text_length(button).is_some()
        || !elisa_ui::widget_activate(button)
        || WIDGET_EVENT_COUNT.load(Ordering::SeqCst) != 1
        || WidgetHandle::from_callback_token(LAST_WIDGET.load(Ordering::SeqCst)) != button
        || LAST_WIDGET_EVENT.load(Ordering::SeqCst) != 0
    {
        eprintln!("Rust host: retained-control create/use/callback path failed");
        failures += 1;
    }
    elisa_ui::widget_tree_reset();
    if elisa_ui::widget_is_live(button)
        || elisa_ui::widget_set_enabled(button, false)
        || elisa_ui::widget_set_selected(checkbox, false)
        || elisa_ui::widget_set_value(slider, 0.5)
        || elisa_ui::widget_request_text_focus(field)
        || elisa_ui::widget_text_length(field).is_some()
        || elisa_ui::widget_activate(button)
    {
        eprintln!("Rust host: tree reset did not reject a stale handle");
        failures += 1;
    }

    elisa_ui::dispatch_event(Event {
        kind: event_kind::POINTER_DOWN,
        x: 12.5,
        y: 34.25,
        dx: 0.0,
        dy: 0.0,
        code: 2,
    });
    if EVENT_COUNT.load(Ordering::SeqCst) != 1 {
        eprintln!("Rust host: pointer event did not survive");
        failures += 1;
    }

    elisa_ui::dispatch_text_input("Hé 👋");
    if TEXT_OK.load(Ordering::SeqCst) != 1 {
        eprintln!("Rust host: UTF-8 text did not survive");
        failures += 1;
    }

    elisa_ui::dispatch_text_editing("é 👋", 99, 99);
    if EDITING_OK.load(Ordering::SeqCst) != 1
        || EDITING_START.load(Ordering::SeqCst) != 3
        || EDITING_LENGTH.load(Ordering::SeqCst) != 0
    {
        eprintln!("Rust host: UTF-8 IME composition did not survive");
        failures += 1;
    }

    elisa_ui::set_viewport(800.0, 600.0);
    if elisa_ui::viewport() != (800.0, 600.0) {
        eprintln!("Rust host: viewport did not survive");
        failures += 1;
    }
    elisa_ui::set_viewport(-10.0, -20.0);
    if elisa_ui::viewport() != (0.0, 0.0) {
        eprintln!("Rust host: negative viewport was not normalized");
        failures += 1;
    }

    if failures == 0 {
        println!("rust: Rust example passed");
        std::process::exit(0);
    }
    eprintln!("rust: Rust example failed");
    std::process::exit(1);
}
