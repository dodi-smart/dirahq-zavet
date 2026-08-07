---
title: Short noun phrase naming the feature
version: 1
# origin — HOW this spec was produced:
#   designed           written before the code existed (intent)
#   session            distilled from work just completed in an agent session
#   reverse-engineered reconstructed from existing code (a hypothesis)
origin: session
# verified: true ONLY after a human confirms the spec matches the code —
# whatever the origin. Everything else is cited as unverified.
verified: false
# confidence — low | med | high, self-assessed coverage.
confidence: med
date: 1970-01-01
# Git pathspecs the spec covers. `*`/`**` glob; commits touching these after
# the spec's last update mark it stale. For `designed` specs the paths may
# not exist yet — staleness starts once commits touch them.
paths:
  - path/or/glob/this/spec/covers/**
# Decisions that shaped this feature. Optional — decision-id references anywhere
# in the body are auto-linked too.
decisions: []
# Scenarios proving this feature still behaves, as `label :: command`. Same
# grammar as a decision's checks and the same posture: the command is opaque
# (any runner, any stack), exit 0 is pass, and it runs only when a human asks
# via `zavet verify` — never from a hook. A spec's checks are feature-level
# ("this flow still works"), where a decision's are invariants
# ("this must never become true again").
checks:
  - short name for the scenario :: command that exits non-zero when it breaks
---

## Overview

What the feature is and why it exists, in a few sentences.

## Behavior

What it does, as observable behavior. For `reverse-engineered` specs every
claim here must be traceable to a file actually read — never invented.

## Interfaces & data

Entry points, commands, schemas, wire formats, storage.

## Invariants

What must stay true. Reference the decisions behind them by id — the ids
auto-link.

## Open Questions

Mandatory and NON-EMPTY for `reverse-engineered` specs: what could not be
reconstructed. Recommended for the rest: what is still undecided or unclear.
A wrong recorded claim is worse than none.
