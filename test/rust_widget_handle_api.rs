extern crate elisa_ui;

use elisa_ui::WidgetHandle;

fn main() {
    let invalid = WidgetHandle::INVALID;
    let from_callback = WidgetHandle::from_callback_token(0x0000_0001_0000_0002);

    assert!(!invalid.is_valid());
    assert!(from_callback.is_valid());
    assert_ne!(invalid, from_callback);
}
