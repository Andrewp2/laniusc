import Lanius.Extraction.Entry.File.Next.Resources
import Lanius.Extraction.Entry.Files.Control
import Lanius.Extraction.Tests.Load
import Lanius.Extraction.Diagnostics.Read
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Next
open Lanius.Core Lanius.Semantics Lanius.Extraction.CompactOutput
open Lanius.Extraction.Entry.File

def checkPipeline (pipeline : Load.Pipeline program) (syntaxStage : Syntax.Stage) (resultsStage : Results.Stage) :
    IO (PLift (Entry.File.Next.Relation pipeline syntaxStage resultsStage)) := do
  let some relation := Entry.File.Next.checkRelation? pipeline syntaxStage resultsStage
    | throw (IO.userError "next-file inputs are shadowed inside the completed file body")
  for id in Entry.File.Next.loadLocals pipeline ++ syntaxStage.bufferLocals do
    if (Entry.File.Next.checkRelation? pipeline { syntaxStage with result := id } resultsStage).isSome ||
        (Entry.File.Next.checkRelation? pipeline syntaxStage { resultsStage with nodes := id }).isSome ||
        (Entry.File.Next.checkRelation? pipeline syntaxStage { resultsStage with tokens := id }).isSome then
      throw (IO.userError "next-file binding checker accepted a shadowed buffer or pointer")
  for id in pipeline.boundLocals ++ [syntaxStage.result, resultsStage.nodes, resultsStage.tokens] do
    if (Entry.File.Next.checkRelation? pipeline { syntaxStage with grammar := id } resultsStage).isSome then
      throw (IO.userError "next-file binding checker accepted a replaced grammar-buffer local")
  pure relation

/-- Exercise only the loading/advance boundary, using the actual checked
reader and host calls. Repeated paths and long-to-short-to-empty contents
expose accidental fresh-buffer assumptions and wrong argument advancement. -/
def checkReuse (program : Program) (lengthId argumentId openId readerId closeId : FunctionId)
    (pathStage : Entry.Path.Length.Stage) (argumentStage : Entry.Path.Read.Stage)
    (unpackStage : Input.Unpack.Stage) (openStage : Entry.File.Open.Stage) (readStage : Entry.File.Read.Stage) : IO Unit := do
  let readStage := { readStage with continuation := Advance.statement pathStage.argument }
  let openStage := { openStage with continuation := readStage.statement readerId closeId }
  let unpackStage := { unpackStage with continuation := openStage.statement openId }
  let argumentStage := { argumentStage with continuation := unpackStage.statement }
  let pathStage := { pathStage with continuation := argumentStage.statement argumentId }
  let files : List (String × List UInt8) := [("α", [65, 66, 67, 68]), ("b", [255]), ("empty", [])]
  let paths := ["α", "b", "empty", "b", "α"]
  let world : Lanius.World.State := {
    arguments := "extractor" :: paths
    files := files.map fun (path, bytes) => ⟨Lanius.World.utf8Bytes path, bytes⟩
    fileHandles := [{ id := 3, path := [66], offset := 7, readable := true }]
    nextFileHandle := 17 }
  let (initial, packedPath) ← Host.prepare world 4
  let (withPath, pathValue, _) ← Tests.Load.buffer initial 8 93
  let (withSource, sourceValue, sourceRoot) ← Tests.Load.buffer withPath 8 91
  let (allocated, scratchValue, _) ← Tests.Load.buffer withSource 4 (-1)
  let mut state := allocated.bindLocals [
    (pathStage.argument, .signed .i32 1), (argumentStage.pointer, .pointer packedPath.address),
    (unpackStage.locals.packed, .slice i32 packedPath.root [] 0 packedPath.length),
    (unpackStage.locals.output, pathValue), (readStage.output, sourceValue), (readStage.packed, scratchValue)]
  let mut words : List Int := List.replicate 8 91
  for index in [:paths.length] do
    let path := paths[index]!
    let some file := world.file? (Lanius.World.utf8Bytes path)
      | throw (IO.userError "reuse fixture path missing")
    let .done .next after := execStmt 2000 program state (pathStage.statement lengthId)
      | throw (IO.userError "reused-buffer file load trapped or did not advance")
    words := file.bytes.map (fun byte => (byte.toNat : Int)) ++ words.drop file.bytes.length
    let reads := if file.bytes.isEmpty then 1 else 2
    let expectedWorld : Lanius.World.State := {
      state.world with
      nextFileHandle := state.world.nextFileHandle + 1
      calls := state.world.calls ++ [.argLen, .argRead, .openRead] ++ List.replicate reads .read ++ [.close] }
    unless after.local? pathStage.argument == some (.signed .i32 (index + 2)) &&
        after.cell? sourceRoot == some (.array (signedI32Values words)) &&
        after.locals == state.locals && reprStr after.i32ArrayViews == reprStr state.i32ArrayViews &&
        after.heap.remaining == state.heap.remaining && reprStr after.world == reprStr expectedWorld do
      throw (IO.userError s!"reused-buffer file load lost cursor, bytes, capacity, or external state at argument {index + 1}")
    state := after

/-- A real loop over the loading/advance boundary must stop at a later rejected
file. Small dirty buffers expose cursor, reuse, handle, and skipped-tail bugs;
the separate whole-body theorem supplies frontend/emitter correctness. The
caller's capacity literal is scaled to eight to match the physical test buffer.
The reader, close, guards, and diagnostics are unchanged; native tests retain
the production capacity and the universal reader theorem covers both. -/
def checkRejectReuse (program : Program) (lengthId argumentId openId readerId closeId : FunctionId)
    (pathStage : Entry.Path.Length.Stage) (argumentStage : Entry.Path.Read.Stage)
    (unpackStage : Input.Unpack.Stage) (openStage : Entry.File.Open.Stage) (readStage : Entry.File.Read.Stage) : IO Unit := do
  let readStage := { readStage with continuation := Advance.statement pathStage.argument }
  let .letLocal count ty (.call reader [handle, output, _, packed]) rest := readStage.statement readerId closeId
    | throw (IO.userError "reader call no longer exposes its capacity argument")
  let scaledRead := .letLocal count ty (.call reader [handle, output, number 8, packed]) rest
  let openStage := { openStage with continuation := scaledRead }
  let unpackStage := { unpackStage with continuation := openStage.statement openId }
  let argumentStage := { argumentStage with continuation := unpackStage.statement }
  let pathStage := { pathStage with continuation := argumentStage.statement argumentId }
  let countId := ([pathStage.argument, pathStage.length, argumentStage.pointer, unpackStage.locals.packed,
    unpackStage.locals.output, unpackStage.locals.cursor, openStage.handle, readStage.output,
    readStage.packed, readStage.count, readStage.closed].foldl max 0) + 1
  for count in [1, 3, 10] do
    for (bad, code) in [("", 2), ("nope", 5), ("big", 6)] do
      let world : Lanius.World.State := {
        arguments := "extractor" :: List.replicate count "a" ++ [bad, "must-not-run"],
        files := [⟨[97], [65]⟩, ⟨Lanius.World.utf8Bytes "big", List.replicate 9 66⟩],
        fileHandles := [⟨3, [98], 7, true, false⟩], nextFileHandle := 17,
        standardOutput := [17], standardError := [19], calls := [.close] }
      let (initial, packedPath) ← Host.prepare world 4
      let (withPath, pathValue, _) ← Tests.Load.buffer initial 8 93
      let (withSource, sourceValue, sourceRoot) ← Tests.Load.buffer withPath 8 91
      let (allocated, scratchValue, _) ← Tests.Load.buffer withSource 4 (-1)
      let before := allocated.bindLocals [
        (pathStage.argument, .signed .i32 1), (argumentStage.pointer, .pointer packedPath.address),
        (unpackStage.locals.packed, .slice i32 packedPath.root [] 0 packedPath.length),
        (unpackStage.locals.output, pathValue), (readStage.output, sourceValue), (readStage.packed, scratchValue),
        (countId, .signed .i32 world.arguments.length)]
      let loop := .whileLoop (Entry.Files.condition pathStage.argument countId) (pathStage.statement lengthId)
      let observed := execStmt 4000 program before loop
      let .done (.returned (some (.signed .i32 result))) after := observed
        | throw (IO.userError s!"later-file reuse loop failed: prefix={count}, target={bad}, result={
            match observed with
            | .done _ _ => "unexpected completion"
            | .trapped reason _ => reprStr reason
            | .exited status _ => s!"exited {status}"
            | .outOfFuel => "out of fuel"}")
      let goodCalls : List HostService := [.argLen, .argRead, .openRead, .read, .read, .close]
      let diagnostics := if code == 6 then Lanius.World.utf8Bytes s!"{count + 1}\n2\n" else []
      let badCalls : List HostService := if code == 2 then [.argLen] else
        [.argLen, .argRead, .openRead] ++
          (if code == 6 then [.read, .close] ++ List.replicate diagnostics.length .writeByte else [])
      let expectedWorld : Lanius.World.State := { world with
        calls := world.calls ++ (List.replicate count goodCalls).flatten ++ badCalls
        standardError := world.standardError ++ diagnostics
        nextFileHandle := world.nextFileHandle + count + (if code == 6 then 1 else 0) }
      unless result == code &&
          after.local? pathStage.argument == some (.signed .i32 (count + 1 : Nat)) &&
          after.cell? sourceRoot == some (.array (signedI32Values (65 :: List.replicate 7 91))) &&
          after.cell? 1 == before.cell? 1 && after.locals == before.locals &&
          after.heap.remaining == before.heap.remaining &&
          reprStr after.i32ArrayViews == reprStr before.i32ArrayViews && reprStr after.world == reprStr expectedWorld do
        throw (IO.userError "later-file reuse changed the wrong cursor, diagnostics, output, handles, source bytes, or executed the unchecked tail")
  IO.println "Nine loading/advance loops reject later empty/missing paths and oversized files after 1, 3, and 10 files, retaining dirty buffers, old handles, output, exact diagnostics, and the stopping cursor."

#eval checkRejectReuse {
    constants := [⟨6, i32, .signed .i32 16384⟩]
    functions := [
      ⟨8, Input.File.parameters, i32, some (Input.File.body 9 6), none⟩,
      ⟨9, [(0, i32), (1, .scalar .rawPtr), (2, .scalar (.unsigned .usize))], i32, none, some (.host .read)⟩,
      ⟨10, [(0, i32)], i32, none, some (.host .close)⟩,
      ⟨11, [(0, i32)], i32, none, some (.host .argLen)⟩,
      ⟨12, [(0, i32), (1, .scalar .rawPtr), (2, .scalar (.unsigned .usize))], i32, none, some (.host .argRead)⟩,
      ⟨13, [(0, .scalar .rawPtr), (1, .scalar (.unsigned .usize))], i32, none, some (.host .openRead)⟩,
      ⟨14, [(0, i32)], i32, some (Diagnostics.Natural.body 15), none⟩,
      ⟨15, [(0, i32), (1, i32)], i32, none, some (.host .writeByte)⟩] }
  11 12 13 8 10 ⟨3, 4, .skip⟩ ⟨3, 5, 4, .skip⟩ ⟨⟨6, 7, none, 8, 4⟩, .skip⟩
  ⟨5, 4, 9, .skip⟩ ⟨9, 10, 11, 12, 13, Diagnostics.Read.statement 14 3 12, .skip⟩

run_elab do
  for name in #[``Entry.File.handoff, ``Handoff.restore, ``Entry.File.Next.stableLocal,
      ``Entry.File.Next.inputNext, ``Entry.File.Next.pathBuffers, ``Entry.File.Next.refreshedBuffer, ``Entry.File.Next.frontend,
      ``Entry.File.Next.syntaxReads, ``Entry.File.Next.savedBuffer, ``Entry.File.Next.savedRead,
      ``Entry.File.Next.position, ``Entry.File.Next.olderHandles, ``Entry.File.Next.rebuild] do
    for assumption in ← Lean.collectAxioms name do
      unless assumption == ``propext || assumption == ``Classical.choice || assumption == ``Quot.sound do
        throwError "next-file resource theorem {name} adds unexpected axiom {assumption}"
  Lean.logInfo "Next-file loading resources, dirty frontend buffers, and retained slice arguments use standard axioms only."

end Lanius.Extraction.Tests.Next
