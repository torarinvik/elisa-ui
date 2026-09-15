# Virtual-list policy

`UiVirtualList` keeps long, uniform lists backend-neutral. An application owns
the item data and widget identities; the module supplies the shared geometry:

- `metrics` normalizes an item extent and inter-item spacing and exposes their
  stride;
- `content_extent` reserves the exact scrollable extent without a trailing
  gap;
- `visible_range` returns a half-open `[first, finish)` row interval with one edge-buffer row
  and an explicit maximum-realized budget; and
- `item_offset`, `count`, and `contains` keep placement and membership checks
  consistent with that interval.
- `semantic_window` computes bounded accessibility navigation metadata for
  logical focus/selection and before/after edges, including targets outside
  the realized range; and
- `move` advances a logical target without requiring its row widget to exist.
- `realize` maps a retained `VisibleRange` onto a bounded pool of application
  row slots, `slot_for` resolves a logical row to its current slot, and
  `slot_generation` gives a stale-rejecting token.

Counts are bounded at `MAX_ITEMS` before entering floating-point geometry.
Negative, zero, or non-finite dimensions become deterministic safe values, and
an empty list always returns an empty range. A zero realization budget means
one row, so callers cannot accidentally disable all semantic or paint work.

Realization keeps a row that stays visible on the same slot and generation, so
per-row state does not flicker while scrolling. A row that leaves the retained
window frees its slot and, if it comes back, crosses a new generation; a late
callback for the old occupancy can be rejected exactly like a stale handle.
Slots are keyed by owner, so one list cannot free or reuse another's rows.
`MAX_REALIZED` bounds the pool; when the visible range is larger than the
budget, the highest rows stay unrealized and the caller chooses the trade-off.

The policy is pure Elisa and is included by `UiWidgets`; native and hosted
adapters only need to realize the returned rows and apply their existing
viewport clipping. This keeps virtualization, scrolling, paint order, and
semantic navigation on the same retained framework facts. Semantic adapters
should expose the logical count independently of the realized widget count.
The retained semantic projection does this today: a virtual-list node carries
its full `collection_count`, while each visible semantic row carries a
one-based `collection_position` and the full `collection_size`. Rebinding a
row slot therefore changes semantic collection metadata even when its stable
widget identity and label stay the same.

For rows that are not realized, an application can attach a typed
`UiVirtualAccessibility::Provider` through `UiHandles`. Elisa validates the
logical index, role, finite value, and bounded UTF-8, then copies the provider's
borrowed label/help into framework scratch before returning the item. Providers
are synchronous and cleared with the retained tree, so a stale list handle
cannot query old application data. Native adapters must copy the returned
scratch views immediately; the provider itself remains application-owned.
For assistive activation of an off-screen row, the same handle can also carry
an `ActivateProvider`. Elisa validates the logical index, invokes it
synchronously, and rejects its result if the callback rebuilt the tree during
the call. This keeps activation out of recycled visual-row slots.

This portable metadata is not yet full native screen-reader virtualization.
The AppKit canvas now publishes a list object with the full logical row count
and accessibility proxies only for currently realized rows; those proxies carry
one-based positions and stable `(list_id, position)` identities. It does not
materialize off-screen rows or yet implement focus-and-scroll traversal. UIKit
still needs a lazy list container wired to these providers and a logical
scroll transaction. Physical VoiceOver / Accessibility Inspector
verification remains required before claiming native collection conformance.
