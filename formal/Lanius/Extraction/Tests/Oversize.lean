import Lanius.Extraction.Entry.Domain
import Lanius.Extraction.Entry.Failure
import Lanius.Extraction.Entry.Startup.Oversize
import Lanius.Extraction.Tests.Host
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Oversize
open Lanius.Core Lanius.Semantics Lanius.Extraction.Entry Lanius.Extraction.CompactOutput

private def world (size : Nat) : Lanius.World.State := {
  arguments := ["extractor", "λ.lani", "unchecked-later"]
  files := [⟨Lanius.World.utf8Bytes "λ.lani", List.replicate size 255⟩]
  fileHandles := [⟨3, [98], 7, true, false⟩]
  nextFileHandle := 17
  standardOutput := [17, 18]
  standardError := [19]
  calls := [.close] }

private def admitted : List Lanius.World.State :=
  [world 65537, world 65538, world 131073,
    { world 65537 with nextFileHandle := 2147483647 },
    { world 65537 with nextFileHandle := 0, fileHandles := [] }]

def check : IO Unit := do
  for world in admitted do
    unless (checkOversizedFileDomain? world).isSome do
      throw (IO.userError "oversized first file was not admitted")
  let base := world 65537
  let longPath := String.ofList (List.replicate 1025 'a')
  for world in [world 0, world 65535, world 65536,
      { base with files := [] }, { base with arguments := ["extractor"] },
      { base with arguments := ["extractor", ""], files := [⟨[], List.replicate 65537 255⟩] },
      { base with arguments := ["extractor", longPath], files := [⟨Lanius.World.utf8Bytes longPath, List.replicate 65537 255⟩] },
      { base with nextFileHandle := 2147483648 },
      { base with fileHandles := [⟨17, [98], 7, true, false⟩] }] do
    if (checkOversizedFileDomain? world).isSome then
      throw (IO.userError "oversized-file domain admitted a fitting file or a false host prerequisite")
  IO.println "Oversized-file domain: 5 accepted cases and 9 rejected mutations cover size, UTF-8 paths, file availability, and handle bounds."

def checkExecutable (checked : CheckedExecution accepted) : IO Unit := do
  for world in admitted do
    let some domain := checkOversizedFileDomain? world
      | throw (IO.userError "oversized-file fixture rejected")
    have _actualMain := checked.oversizedFile domain.down
    pure ()
  let pipeline := checked.file.pipeline
  let some diagnostics := Diagnostics.Read.check? accepted.checked.program
      pipeline.path.argument pipeline.read.count pipeline.read.failure
    | throw (IO.userError "actual read diagnostics source rejected")
  for changed in [returned (number 6), .skip,
      Diagnostics.Read.statement (diagnostics.writer.source.source.function.id + 1) pipeline.path.argument pipeline.read.count,
      Diagnostics.Read.statement diagnostics.writer.source.source.function.id pipeline.path.argument (pipeline.read.count + 1)] do
    if (Diagnostics.Read.check? accepted.checked.program pipeline.path.argument pipeline.read.count changed).isSome then
      throw (IO.userError "removed diagnostics, changed writer, or wrong error-count local was accepted")
  IO.println "Actual-main oversized-file theorem instantiated on 5 worlds: closes the file, returns 6, and preserves stdout."

/-- Fault injection isolates the caller's unconditional close from the
separately proved reader loop. It tests both negative reader codes and a
successful zero-byte result, retaining dirty buffers and an older handle. -/
def checkClose (program : Program) (reader closer : FunctionId) (sourceStage : File.Read.Stage) (argument : VarId) : IO Unit := do
  for status in ([-2, -1, 0] : List Int) do
    let functions := program.functions.map fun function =>
      if function.id == reader then { function with body := some (returned (.value (.signed .i32 status))) } else function
    let injected := { program with functions }
    let world : Lanius.World.State := {
      fileHandles := [⟨3, [98], 7, true, false⟩, ⟨7, [97], 0, true, false⟩]
      standardOutput := [17]
      standardError := [19] }
    let (initial, buffer) ← Host.prepare world 4
    let before := initial.bindLocals [
      (sourceStage.handle, .signed .i32 7),
      (sourceStage.output, .slice i32 buffer.root [] 0 buffer.length),
      (sourceStage.packed, .slice i32 buffer.root [] 0 buffer.length), (argument, .signed .i32 4)]
    let stage := { sourceStage with continuation := returned (number 99) }
    let .done (.returned (some (.signed .i32 code))) after := execStmt 200 injected before (stage.statement reader closer)
      | throw (IO.userError "read/close fault injection trapped or failed to return")
    unless code == (if status < 0 then 6 else 99) &&
        after.world.calls == [.close] ++ (if status < 0 then List.replicate 4 .writeByte else []) &&
        after.world.fileHandles.length == 1 && (after.world.handle? 7).isNone &&
        (after.world.handle? 3).map (·.offset) == some 7 &&
        after.world.standardOutput == world.standardOutput &&
        after.world.standardError == world.standardError ++
          (if status < 0 then Lanius.World.utf8Bytes s!"4\n{0 - status}\n" else []) &&
        after.locals == before.locals && after.cell? 0 == before.cell? 0 && after.cell? 1 == before.cell? 1 &&
        after.heap.remaining == before.heap.remaining do
      throw (IO.userError "reader rejection skipped close, entered the frontend, or changed caller storage")

private def fixture : Program := { functions := [
  ⟨8, Input.File.parameters, i32, some (returned (number 0)), none⟩,
  ⟨9, [(0, i32)], i32, none, some (.host .close)⟩,
  ⟨10, [(0, i32)], i32, some (Diagnostics.Natural.body 11), none⟩,
  ⟨11, [(0, i32), (1, i32)], i32, none, some (.host .writeByte)⟩] }

#eval check
#eval checkClose fixture 8 9 ⟨0, 1, 2, 3, 4, Diagnostics.Read.statement 10 5 3, .skip⟩ 5

run_elab do
  for name in #[``Input.File.readOversized, ``Input.File.iterationOversized, ``Input.File.rejectsLoop,
      ``Input.File.runsLoop, ``Input.File.body_returns, ``Input.File.Checked.read,
      ``File.Read.Stage.readClose, ``File.Read.Stage.rejectsOversized, ``File.Load.Pipeline.prepare,
      ``File.Load.Pipeline.rejectsOversized, ``Files.LoadingSource.available, ``Startup.rejectsOversized,
      ``Diagnostics.Read.check?, ``Diagnostics.Read.Checked.oversized,
      ``checkOversizedFileDomain?, ``CheckedExecution.oversizedFile] do
    for assumption in ← Lean.collectAxioms name do
      unless assumption == ``propext || assumption == ``Classical.choice || assumption == ``Quot.sound do
        throwError "Oversized-file theorem {name} depends on unexpected axiom {assumption}"

end Lanius.Extraction.Tests.Oversize
