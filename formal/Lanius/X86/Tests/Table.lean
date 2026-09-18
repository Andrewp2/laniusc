import Lanius.X86.Source.Table
import Lean.Util.CollectAxioms

namespace Lanius.X86.Tests.Table

open Lanius.Core Lanius.Semantics Lanius.X86.Source

/-- Later duplicate keys must not override the first matching branch. -/
theorem firstMatch (program : Program) (input : Int) (found : before.local? 0 = some (.signed .i32 input)) :
    Executes program before (Source.Table.body (program := program) [(.literal 2, .literal 7), (.literal 2, .literal 9)])
      (.returned (some (.signed .i32 (if input = 2 then 7 else -1)))) before := by
  by_cases same : input = 2 <;>
    simpa [Source.Table.values, Source.Table.lookup, Source.Table.Atom.value, same] using
    Source.Table.executes (program := program) [(.literal 2, .literal 7), (.literal 2, .literal 9)] input found

private def fixture : Program := { constants := [
  ⟨40, i32, .signed .i32 2⟩, ⟨91, i32, .signed .i32 4⟩,
  ⟨92, .scalar .bool, .boolean true⟩] }

private def fallback : Stmt := returned (.unary .negate (number 1))
private def row (key result : Expr) (tail : Stmt := fallback) : Stmt :=
  .sequence (.ifThenElse (.binary .equal (read 0) key) (returned result) .skip) tail

private def check : IO Unit := do
  -- IDs 40/91 are deliberately different from the values 2/4.
  unless (Source.Table.rows? fixture (row (.constant 40) (.constant 91))).map Source.Table.values == some [(2, 4)] do
    throw (IO.userError "table did not authenticate the actual constant values")
  for changed in [row (.constant 999) (.constant 91), row (.constant 40) (.constant 92),
      row (.constant 40) (.call 0 []), row (.call 0 []) (number 4),
      row (number 2) (number 4) .skip,
      .sequence (.ifThenElse (.binary .equal (read 1) (number 2)) (returned (number 4)) .skip) fallback,
      .sequence (.ifThenElse (.binary .notEqual (read 0) (number 2)) (returned (number 4)) .skip) fallback,
      .sequence (.expression (.assign .set (.local 0) (number 2))) (row (number 2) (number 4))] do
    unless (Source.Table.rows? fixture changed).isNone do
      throw (IO.userError "table admitted a missing/wrong constant, call, changed predicate, effect, or missing fallback")
#eval check

run_elab do
  let standard : Array Lean.Name := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``Source.Table.Atom.evaluates, ``Source.Table.executes, ``Source.Table.Checked.spec, ``firstMatch] do
    let axioms ← Lean.collectAxioms name
    unless axioms.all standard.contains do throwError "table added trust: {name}: {axioms}"
  Lean.logInfo "Table execution: first-match semantics, actual constant values, rejection of effects, and standard axioms only."

end Lanius.X86.Tests.Table
