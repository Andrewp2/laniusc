import Lanius.Extraction.Entry.Suffix.Resources
import Lanius.Extraction.Tests.CompactOutput.Text
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Suffix
open Lanius.Core Lanius.Semantics Lanius.Extraction.Entry

/-- Reject changes to the actual suffix's storage, cursor, saved position,
callee, and guard. Execution correctness is supplied by the universal theorem,
not by replacing the text helper with a test-only implementation. -/
def checkSource (function : FunctionId) (framing : Framing.Stage) (statement : Stmt) : IO Unit := do
  let some checked := Entry.Suffix.check? function statement
    | throw (IO.userError "final suffix differs from its checked append/guard body")
  let stage := checked.locals
  unless (Entry.Suffix.checkSupported? stage framing).isSome do
    throw (IO.userError "final suffix uses different framing storage or shadows a live binding")
  for changed in [{ stage with previous := stage.output },
      { stage with previous := stage.position }, { stage with previous := stage.closing },
      { stage with output := stage.position }, { stage with closing := stage.position },
      { stage with position := stage.previous }, { stage with capacity := stage.capacity + 1 }] do
    if (Entry.Suffix.checkSupported? changed framing).isSome then
      throw (IO.userError "suffix source accepted changed storage, capacity, or cursor bindings")
  if (Entry.Suffix.check? function (stage.statement (function + 1))).isSome then
    throw (IO.userError "suffix source accepted an unproved text callee")
  let .letLocal previous type value (.sequence assignment
      (.sequence (.ifThenElse (.binary _ left right) yes no) continuation)) := statement
    | throw (IO.userError "checked suffix does not expose its exact cursor guard")
  let changed := .letLocal previous type value (.sequence assignment
    (.sequence (.ifThenElse (.binary .equal left right) yes no) continuation))
  if (Entry.Suffix.check? function changed).isSome then
    throw (IO.userError "suffix source accepted an inverted cursor guard")

/-- An effectful continuation detects accidental fallthrough after overflow.
The literal and text callee are the actual source-linked ones. -/
def checkExecution (program : Program) (function : FunctionId) (literal : String) : IO Unit := do
  let bytes := ExtractorContract.moduleSuffix.toUTF8.toList
  for capacity in [146, 147, 149, 822, 823] do
    let stage : Entry.Suffix.Stage := ⟨10, 11, 12, 13, capacity,
      .sequence (.expression (.assign .set (.local 14) (.value (.signed .i32 999))))
        (.returnValue (some (.value (.signed .i32 77))))⟩
    let original : List Int := List.replicate 826 (-500)
    let before : State := ({
      cells := [⟨0, some (.array (signedI32Values original))⟩], nextCell := 1
      world := { standardOutput := [17], standardError := [18] } } : State).bindLocals
        [(11, .signed .i32 146), (12, .slice (.scalar (.signed .i32)) 0 [] 0 original.length),
          (13, .string literal), (14, .signed .i32 41)]
    let written := bytes.take (capacity - 146)
    let wanted := original.take 146 ++ written.map (fun byte => Int.ofNat byte.toNat) ++
      original.drop (146 + written.length)
    let fits := 146 + bytes.length ≤ capacity
    match execStmt 6000 program before (stage.statement function) with
    | .done (.returned (some (.signed .i32 code))) after =>
      unless code == (if fits then 77 else 25) &&
          after.local? 14 == some (.signed .i32 (if fits then 999 else 41)) &&
          after.local? 11 == some (.signed .i32 (if fits then Int.ofNat (146 + bytes.length) else -1)) &&
          after.cell? 0 == some (.array (signedI32Values wanted)) do
        throw (IO.userError s!"suffix guard/result/partial buffer failed at capacity {capacity}")
      unless after.locals == before.locals && after.world.calls == before.world.calls &&
          after.world.standardOutput == before.world.standardOutput && after.world.standardError == before.world.standardError do
        throw (IO.userError "suffix changed scope or emitted output before the packing/stdout tail")
    | _ => throw (IO.userError "suffix trapped or exhausted fuel")

run_elab do
  let standard : Array Lean.Name := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``Entry.Suffix.bytes_length, ``Entry.Suffix.sum_ne_error,
      ``Entry.Suffix.Stage.executes, ``Entry.Startup.Ready.suffixResources] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption do
        throwError "Suffix theorem {name} adds unexpected axiom {assumption}"
  Lean.logInfo "Suffix success and partial-output overflow return use only standard Lean axioms; overflow skips the remaining tail."

end Lanius.Extraction.Tests.Suffix
