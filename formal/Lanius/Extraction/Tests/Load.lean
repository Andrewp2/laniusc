import Lanius.Extraction.Entry.File.Load
import Lanius.Extraction.Tests.Host
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Load

open Lanius.Core Lanius.Semantics Lanius.Extraction.CompactOutput

def buffer (before : State) (count : Nat) (word : Int) : IO (State × Value × CellId) := do
  let .allocated address heap := before.heap.allocate (count * 4) 4
    | throw (IO.userError "load-test buffer allocation failed")
  let .done value mapped := mapRawI32Slice { before with heap } address count
    | throw (IO.userError "load-test view registration failed")
  let some initialized := mapped.assignCell before.nextCell (.array (signedI32Values (List.replicate count word)))
    | throw (IO.userError "load-test buffer initialization failed")
  pure (initialized, value, before.nextCell)

/-- Exercise the composed path/open/read/close sequence, using recovered
source bindings. Only the continuation is replaced with a count return.
Small physical fixtures cover actual accesses; production capacities are
covered by the universal theorem, not by a costly interpreted allocation. -/
def check (program : Program) (lengthId argumentId openId readerId closeId : FunctionId)
    (pathStage : Entry.Path.Length.Stage) (argumentStage : Entry.Path.Read.Stage)
    (unpackStage : Input.Unpack.Stage) (openStage : Entry.File.Open.Stage) (readStage : Entry.File.Read.Stage) : IO Unit := do
  let readStage := { readStage with continuation := returned (read readStage.count) }
  let openStage := { openStage with continuation := readStage.statement readerId closeId }
  let unpackStage := { unpackStage with continuation := openStage.statement openId }
  let argumentStage := { argumentStage with continuation := unpackStage.statement }
  let pathStage := { pathStage with continuation := argumentStage.statement argumentId }
  for path in ["a", "é/λ.lani"] do
    for bytes in ([[], [0], [255, 0, 128, 127, 42]] : List (List UInt8)) do
      let pathBytes := Lanius.World.utf8Bytes path
      let world : Lanius.World.State := {
        arguments := ["extractor", path]
        files := [⟨pathBytes, bytes⟩]
        fileHandles := [{ id := 3, path := [66], offset := 7, readable := true }]
        nextFileHandle := 17 }
      let (initial, packedPath) ← Host.prepare world 4
      let (withPath, pathValue, pathRoot) ← buffer initial (pathBytes.length + 3) 93
      let (withSource, sourceValue, sourceRoot) ← buffer withPath (bytes.length + 3) 91
      let (allocated, scratchValue, _) ← buffer withSource 4 (-1)
      let before := allocated.bindLocals [
        (pathStage.argument, .signed .i32 1), (argumentStage.pointer, .pointer packedPath.address),
        (unpackStage.locals.packed, .slice i32 packedPath.root [] 0 packedPath.length),
        (unpackStage.locals.output, pathValue), (readStage.output, sourceValue), (readStage.packed, scratchValue)]
      let .done (.returned (some (.signed .i32 count))) after :=
          execStmt 2000 program before (pathStage.statement lengthId)
        | throw (IO.userError "composed file load trapped or exhausted fuel")
      let reads := if bytes.isEmpty then 1 else 2
      unless count == bytes.length &&
          after.world.calls == [.argLen, .argRead, .openRead] ++ List.replicate reads .read ++ [.close] &&
          after.world.nextFileHandle == 18 &&
          after.world.fileHandles.map (fun handle => (handle.id, handle.path, handle.offset, handle.readable)) ==
            before.world.fileHandles.map (fun handle => (handle.id, handle.path, handle.offset, handle.readable)) &&
          after.world.files.map (fun file => (file.path, file.bytes)) == before.world.files.map (fun file => (file.path, file.bytes)) &&
          after.world.arguments == before.world.arguments && after.locals == before.locals &&
          after.cell? 1 == before.cell? 1 && after.heap.remaining == before.heap.remaining &&
          after.cell? pathRoot == some (.array (signedI32Values (pathBytes.map (fun byte => (byte.toNat : Int)) ++ [93, 93, 93]))) &&
          after.cell? sourceRoot == some (.array (signedI32Values (bytes.map (fun byte => (byte.toNat : Int)) ++ [91, 91, 91]))) do
        throw (IO.userError s!"composed file load lost bytes, tails, handles, or caller state: path={path}, bytes={bytes.length}")

private def fixture : Program := {
  constants := [⟨6, i32, .signed .i32 16384⟩]
  functions := [
    ⟨8, Input.File.parameters, i32, some (Input.File.body 9 6), none⟩,
    ⟨9, [(0, i32), (1, .scalar .rawPtr), (2, .scalar (.unsigned .usize))], i32, none, some (.host .read)⟩,
    ⟨10, [(0, i32)], i32, none, some (.host .close)⟩,
    ⟨11, [(0, i32)], i32, none, some (.host .argLen)⟩,
    ⟨12, [(0, i32), (1, .scalar .rawPtr), (2, .scalar (.unsigned .usize))], i32, none, some (.host .argRead)⟩,
    ⟨13, [(0, .scalar .rawPtr), (1, .scalar (.unsigned .usize))], i32, none, some (.host .openRead)⟩] }

private def path : Entry.Path.Length.Stage := ⟨3, 4, .skip⟩
private def argument : Entry.Path.Read.Stage := ⟨3, 5, 4, .skip⟩
private def unpack : Input.Unpack.Stage := ⟨⟨6, 7, none, 8, 4⟩, .skip⟩
private def opened : Entry.File.Open.Stage := ⟨5, 4, 9, .skip⟩
private def reader : Entry.File.Read.Stage := ⟨9, 10, 11, 12, 13, returned (number 6), .skip⟩

#eval check fixture 11 12 13 8 10 path argument unpack opened reader

#eval show IO Unit from do
  unless (Entry.File.Load.checkRelation? path unpack opened reader).isSome do
    throw (IO.userError "valid path-to-reader bindings rejected")
  for changed in [{ reader with handle := 0 }, { reader with output := path.length },
      { reader with output := unpack.locals.cursor }, { reader with output := opened.handle },
      { reader with packed := path.length }, { reader with packed := unpack.locals.cursor },
      { reader with packed := opened.handle }, { reader with count := path.length }, { reader with closed := path.length }] do
    if (Entry.File.Load.checkRelation? path unpack opened changed).isSome then
      throw (IO.userError "disconnected handle or shadowed reader input accepted")

run_elab do
  for name in #[``Entry.File.Load.checkRelation?, ``Entry.File.Load.Pipeline.executes,
      ``Allocation.Registry.disjoint, ``Allocation.Registry.apart, ``Allocation.hostAllocation_exists] do
    for assumption in ← Lean.collectAxioms name do
      unless assumption == ``propext || assumption == ``Classical.choice || assumption == ``Quot.sound do
        throwError "File-load theorem {name} depends on unexpected axiom {assumption}"

/- A fresh backing cell does not make an already registered address fresh.
This counterexample guards the distinction enforced by the stronger registry. -/
#eval show IO Unit from do
  let (before, view) ← Host.prepare {} 2
  unless decide (before.i32ArrayViews.Pairwise fun left right => left.address ≠ right.address) do
    throw (IO.userError "separate test allocations unexpectedly alias")
  let .done _ after := mapRawI32Slice before view.address view.length
    | throw (IO.userError "repeated raw-view registration unexpectedly rejected")
  unless decide (after.i32ArrayViews.Pairwise fun left right => left.root ≠ right.root) &&
      !decide (after.i32ArrayViews.Pairwise fun left right => left.address ≠ right.address) do
    throw (IO.userError "address-alias counterexample no longer distinguishes roots from byte storage")

end Lanius.Extraction.Tests.Load
