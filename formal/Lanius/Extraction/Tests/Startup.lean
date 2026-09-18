import Lanius.Extraction.Entry.Startup.Output
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Startup
open Lanius.Core Lanius.Semantics Lanius.Extraction.Entry

/-- Exercise the allocation boundary on the actual extracted declarations.
Changed capacity, shadowing, or pointer provenance must not reuse the proof. -/
def checkAllocations (buffers : List Allocation.Buffer) (aliases : List Pointers.Alias)
    (literal : Grammar.LiteralStage) (framing : Framing.Stage) (argument : VarId) : IO Unit := do
  for buffer in buffers do
    unless (Files.checkBufferSource? buffers aliases literal framing argument buffer.binding buffer.count).isSome do
      throw (IO.userError "startup fails to retain an actual allocated buffer at file entry")
    for count in [buffer.count + 1, buffer.count - 1] do
      if count != buffer.count &&
          (Files.checkBufferSource? buffers aliases literal framing argument buffer.binding count).isSome then
        throw (IO.userError "file-entry allocation accepted a changed physical capacity")
    if (Files.checkBufferSource? buffers aliases literal framing buffer.binding buffer.binding buffer.count).isSome then
      throw (IO.userError "argument cursor may shadow an allocated slice")
    for shadowed in startupLocals literal framing do
      if (Files.checkBufferSource? buffers aliases literal framing argument shadowed buffer.count).isSome then
        throw (IO.userError "startup temporary may stand in for an allocated slice")
    if (Files.checkBufferSource? buffers (aliases ++ [⟨buffer.binding, .slice buffer.binding⟩])
        literal framing argument buffer.binding buffer.count).isSome then
      throw (IO.userError "pointer alias may overwrite its allocated slice")
  for alias in aliases do
    match alias.source with
    | .localValue _ => pure ()
    | .slice binding =>
      unless (Files.checkPointerSource? aliases literal framing argument alias.name binding).isSome do
        throw (IO.userError "actual slice-pointer alias lost its allocation provenance")
      if (Files.checkPointerSource? aliases literal framing argument alias.name (binding + 1000000)).isSome then
        throw (IO.userError "pointer may refer to a different slice")
      if (Files.checkPointerSource? (aliases ++ [alias]) literal framing argument alias.name binding).isSome then
        throw (IO.userError "duplicate aliases may conceal a later overwrite")
      if (Files.checkPointerSource? aliases literal { framing with position := alias.name }
          argument alias.name binding).isSome then
        throw (IO.userError "output cursor may overwrite a file-loading pointer")
      if (Files.checkPointerSource? aliases literal framing alias.name alias.name binding).isSome then
        throw (IO.userError "argument cursor may overwrite a file-loading pointer")

/-- Authenticate initial frontend and output storage on the actual source.
Mutations target the request/grammar connections, buffer reuse, and both
cursors; no production-sized interpreted allocation fixture is required. -/
def checkFirstFile (pipeline : File.Load.Pipeline program)
    (syntaxStage : File.Syntax.Stage) (collectStage : File.Collect.Stage)
    (emitStage : File.Emit.Stage) (header : Header.Stage)
    (buffers : List Allocation.Buffer) (aliases : List Pointers.Alias)
    (literal : Grammar.LiteralStage) (framing : Framing.Stage) : IO Unit := do
  if ({ framing with position := framing.closing }).checkSupported?.isSome then
    throw (IO.userError "output cursor may shadow the suffix string needed after the file loop")
  unless (Files.checkFrontendSource? pipeline syntaxStage buffers aliases literal framing).isSome do
    throw (IO.userError "initial frontend resources do not match the actual startup allocations")
  for stage in [{ syntaxStage with source := syntaxStage.raw },
      { syntaxStage with grammar := syntaxStage.source },
      { syntaxStage with canonical := syntaxStage.raw },
      { syntaxStage with raw := pipeline.read.packed },
      { syntaxStage with offsets := syntaxStage.kinds }] do
    if (Files.checkFrontendSource? pipeline stage buffers aliases literal framing).isSome then
      throw (IO.userError "initial frontend accepted a disconnected source/grammar or overlapping working buffer")
  for count in [2178, 2180] do
    let changed := { literal with setup := { literal.setup with cursor := { literal.setup.cursor with
      locals := { literal.setup.cursor.locals with count } } } }
    if (Files.checkFrontendSource? pipeline syntaxStage buffers aliases changed framing).isSome then
      throw (IO.userError "initial frontend accepted a partially or excessively decoded grammar")
  unless (Files.checkOutputSource? pipeline syntaxStage collectStage emitStage header
      buffers aliases literal framing).isSome do
    throw (IO.userError "initial semantic/output resources do not match the startup header")
  for capacity in [8388607, 8388609] do
    if (Files.checkOutputSource? pipeline syntaxStage collectStage emitStage header
        buffers aliases literal { framing with capacity }).isSome then
      throw (IO.userError "framing and final suffix may use a different logical capacity from file emission")
  for stage in [{ collectStage with semantic := emitStage.output },
      { collectStage with semantic := syntaxStage.raw },
      { collectStage with semantic := pipeline.read.output }] do
    if (Files.checkOutputSource? pipeline syntaxStage stage emitStage header buffers aliases literal framing).isSome then
      throw (IO.userError "semantic collection may overwrite output, frontend, or source storage")
  for stage in [{ emitStage with output := collectStage.semantic },
      { emitStage with position := pipeline.path.argument },
      { emitStage with position := header.position + 1000000 }] do
    if (Files.checkOutputSource? pipeline syntaxStage collectStage stage header buffers aliases literal framing).isSome then
      throw (IO.userError "file emission accepted a disconnected output buffer or cursor")

run_elab do
  let standard : Array Lean.Name := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``Allocation.Registry.view_eq, ``Entry.Pointers.Pointer.Resolves.sliceAddress,
      ``Entry.Pointers.Pointer.evaluates, ``Entry.Pointers.aliasesExecute, ``Entry.Pointers.executeEntry,
      ``Entry.Pointers.preserveNonarray, ``Entry.Pointers.retainedBuffer, ``Entry.Retained.buffer,
      ``Entry.Framing.Stage.withHeader, ``Entry.initializeHeader,
      ``Host.RepresentableViews.ofRuntime, ``Entry.Files.CheckedSource.enter,
      ``Entry.Files.BufferSource.storage, ``Entry.Files.BufferStorage.apart,
      ``Entry.Files.PointerSource.read, ``Entry.Files.LoadingSource.input, ``Entry.Files.CheckedSource.loading,
      ``Entry.Grammar.indexedLanius_wellFormed, ``Entry.Files.InputStorage.apart,
      ``Entry.Files.FrontendSource.grammarWords, ``Entry.Files.FrontendSource.prepare, ``Entry.Files.FrontendSource.apart,
      ``Entry.Files.OutputSource.resources, ``Entry.Files.CheckedSource.resources, ``Entry.Startup.reaches,
      ``Prefix.Reaches.completeReturn, ``Entry.Files.CheckedSource.afterLoop,
      ``Entry.Files.Result.carriedNonScalar, ``Entry.Startup.Ready.loopCursors,
      ``Entry.Startup.Ready.bufferAfterFiles, ``Entry.Startup.Ready.suffixAfterFiles] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption do
        throwError "Startup resource theorem {name} adds unexpected axiom {assumption}"
  let baseline ← Lean.collectAxioms ``Frontend.CheckedSyntax.call_evaluates
  for name in #[``Entry.Files.CheckedSource.runFromStartup, ``Entry.Startup.runFiles] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption || baseline.contains assumption do
        throwError "Startup-to-file-loop composition {name} adds unexpected axiom {assumption}"
  Lean.logInfo "Startup, first-file resources, final live buffers/suffix, and main-scope return composition use only standard Lean axioms; running the ordered loop adds no assumptions beyond the existing frontend baseline."

end Lanius.Extraction.Tests.Startup
