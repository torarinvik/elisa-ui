//! Safe Rust wrapper over elisa-ui's stable C boundary.
//!
//! This module is the Rust face of `include/elisa_ui.h`. It owns the two things
//! the C boundary cannot express: borrowed text is a `&str` whose lifetime ends
//! at the call, and a retained widget identity is an opaque `WidgetHandle`
//! that cannot be decoded or persisted across a tree reset.
//!
//! The application callbacks (`elisa_ui_on_*`) remain the caller's to
//! implement, exactly as in C; this wrapper supplies typed host calls and a
//! bounded retained-control subset. It adds no dependency to applications that
//! choose another framework.

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
    pub const POINTER_CANCEL: i32 = 14;
    pub const CONTACT_BEGAN: i32 = 15;
    pub const CONTACT_MOVED: i32 = 16;
    pub const CONTACT_ENDED: i32 = 17;
    pub const CONTACT_CANCELLED: i32 = 18;
}

pub mod contact_tool {
    pub const FINGER: i32 = 0;
    pub const STYLUS: i32 = 1;
    pub const INDIRECT: i32 = 2;
    pub const UNKNOWN: i32 = 3;
}

/// Opaque retained-widget identity. The token is valid only for the current
/// retained-tree lifetime; zero means invalid.
#[repr(transparent)]
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct WidgetHandle(u64);

impl WidgetHandle {
    pub const INVALID: WidgetHandle = WidgetHandle(0);

    /// Wrap a token received from `elisa_ui_on_widget_event` without exposing
    /// its slot/epoch encoding. Keep it only while the retained tree is live.
    pub const fn from_callback_token(token: u64) -> WidgetHandle {
        WidgetHandle(token)
    }

    pub fn is_valid(self) -> bool {
        self.0 != 0
    }
}

impl Default for WidgetHandle {
    fn default() -> Self {
        WidgetHandle::INVALID
    }
}

/// Packed `0xRRGGBBAA` color used by the retained-control C boundary.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct ColorRgba(u32);

impl ColorRgba {
    pub const fn new(red: u8, green: u8, blue: u8, alpha: u8) -> ColorRgba {
        ColorRgba(
            ((red as u32) << 24) | ((green as u32) << 16) | ((blue as u32) << 8) | alpha as u32,
        )
    }
}

/// A parent choice that distinguishes the root sentinel from an invalid token.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum WidgetParent {
    Root,
    Widget(WidgetHandle),
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
    fn elisa_ui_widget_tree_reset();
    fn elisa_ui_widget_column(parent: u64, padding: f32, spacing: f32, color_rgba: u32) -> u64;
    fn elisa_ui_widget_row(parent: u64, padding: f32, spacing: f32, color_rgba: u32) -> u64;
    fn elisa_ui_widget_label(
        parent: u64,
        text: *const c_char,
        length: usize,
        size: f32,
        color_rgba: u32,
    ) -> u64;
    fn elisa_ui_widget_text_field(
        parent: u64,
        initial: *const c_char,
        length: usize,
        min_width: f32,
        min_height: f32,
        size: f32,
        ink_rgba: u32,
        fill_rgba: u32,
    ) -> u64;
    fn elisa_ui_widget_button(
        parent: u64,
        min_width: f32,
        min_height: f32,
        color_rgba: u32,
        hover_rgba: u32,
        press_rgba: u32,
    ) -> u64;
    fn elisa_ui_widget_radio_button(
        parent: u64,
        min_width: f32,
        min_height: f32,
        color_rgba: u32,
        hover_rgba: u32,
        press_rgba: u32,
    ) -> u64;
    fn elisa_ui_widget_check_box(
        parent: u64,
        min_width: f32,
        min_height: f32,
        color_rgba: u32,
        hover_rgba: u32,
        press_rgba: u32,
    ) -> u64;
    fn elisa_ui_widget_slider(
        parent: u64,
        min_width: f32,
        min_height: f32,
        value: f32,
        track_rgba: u32,
        fill_rgba: u32,
        thumb_rgba: u32,
    ) -> u64;
    fn elisa_ui_widget_progress_bar(
        parent: u64,
        min_width: f32,
        min_height: f32,
        value: f32,
        track_rgba: u32,
        fill_rgba: u32,
    ) -> u64;
    fn elisa_ui_widget_set_text(
        widget: u64,
        text: *const c_char,
        length: usize,
        size: f32,
        color_rgba: u32,
    ) -> i32;
    fn elisa_ui_widget_set_enabled(widget: u64, enabled: i32) -> i32;
    fn elisa_ui_widget_set_visible(widget: u64, visible: i32) -> i32;
    fn elisa_ui_widget_set_selected(widget: u64, selected: i32) -> i32;
    fn elisa_ui_widget_selected(widget: u64) -> i32;
    fn elisa_ui_widget_set_value(widget: u64, value: f32) -> i32;
    fn elisa_ui_widget_value(widget: u64) -> f32;
    fn elisa_ui_widget_request_text_focus(widget: u64) -> i32;
    fn elisa_ui_widget_text_length(widget: u64) -> i32;
    fn elisa_ui_widget_copy_text(widget: u64, destination: *mut c_char, capacity: usize) -> usize;
    fn elisa_ui_widget_activate(widget: u64) -> i32;
    fn elisa_ui_widget_is_valid(widget: u64) -> i32;
}

fn widget_parent_token(parent: WidgetParent) -> Option<u64> {
    match parent {
        WidgetParent::Root => Some(0),
        WidgetParent::Widget(handle) if handle.is_valid() => Some(handle.0),
        WidgetParent::Widget(_) => None,
    }
}

fn widget_result(token: u64) -> Option<WidgetHandle> {
    if token == 0 {
        None
    } else {
        Some(WidgetHandle(token))
    }
}

/// Destroy the current retained tree. Every previously issued handle becomes
/// stale; a later tree starts a new token generation.
pub fn widget_tree_reset() {
    // SAFETY: no arguments or retained pointers cross this boundary.
    unsafe { elisa_ui_widget_tree_reset() }
}

/// Create a vertical container beneath the root or another live container.
pub fn widget_column(
    parent: WidgetParent,
    padding: f32,
    spacing: f32,
    color: ColorRgba,
) -> Option<WidgetHandle> {
    let parent = widget_parent_token(parent)?;
    // SAFETY: only scalar values and a generation-checked opaque parent token.
    let token = unsafe { elisa_ui_widget_column(parent, padding, spacing, color.0) };
    widget_result(token)
}

/// Create a horizontal container beneath the root or another live container.
pub fn widget_row(
    parent: WidgetParent,
    padding: f32,
    spacing: f32,
    color: ColorRgba,
) -> Option<WidgetHandle> {
    let parent = widget_parent_token(parent)?;
    // SAFETY: only scalar values and a generation-checked opaque parent token.
    let token = unsafe { elisa_ui_widget_row(parent, padding, spacing, color.0) };
    widget_result(token)
}

/// Create a retained text label from a counted UTF-8 string.
pub fn widget_label(
    parent: WidgetParent,
    text: &str,
    size: f32,
    color: ColorRgba,
) -> Option<WidgetHandle> {
    let parent = widget_parent_token(parent)?;
    // SAFETY: `text` is valid UTF-8 and borrowed for this synchronous call;
    // Elisa copies its bounded prefix into retained storage.
    let token = unsafe {
        elisa_ui_widget_label(
            parent,
            text.as_ptr() as *const c_char,
            text.len(),
            size,
            color.0,
        )
    };
    widget_result(token)
}

/// Create an editable field with an initial value. Compose its label as a
/// sibling text label; the returned field value remains text-input-owned.
pub fn widget_text_field(
    parent: WidgetParent,
    initial: &str,
    min_width: f32,
    min_height: f32,
    size: f32,
    ink: ColorRgba,
    fill: ColorRgba,
) -> Option<WidgetHandle> {
    let parent = widget_parent_token(parent)?;
    // SAFETY: `initial` is valid UTF-8 and borrowed only for this synchronous
    // call; Elisa copies its bounded prefix into retained field storage.
    let token = unsafe {
        elisa_ui_widget_text_field(
            parent,
            initial.as_ptr() as *const c_char,
            initial.len(),
            min_width,
            min_height,
            size,
            ink.0,
            fill.0,
        )
    };
    widget_result(token)
}

/// Create an interactive button beneath a live container.
pub fn widget_button(
    parent: WidgetParent,
    min_width: f32,
    min_height: f32,
    color: ColorRgba,
    hover: ColorRgba,
    press: ColorRgba,
) -> Option<WidgetHandle> {
    let parent = widget_parent_token(parent)?;
    // SAFETY: only scalar values and a generation-checked opaque parent token.
    let token =
        unsafe { elisa_ui_widget_button(parent, min_width, min_height, color.0, hover.0, press.0) };
    widget_result(token)
}

/// Create a radio button; selection-group behavior remains application-owned.
pub fn widget_radio_button(
    parent: WidgetParent,
    min_width: f32,
    min_height: f32,
    color: ColorRgba,
    hover: ColorRgba,
    press: ColorRgba,
) -> Option<WidgetHandle> {
    let parent = widget_parent_token(parent)?;
    // SAFETY: scalar values and a generation-checked opaque parent token.
    let token = unsafe {
        elisa_ui_widget_radio_button(parent, min_width, min_height, color.0, hover.0, press.0)
    };
    widget_result(token)
}

/// Create a check box beneath a live container.
pub fn widget_check_box(
    parent: WidgetParent,
    min_width: f32,
    min_height: f32,
    color: ColorRgba,
    hover: ColorRgba,
    press: ColorRgba,
) -> Option<WidgetHandle> {
    let parent = widget_parent_token(parent)?;
    // SAFETY: scalar values and a generation-checked opaque parent token.
    let token = unsafe {
        elisa_ui_widget_check_box(parent, min_width, min_height, color.0, hover.0, press.0)
    };
    widget_result(token)
}

/// Create a normalized slider with track, fill, and thumb colors.
pub fn widget_slider(
    parent: WidgetParent,
    min_width: f32,
    min_height: f32,
    value: f32,
    track: ColorRgba,
    fill: ColorRgba,
    thumb: ColorRgba,
) -> Option<WidgetHandle> {
    let parent = widget_parent_token(parent)?;
    // SAFETY: scalar values and a generation-checked opaque parent token.
    let token = unsafe {
        elisa_ui_widget_slider(
            parent, min_width, min_height, value, track.0, fill.0, thumb.0,
        )
    };
    widget_result(token)
}

/// Create a normalized progress indicator beneath a live container.
pub fn widget_progress_bar(
    parent: WidgetParent,
    min_width: f32,
    min_height: f32,
    value: f32,
    track: ColorRgba,
    fill: ColorRgba,
) -> Option<WidgetHandle> {
    let parent = widget_parent_token(parent)?;
    // SAFETY: scalar values and a generation-checked opaque parent token.
    let token = unsafe {
        elisa_ui_widget_progress_bar(parent, min_width, min_height, value, track.0, fill.0)
    };
    widget_result(token)
}

/// Set a control caption. The C boundary copies the counted UTF-8 bytes before
/// returning; embedded NUL bytes remain part of the text.
pub fn widget_set_text(widget: WidgetHandle, text: &str, size: f32, color: ColorRgba) -> bool {
    if !widget.is_valid() {
        return false;
    }
    // SAFETY: `text` is valid UTF-8 and borrowed for this synchronous call.
    unsafe {
        elisa_ui_widget_set_text(
            widget.0,
            text.as_ptr() as *const c_char,
            text.len(),
            size,
            color.0,
        ) == 1
    }
}

pub fn widget_set_enabled(widget: WidgetHandle, enabled: bool) -> bool {
    if !widget.is_valid() {
        return false;
    }
    // SAFETY: scalar arguments only; the boundary validates the token.
    unsafe { elisa_ui_widget_set_enabled(widget.0, enabled as i32) == 1 }
}

pub fn widget_set_visible(widget: WidgetHandle, visible: bool) -> bool {
    if !widget.is_valid() {
        return false;
    }
    // SAFETY: scalar arguments only; the boundary validates the token.
    unsafe { elisa_ui_widget_set_visible(widget.0, visible as i32) == 1 }
}

/// Set selection on a radio button or check box. Radio grouping is caller-owned.
pub fn widget_set_selected(widget: WidgetHandle, selected: bool) -> bool {
    if !widget.is_valid() {
        return false;
    }
    // SAFETY: scalar arguments only; the boundary validates token and kind.
    unsafe { elisa_ui_widget_set_selected(widget.0, selected as i32) == 1 }
}

/// Read selection; false is also returned for stale or non-selection controls.
pub fn widget_selected(widget: WidgetHandle) -> bool {
    if !widget.is_valid() {
        return false;
    }
    // SAFETY: scalar argument only; the boundary validates the token.
    unsafe { elisa_ui_widget_selected(widget.0) == 1 }
}

/// Set a finite slider/progress value, normalized by Elisa to the range [0, 1].
pub fn widget_set_value(widget: WidgetHandle, value: f32) -> bool {
    if !widget.is_valid() {
        return false;
    }
    // SAFETY: scalar arguments only; the boundary validates token, kind, and finiteness.
    unsafe { elisa_ui_widget_set_value(widget.0, value) == 1 }
}

/// Read a slider/progress value; unsupported or stale handles return zero.
pub fn widget_value(widget: WidgetHandle) -> f32 {
    if !widget.is_valid() {
        return 0.0;
    }
    // SAFETY: scalar argument only; the boundary validates the token.
    unsafe { elisa_ui_widget_value(widget.0) }
}

/// Request keyboard focus for a live text field.
pub fn widget_request_text_focus(widget: WidgetHandle) -> bool {
    if !widget.is_valid() {
        return false;
    }
    // SAFETY: scalar argument only; the boundary validates token and kind.
    unsafe { elisa_ui_widget_request_text_focus(widget.0) == 1 }
}

/// Return the current text-field value in bytes, or `None` for stale/non-text handles.
pub fn widget_text_length(widget: WidgetHandle) -> Option<usize> {
    if !widget_is_live(widget) {
        return None;
    }
    // SAFETY: scalar argument only; the boundary validates the token.
    let length = unsafe { elisa_ui_widget_text_length(widget.0) };
    (length >= 0).then_some(length as usize)
}

/// Copy a UTF-8-safe prefix of a text field into caller-owned storage.
/// Returns `None` for stale/non-text handles, otherwise the bytes copied.
pub fn widget_copy_text(widget: WidgetHandle, destination: &mut [u8]) -> Option<usize> {
    widget_text_length(widget)?;
    // SAFETY: the destination is writable for exactly its length and Elisa
    // copies synchronously without retaining the pointer.
    Some(unsafe {
        elisa_ui_widget_copy_text(
            widget.0,
            destination.as_mut_ptr() as *mut c_char,
            destination.len(),
        )
    })
}

/// Read the complete bounded text-field value as a Rust string.
pub fn widget_text(widget: WidgetHandle) -> Option<String> {
    let length = widget_text_length(widget)?;
    let mut bytes = vec![0; length];
    let copied = widget_copy_text(widget, &mut bytes)?;
    if copied != length {
        return None;
    }
    String::from_utf8(bytes).ok()
}

/// Synchronously activate a live control. Its callback may run before return.
pub fn widget_activate(widget: WidgetHandle) -> bool {
    if !widget.is_valid() {
        return false;
    }
    // SAFETY: scalar argument only; the boundary validates the token.
    unsafe { elisa_ui_widget_activate(widget.0) == 1 }
}

/// Ask Elisa whether a token still belongs to the current retained tree.
pub fn widget_is_live(widget: WidgetHandle) -> bool {
    if !widget.is_valid() {
        return false;
    }
    // SAFETY: scalar argument only; the boundary validates the token.
    unsafe { elisa_ui_widget_is_valid(widget.0) == 1 }
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
    unsafe { elisa_ui_dispatch_event(event.kind, event.x, event.y, event.dx, event.dy, event.code) }
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
