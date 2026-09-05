# Localization and RTL policy

`UiLocalization` keeps layout-affecting locale decisions in Elisa. It detects
common RTL language tags (`ar`, `fa`, `he`, `ur`, `ps`, `dv`, and `yi`), maps
logical start/end to the existing cross-axis alignment enum, and mirrors an
already-resolved item origin without allowing negative geometry.

`plural` returns a typed category for the common English/French/Arabic,
Russian/Ukrainian, and Polish rules, with a deterministic one/other fallback
for unknown languages. Message catalogs remain application-owned; they consume
the category instead of making each backend parse locale strings independently.

Locale changes should invalidate layout, paint, and semantics together. Claim
dynamic item identity through `UiIdentity` before rebuilding a localized list so
RTL/retranslation does not transfer focus or edit state by position.
