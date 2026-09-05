# Localization and RTL policy

`UiLocalization` keeps layout-affecting locale decisions in Elisa. It detects
common RTL language tags (`ar`, `fa`, `he`, `ur`, `ps`, `dv`, and `yi`), maps
logical start/end to the existing cross-axis alignment enum, and mirrors an
already-resolved item origin without allowing negative geometry.

The active locale is also retained in a bounded Elisa-owned buffer. `set_locale`
canonicalizes ASCII case and underscore separators, returns whether the value
changed, and exposes a monotonic `revision` plus a `snapshot` for inspectors or
adapters. Repeating the same canonical tag is a no-op; a real change invalidates
layout, paint, and semantics together. Oversized tags are copied as a bounded
prefix and reported as `truncated` rather than reaching native code unchecked.

`plural` returns a typed category for the common English/French/Arabic,
Russian/Ukrainian, and Polish rules, with a deterministic one/other fallback
for unknown languages. Message catalogs remain application-owned; they consume
the category instead of making each backend parse locale strings independently.

Claim dynamic item identity through `UiIdentity` before rebuilding a localized
list so RTL/retranslation does not transfer focus or edit state by position.
