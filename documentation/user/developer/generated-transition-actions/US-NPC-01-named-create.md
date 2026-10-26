# US-NPC-01 — Preserve an authored create action

As a resource author, I can give the primary create action a custom name.

When a resource declares any create action, the state-machine transformer keeps
that action and does not generate another primary create action. A create action
still initializes the configured default state through the normal Ash pipeline.

Verification: `test/named_primary_create_test.exs` inspects the transformed action
metadata and executes the authored `:provision` action.
