import Lanius.Extraction.CompactOutput.Text.Call
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.CompactOutput.Text
open Lanius.Core Lanius.Semantics Lanius.Extraction.CompactOutput

private def fixture : Program := { functions := [
  ⟨1, byteParameters, i32, some byteBody, none⟩,
  ⟨2, Text.parameters, i32, some (Text.body 1), none⟩] }

/-- Exercise packed UTF-8 reads and every capacity around short strings.
The same check is run against the actual self-extracted text helper. -/
def checkExecution (program : Program) (function : FunctionId) : IO Unit := do
  for source in ["", "a", "é", "λZ", "abcd", "🙂Z"] do
    let bytes := source.toUTF8.toList
    let padded := source ++ String.ofList (List.replicate ((4 - bytes.length % 4) % 4) '\x00')
    for start in [0, 2] do
      let original : List Int := (List.range (start + bytes.length + 2)).map (fun index => -1000 - Int.ofNat index)
      let before : State := (List.range 10).foldl
        (fun state id => state.bindLocal id (.signed .i32 (700 + id : Nat)))
        { cells := [⟨0, some (.array (signedI32Values original))⟩], nextCell := 1,
          world := { standardOutput := [17], standardError := [18] } }
      for spare in List.range (bytes.length + 3) do
        let capacity := start + spare
        let args := Text.arguments (.slice i32 0 [] 0 original.length) capacity start padded bytes.length
        let written := bytes.take spare
        let wanted := original.take start ++ written.map (fun byte => Int.ofNat byte.toNat) ++
          original.drop (start + written.length)
        let expected : Int := if bytes.length ≤ spare then Int.ofNat (start + bytes.length) else -1
        match evalExpr 300 program before (.call function (args.map Expr.value)) with
        | .done (.signed .i32 result) after =>
          unless result == expected && after.cell? 0 == some (.array (signedI32Values wanted)) do
            throw (IO.userError s!"text result/partial buffer differs: bytes={bytes.length}, start={start}, spare={spare}")
          unless after.locals == before.locals && after.world.calls == before.world.calls &&
              after.world.standardOutput == before.world.standardOutput &&
              after.world.standardError == before.world.standardError do
            throw (IO.userError "text helper changed caller scope or performed external I/O")
          for cell in before.cells do
            if cell.id != 0 && after.cell? cell.id != cell.value then
              throw (IO.userError "text helper overwrote an unrelated caller cell")
          unless after.i32ArrayViews.length == before.i32ArrayViews.length + 1 do
            throw (IO.userError "text helper did not retain its borrowed packed-string view")
        | _ => throw (IO.userError "text helper trapped or exhausted fuel on a supported input")

#eval checkExecution fixture 2

run_elab do
  let standard : Array Lean.Name := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``Text.stepFull, ``Text.executesOverflowLoop, ``Text.executesLoopAndReturn,
      ``Text.executes, ``Text.Checked.append, ``Text.preservesRegistry] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption do
        throwError "Text capacity theorem {name} adds unexpected axiom {assumption}"
  Lean.logInfo "Text execution covers empty, fitting, and partial-output exhaustion with standard Lean axioms."

end Lanius.Extraction.Tests.CompactOutput.Text
