import Lanius.World.FileRead
import Lanius.Extraction.Input.Unpacking
import Lanius.Extraction.Input.Loop
import Lanius.Extraction.Input.Request

open Lanius.Core Lanius.Semantics Lanius.World

private def fileBytes : List UInt8 := [255, 128, 127, 254, 42]
private def initial : Lanius.World.State := {
  arguments := ["extractor", "A"]
  files := [⟨[65], fileBytes⟩]
  fileHandles := [{ id := 3, path := [66], offset := 7, readable := true }]
  nextFileHandle := 4
}

private def readSessionPreservesInputs : Bool := Id.run do
  let (id, opened) := openFile initial [65] true false false
  let some (first, readFirst) := readFileBytes opened id 3 | return false
  let some (last, readLast) := readFileBytes readFirst id 10 | return false
  let some (eof, readEof) := readFileBytes readLast id 1 | return false
  let some closed := closeHandle readEof id | return false
  return first == [255, 128, 127] && last == [254, 42] && eof.isEmpty &&
    closed.arguments == initial.arguments &&
    (closed.file? [65]).map (·.bytes) == some fileBytes &&
    closed.fileHandles.length == 1 &&
    (closed.handle? 3).map (·.offset) == some 7 && (closed.handle? id).isNone

example : readSessionPreservesInputs = true := by native_decide

-- A zero-size request is not EOF: the next positive request still gets data.
private def zeroRequestIsNotEof : Bool := Id.run do
  let (id, opened) := openFile initial [65] true false false
  let some (empty, unchanged) := readFileBytes opened id 0 | return false
  let some (first, _) := readFileBytes unchanged id 1 | return false
  return empty.isEmpty && first == [255]

example : zeroRequestIsNotEof = true := by native_decide

-- A partial raw read overwrites only five of the scratch buffer's eight
-- bytes. Decoding both words must retain the three untouched trailing bytes.
private def partialReadBytes : List UInt8 := [255, 128, 127, 254, 42, 9, 9, 9]
private def partialWordRoundTrip : Bool :=
  match decodeI32Array 2 partialReadBytes with
  | .error _ => false
  | .ok words =>
      match encodeI32Array words with
      | .error _ => false
      | .ok bytes => bytes == partialReadBytes

example : partialWordRoundTrip = true := by native_decide

open Lanius.Extraction.Input

private def unpackLocals : UnpackLocals := ⟨3, 1, 5, 10, 9⟩

example : (checkUnpackLoop? unpackLocals.loop).isSome = true := by decide

private def wrongReadCursor : Stmt :=
  .whileLoop (.binary .notEqual (.local unpackLocals.cursor) (.local unpackLocals.length))
    (.sequence (.expression ({ unpackLocals with cursor := 99 }.assignment))
      (.sequence (.expression (.assign .add (.local unpackLocals.cursor)
        (.value (.signed .i32 1)))) .skip))

example : (checkUnpackLoop? wrongReadCursor).isSome = false := by decide

-- Exercise every byte value at every packed lane, preserving a previous
-- chunk and unused output capacity. The final packed word is only partial.
private def unpackExecutionPreservesSurroundings (count : Nat) : Bool := Id.run do
  let bytes := (List.range count).map (fun index => UInt8.ofNat (index / 4))
  let packed := Lanius.Extraction.OutputPacking.pack bytes
  let earlier : List Int := [17, 29]
  let untouched := List.replicate (count + 3) (93 : Int)
  let state : Lanius.Semantics.State := {
    locals := [(1, 3), (3, 4), (10, 2), (5, 5), (9, 6)]
    cells := [
      ⟨0, some (.array (signedI32Values (earlier ++ untouched)))⟩,
      ⟨1, some (.array packed)⟩,
      ⟨2, some (.signed .i32 0)⟩,
      ⟨3, some (.slice (.scalar (.signed .i32)) 0 [] 0 (earlier.length + untouched.length))⟩,
      ⟨4, some (.slice (.scalar (.signed .i32)) 1 [] 0 packed.length)⟩,
      ⟨5, some (.signed .i32 earlier.length)⟩,
      ⟨6, some (.signed .i32 count)⟩]
    nextCell := 7
  }
  match execStmt (count * 2 + 100) { target := .x86_64 } state unpackLocals.loop with
  | .done .next after =>
      return after.cell? 0 == some (.array (signedI32Values
        (earlier ++ bytes.map (fun byte => (byte.toNat : Int)) ++ List.replicate 3 93))) &&
        after.cell? 1 == some (.array packed) &&
        after.local? unpackLocals.cursor == some (.signed .i32 count)
  | _ => return false

example : ([0, 1, 2, 3, 4, 5, 1024, 1025].all unpackExecutionPreservesSurroundings) = true := by
  native_decide

-- The actual Core host-call path refreshes every registered view. Reading
-- scratch must preserve another view's signed extremes and the unread tail.
private def readProgram : Program := {
  target := .x86_64
  functions := [⟨0, [(0, .scalar (.signed .i32)), (1, .scalar .rawPtr),
    (2, .scalar (.unsigned .usize))], .scalar (.signed .i32), none, some (.host .read)⟩]
}

private def readScratch : Expr := .call 0 [
  .value (.signed .i32 7), .value (.pointer 4), .value (.unsigned .usize 8)]

private def readingPreservesRegisteredBuffer : Bool := Id.run do
  let keptValues : List Int := [-2147483648, 2147483647]
  let state : Lanius.Semantics.State := {
    world := {
      files := [⟨[65], fileBytes⟩]
      fileHandles := [{ id := 7, path := [65], readable := true }]
      nextFileHandle := 8
    }
    heap := {
      blocks := [
        { base := 4, size := 8, alignment := 4, bytes := List.replicate 8 9 },
        { base := 12, size := 8, alignment := 4, bytes := keptValues.flatMap i32Bytes }]
      nextAddress := 20
    }
  }
  let .done (.slice _ scratchRoot [] 0 2) scratch := mapRawI32Slice state 4 2 | return false
  let .done (.slice _ keptRoot [] 0 2) registered := mapRawI32Slice scratch 12 2 | return false
  let .done (.pointer 4) reused := mapI32SliceDataPtr registered scratchRoot [] 0 2 | return false
  let .done (.signed .i32 5) read := evalExpr 30 readProgram reused readScratch | return false
  let .done (.signed .i32 0) eof := evalExpr 30 readProgram read readScratch | return false
  let expectedScratch := [decodeI32 [255, 128, 127, 254], decodeI32 [42, 9, 9, 9]]
  return scratchRoot != keptRoot && reused.i32ArrayViews.length == 2 &&
    read.cell? keptRoot == some (.array (signedI32Values keptValues)) &&
    eof.cell? keptRoot == read.cell? keptRoot &&
    read.cell? scratchRoot == some (.array (signedI32Values expectedScratch)) &&
    eof.cell? scratchRoot == read.cell? scratchRoot &&
    (eof.world.handle? 7).map (·.offset) == some 5 &&
    eof.world.standardOutput.isEmpty && eof.world.calls == [.read, .read]

example : readingPreservesRegisteredBuffer = true := by native_decide

example : ([0, 1, 65534, 65535, 65536, 65537].map requestSize) =
    [1, 2, 65535, 65536, 65536, 65536] := by decide

example : (checkRequestAdjustment? (RequestLocals.adjust ⟨8, 7⟩)).isSome = true := by decide

example : (checkRequestAdjustment? (.ifThenElse
    (.binary .less (.local 8) (.local 7))
    (.sequence (.expression (.assign .set (.local 7)
      (.binary .add (.local 8) (.value (.signed .i32 0))))) .skip) .skip)).isSome = false := by decide
