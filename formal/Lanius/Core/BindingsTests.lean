import Lanius.Core.Bindings
import Lanius.Semantics.ExpressionProof

namespace Lanius.Core.BindingsTests

open Lanius Lanius.Semantics

private def sample (offset : Nat) : Function := {
  id := 7, parameters := [(offset + 10, .unit), (offset + 11, .unit)], returnType := .unit,
  body := some (.letLocal (offset + 20) .unit (.value .unit) (.sequence
    (.ifThenElse (.value (.boolean true)) (.letUninitialized (offset + 30) .unit .skip) .skip)
    (.whileLoop (.value (.boolean false)) (.letLocal (offset + 40) .unit (.value .unit) .skip)))) }

example (offset : Nat) : (sample offset).argumentId 1 = offset + 11 := rfl
example (offset : Nat) : (sample offset).bindingId 0 = offset + 20 := rfl
example (offset : Nat) : (sample offset).bindingId 1 = offset + 30 := rfl
example (offset : Nat) : (sample offset).bindingId 2 = offset + 40 := rfl

example (offset : Nat) : (sample offset).whileLoop 0 =
    (.value (.boolean false), .letLocal (offset + 40) .unit (.value .unit) .skip) := rfl
example (offset : Nat) : (sample offset).whileLoop 1 = (.value (.boolean true), .skip) := rfl

-- Nested loops remain in preorder; selecting the inner loop returns its real body.
example : (Stmt.whileLoop (.local 1) (.sequence .skip (.whileLoop (.local 2) (.expression (.local 3))))).whileLoops =
    [(.local 1, .sequence .skip (.whileLoop (.local 2) (.expression (.local 3)))),
     (.local 2, .expression (.local 3))] := rfl

-- Closed selectors normalize without making clients name source token IDs.
example (state : State) (found : state.local? 1030 = some .unit) :
    state.local? ((sample 1000).bindingId 1) = some .unit := by core_local

end Lanius.Core.BindingsTests
