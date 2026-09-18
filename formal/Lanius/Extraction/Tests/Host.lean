import Lanius.Extraction.Host.Arguments.Read
import Lanius.Extraction.Host.File.Read
import Lanius.Extraction.Host.File.Close
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Host

open Lanius.Core Lanius.Semantics

private def i32 : Ty := .scalar (.signed .i32)
private def parameters : List (VarId × Ty) := [(0, i32), (1, .scalar .rawPtr), (2, .scalar (.unsigned .usize))]
private def fixture : Program := { functions := [
  ⟨8, parameters, i32, none, some (.host .argRead)⟩,
  ⟨9, parameters, i32, none, some (.host .read)⟩,
  ⟨10, [(0, .scalar .rawPtr), (1, .scalar (.unsigned .usize))], i32, none, some (.host .openRead)⟩,
  ⟨11, [(0, i32)], i32, none, some (.host .close)⟩] }

/-- Two independent raw buffers, with nonzero trailing bytes and signed
boundary words. Copying into the first must leave the second unchanged. -/
def prepare (world : Lanius.World.State) (count : Nat) : IO (State × I32ArrayView) := do
  let initial : State := { world }
  let .allocated address heap := initial.heap.allocate (count * 4) 4
    | throw (IO.userError "host-test scratch allocation failed")
  let .done _ first := mapRawI32Slice { initial with heap } address count
    | throw (IO.userError "host-test scratch registration failed")
  let .allocated keptAddress heap := first.heap.allocate 8 4
    | throw (IO.userError "host-test kept allocation failed")
  let .done _ both := mapRawI32Slice { first with heap } keptAddress 2
    | throw (IO.userError "host-test kept registration failed")
  let some initialized := both.assignCell 0 (.array (signedI32Values (List.replicate count (-1))))
    | throw (IO.userError "host-test scratch cell missing")
  let some ready := initialized.assignCell 1 (.array (signedI32Values [-2147483648, 2147483647]))
    | throw (IO.userError "host-test kept cell missing")
  let view :: _ := ready.i32ArrayViews | throw (IO.userError "host-test registry empty")
  pure (ready, view)

def checkCopy (before after : State) (view : I32ArrayView) (bytes : List UInt8) : IO Unit := do
  let some (.array words) := after.cell? view.root | throw (IO.userError "copied array missing")
  let .ok raw := encodeI32Array words | throw (IO.userError "copied array has invalid element type")
  unless raw == bytes ++ List.replicate (view.length * 4 - bytes.length) 255 &&
      after.cell? 1 == before.cell? 1 && after.locals == before.locals &&
      after.world.arguments == before.world.arguments &&
      after.heap.remaining == before.heap.remaining &&
      (after.i32ArrayViews.map fun view => (view.address, view.root, view.projections, view.length)) ==
        (before.i32ArrayViews.map fun view => (view.address, view.root, view.projections, view.length)) do
    throw (IO.userError "host copy changed byte order, trailing storage, kept buffer, or frame")

def checkArguments (program : Program) (function : FunctionId) : IO Unit := do
  for argument in ["", "a", "é/λ.lani", "0123456789abcdefXYZ"] do
    for capacity in [0, 1, 2, 3, 4, 5, 7, 8, 15, 16] do
      let (before, view) ← prepare { arguments := ["extractor", argument] } 4
      let values := [.signed .i32 1, .pointer view.address, .unsigned .usize capacity]
      match evalExpr 100 program before (.call function (values.map Expr.value)) with
      | .done (.signed .i32 count) after =>
          let bytes := (Lanius.World.utf8Bytes argument).take capacity
          unless count == bytes.length && after.world.calls == [.argRead] do
            throw (IO.userError "argument read returned wrong byte count or host trace")
          checkCopy before after view bytes
      | _ => throw (IO.userError "argument read trapped or exhausted fuel")

def checkFile (program : Program) (function : FunctionId) : IO Unit := do
  let bytes : List UInt8 := [255, 0, 128, 127, 42, 254, 17, 99, 200, 3, 4]
  for offset in [0, 1, 4, 10, 11, 12] do
    for request in [0, 1, 3, 4, 5, 8, 16] do
      let world : Lanius.World.State := {
        arguments := ["extractor", "file"]
        files := [⟨[65], bytes⟩]
        fileHandles := [{ id := 7, path := [65], offset, readable := true }]
        nextFileHandle := 8 }
      let (before, view) ← prepare world 4
      let values := [.signed .i32 7, .pointer view.address, .unsigned .usize request]
      match evalExpr 100 program before (.call function (values.map Expr.value)) with
      | .done (.signed .i32 count) after =>
          let returnedBytes := (bytes.drop offset).take request
          unless count == returnedBytes.length && after.world.calls == [.read] &&
              (after.world.handle? 7).map (·.offset) == some (offset + returnedBytes.length) &&
              (after.world.file? [65]).map (·.bytes) == some bytes do
            throw (IO.userError "file read fabricated bytes, moved the handle incorrectly, or changed its file")
          checkCopy before after view returnedBytes
      | _ => throw (IO.userError "file read trapped or exhausted fuel")

#eval checkArguments fixture 8
#eval checkFile fixture 9

def checkSession (program : Program) (argumentRead openRead fileRead close : FunctionId) : IO Unit := do
  let path := "λ.lani"
  let pathBytes := Lanius.World.utf8Bytes path
  let bytes : List UInt8 := [255, 0, 128, 127, 42, 254, 17, 99, 200, 3, 4]
  let world : Lanius.World.State := {
    arguments := ["extractor", path]
    files := [⟨pathBytes, bytes⟩]
    fileHandles := [{ id := 3, path := [66], offset := 7, readable := true }]
    nextFileHandle := 4 }
  let (before, view) ← prepare world 4
  let call := fun state function values => evalExpr 100 program state (.call function (values.map Expr.value))
  let .done (.signed .i32 length) copied :=
      call before argumentRead [.signed .i32 1, .pointer view.address, .unsigned .usize pathBytes.length]
    | throw (IO.userError "session argument copy failed")
  unless length == pathBytes.length do throw (IO.userError "session copied wrong path length")
  checkCopy before copied view pathBytes
  let .done (.signed .i32 handle) opened := call copied openRead [.pointer view.address, .unsigned .usize pathBytes.length]
    | throw (IO.userError "session open failed")
  unless handle == 4 && (opened.world.handle? handle).map (·.path) == some pathBytes do
    throw (IO.userError "open did not use the exact copied UTF-8 path or fresh handle")
  let .done (.signed .i32 count) read := call opened fileRead [.signed .i32 handle, .pointer view.address, .unsigned .usize 16]
    | throw (IO.userError "session file read failed")
  unless count == bytes.length do throw (IO.userError "session returned wrong file length")
  checkCopy before read view bytes
  let .done (.signed .i32 eof) ended := call read fileRead [.signed .i32 handle, .pointer view.address, .unsigned .usize 1]
    | throw (IO.userError "session EOF read failed")
  unless eof == 0 && ended.cell? 0 == read.cell? 0 do
    throw (IO.userError "EOF read changed the buffer or fabricated bytes")
  let .done (.signed .i32 status) closed := call ended close [.signed .i32 handle]
    | throw (IO.userError "session close failed")
  unless status == 0 && closed.world.fileHandles.length == 1 &&
      (closed.world.handle? 3).map (·.offset) == some 7 && (closed.world.handle? handle).isNone &&
      closed.world.arguments == before.world.arguments && (closed.world.file? pathBytes).map (·.bytes) == some bytes &&
      closed.world.calls == [.argRead, .openRead, .read, .read, .close] &&
      closed.cell? 0 == read.cell? 0 && closed.cell? 1 == before.cell? 1 do
    throw (IO.userError "open/read/close session changed input, leaked a handle, or changed a buffer")

#eval checkSession fixture 8 10 9 11

run_elab do
  for name in #[``Lanius.Extraction.Host.copiedAfterRefresh, ``Lanius.Extraction.Host.copyPreservesView,
      ``Lanius.Extraction.Host.evaluatesCopy, ``Lanius.Extraction.Host.checkExternal?,
      ``Lanius.Extraction.Host.CheckedExternal.bindings, ``Lanius.Extraction.Host.Arguments.copyExact,
      ``Lanius.Extraction.Host.Arguments.evaluatesRead, ``Lanius.Extraction.Host.File.evaluatesRead,
      ``Lanius.Extraction.Input.decode_i32_array_values, ``Lanius.Extraction.Host.Copied.loadAfterSync,
      ``Lanius.Extraction.Host.File.evaluatesOpen, ``Lanius.Extraction.Host.File.evaluatesClose] do
    for assumption in ← Lean.collectAxioms name do
      unless assumption == ``propext || assumption == ``Classical.choice || assumption == ``Quot.sound do
        throwError "Host input theorem {name} depends on unexpected axiom {assumption}"

end Lanius.Extraction.Tests.Host
