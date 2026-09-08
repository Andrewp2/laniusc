import Lanius.Extraction.CompactOutput.HexByte
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.CompactOutput

open Lanius.Core Lanius.Semantics Lanius.Extraction.CompactOutput

private def fixture : Program := { functions := [
  ⟨1, byteParameters, i32, some byteBody, none⟩,
  ⟨2, [(0, i32)], i32, some digitBody, none⟩,
  ⟨3, byteParameters, i32, some (hexByteBody 1 2), none⟩] }

private def original : List Int := [511, -17, 1000, 1777, 2048, 6000]
private def caller : State := (List.range 8).foldl
  (fun state id => state.bindLocal id (.signed .i32 (800 + id : Nat)))
  { cells := [⟨0, some (.array (signedI32Values original))⟩], nextCell := 1 }

private def checkFrame (before after : State) (output : Bool) : IO Unit := do
  unless after.locals == before.locals do throw (IO.userError "writer did not restore caller locals")
  for cell in before.cells do
    if !output || cell.id != 0 then
      unless after.cell? cell.id == cell.value do
        throw (IO.userError s!"writer changed unrelated caller cell {cell.id}")

private def ascii (value : Nat) : Int := ("0123456789abcdef".toUTF8[value]!).toNat

/-- Also called with the actual checked source, not just the small fixture. -/
def checkExecution (program : Program) (byteId digitId hexByteId : FunctionId) : IO Unit := do
  for value in List.range 16 do
    match evalExpr 100 program caller (.call digitId [.value (.signed .i32 value)]) with
    | .done (.signed .i32 result) after =>
      unless result == ascii value do throw (IO.userError "hex_digit disagrees with lowercase ASCII alphabet")
      checkFrame caller after false
    | _ => throw (IO.userError "hex_digit trapped or exhausted")
  for capacity in [0, 1, 3, 4] do
    for position in ([-1, 0, 1, 3, 4] : List Int) do
      for value in ([-1, 0, 15, 16, 255, 256] : List Int) do
        let good := 0 ≤ position && position < capacity && 0 ≤ value && value < 256
        let values := byteValues (.slice i32 0 [] 0 original.length) capacity position value
        match evalExpr 150 program caller (.call byteId (values.map Expr.value)) with
        | .done (.signed .i32 result) after =>
          let contents := if good then original.set position.toNat value else original
          unless result == (if good then position + 1 else -1) &&
              after.cell? 0 == some (.array (signedI32Values contents)) do
            throw (IO.userError "byte append violated exact write/capacity/error contract")
          checkFrame caller after good
        | _ => throw (IO.userError "byte append trapped or exhausted")
  for value in List.range 256 do
    -- Every byte, both nibbles, and exact/spare/partial/no-room destinations.
    for (capacity, position) in ([(2, 0), (4, 1), (2, 1), (0, 0), (3, -1)] : List (Nat × Int)) do
      let goodFirst := 0 ≤ position && position < capacity
      let goodSecond := 0 ≤ position && position + 1 < capacity
      let first := if goodFirst then original.set position.toNat (ascii (value / 16)) else original
      let wanted := if goodSecond then first.set (position.toNat + 1) (ascii (value % 16)) else first
      let values := byteValues (.slice i32 0 [] 0 original.length) capacity position value
      match evalExpr 300 program caller (.call hexByteId (values.map Expr.value)) with
      | .done (.signed .i32 result) after =>
        unless result == (if goodSecond then position + 2 else -1) &&
            after.cell? 0 == some (.array (signedI32Values wanted)) do
          throw (IO.userError s!"hex_byte wrong at value {value}, capacity {capacity}, position {position}")
        checkFrame caller after goodFirst
      | _ => throw (IO.userError "hex_byte trapped or exhausted")
  for functionId in [byteId, hexByteId] do
    for value in ([-2147483648, -1, 256, 2147483647] : List Int) do
      -- An invalid value must return before trying to dereference this unit.
      let arguments := (byteValues .unit 4 0 value).map Expr.value
      match evalExpr 100 program caller (.call functionId arguments) with
      | .done (.signed .i32 (-1)) after => checkFrame caller after false
      | _ => throw (IO.userError "invalid byte accessed a buffer or failed to reject")

#eval checkExecution fixture 1 2 3

-- Reject missing guards and substituted helper IDs.
private def checkShapes : IO Unit := do
  let .sequence _ rest := hexByteBody 1 2 | throw (IO.userError "missing hex_byte guard")
  for changed in [rest, .sequence .skip rest, hexByteBody 2 1] do
    unless (Core.Equality.statement? changed (hexByteBody 1 2)).isNone do
      throw (IO.userError "complete writer source check accepted changed control flow or helper IDs")
#eval checkShapes

run_elab do
  let standard : Array Lean.Name := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``CheckedByte.append, ``CheckedByte.reject, ``CheckedByte.write, ``CheckedDigit.call_digit,
      ``shift_right, ``mask_nibble, ``nibble_evaluates, ``append_digit, ``CheckedHexByte.write, ``CheckedHexByte.reject] do
    unless (← Lean.getEnv).contains name do throwError "missing writer theorem {name}"
    let axioms ← Lean.collectAxioms name
    unless axioms.all standard.contains do throwError "writer proof added trust assumptions: {name}: {axioms}"
  Lean.logInfo "Ten byte/hex-writer theorems use only standard Lean axioms."

end Lanius.Extraction.Tests.CompactOutput
