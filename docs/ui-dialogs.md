# Dialog policy

`UiDialog` is the backend-neutral modal state machine. It keeps a bounded stack
of typed `Alert`, `Confirm`, and `Sheet` records, copies labels into fixed
storage, and returns generation-checked handles. The application owns the
content and decides how to render it; a native or hosted adapter only displays
the current record and reports `Primary`, `Secondary`, `Cancelled`, or `Back`.

`back()` always targets the newest open dialog, which gives mobile back buttons
and desktop Escape handling one consistent policy. `dismiss_owner` cancels all
still-open dialogs for a disposed view or task owner, preventing callbacks from
reopening dead surfaces. Choosing a result closes the dialog but leaves its
handle readable until explicit `dispose`, so the owner can consume the result
after the presentation surface has disappeared. Disposal advances the
generation before the slot can be reused.

The fixed `MAX_DIALOGS` and `TEXT_CAPACITY` bounds make exhaustion and label
truncation observable and allocation-free. The module does not create native
windows, perform permission work, or trap OS navigation; those remain backend
and host responsibilities around this shared policy.
