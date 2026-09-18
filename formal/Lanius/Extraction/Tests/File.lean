import Lanius.Extraction.Input.File.Call
import Lanius.Extraction.Tests.Host
import Lanius.Extraction.Entry.File.Read
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.File

open Lanius.Core Lanius.Semantics Lanius.Extraction.CompactOutput

private def fixture : Program := {
  constants := [⟨6, i32, .signed .i32 16384⟩]
  functions := [
    ⟨9, [(0, i32), (1, .scalar .rawPtr), (2, .scalar (.unsigned .usize))], i32, none, some (.host .read)⟩,
    ⟨10, [(0, i32)], i32, none, some (.host .close)⟩,
    ⟨8, Input.File.parameters, i32, some (Input.File.body 9 6), none⟩] }

/-- Execute the complete source-shaped reader on byte-lane, EOF, capacity,
and offset boundaries. Independent expected bytes also check the unwritten
tail, another registered buffer, an older handle, and the caller's locals. -/
def check (program : Program) (reader : FunctionId) : IO Unit := do
  let source : List UInt8 := [255, 0, 128, 127, 42, 254, 17, 99, 200, 3, 4]
  for length in [0, 1, 3, 4, 5, 11] do
    for offset in [0, 1, 12] do
      for capacity in [0, 3, 4, 5, 11] do
        let bytes := source.take length
        let world : Lanius.World.State := {
          files := [⟨[65], bytes⟩]
          fileHandles := [{ id := 3, path := [66], offset := 7, readable := true },
            { id := 7, path := [65], offset, readable := true }]
          nextFileHandle := 8 }
        let (initial, packed) ← Host.prepare world 4
        let count := capacity + 2
        let .allocated address heap := initial.heap.allocate (count * 4) 4
          | throw (IO.userError "file-reader output allocation failed")
        let .done (.slice _ root _ _ _) mapped := mapRawI32Slice { initial with heap } address count
          | throw (IO.userError "file-reader output registration failed")
        let some initialized := mapped.assignCell root (.array (signedI32Values (List.replicate count 91)))
          | throw (IO.userError "file-reader output initialization failed")
        let before := initialized.bindLocal 77 (.signed .i32 1234)
        let arguments := [.signed .i32 7, .slice i32 root [] 0 count, .signed .i32 capacity,
          .slice i32 packed.root [] 0 packed.length]
        let .done (.signed .i32 result) after := evalExpr 2000 program before (.call reader (arguments.map Expr.value))
          | throw (IO.userError s!"file reader failed: length={length}, offset={offset}, capacity={capacity}")
        let remaining := bytes.drop offset
        let fits := remaining.length ≤ capacity
        let expectedResult : Int := if fits then remaining.length else -2
        let output := if fits then remaining.map (fun byte => (byte.toNat : Int)) ++ List.replicate (count - remaining.length) 91
          else List.replicate count 91
        let readCount := if fits && !remaining.isEmpty then 2 else 1
        unless result == expectedResult && after.cell? root == some (.array (signedI32Values output)) &&
            after.cell? 1 == before.cell? 1 && after.locals == before.locals && after.local? 77 == some (.signed .i32 1234) &&
            after.heap.remaining == before.heap.remaining &&
            after.world.calls == List.replicate readCount .read &&
            (after.world.handle? 7).map (·.offset) == some (offset + min remaining.length (capacity + 1)) &&
            (after.world.handle? 3).map (fun handle => (handle.id, handle.path, handle.offset, handle.readable)) ==
              (before.world.handle? 3).map (fun handle => (handle.id, handle.path, handle.offset, handle.readable)) &&
            (after.world.files.map fun file => (file.path, file.bytes)) == (before.world.files.map fun file => (file.path, file.bytes)) &&
            after.world.fileHandles.length == before.world.fileHandles.length do
          throw (IO.userError s!"file reader violated bytes, capacity, EOF, offset, or frame: length={length}, offset={offset}, capacity={capacity}")

#eval check fixture 8

/-- A five-byte read/close session with spare storage and a second live
buffer. The executable only accesses the bytes actually returned by read;
small physical buffers isolate the session's control flow and frame. The
universal theorem, not this fixture, covers production-size allocations. -/
def checkStage (program : Program) (reader closer : FunctionId) (sourceStage : Entry.File.Read.Stage) : IO Unit := do
  let bytes : List UInt8 := [255, 0, 128, 127, 42]
  let world : Lanius.World.State := {
    files := [⟨[65], bytes⟩]
    fileHandles := [{ id := 3, path := [66], offset := 7, readable := true },
      { id := 7, path := [65], readable := true }]
    nextFileHandle := 8 }
  let (initial, packed) ← Host.prepare world 4
  let .allocated address heap := initial.heap.allocate (8 * 4) 4
    | throw (IO.userError "read/close output allocation failed")
  let .done (.slice _ root _ _ _) mapped := mapRawI32Slice { initial with heap } address 8
    | throw (IO.userError "read/close output registration failed")
  let some initialized := mapped.assignCell root (.array (signedI32Values (List.replicate 8 91)))
    | throw (IO.userError "read/close output initialization failed")
  let before := initialized.bindLocals [
    (sourceStage.handle, .signed .i32 7), (sourceStage.output, .slice i32 root [] 0 8),
    (sourceStage.packed, .slice i32 packed.root [] 0 packed.length)]
  let stage := { sourceStage with continuation := returned (read sourceStage.count) }
  let .done (.returned (some (.signed .i32 count))) after := execStmt 2000 program before (stage.statement reader closer)
    | throw (IO.userError "read/close stage failed or exhausted fuel")
  unless count == bytes.length && after.world.calls == [.read, .read, .close] &&
      after.world.fileHandles.length == 1 && (after.world.handle? 7).isNone &&
      (after.world.handle? 3).map (·.offset) == some 7 && after.locals == before.locals &&
      after.cell? 1 == before.cell? 1 && after.heap.remaining == before.heap.remaining &&
      after.cell? root == some (.array (signedI32Values
        (bytes.map (fun byte => (byte.toNat : Int)) ++ List.replicate (8 - bytes.length) 91))) do
    throw (IO.userError "read/close stage lost bytes, caller storage, or original handles")

private def stage : Entry.File.Read.Stage := ⟨0, 1, 2, 3, 4, returned (number 99), .skip⟩

#eval checkStage fixture 8 10 stage

#eval show IO Unit from do
  unless (Entry.File.Read.check? 8 10 (stage.statement 8 10)).isSome && stage.checkSupported?.isSome do
    throw (IO.userError "exact read/close source stage rejected")
  if (Entry.File.Read.check? 7 10 (stage.statement 8 10)).isSome ||
      (Entry.File.Read.check? 8 11 (stage.statement 8 10)).isSome ||
      ({ stage with count := stage.handle } : Entry.File.Read.Stage).checkSupported?.isSome ||
      ({ stage with closed := stage.count } : Entry.File.Read.Stage).checkSupported?.isSome then
    throw (IO.userError "wrong callee or shadowed read/close binding accepted")

run_elab do
  for name in #[``Input.File.check?, ``Input.File.prepareRequest, ``Input.File.executesIteration,
      ``Input.File.readNext, ``Input.File.executesRead, ``Input.File.guards_eof,
      ``Input.File.guards_continue, ``Input.File.guards_overflow, ``Input.File.unpackChunk,
      ``Input.File.iterationStep, ``Input.File.completesLoop, ``Input.File.readOversized,
      ``Input.File.iterationOversized, ``Input.File.rejectsLoop, ``Input.File.runsLoop,
      ``Input.File.body_returns, ``Input.File.Checked.read,
      ``Entry.File.Read.check?, ``Entry.File.Read.closesFresh, ``Entry.File.Read.Stage.executes,
      ``Lanius.Extraction.Host.Effect.ofHost, ``Lanius.Extraction.Host.Effect.closePrefix] do
    for assumption in ← Lean.collectAxioms name do
      unless assumption == ``propext || assumption == ``Classical.choice || assumption == ``Quot.sound do
        throwError "File reader theorem {name} depends on unexpected axiom {assumption}"

end Lanius.Extraction.Tests.File
