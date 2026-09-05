# Constraint policy

`UiConstraints` keeps size negotiation in Elisa so native and hosted layouts
do not invent different answers for the same widget declaration. A
`Range{minimum, preferred, maximum}` describes one logical axis:

- `minimum` is the required extent;
- `preferred` is an intrinsic/layout hint, clamped into the legal range; and
- `maximum` is an optional cap (`UNBOUNDED`/zero means no cap).

`normalize` repairs malformed declarations and sets `conflict` when a
preferred or maximum value had to be changed. A maximum below the minimum is
raised to the minimum so required content remains accessible. `resolve`
clamps available space to the normalized range and reports whether the lower
or upper bound was used; it does not force every allocation to the preferred
size, allowing containers to distribute extra space normally.

All extents are finite, nonnegative, and bounded by `MAX_EXTENT`. The module
is opt-in and can be used by sizers, responsive arrangements, custom controls,
or future intrinsic text/image measurement without adding state to every
widget handle.
