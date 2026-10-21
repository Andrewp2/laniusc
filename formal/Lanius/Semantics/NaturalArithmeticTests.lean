import Lanius.Semantics.NaturalArithmetic

namespace Lanius.Semantics.NaturalArithmeticTests

open Lanius.Core

example (target : Target) (value : Nat) (bounded : value < 2 ^ 31)
    (nonnegative : 0 ≤ wrapSigned target .i32 ((value : Int) + 1)) :
    evalBinaryValue target .add (.signed .i32 value) (.signed .i32 1) =
      .ok (.signed .i32 (value + 1 : Nat)) :=
  eval_i32_addNat target value 1 (i32_succ_bound target value bounded nonnegative)

-- Adjacent boundary values: the last safe increment and the overflow edge.
example (target : Target) : wrapSigned target .i32 2147483647 = 2147483647 := rfl
example (target : Target) : wrapSigned target .i32 2147483648 = -2147483648 := rfl
example (target : Target) : ¬ 0 ≤ wrapSigned target .i32 2147483648 := by
  change ¬ (0 : Int) ≤ -2147483648
  decide

#print axioms i32_succ_bound

end Lanius.Semantics.NaturalArithmeticTests
