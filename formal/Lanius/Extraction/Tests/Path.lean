import Lanius.Extraction.Entry.Path.Length
import Lanius.Extraction.Entry.Path.Prefix
import Lanius.Extraction.Input.Unpack.Initialize
import Lanius.Extraction.Entry.Path.Initialize
import Lanius.Extraction.Entry.File.Initialize
import Lanius.Extraction.Entry.Failure
import Lanius.Extraction.Tests.Host
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Path

open Lanius.Core Lanius.Semantics Lanius.Extraction.CompactOutput

private def lengthFunction : Function := ⟨7, [(0, i32)], i32, none, some (.host .argLen)⟩

private def fixture : Program := { functions := [lengthFunction] }

private def stage : Entry.Path.Length.Stage := ⟨3, 4, returned (read 4)⟩

/-- Exercise UTF-8 byte lengths and both sides of the path limit with a live
registered buffer. A host call must preserve its contents through sync. -/
def checkExecution (program : Program) (function : FunctionId) : IO Unit := do
  for path in ["", "a", "é", "é/λ.lani", String.ofList (List.replicate 1024 'a'),
      String.ofList (List.replicate 1025 'a'), String.ofList (List.replicate 512 'é'),
      String.ofList (List.replicate 513 'é')] do
    let initial : State := { world := { arguments := ["extractor", path] } }
    let .allocated address heap := initial.heap.allocate 8 4
      | throw (IO.userError "path-test buffer allocation failed")
    let .done _ registered := mapRawI32Slice { initial with heap } address 2
      | throw (IO.userError "path-test raw view failed")
    let some contents := registered.assignCell 0 (.array (signedI32Values [2147483647, -2147483648]))
      | throw (IO.userError "path-test initial contents unavailable")
    let before := contents.bindLocal stage.argument (.signed .i32 1)
    match execStmt 100 program before (stage.statement function) with
    | .done (.returned (some (.signed .i32 result))) after =>
        let length := path.toUTF8.size
        let expected : Int := if length == 0 || 1024 < length then 2 else length
        unless result == expected && after.locals == before.locals &&
            after.world.arguments == before.world.arguments &&
            after.world.calls == before.world.calls ++ [.argLen] &&
            (after.i32ArrayViews.map fun view => (view.address, view.root, view.projections, view.length)) ==
              (before.i32ArrayViews.map fun view => (view.address, view.root, view.projections, view.length)) &&
            after.cell? 0 == before.cell? 0 do
          throw (IO.userError s!"path length/guard or host frame failed for {length} UTF-8 bytes")
    | _ => throw (IO.userError "path-length stage trapped or exhausted fuel")

#eval checkExecution fixture 7

/-- Instantiate the public first-path theorem on the accepted source, not a
handwritten main. The fields deliberately violate the normal loading domain.
Proof instantiation does not execute the large startup workspaces. -/
def checkExecutable (checked : Entry.CheckedExecution accepted) : IO Unit := do
  for path in ["", String.ofList (List.replicate 1025 'a'), String.ofList (List.replicate 513 'é')] do
    let world : Lanius.World.State := {
      arguments := ["extractor", path, "later-missing-file"], standardInput := [99],
      standardOutput := [17, 18], standardError := [19], environment := [("x", "y")],
      files := [], fileHandles := [⟨-1, [97], 100, false, true⟩],
      nextFileHandle := 2 ^ 80, calls := [.close] }
    if size : path.toUTF8.size ≤ 2147483647 then
      if invalid : path.toUTF8.size = 0 ∨ 1025 ≤ path.toUTF8.size then
        have _publicRejection := checked.invalidPath world
          (by change 1 < (3 : Nat); decide) (by change (3 : Nat) < 2 ^ 31; decide)
          path rfl size invalid
        pure ()
      else throw (IO.userError "invalid-path fixture is inside the accepted length range")
    else throw (IO.userError "invalid-path fixture exceeds the modeled host length range")
  IO.println "Actual-main rejection theorem instantiated for empty, 1025-byte ASCII, and 1026-byte UTF-8 paths without loading-domain assumptions."
  for path in ["missing", "é/λ.lani"] do
    let world : Lanius.World.State := {
      arguments := ["extractor", path, "later-missing-file"], standardOutput := [17], standardError := [19],
      files := [], fileHandles := [⟨-1, [97], 100, false, true⟩], nextFileHandle := 2 ^ 80, calls := [.close] }
    if nonempty : 0 < path.toUTF8.size then
      if fits : path.toUTF8.size ≤ 1024 then
        have _publicRejection := checked.missingFile world
          (by change 1 < (3 : Nat); decide) (by change (3 : Nat) < 2 ^ 31; decide)
          path rfl nonempty fits rfl
        pure ()
      else throw (IO.userError "missing-file fixture exceeds the path limit")
    else throw (IO.userError "missing-file fixture has an empty path")
  IO.println "Actual-main missing-file rejection theorem instantiated for ASCII and UTF-8 paths without a handle bound or later-file assumptions."

/-- Exercise the composed source stages, including scope restoration, exact
packed argument bytes, and early rejection before the copy host call. -/
def checkPrefix (program : Program) (lengthFunction readFunction : FunctionId) : IO Unit := do
  let copy : Entry.Path.Read.Stage := ⟨3, 5, 4, returned (read 4)⟩
  let prefixStage : Entry.Path.Length.Stage := ⟨3, 4, copy.statement readFunction⟩
  for path in ["", "a", "abc", "abcd", "abcde", "é/λ.lani",
      String.ofList (List.replicate 1024 'a'), String.ofList (List.replicate 1025 'a')] do
    let (registered, view) ← Tests.Host.prepare { arguments := ["extractor", path] } 256
    let before := (registered.bindLocal 3 (.signed .i32 1)).bindLocal 5 (.pointer view.address)
    match execStmt 150 program before (prefixStage.statement lengthFunction) with
    | .done (.returned (some (.signed .i32 result))) after =>
        let size := path.toUTF8.size
        if size == 0 || 1024 < size then
          unless result == 2 && after.world.calls == [.argLen] && after.cell? 0 == before.cell? 0 do
            throw (IO.userError "invalid path was copied or failed to return code two")
        else
          unless result == size && after.world.calls == [.argLen, .argRead] do
            throw (IO.userError "path prefix returned an incorrect count or host trace")
          Tests.Host.checkCopy before after view (Lanius.World.utf8Bytes path)
        unless after.locals == before.locals do
          throw (IO.userError "path prefix failed to restore caller locals")
    | _ => throw (IO.userError "path prefix trapped or exhausted fuel")

#eval checkPrefix { fixture with functions := fixture.functions ++ [
  ⟨8, [(0, i32), (1, .scalar .rawPtr), (2, .scalar (.unsigned .usize))], i32, none, some (.host .argRead)⟩] } 7 8

/-- Run the length/copy/unpack sequence with an independently allocated
destination and a third buffer that must remain untouched. -/
def checkOpenedPath (program : Program) (lengthFunction readFunction openFunction : FunctionId) : IO Unit := do
  let opened : Entry.File.Open.Stage := ⟨5, 4, 9, returned (read 9)⟩
  let unpack : Input.Unpack.Stage := ⟨⟨6, 7, none, 8, 4⟩, opened.statement openFunction⟩
  let copy : Entry.Path.Read.Stage := ⟨3, 5, 4, unpack.statement⟩
  let prefixStage : Entry.Path.Length.Stage := ⟨3, 4, copy.statement readFunction⟩
  for path in ["a", "ab", "abc", "abcd", "abcde", "abcdef", "abcdefg", "é/λ.lani"] do
    let bytes := Lanius.World.utf8Bytes path
    let capacity := bytes.length + 3
    let (registered, view) ← Tests.Host.prepare {
      arguments := ["extractor", path], files := [⟨bytes, [65, 66]⟩], nextFileHandle := 17,
      fileHandles := [{ id := 3, path := [66], readable := true, offset := 7 }] } 4
    let .allocated address heap := registered.heap.allocate (capacity * 4) 4
      | throw (IO.userError "unpack-test destination allocation failed")
    let outputCell := registered.nextCell
    let .done output allocated := mapRawI32Slice { registered with heap } address capacity
      | throw (IO.userError "unpack-test destination registration failed")
    let some initialized := allocated.assignCell outputCell (.array (signedI32Values (List.replicate capacity 93)))
      | throw (IO.userError "unpack-test destination initialization failed")
    let before := initialized.bindLocals [
      (3, .signed .i32 1), (5, .pointer view.address),
      (6, .slice i32 view.root [] 0 view.length), (7, output)]
    match execStmt (bytes.length * 2 + 200) program before (prefixStage.statement lengthFunction) with
    | .done (.returned (some (.signed .i32 count))) after =>
        unless count == 17 && after.world.calls == [.argLen, .argRead, .openRead] &&
            (after.world.handle? 17).map (·.path) == some bytes &&
            (after.world.handle? 3).map (·.offset) == some 7 &&
            after.cell? outputCell == some (.array (signedI32Values
              (bytes.map (fun byte => (byte.toNat : Int)) ++ List.replicate 3 93))) do
          throw (IO.userError "path unpack changed byte order, destination tail, or return count")
        Tests.Host.checkCopy before after view bytes
    | _ => throw (IO.userError "composed path unpack trapped or exhausted fuel")

#eval checkOpenedPath { fixture with functions := fixture.functions ++ [
  ⟨8, [(0, i32), (1, .scalar .rawPtr), (2, .scalar (.unsigned .usize))], i32, none, some (.host .argRead)⟩,
  ⟨10, [(0, .scalar .rawPtr), (1, .scalar (.unsigned .usize))], i32, none, some (.host .openRead)⟩] } 7 8 10

/-- Missing files must reject before the read continuation. The existing
unpack prefix may update its two path buffers, but not another live buffer,
the filesystem, existing handles, the handle counter, or process output. -/
def checkMissing (program : Program) (lengthFunction readFunction openFunction : FunctionId) : IO Unit := do
  let opened : Entry.File.Open.Stage := ⟨5, 4, 9, returned (number 42)⟩
  let unpack : Input.Unpack.Stage := ⟨⟨6, 7, none, 8, 4⟩, opened.statement openFunction⟩
  let copy : Entry.Path.Read.Stage := ⟨3, 5, 4, unpack.statement⟩
  let pathStage : Entry.Path.Length.Stage := ⟨3, 4, copy.statement readFunction⟩
  for path in ["missing", "é/λ.lani"] do
    for counter in [0, 2147483647, 2 ^ 80] do
      let bytes := Lanius.World.utf8Bytes path
      let world : Lanius.World.State := {
        arguments := ["extractor", path], files := [⟨[65], [99]⟩],
        fileHandles := [⟨-1, [65], 100, false, true⟩], nextFileHandle := counter,
        standardOutput := [17], standardError := [19], calls := [.close] }
      let (registered, view) ← Tests.Host.prepare world 4
      let .allocated address heap := registered.heap.allocate ((bytes.length + 3) * 4) 4
        | throw (IO.userError "missing-file path buffer allocation failed")
      let .done output allocated := mapRawI32Slice { registered with heap } address (bytes.length + 3)
        | throw (IO.userError "missing-file path buffer registration failed")
      let before := allocated.bindLocals [
        (3, .signed .i32 1), (5, .pointer view.address),
        (6, .slice i32 view.root [] 0 view.length), (7, output)]
      let .done (.returned (some (.signed .i32 code))) after :=
          execStmt (bytes.length * 2 + 200) program before (pathStage.statement lengthFunction)
        | throw (IO.userError "missing-file rejection trapped or exhausted fuel")
      unless code == 5 && after.locals == before.locals &&
          after.world.calls == world.calls ++ [.argLen, .argRead, .openRead] &&
          after.world.nextFileHandle == counter && after.world.arguments == world.arguments &&
          after.world.standardOutput == world.standardOutput && after.world.standardError == world.standardError &&
          after.world.files.map (fun file => (file.path, file.bytes)) == world.files.map (fun file => (file.path, file.bytes)) &&
          after.world.fileHandles.map (fun handle => (handle.id, handle.path, handle.offset, handle.readable, handle.writable)) ==
            world.fileHandles.map (fun handle => (handle.id, handle.path, handle.offset, handle.readable, handle.writable)) &&
          after.cell? 1 == before.cell? 1 && after.heap.remaining == before.heap.remaining do
        throw (IO.userError "missing-file rejection ran its continuation, changed external state, or lost the kept buffer")
      Tests.Host.checkCopy before after view bytes
  IO.println "Missing-file prefix returns 5 in six UTF-8/counter cases, with no read, close, handle creation, or output."

#eval checkMissing { fixture with functions := fixture.functions ++ [
  ⟨8, [(0, i32), (1, .scalar .rawPtr), (2, .scalar (.unsigned .usize))], i32, none, some (.host .argRead)⟩,
  ⟨10, [(0, .scalar .rawPtr), (1, .scalar (.unsigned .usize))], i32, none, some (.host .openRead)⟩] } 7 8 10

#eval show IO Unit from do
  unless (Host.checkLength? fixture 7).isSome &&
      (Entry.Path.Length.check? 7 (stage.statement 7)).isSome do
    throw (IO.userError "exact argument-length service or path stage rejected")
  if (Entry.Path.Length.check? 8 (stage.statement 7)).isSome then
    throw (IO.userError "path stage with wrong host call accepted")
  let noGuard := .letLocal stage.length i32 (.call 7 [read stage.argument])
    (.sequence .skip stage.continuation)
  if (Entry.Path.Length.check? 7 noGuard).isSome then
    throw (IO.userError "path stage without its length guard accepted")
  for (upper, code) in [(1024, 2), (1026, 2), (1025, 5)] do
    let changed := .letLocal stage.length i32 (.call 7 [read stage.argument])
      (.sequence (.ifThenElse
        (binary .logicalOr (binary .lessEqual (read stage.length) (number 0))
          (binary .greaterEqual (read stage.length) (number upper)))
        (returned (number code)) .skip) stage.continuation)
    if (Entry.Path.Length.check? 7 changed).isSome then
      throw (IO.userError "changed path limit or failure code reused the exact-source proof")
  for function in [
      { lengthFunction with external := some (.host .argc) },
      { lengthFunction with body := some .skip },
      { lengthFunction with parameters := [] }] do
    if (Host.checkLength? { fixture with functions := [function] } 7).isSome then
      throw (IO.userError "incorrect host declaration accepted as argument length")
  let copy : Entry.Path.Read.Stage := ⟨3, 5, 4, .skip⟩
  unless (Entry.Path.Read.check? 8 (copy.statement 8)).isSome && (Entry.Path.checkRelation? stage copy).isSome do
    throw (IO.userError "exact argument-copy stage or binding relation rejected")
  if (Entry.Path.Read.check? 9 (copy.statement 8)).isSome ||
      (Entry.Path.checkRelation? stage { copy with argument := 99 }).isSome ||
      (Entry.Path.checkRelation? stage { copy with pointer := stage.length }).isSome then
    throw (IO.userError "wrong copy service or shadowed path binding accepted")
  let unpack : Input.Unpack.Stage := ⟨⟨6, 7, none, 8, 4⟩, .skip⟩
  unless (Input.Unpack.check? unpack.statement).isSome && unpack.checkSupported?.isSome do
    throw (IO.userError "exact path unpack stage rejected")
  for locals in [{ unpack.locals with cursor := 6 }, { unpack.locals with cursor := 7 },
      { unpack.locals with cursor := 4 }, { unpack.locals with total := some 8 }] do
    if ({ unpack with locals } : Input.Unpack.Stage).checkSupported?.isSome then
      throw (IO.userError "shadowed unpack binding accepted")
  let offsetUnpack : Input.Unpack.Stage := { unpack with locals := { unpack.locals with total := some 9 } }
  unless offsetUnpack.checkSupported?.isSome do
    throw (IO.userError "disjoint file-offset unpack form rejected")
  if (Entry.Path.checkUnpackRelation? stage copy offsetUnpack).isSome then
    throw (IO.userError "file-offset unpack form accepted as a direct path copy")
  if (Input.Unpack.check? (.letLocal 8 i32 (number 1)
      (.sequence unpack.locals.loop .skip))).isSome then
    throw (IO.userError "nonzero initial path cursor accepted")
  let opened : Entry.File.Open.Stage := ⟨copy.pointer, unpack.locals.length, 9, .skip⟩
  unless (Entry.File.Open.check? 10 (opened.statement 10)).isSome &&
      (Entry.File.checkPathRelation? copy unpack opened).isSome do
    throw (IO.userError "exact file-open stage or path/open binding relation rejected")
  if (Entry.File.Open.check? 11 (opened.statement 10)).isSome ||
      (Entry.File.checkPathRelation? copy unpack { opened with pointer := 99 }).isSome ||
      (Entry.File.checkPathRelation? copy unpack { opened with handle := unpack.locals.length }).isSome ||
      (Entry.File.checkPathRelation? copy { unpack with locals := { unpack.locals with cursor := copy.pointer } } opened).isSome then
    throw (IO.userError "wrong file opener or shadowed path pointer accepted")

run_elab do
  for name in #[``Allocation.Registry.refresh, ``Allocation.Registry.withWorld,
      ``Host.Frame.preservesLocal, ``Host.evaluatesReadOnly, ``Host.readOnlyPreservesView,
      ``Host.checkLength?, ``Host.CheckedLength.evaluates, ``Host.i32Result_nat,
      ``Entry.Path.Length.check?, ``Entry.Path.Length.Stage.guardResult,
      ``Entry.Path.Length.Stage.executes, ``Entry.Path.Length.Stage.rejects,
      ``Entry.Files.CheckedSource.reaches, ``Entry.Files.CheckedSource.first,
      ``Entry.Files.First.completeReturn, ``Entry.CheckedExecution.invalidPath,
      ``Entry.Path.Read.check?, ``Entry.Path.Read.Stage.executes,
      ``Entry.Path.checkRelation?, ``Entry.Path.bytes_length, ``Entry.Path.Length.Stage.withRead,
      ``Input.UnpackLocals.Offset.preserved, ``Input.executes_unpacking_body, ``Input.executes_unpacking_loop,
      ``Input.Unpack.check?, ``Input.Unpack.Stage.executes,
      ``Entry.Path.checkUnpackRelation?, ``Entry.Path.Length.Stage.withUnpack,
      ``Host.representableAfterRefresh, ``Host.RepresentableViews.bindLocal, ``Host.RepresentableViews.transport,
      ``Entry.File.Open.check?, ``Entry.File.Open.Stage.executes, ``Entry.File.prepare,
      ``Host.File.evaluatesMissing, ``Entry.File.Open.Stage.rejectsMissing,
      ``Entry.File.Load.Pipeline.rejectsMissing, ``Entry.Files.LoadingSource.pathBuffers,
      ``Entry.CheckedExecution.missingFile] do
    let axioms ← Lean.collectAxioms name
    for assumption in axioms do
      unless assumption == ``propext || assumption == ``Classical.choice || assumption == ``Quot.sound do
        throwError "{name} depends on unexpected axiom {assumption}"

end Lanius.Extraction.Tests.Path
