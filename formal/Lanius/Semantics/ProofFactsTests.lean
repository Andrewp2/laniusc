import Lanius.Semantics.CountedLocal

namespace Lanius.Semantics.ProofFactsTests

open Lanius Lanius.Core

private structure Limit where
  value : Nat
  bound : value < 8

private structure Inputs (base : State) where
  limit : Limit
  formed : base.CellsWellFormed
  value : base.local? 11 = some (.signed .i32 limit.value)

-- Shallow exposure retains direct fields but does not eagerly introduce
-- nested bounds. The default mode still exposes those bounds when needed.
example (inputs : Inputs base) : base.CellsWellFormed := by
  core_facts 1 [inputs]
  core_contract

example (inputs : Inputs base) : inputs.limit.value < 8 := by
  core_facts 1 [inputs]
  fail_if_success omega
  core_facts [inputs]
  omega

-- Nested resource facts and a registered counter-frame transport compose;
-- neither the fields nor the derived current lookup need handwritten aliases.
example (inputs : Inputs base) (frame : CountedLocal base current 17 index) :
    current.local? 11 = some (.signed .i32 inputs.limit.value) := by
  core_facts [inputs, frame]
  core_local

example (inputs : Inputs base) (frame : CountedLocal base current 17 index) :
    (current.bindLocal 11 .unit).CellsWellFormed := by
  core_facts [inputs, frame]
  core_formed

example (inputs : Inputs base) (frame : CountedLocal base current 17 index) :
    StableExpr 2 program current (.binary .less (.local 11) (.value (.signed .i32 8)))
      (.boolean true) current := by
  core_facts [inputs, frame]
  core_guard

-- Facts are projections, not invented hypotheses. A wrong bound, wrong
-- counter value, and a lookup overwritten by a shadowing local all fail.
example (inputs : Inputs base) (frame : CountedLocal base current 17 index) : True := by
  core_facts [inputs, frame]
  fail_if_success have wrong : 8 ≤ inputs.limit.value := by omega
  fail_if_success have wrong : current.local? 17 = some (.boolean false) := by core_local
  fail_if_success
    have wrong : (current.bindLocal 11 .unit).local? 11 =
        some (.signed .i32 inputs.limit.value) := by core_local
  trivial

end Lanius.Semantics.ProofFactsTests
