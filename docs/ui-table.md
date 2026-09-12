# Table column layout

`UiTable` ([src/widgets/ui_table.elisa](../src/widgets/ui_table.elisa)) owns the
one piece box layout cannot: a column width shared across independently built
rows. Applications own the row widgets, cells, and data; the module resolves
column geometry once against the available width.

Each column declares a `minimum`, `preferred`, and `maximum` width plus a `grow`
weight. `layout(available, spacing)` then:

1. starts every column at its preferred width, clamped to `[minimum, maximum]`;
2. if the columns fit, shares the leftover by grow weight, capped at `maximum`;
3. if they do not fit, takes the deficit from columns with slack above
   `minimum`, proportional to that slack;
4. if the minimums still do not fit, keeps the minimums and reports
   `overflowed`, so the caller clips or scrolls instead of silently shrinking
   text.

`column_width`, `column_x`, and `content_width` report the result. All inputs
are normalized against the framework geometry envelope, so negative or
non-finite sizes cannot escape into layout.

The result is deterministic and allocation-free. `overflowed` is the signal
that the available width is below the minimums, not an error; row realization is
separate and belongs to `UiVirtualList`. Table cells use the existing semantic
roles (`Label`, `TextField`, `Button`), so a table needs no new accessibility
vocabulary.

`test/ui_table_test.elisa` covers weighted growth, maximum caps, deficit
sharing, minimum floors, single-column exact fit, and the overflow report.
