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
- `semantic_window` publishes bounded accessibility metadata for the logical
  list, including before/after navigation edges and focused/selected indexes
  even when those rows are outside the realized range; and
- `move` advances a logical target without requiring its row widget to exist.

Counts are bounded at `MAX_ITEMS` before entering floating-point geometry.
Negative, zero, or non-finite dimensions become deterministic safe values, and
an empty list always returns an empty range. A zero realization budget means
one row, so callers cannot accidentally disable all semantic or paint work.

The policy is pure Elisa and is included by `UiWidgets`; native and hosted
adapters only need to realize the returned rows and apply their existing
viewport clipping. This keeps virtualization, scrolling, paint order, and
semantic navigation on the same retained framework facts. Semantic adapters
should expose `total` and the logical focus/selection indexes, then realize or
scroll to an off-screen target when assistive navigation requests it.
