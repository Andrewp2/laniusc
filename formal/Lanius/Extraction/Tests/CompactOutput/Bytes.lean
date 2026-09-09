import Lanius.Extraction.CompactOutput.Bytes.Call
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.CompactOutput.Bytes

open Lanius.Core Lanius.Semantics Lanius.Extraction.CompactOutput

def checkExecution (program : Program) (functionId : FunctionId) : IO Nat := do
  let mut calls := 0
  for values in ([[], [0], [255], [0, 15, 16, 127, 255]] : List (List Nat)) do
    let digits := values.flatMap fun value =>
      let chars := Nat.toDigits 16 value
      (List.replicate (2 - chars.length) '0' ++ chars).map (fun c => Int.ofNat c.toNat)
    for spare in ([[], [-999, 256, -1]] : List (List Int)) do
      let input := values.map Int.ofNat ++ spare
      let original := (List.range 16).map (fun n => -500 + Int.ofNat n)
      let before : State := (List.range 8).foldl
        (fun state id => state.bindLocal id (.signed .i32 (700 + id : Nat)))
        { cells := [⟨0, some (.array (signedI32Values input))⟩,
                    ⟨1, some (.array (signedI32Values original))⟩], nextCell := 2 }
      for capacity in List.range 13 do
        for position in ([0, 2, -1, 2147483647] : List Int) do
          let count := if position < 0 then 0 else min digits.length (capacity - position.toNat)
          let expectedPosition := if values.isEmpty then position
            else if position < 0 || count < digits.length then -1 else position + Int.ofNat digits.length
          let expected := if count == 0 then original else
            original.take position.toNat ++ digits.take count ++ original.drop (position.toNat + count)
          let args := [Value.slice i32 0 [] 0 input.length, .signed .i32 values.length,
            .slice i32 1 [] 0 original.length, .signed .i32 capacity, .signed .i32 position]
          match evalExpr 2000 program before (.call functionId (args.map Expr.value)) with
          | .done (.signed .i32 result) after =>
            unless result == expectedPosition && after.cell? 1 == some (.array (signedI32Values expected)) do
              throw (IO.userError s!"bytes output differs: {values}, capacity {capacity}, cursor {position}")
            unless after.locals == before.locals do throw (IO.userError "bytes leaked its locals")
            for cell in before.cells do
              if cell.id != 1 then
                unless after.cell? cell.id == cell.value do throw (IO.userError "bytes modified input/caller storage")
          | _ => throw (IO.userError "bytes trapped or exhausted")
          calls := calls + 1
  for length in ([-1, -2147483648] : List Int) do
    let before : State := ({} : State).bindLocal 9 (.signed .i32 33)
    let args := CompactOutput.Bytes.argumentsValues .unit .unit length 0 0
    match evalExpr 100 program before (.call functionId (args.map Expr.value)) with
    | .done (.signed .i32 (-1)) after =>
      unless after.locals == before.locals && after.cell? 0 == before.cell? 0 do
        throw (IO.userError "negative length changed caller storage")
    | _ => throw (IO.userError "negative length accessed a buffer or failed to reject")
    calls := calls + 1
  pure calls

private def fixture : Program := { functions := [
  ⟨1, byteParameters, i32, some byteBody, none⟩,
  ⟨2, [(0, i32)], i32, some digitBody, none⟩,
  ⟨3, byteParameters, i32, some (hexByteBody 1 2), none⟩,
  ⟨4, CompactOutput.Bytes.parameters, i32, some (CompactOutput.Bytes.body 3), none⟩] }

private def check : IO Unit := do
  let calls ← checkExecution fixture 4
  let complete := CompactOutput.Bytes.body 3
  let .sequence _ rest := complete | throw (IO.userError "missing bytes length guard")
  for changed in [rest, CompactOutput.Bytes.body 99,
      .sequence complete (.expression (.assign .set (.local 77) (number 0)))] do
    unless (Core.Equality.statement? changed complete).isNone do
      throw (IO.userError "bytes equality accepted a missing guard, wrong helper, or extra effect")
  IO.println s!"bytes: {calls} executions check independent hex encoding, logical length, spare input, partial output, and caller frames."
#eval check

run_elab do
  let standard : Array Lean.Name := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``CompactOutput.Bytes.read_write, ``CompactOutput.Bytes.assign_byte,
      ``CompactOutput.Bytes.Owned.append, ``CompactOutput.Bytes.Owned.increment,
      ``CompactOutput.Bytes.execute_loop, ``CompactOutput.Bytes.Entry.invariant,
      ``CompactOutput.Bytes.Entry.execute, ``CompactOutput.Bytes.Checked.write,
      ``CompactOutput.Bytes.Checked.reject, ``CompactOutput.Bytes.Checked.success,
      ``CompactOutput.Bytes.encoding_length] do
    unless (← Lean.getEnv).contains name do throwError "Missing byte-loop theorem {name}"
    for axiomName in ← Lean.collectAxioms name do
      unless standard.contains axiomName do throwError "Byte-loop theorem {name} depends on {axiomName}"
  Lean.logInfo "Eleven byte serializer theorems, including the complete loop/body/public call, use standard axioms only."

end Lanius.Extraction.Tests.CompactOutput.Bytes
