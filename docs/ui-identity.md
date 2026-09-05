# Stable dynamic identity

`UiIdentity` keeps application-owned keys stable while a list or form is
rebuilt. It is intentionally separate from widget position and from the
virtual-list geometry policy:

```text
UiIdentity::begin()
for item in model:
    handle = UiIdentity::claim(item.id)
UiIdentity::finish()
```

Keys keep their slot and generation when rows reorder, so application state
keyed by the handle can preserve focus, selection, scroll anchors, and edit
history. A key omitted from the next transaction is retired; its generation is
advanced before the slot is reusable, so late callbacks carrying an old handle
fail closed. Duplicate keys are rejected instead of aliasing two rows to one
state record.

The registry is fixed-capacity (`MAX_KEYS = 1024`) and allocation-free. If a
model exceeds the bound, `Snapshot::overflowed` is set and the new claim
returns `UiIdentity::invalid()`. Applications should claim all logical model
keys before applying `UiVirtualList::visible_range`; off-screen items still
need identity even when their row widgets are not realized.
