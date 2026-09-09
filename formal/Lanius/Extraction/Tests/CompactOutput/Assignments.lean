import Lanius.Extraction.CompactOutput.Assignments.Domain
import Lanius.Extraction.CompactOutput.Assignments.Source
import Lanius.Extraction.CompactOutput.Assignments.Read
import Lanius.Extraction.CompactOutput.Assignments.Failure
import Lanius.Extraction.CompactOutput.Assignments.Success
import Lanius.Extraction.CompactOutput.Assignments.Loop
import Lanius.Extraction.CompactOutput.Assignments.Reject
import Lanius.Extraction.CompactOutput.Assignments.Call
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.CompactOutput.Assignments

open Lanius.Extraction.CompactOutput
open Lanius.Core Lanius.Semantics Lanius.Extraction.SemanticTokens

def checkExecution (program : Program) (functionId : FunctionId) : IO Nat := do
  let mut calls := 0
  for assignments in ([[], [⟨0, none⟩], [⟨15, some 16⟩, ⟨32767, none⟩]] : List (List Assignment)) do
    let digits := assignments.flatMap fun assignment =>
      [assignment.first, assignment.second.map (· + 1) |>.getD 0] |>.flatMap fun value =>
        let chars := Nat.toDigits 16 value
        (List.replicate (8 - chars.length) '0' ++ chars).map (fun c => Int.ofNat c.toNat)
    for spare in ([[], [-9, 2147483647, -1]] : List (List Int)) do
      let input := assignments.flatMap Assignment.words ++ spare
      let original := (List.range 40).map (fun n => -500 + Int.ofNat n)
      let before : State := (List.range 10).foldl
        (fun state id => state.bindLocal id (.signed .i32 (800 + id : Nat)))
        { cells := [⟨0, some (.array (signedI32Values input))⟩,
                    ⟨1, some (.array (signedI32Values original))⟩], nextCell := 2 }
      for capacity in List.range 35 do
        for position in ([0, 2, -1, 2147483647] : List Int) do
          let count := if position < 0 then 0 else min digits.length (capacity - position.toNat)
          let expectedPosition := if assignments.isEmpty then position
            else if position < 0 || count < digits.length then -1 else position + Int.ofNat digits.length
          let expected := if count == 0 then original else
            original.take position.toNat ++ digits.take count ++ original.drop (position.toNat + count)
          let args := Assignments.argumentsValues (.slice i32 0 [] 0 input.length)
            (.slice i32 1 [] 0 original.length) input.length assignments.length capacity position
          match evalExpr 4000 program before (.call functionId (args.map Expr.value)) with
          | .done (.signed .i32 result) after =>
            unless result == expectedPosition && after.cell? 1 == some (.array (signedI32Values expected)) do
              throw (IO.userError s!"semantic serializer differs: {repr assignments}, capacity {capacity}, cursor {position}")
            unless after.locals == before.locals do throw (IO.userError "semantic serializer leaked locals")
            for cell in before.cells do
              if cell.id != 1 then
                unless after.cell? cell.id == cell.value do throw (IO.userError "semantic serializer changed input/caller storage")
          | _ => throw (IO.userError "semantic serializer trapped or exhausted")
          calls := calls + 1
  pure calls

private def fixture : Program := { functions := [
  ⟨1, byteParameters, i32, some byteBody, none⟩,
  ⟨2, [(0, i32)], i32, some digitBody, none⟩,
  ⟨3, byteParameters, i32, some (Word.body 1 2), none⟩,
  ⟨4, Assignments.parameters, i32, some (Assignments.body 3), none⟩] }

private def check : IO Unit := do
  let calls ← checkExecution fixture 4
  IO.println s!"semantic serializer: {calls} calls checked against independent fixed-width encoding, sentinels, spare capacity, all output cutoffs, and caller frames."
#eval check

run_elab do
  let standard : Array Lean.Name := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``Assignments.encode_second, ``Assignments.fields_valid,
      ``Assignments.field_bounds, ``Assignments.stored_fields, ``Assignments.write_fields,
      ``Assignments.stored_pair, ``Assignments.read_pair, ``Assignments.initialize_fields,
      ``Assignments.Entry.write, ``Assignments.Entry.failure,
      ``appendAll_done_nonnegative, ``Assignments.Entry.success,
      ``Assignments.Owned.transition, ``Assignments.Owned.condition, ``Assignments.execute_loop,
      ``Assignments.entry_guard, ``Assignments.entry_guard_passes, ``Assignments.entry_guard_rejects,
      ``Assignments.Checked.short_input, ``Assignments.Function.Entry.invariant,
      ``Assignments.Function.Entry.execute, ``Assignments.Checked.write] do
    unless (← Lean.getEnv).contains name do throwError "Missing assignment field theorem {name}"
    for axiomName in ← Lean.collectAxioms name do
      unless standard.contains axiomName do throwError "Assignment theorem {name} depends on {axiomName}"
  Lean.logInfo "Twenty-two assignment theorems, including the complete public write call, use standard axioms only."

end Lanius.Extraction.Tests.CompactOutput.Assignments
