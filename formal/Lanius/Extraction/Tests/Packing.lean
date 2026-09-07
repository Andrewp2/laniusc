import Lanius.Extraction.OutputPacking.Clear

open Lanius.Core Lanius.Semantics Lanius.Extraction.OutputPacking

private def locals : LoopLocals := ⟨8, 12, 36, 23⟩

example : (checkPackingLoop? locals.loop).isSome = true := by decide

-- Looking like a packing assignment is insufficient: a different cursor
-- update does not satisfy the loop proof's termination or indexing invariant.
private def wrongCursor : Stmt :=
  .whileLoop (.binary .notEqual (.local locals.cursor) (.local locals.length))
    (.sequence (.expression locals.assignment)
      (.sequence (.expression (.assign .add (.local 99)
        (.value (.signed .i32 1)))) .skip))

example : (checkPackingLoop? wrongCursor).isSome = false := by decide

private def extraEffect : Stmt :=
  .whileLoop (.binary .notEqual (.local locals.cursor) (.local locals.length))
    (.sequence locals.body (.expression (.call 99 [])))

example : (checkPackingLoop? extraEffect).isSome = false := by decide

-- An assignment reading a different cursor is also rejected, even if the
-- enclosing loop's condition and increment agree.
private def wrongReadCursor : Stmt :=
  .whileLoop (.binary .notEqual (.local locals.cursor) (.local locals.length))
    (.sequence (.expression ({ locals with cursor := 99 }.assignment))
      (.sequence (.expression (.assign .add (.local locals.cursor)
        (.value (.signed .i32 1)))) .skip))

example : (checkPackingLoop? wrongReadCursor).isSome = false := by decide

example : (findPackingLoop? (.letLocal 0 (.scalar (.signed .i32))
    (.value (.signed .i32 0)) (.sequence .skip locals.loop))).isSome = true := by decide

example : (findPackingLoop? (.sequence wrongCursor extraEffect)).isSome = false := by decide

example : (checkClearLoop? locals.clearLoop).isSome = true := by decide
example : (checkClearLoop? locals.loop).isSome = false := by decide
example : (checkPackingLoop? locals.clearLoop).isSome = false := by decide
example : (findClearLoop? (.sequence locals.loop locals.clearLoop)).isSome = true := by decide

private def preparation : Preparation := ⟨locals, 34, 35, .returnValue (some (.value (.signed .i32 0)))⟩

example : (checkPreparation? preparation.statement).isSome = true := by decide

private def reversedPhases : Stmt :=
  match preparation.statement with
  | .letLocal words wordsTy wordsValue
      (.letLocal clear clearTy clearValue
        (.sequence clearLoop (.letLocal cursor cursorTy cursorValue (.sequence packLoop rest)))) =>
      .letLocal words wordsTy wordsValue
        (.letLocal clear clearTy clearValue
          (.sequence packLoop (.letLocal cursor cursorTy cursorValue (.sequence clearLoop rest))))
  | _ => .skip

example : (checkPreparation? reversedPhases).isSome = false := by decide

private def wrongWordCount : Stmt :=
  match preparation.statement with
  | .letLocal words type _ rest => .letLocal words type (.value (.signed .i32 0)) rest
  | _ => .skip

example : (checkPreparation? wrongWordCount).isSome = false := by decide

-- Exercise the real loop on a partial word with its sign bit set, with
-- spare capacity in both buffers. Neither unused tail may be overwritten.
private def inputBytes : List UInt8 := [255, 128, 127, 254, 42]
private def inputValues : List Int := [255, 128, 127, 254, 42, 87, 99, 120]
private def packingState : State := {
  locals := [(8, 3), (12, 4), (36, 2), (23, 5)]
  cells := [
    ⟨0, some (.array (signedI32Values [0, 0, 12345]))⟩,
    ⟨1, some (.array (signedI32Values inputValues))⟩,
    ⟨2, some (.signed .i32 0)⟩,
    ⟨3, some (.slice (.scalar (.signed .i32)) 0 [] 0 3)⟩,
    ⟨4, some (.slice (.scalar (.signed .i32)) 1 [] 0 8)⟩,
    ⟨5, some (.signed .i32 5)⟩]
  nextCell := 6
}

private def packingExecutionPreservesTails : Bool :=
  match execStmt 100 { target := .x86_64 } packingState locals.loop with
  | .done .next after =>
      after.cell? 0 == some (.array (pack inputBytes ++ signedI32Values [12345])) &&
      after.cell? 1 == some (.array (signedI32Values inputValues)) &&
      after.local? locals.cursor == some (.signed .i32 5)
  | _ => false

example : packingExecutionPreservesTails = true := by native_decide
