-- TESTS/check_policy_spec.lua — `opts.checks`.
--
-- The unit under test is deliberately not `check.run`: driving a real scan to
-- prove that a policy dropped a finding would make this spec depend on a
-- fixture continuing to raise that exact check, which is a thing that
-- legitimately changes. `check_policy.apply` takes findings and returns
-- findings, so every case here is stated in one line and stays true.
--
-- The one thing that *is* asserted end to end is that `check.run` calls it at
-- all, and after `extra_checks` — because "the module works and nothing uses
-- it" is precisely the shape of the bug this whole option exists to remove.

return function(H)
  local eq, ok = H.eq, H.ok
  local policy = require("documentation.core.check_policy")

  ---@param severity string
  ---@param check string
  ---@return Documentation.Finding
  local function finding(severity, check)
    return { severity = severity, check = check, node = "n", params = {} }
  end

  local input = {
    finding("error", "missing-module-tag"),
    finding("warn", "missing-summary"),
    finding("info", "dead-function"),
    finding("warn", "unused-require"),
  }

  ---`check` codes of a result list, joined, so a mismatch reads as a list
  ---rather than as "expected table, got table".
  ---@param list Documentation.Finding[]
  ---@return string
  local function codes(list)
    local out = {}
    for _, f in ipairs(list) do
      out[#out + 1] = f.severity .. ":" .. f.check
    end
    return table.concat(out, " ")
  end

  -- ---------------------------------------------------------------------
  -- No policy: the same list, and the *same table*, so the common case
  -- costs nothing.
  -- ---------------------------------------------------------------------

  ok(policy.apply(input, nil) == input, "apply: no policy returns the input table itself")
  ok(policy.apply(input, {}) == input, "apply: an empty policy returns the input table itself")

  -- ---------------------------------------------------------------------
  -- Switching one off.
  -- ---------------------------------------------------------------------

  eq(
    codes(policy.apply(input, { ["missing-summary"] = false })),
    "error:missing-module-tag info:dead-function warn:unused-require",
    "apply: false drops every finding of that check and nothing else"
  )

  eq(#policy.apply(input, {
    ["missing-module-tag"] = false,
    ["missing-summary"] = false,
    ["dead-function"] = false,
    ["unused-require"] = false,
  }), 0, "apply: switching every check off leaves an empty list, not an error")

  -- Dropped, not downgraded. Asserted explicitly because "off" quietly
  -- meaning "info" would still show in the page's Findings tab and still
  -- count in the tally — a reader would reasonably conclude the option does
  -- not work.
  for _, f in ipairs(policy.apply(input, { ["dead-function"] = false })) do
    ok(f.check ~= "dead-function", "apply: a switched-off check leaves no downgraded remnant")
  end

  -- ---------------------------------------------------------------------
  -- Re-grading.
  -- ---------------------------------------------------------------------

  local graded = policy.apply(input, { ["missing-module-tag"] = "info" })
  eq(
    codes(graded),
    "info:missing-module-tag warn:missing-summary info:dead-function warn:unused-require",
    "apply: a severity string re-grades that check"
  )
  eq(input[1].severity, "error", "apply: re-grading copies the finding rather than mutating it")

  ok(
    policy.apply(input, { ["missing-summary"] = "warn" })[2] == input[2],
    "apply: re-grading to the severity it already has copies nothing"
  )

  -- ---------------------------------------------------------------------
  -- Values that are not a policy. The rule is that an unusable value is
  -- ignored, never treated as `false` — silently deleting findings because
  -- somebody misspelled a severity is worse than ignoring the line.
  -- ---------------------------------------------------------------------

  eq(
    #policy.apply(input, { ["missing-summary"] = "warning" }),
    4,
    "apply: a misspelled severity ignores the line rather than dropping the check"
  )
  eq(#policy.apply(input, { ["missing-summary"] = true }), 4, "apply: true means leave it alone")
  eq(
    #policy.apply(input, { ["nothing-raises-this"] = false }),
    4,
    "apply: a code nothing raises is inert"
  )

  -- ---------------------------------------------------------------------
  -- Validation. Two different mistakes, two different messages, because the
  -- fix for one is not the fix for the other.
  -- ---------------------------------------------------------------------

  local messages = {}
  local note = {
    warn = function(msg)
      messages[#messages + 1] = msg
    end,
  }

  policy.validate({ ["dead-fn"] = false }, note)
  eq(#messages, 1, "validate: a typo'd check code warns")
  ok(messages[1]:match("dead%-fn"), "validate: the warning names the code")

  messages = {}
  policy.validate({ ["missing-summary"] = "loud" }, note)
  eq(#messages, 1, "validate: an unusable value warns")
  ok(messages[1]:match("loud"), "validate: the warning names the value")

  messages = {}
  policy.validate({ ["missing-summary"] = false, ["dead-function"] = "info" }, note)
  eq(#messages, 0, "validate: a well-formed policy is silent")

  -- An `extra_checks` code is legitimately unknown to this repository, so
  -- the message must not call it a typo — but it is still worth reporting,
  -- since a typo is indistinguishable from it and silence is what this
  -- module exists to remove.
  messages = {}
  policy.validate({ ["my-own-check"] = false }, note)
  ok(
    messages[1] and messages[1]:match("extra_checks"),
    "validate: the unknown-code warning says an extra_checks code is fine here"
  )

  -- No `notify` is the standalone build's situation: `core/` has to stay
  -- runnable with no notification surface at all, so this must be a no-op
  -- rather than an index of a nil. The assertion is that the call returns.
  policy.validate({ ["dead-fn"] = false }, nil)
  ok(true, "validate: no notify is a no-op rather than an error")

  -- ---------------------------------------------------------------------
  -- `check.run` actually applies it, and after `extra_checks`.
  -- ---------------------------------------------------------------------

  local check = require("documentation.core.check")
  local empty_ir = { root = "lua", nodes = {}, order = {}, edges = {}, meta = {} }

  local ran = check.run(empty_ir, {
    root = ".",
    extra_checks = {
      function()
        return { finding("error", "mine"), finding("warn", "also-mine") }
      end,
    },
  })
  eq(codes(ran), "error:mine warn:also-mine", "check.run: extra_checks reach the output")

  local filtered = check.run(empty_ir, {
    root = ".",
    checks = { mine = false, ["also-mine"] = "info" },
    extra_checks = {
      function()
        return { finding("error", "mine"), finding("warn", "also-mine") }
      end,
    },
  })
  eq(
    codes(filtered),
    "info:also-mine",
    "check.run: the policy reaches extra_checks results too, and runs before the sort"
  )
end
