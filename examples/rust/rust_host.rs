//! Minimal Rust host/app example for elisa-ui's stable C boundary.
//!
//! It implements the application callbacks and drives the typed host calls
//! through the safe wrapper in `bindings/rust/elisa_ui.rs`. This example is
//! voluntary: a Rust application that chose another framework never links it.

#[path = "../../bindings/rust/elisa_ui.rs"]
mod elisa_ui;

use core::ffi::c_char;
use elisa_ui::{event_kind, Event, WidgetHandle};
use std::sync::atomic::{AtomicI32, AtomicUsize, Ordering};

static EVENT_COUNT: AtomicUsize = AtomicUsize::new(0);
static TEXT_OK: AtomicUsize = AtomicUsize::new(0);
static EDITING_OK: AtomicUsize = AtomicUsize::new(0);
static EDITING_START: AtomicI32 = AtomicI32::new(-1);
static EDITING_LENGTH: AtomicI32 = AtomicI32::new(-1);

#[no_mangle]
pub extern "C" fn elisa_ui_on_init() {}

#[no_mangle]
pub extern "C" fn elisa_ui_on_frame() {}

#[no_mangle]
pub extern "C" fn elisa_ui_on_widget_event(_widget: u64, _event: i32) {
    let _ = WidgetHandle::INVALID.is_valid();
}

#[no_mangle]
pub extern "C" fn elisa_ui_on_event(event: *const Event) {
    if event.is_null() {
        return;
    }
    // SAFETY: the callee borrows a valid record for the call.
    let event = unsafe { *event };
    if event.kind == event_kind::POINTER_DOWN && event.x == 12.5 && event.y == 34.25 && event.code == 2 {
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
