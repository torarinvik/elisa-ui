//! Safe Rust wrapper over elisa-ui's stable C boundary.
//!
//! This module is the Rust face of `include/elisa_ui.h`. It owns the two things
//! the C boundary cannot express: borrowed text is a `&str` whose lifetime ends
//! at the call, and a retained widget identity is an opaque `WidgetHandle`
//! that cannot be decoded or persisted across a tree reset.
//!
//! The application callbacks (`elisa_ui_on_*`) remain the caller's to
//! implement, exactly as in C; this wrapper only supplies the typed host-side
//! calls. It adds no dependency to applications that choose another framework.

// The full published vocabulary is part of the wrapper's surface even when a
// particular example uses only part of it.
#![allow(dead_code)]

use core::ffi::c_char;

/// Mirrors `elisa_ui_event` field for field.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Event {
    pub kind: i32,
    pub x: f32,
    pub y: f32,
    pub dx: f32,
    pub dy: f32,
    pub code: i32,
}

/// Published wire ordinals. Stable across minor/patch ABI changes.
pub mod event_kind {
    pub const NONE: i32 = 0;
    pub const QUIT: i32 = 1;
    pub const POINTER_MOVE: i32 = 2;
    pub const POINTER_DOWN: i32 = 3;
    pub const POINTER_UP: i32 = 4;
    pub const POINTER_LEAVE: i32 = 5;
    pub const KEY_DOWN: i32 = 6;
    pub const KEY_UP: i32 = 7;
    pub const RESIZE: i32 = 8;
    pub const SCROLL: i32 = 9;
    pub const GAMEPAD_BUTTON: i32 = 10;
    pub const GAMEPAD_AXIS: i32 = 11;
    pub const FOCUS_GAINED: i32 = 12;
    pub const FOCUS_LOST: i32 = 13;
}

/// Opaque retained-widget identity. The token is valid only for the current
/// retained-tree lifetime; zero means invalid.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct WidgetHandle(pub u64);

impl WidgetHandle {
    pub const INVALID: WidgetHandle = WidgetHandle(0);

    pub fn is_valid(self) -> bool {
        self.0 != 0
    }
}

impl Default for WidgetHandle {
    fn default() -> Self {
        WidgetHandle::INVALID
    }
}

extern "C" {
    pub fn elisa_ui_abi_version() -> u32;
    pub fn elisa_ui_dispatch_event(kind: i32, x: f32, y: f32, dx: f32, dy: f32, code: i32);
    pub fn elisa_ui_dispatch_text_input(text: *const c_char, length: usize);
    pub fn elisa_ui_dispatch_text_editing(
        text: *const c_char,
        length: usize,
        selected_start: i32,
        selected_length: i32,
    );
    pub fn elisa_ui_set_viewport(width: f32, height: f32);
    pub fn elisa_ui_viewport_width() -> f32;
    pub fn elisa_ui_viewport_height() -> f32;
}

/// The packed ABI version reported by the linked Elisa implementation.
pub fn abi_version() -> u32 {
    // SAFETY: no arguments and no retained state.
    unsafe { elisa_ui_abi_version() }
}

/// Deliver one event. The struct is passed by value, so no pointer outlives
/// the call.
pub fn dispatch_event(event: Event) {
    // SAFETY: all fields are plain scalars.
    unsafe {
        elisa_ui_dispatch_event(event.kind, event.x, event.y, event.dx, event.dy, event.code)
    }
}

/// Deliver committed UTF-8 text. The `&str` borrow guarantees the bytes outlive
/// the call, which is the lifetime rule the raw C signature states in prose.
pub fn dispatch_text_input(text: &str) {
    // SAFETY: `text` is valid UTF-8 for `text.len()` bytes for the duration of
    // the call; the callee copies before returning.
    unsafe { elisa_ui_dispatch_text_input(text.as_ptr() as *const c_char, text.len()) }
}

/// Deliver live IME composition text with UTF-8 scalar selection offsets.
pub fn dispatch_text_editing(text: &str, selected_start: i32, selected_length: i32) {
    // SAFETY: as `dispatch_text_input`.
    unsafe {
        elisa_ui_dispatch_text_editing(
            text.as_ptr() as *const c_char,
            text.len(),
            selected_start,
            selected_length,
        )
    }
}

/// Set the logical viewport; negative extents are normalized by Elisa.
pub fn set_viewport(width: f32, height: f32) {
    // SAFETY: scalars only.
    unsafe { elisa_ui_set_viewport(width, height) }
}

/// Read back the normalized logical viewport.
pub fn viewport() -> (f32, f32) {
    // SAFETY: no arguments and no retained state.
    unsafe { (elisa_ui_viewport_width(), elisa_ui_viewport_height()) }
}

/// The raw callback record type used by the `elisa_ui_on_event` callback.
pub type RawEvent = Event;

/// A borrowed byte string handed to a callback. Its lifetime ends when the
/// callback returns; copy anything you need to keep.
pub unsafe fn borrowed_str<'a>(text: *const c_char, length: usize) -> Option<&'a str> {
    if text.is_null() {
        return None;
    }
    let bytes = core::slice::from_raw_parts(text as *const u8, length);
    core::str::from_utf8(bytes).ok()
}
