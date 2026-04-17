`gated_action.when` must have at least one entry. An empty CASE/WHEN has no
meaning — authors should just route to `else` directly if they have no
conditions. Schema requires minItems: 1.
