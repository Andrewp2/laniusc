import Lanius.Extraction.CompactOutput.Word.Call
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.CompactOutput.Word

open Lanius.Core Lanius.Semantics Lanius.Extraction.CompactOutput

private def fixture : Program := { functions := [
  ⟨1, byteParameters, i32, some byteBody, none⟩,
  ⟨2, [(0, i32)], i32, some digitBody, none⟩,
  ⟨4, byteParameters, i32, some (CompactOutput.Word.body 1 2), none⟩] }

private def original : List Int := (List.range 16).map (fun n => -500 + Int.ofNat n)
private def caller : State := (List.range 8).foldl
  (fun state id => state.bindLocal id (.signed .i32 (800 + id : Nat)))
  { cells := [⟨0, some (.array (signedI32Values original))⟩], nextCell := 1 }

private def frame (after : State) (output : Bool) : IO Unit := do
  unless after.locals == caller.locals do throw (IO.userError "hex_u32 did not restore caller locals")
  for cell in caller.cells do
    if !output || cell.id != 0 then
      unless after.cell? cell.id == cell.value do
        throw (IO.userError s!"hex_u32 changed unrelated caller cell {cell.id}")

-- Independent division-based standard-library formatting, not the proved
-- shift/mask traversal or its appendAll outcome model.
private def expected (value : Nat) : List Int :=
  let digits := Nat.toDigits 16 value
  (List.replicate (8 - digits.length) '0' ++ digits).map (fun c => c.toNat)

def checkExecution (program : Program) (functionId : FunctionId) : IO Nat := do
  let values := ((List.range 8).flatMap (fun n => [16 ^ n - 1, 16 ^ n, 16 ^ n + 1]) ++
    (List.range 31).map (fun n => 2 ^ n) ++ [19088743, 305419896, 1431655765, 1789569706, 2147483647]).eraseDups
  let mut calls := 0
  for value in values do
    for capacity in List.range 11 do
      for position in ([0, 2, -1, 2147483647] : List Int) do
        let count := if position < 0 then 0 else min 8 (capacity - position.toNat)
        let next : Int := if position < 0 || count < 8 then -1 else position + 8
        let contents := if count == 0 then original else
          original.take position.toNat ++ (expected value).take count ++ original.drop (position.toNat + count)
        let arguments := (byteValues (.slice i32 0 [] 0 original.length) capacity position value).map Expr.value
        match evalExpr 600 program caller (.call functionId arguments) with
        | .done (.signed .i32 result) after =>
          unless result == next && after.cell? 0 == some (.array (signedI32Values contents)) do
            throw (IO.userError s!"hex_u32 wrong at value {value}, capacity {capacity}, position {position}")
          frame after (0 < count)
        | _ => throw (IO.userError "hex_u32 trapped, exhausted, or returned the wrong type")
        calls := calls + 1
  for (capacity, position, value) in
      ([(4, 0, -1), (4, 0, -2147483648), (2147483647, 2147483647, 0),
        (0, 0, 2147483647), (4, -2147483648, 1)] : List (Int × Int × Int)) do
    -- These paths must not dereference the deliberately invalid output value.
    let arguments := (byteValues .unit capacity position value).map Expr.value
    match evalExpr 200 program caller (.call functionId arguments) with
    | .done (.signed .i32 (-1)) after => frame after false
    | _ => throw (IO.userError "hex_u32 rejection accessed a buffer or failed to return -1")
    calls := calls + 1
  pure calls

private def checkFixture : IO Unit := do
  let calls ← checkExecution fixture 4
  IO.println s!"hex_u32: {calls} calls checked against independent fixed-width formatting, every output cutoff, and caller frames."
  let complete := CompactOutput.Word.body 1 2
  let .sequence _ rest := complete | throw (IO.userError "missing word guard")
  for changed in [rest, .sequence .skip rest, CompactOutput.Word.body 2 1,
      .sequence complete (.expression (.assign .set (.local 77) (number 0)))] do
    unless (Core.Equality.statement? changed complete).isNone do
      throw (IO.userError "word source equality accepted a missing guard, wrong helper, or extra effect")
#eval checkFixture

run_elab do
  let standard : Array Lean.Name := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``Lanius.Separation.evaluatesOwnedLocalSet, ``appendAll_success, ``hexDigits_bytes,
      ``CompactOutput.Word.Entry.invariant, ``CompactOutput.Word.execute_loop,
      ``CompactOutput.Word.Entry.execute, ``CompactOutput.Word.Checked.write,
      ``CompactOutput.Word.Checked.success, ``CompactOutput.Word.Checked.reject] do
    unless (← Lean.getEnv).contains name do throwError "missing word theorem {name}"
    let axioms ← Lean.collectAxioms name
    unless axioms.all standard.contains do throwError "word proof added trust assumptions: {name}: {axioms}"
  Lean.logInfo "Nine word-writer, buffer, and call-assignment theorems use only standard Lean axioms."

end Lanius.Extraction.Tests.CompactOutput.Word
