# Application state snapshots

`UiState` provides an explicit, bounded persistence hook for application-owned
values. It never walks the retained widget tree and never serializes a
`UiHandles::Handle`, arena index, reference, or arbitrary heap object.

Applications assign stable numeric IDs to their own fields:

```elisa
include "../../src/core/ui_state.elisa"

UiState::begin()
_ = UiState::put_text(1, draft)
_ = UiState::put_bool(2, sidebar_open)
_ = UiState::put_f32(3, zoom)
length: usize = UiState::copy_to(&bytes[0], capacity)
```

The host may persist the returned versioned blob. After a surface is recreated,
the application passes it back to `UiState::restore`; only a completely valid
snapshot becomes queryable:

```elisa
if UiState::restore(&bytes[0], length):
    draft <- UiState::text(1)
    sidebar_open <- UiState::bool(2, false)
    zoom <- UiState::f32(3, 1.0)
```

The format is capped at 4 KiB and 128 records. Text fields are capped at 1024
bytes, IDs must be unique within one snapshot, and values are typed (`Text`,
`F32`, `I32`, or `Bool`). Bad magic/version, truncation, malformed lengths,
duplicate IDs, unsupported kinds, and capacity exhaustion fail closed. A failed
restore clears the previously queryable snapshot; non-finite IEEE-754 `F32`
payloads are rejected rather than silently coerced to zero. This is application data,
not a framework heap checkpoint; widget handles must be rebuilt and reacquired
after restoration.
