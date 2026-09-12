# Tree structure policy

`UiTree` ([src/widgets/ui_tree.elisa](../src/widgets/ui_tree.elisa)) owns the
hierarchy policy a tree control needs while applications own the node data and
row widgets.

Nodes are registered with `register(id, parent)`; `ROOT` (zero) is the virtual
root. A parent must be registered before its children, and duplicate ids,
unknown parents, and the zero id fail closed. Child and sibling links are built
at registration time, so the visible order is a real depth-first walk rather
than registration order.

Expansion is explicit: `set_expanded` and `toggle` change one node,
`is_expanded`/`has_children` report structure, and `reveal(id)` expands every
collapsed ancestor so a logical target becomes visible. The flattened order is
read through `visible_count`, `visible_id`, `visible_index_of`, and
`depth_of`; `move_visible` steps through it and skips collapsed descendants.

The traversal is iterative and bounded by `MAX_NODES`, so a hostile or very deep
tree cannot recurse the runtime stack. `reveal` is what assistive navigation
uses to bring an off-screen target into the visible window before scrolling to
it. Tree rows use the existing semantic roles (`Label`, `Button`, `Group`), so
no new accessibility vocabulary is needed.

`test/ui_tree_test.elisa` covers depth-first order, expansion/collapse,
`reveal`, visible navigation, invalid registration, and the snapshot.
