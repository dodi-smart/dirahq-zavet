---
id: D-0000
title: Short imperative summary of the decision
status: active
# Guard globs: `*` and `**` both cross directory boundaries (so `src/*.rs`
# also matches nested files); a trailing `/` prefix-matches the directory.
guards:
  - path/or/glob/of/code/this/decision/shapes/**
# How anyone would know this decision still holds, as `label :: command`.
# The command is opaque — any runner, any stack; exit 0 is pass and nothing
# about its output is read. An item with no `::` IS the command. Quote an
# item whose command contains ` #`. Delete the key if the invariant cannot be
# checked mechanically, and say so under ## Verification instead.
checks:
  - short name for the invariant :: command that exits non-zero when it breaks
# Set by a LATER record that corrects one claim here; leave it off until then.
# This record stays `active` and keeps its body — corrections annotate,
# supersession replaces.
# corrected-by: D-0000
origin: recorded
verified: true
---

## Decision

One or two sentences: what was decided.

## Why

The constraint or reasoning a future reader could not reconstruct from the code.

## Rejected

- Alternative — why it lost.

## Agent directives

- Concrete do/don't for anyone (human or agent) editing the guarded paths.

## Verification

How the directives above are enforced — name the `checks:` entries, or state
plainly that this one is not mechanically checkable and what a human has to
look at instead. An unchecked invariant is fine; an unchecked invariant that
reads as if it were enforced is not.

## Open questions

- What could not be established. Delete the section if there are none;
  mandatory and non-empty when `origin: reverse-engineered`.
