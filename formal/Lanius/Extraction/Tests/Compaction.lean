import Lanius.Extraction.CanonicalTokens.Compaction.Call
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Compaction

open Lanius.Core Lanius.Semantics Lanius.Compiler Lanius.Compiler.Lexer
open Lanius.Extraction.CanonicalTokens.CanonicalizeModel

private def samples : List (String × List RawToken) := [
  ("", []),
  ("return", [⟨.identifier, 0, 6⟩]),
  (" //x", [⟨.whitespace, 0, 1⟩, ⟨.lineComment, 1, 4⟩]),
  ("..=", [⟨.dotDot, 0, 2⟩, ⟨.assign, 2, 3⟩]),
  (".. =", [⟨.dotDot, 0, 2⟩, ⟨.whitespace, 2, 3⟩, ⟨.assign, 3, 4⟩]),
  ("fn x..=1", [⟨.identifier, 0, 2⟩, ⟨.whitespace, 2, 3⟩, ⟨.identifier, 3, 4⟩,
    ⟨.dotDot, 4, 6⟩, ⟨.assign, 6, 7⟩, ⟨.integer, 7, 8⟩])
]

private def register (before : State) (words : List Int) : IO State := do
  let .allocated address heap := before.heap.allocate (words.length * 4) 4
    | throw (IO.userError "compaction native buffer allocation failed")
  let .done _ registered := mapRawI32Slice { before with heap } address words.length
    | throw (IO.userError "compaction native buffer registration failed")
  let some ready := registered.assignCell before.nextCell (.array (signedI32Values words))
    | throw (IO.userError "compaction native buffer initialization failed")
  pure ready

/-- Exercise the native boundary after compaction as well as its semantic
cells: every borrowed keyword view must survive synchronization, together
with the original input, output capacity, and unrelated signed-boundary data. -/
private def checkMemory (before after : State) : IO Unit := do
  let viewKey := fun (view : I32ArrayView) => (view.address, view.root, view.projections, view.length)
  unless (after.i32ArrayViews.take before.i32ArrayViews.length).map viewKey == before.i32ArrayViews.map viewKey &&
      after.heap.remaining == before.heap.remaining && after.cell? 2 == before.cell? 2 do
    throw (IO.userError "compaction changed an existing registration, allocation budget, or unrelated buffer")
  unless after.i32ArrayViews.Pairwise (fun left right => left.root ≠ right.root ∧ left.address ≠ right.address) do
    throw (IO.userError "compaction introduced aliased native views")
  let .ok synced := syncI32ViewsToHeap after
    | throw (IO.userError "compaction left an unencodable native word buffer")
  let .ok refreshed := syncI32ViewsFromHeap synced
    | throw (IO.userError "compaction left an unreadable native word buffer")
  for view in after.i32ArrayViews do
    unless refreshed.cell? view.root == after.cell? view.root do
      throw (IO.userError "compaction changed registered contents across the host synchronization boundary")

/-- Regression execution of the actual checked function, not proof evidence.
Distinctive spare words detect writes past the canonical output prefix. -/
def check (program : Program) (function : FunctionId) : IO Unit := do
  for (text, raw) in samples do
    let source : List Byte := text.toUTF8.toList.map fun byte => ⟨byte.toNat, byte.toNat_lt⟩
    let canonical := canonicalizeTokens source raw
    for capacity in [0, 1, 7, 29] do
      let spare := (List.range capacity).map fun index => -(Int.ofNat index + 100)
      let records := encodeTokens raw ++ spare
      let expected := encodeTokens canonical ++ records.drop (3 * canonical.length)
      let withSource ← register {} (sourceIntegers source)
      let withRecords ← register withSource records
      let before ← register withRecords [-2147483648, 2147483647, 255]
      match evalExpr 10000 program before (.call function [
          .value (.slice (.scalar (.signed .i32)) 0 [] 0 source.length),
          .value (.slice (.scalar (.signed .i32)) 1 [] 0 records.length),
          .value (.signed .i32 raw.length)]) with
      | .done (.signed .i32 count) after =>
          unless count == (canonical.length : Int) &&
              after.cell? 1 == some (.array (signedI32Values expected)) &&
              after.cell? 0 == before.cell? 0 && after.locals == before.locals do
            throw (IO.userError s!"canonicalization disagrees on {reprStr text}, spare words={capacity}")
          checkMemory before after
      | _ => throw (IO.userError s!"canonicalization did not return on {reprStr text}, spare words={capacity}")

run_elab do
  for name in #[``Host.MemoryFrame.borrowed, ``Host.MemoryFrame.scalar, ``Host.MemoryFrame.arraySet,
      ``CanonicalTokens.Ascii.executes_sourceBody, ``CanonicalTokens.Ascii.evaluates_call,
      ``CanonicalTokens.Dispatch.CheckedFunction.evaluates_call, ``CanonicalTokens.Kind.Checked.evaluates_call,
      ``CanonicalTokens.Compaction.CheckedSource.evaluates_call] do
    for assumption in ← Lean.collectAxioms name do
      unless assumption == ``propext || assumption == ``Classical.choice || assumption == ``Quot.sound do
        throwError "Native compaction theorem {name} depends on unexpected axiom {assumption}"

end Lanius.Extraction.Tests.Compaction
