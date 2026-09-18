import Lanius.Extraction.CoreTypingChecker
import Lanius.Extraction.KernelReduction
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Typing
open Lanius.Core Lanius.Typing

private def i32 : Ty := .scalar (.signed .i32)
private def zero : Expr := .value (.signed .i32 0)
private def casts : Nat → Expr
  | 0 => zero
  | depth + 1 => .cast (.signed .i32) (casts depth)

-- Each cast must reuse its child's inferred type/proof, not infer it twice.
private theorem nested_casts :
    ((CoreTyping.inferExpr {} Context.empty (casts 64)).map (·.type)) = some i32 := by
  kernel_rfl

private opaque unused : Expr := zero
private opaque unusedArguments : List Expr := [zero]

-- Structural recursion must reject the bad prefix without evaluating an
-- opaque, irrelevant suffix merely to compute a termination measure.
private theorem skips_suffix :
    (CoreTyping.inferExpr {} Context.empty (.binary .add (.local 9) unused)).isNone = true ∧
    (CoreTyping.inferExpr {} Context.empty (.call 9 unusedArguments)).isNone = true := by
  constructor <;> kernel_rfl

private def casesPass : Bool :=
  let infer := fun expression => (CoreTyping.inferExpr {} Context.empty expression).map (·.type)
  [(.cast .bool zero, none),
    (.arrayToSlice i32 (.array i32 [zero]), some (.slice i32)),
    (.arrayToSlice (.scalar .bool) (.array i32 [zero]), none),
    (.index (.array i32 [zero]) zero, some i32),
    (.index (.array i32 [zero]) (.value (.boolean false)), none),
    (.matchValue zero [(.wildcard, zero), (.bind 3, .local 3)], some i32),
    (.matchValue zero [(.wildcard, zero), (.wildcard, .value (.boolean false))], none),
    (.matchValue zero [], none)].all fun (expression, expected) => infer expression == expected

private theorem accepted_and_rejected : casesPass = true := by kernel_rfl

private theorem loops :
    (CoreTyping.checkStmt {} .unit Context.empty false
      (.forValues 0 (.array i32 [zero]) .continueLoop)).isSome = true ∧
    (CoreTyping.checkStmt {} .unit (Context.empty.bind 1 (.slice i32)) false
      (.forValues 0 (.local 1) .breakLoop)).isSome = true ∧
    (CoreTyping.checkStmt {} .unit Context.empty false
      (.forValues 0 zero .skip)).isNone = true := by
  decide +kernel

run_elab do
  for name in #[``nested_casts, ``skips_suffix, ``accepted_and_rejected, ``loops,
      ``CoreTyping.inferExpr, ``CoreTyping.inferPlace, ``CoreTyping.checkProgram] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "Core typing {name} uses unexpected assumption {assumption}"

end Lanius.Extraction.Tests.Typing
