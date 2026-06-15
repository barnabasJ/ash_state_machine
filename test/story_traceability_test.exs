# SPDX-FileCopyrightText: 2023 ash_state_machine contributors <https://github.com/ash-project/ash_state_machine/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.StoryTraceabilityTest do
  @moduledoc """
  The story↔test traceability gate for `ash_state_machine`. Each user story is
  its own file under `documentation/user/<user-type>/<feature>/US-*.md` (with a
  Given/When/Then); the tests that exercise it reference it with `@tag story:`.
  The shared `StoryTraceability.SuiteCheck` ratchets two numbers — package tests
  with no story tag, and documented stories with no test — so coverage can only
  hold or improve.

  Package-local adoption of the repo's documentation-conformance pattern (see
  `documentation/user/qa-engineer/doc-conformance/` in ash_jobs). The baselines
  self-initialize on the first run and are committed thereafter.
  """
  use StoryTraceability.SuiteCheck,
    docs: "documentation/user/**/US-*.md",
    tests: "test/**/*_test.exs",
    baseline_dir: "test"
end
