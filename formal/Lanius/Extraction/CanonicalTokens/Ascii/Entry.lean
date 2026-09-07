import Lanius.Memory.Borrowed
import Lanius.Extraction.Input.Unpacking
import Lanius.Extraction.CanonicalTokens.Ascii.Source
import Lanius.Separation

namespace Lanius.Extraction.CanonicalTokens.Ascii

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Memory
open Lanius.Separation

/-- Exposing a word-padded string and borrowing its i32 view succeeds without
an allocator assumption. The resulting words encode exactly the string bytes;
all previous semantic cells and caller locals are preserved. -/
theorem string_words (before : State) (text : String) (count : Nat)
    (wellFormed : StateWellFormed before)
    (size : (Lanius.World.utf8Bytes text).length = count * 4) :
    ∃ words : List Int, ∃ address pointed after,
      words.length = count ∧
      mapStringDataPtr before text = .done (.pointer address) pointed ∧
      pointed.locals = before.locals ∧ pointed.cells = before.cells ∧
      mapRawI32Slice pointed address count =
        .done (.slice (.scalar (.signed .i32)) before.nextCell [] 0 count) after ∧
      encodeI32Array (signedI32Values words) = .ok (Lanius.World.utf8Bytes text) ∧
      after.cellEntry? before.nextCell = some {
        id := before.nextCell, value := some (.array (signedI32Values words)) } ∧
      StateWellFormed after ∧ after.locals = before.locals ∧
      (∀ cell, cell < before.nextCell → after.cellEntry? cell = before.cellEntry? cell) ∧
      after.nextCell = before.nextCell + 1 ∧ after.world = before.world ∧
      CellDomainExtension before after ∧ (∀ id, after.local? id = before.local? id) := by
  let bytes := Lanius.World.utf8Bytes text
  change bytes.length = count * 4 at size
  let address := alignUp (max before.heap.nextAddress 1) 4
  let heap : Heap := {
    before.heap with
    blocks := before.heap.blocks ++ [{
      base := address
      size := bytes.length
      alignment := 4
      bytes
      owned := false }]
    nextAddress := address + max bytes.length 1
  }
  have mapped : before.heap.mapBorrowed bytes 4 = .allocated address heap := rfl
  have heapWF : HeapWellFormed heap := by
    have result := mapBorrowed_preserves_heap_well_formed
      (bytes := bytes) (alignment := 4) wellFormed.heapWellFormed
    simpa only [mapped, AllocationResultWellFormed] using result
  have found := Heap.mapped_borrowed_block wellFormed.heapWellFormed mapped
  have protect := Heap.protect_borrowed_identity heapWF found rfl rfl
  have loaded := Heap.loadBytes_mapped_borrowed wellFormed.heapWellFormed mapped
  obtain ⟨words, length, decoded, encoded⟩ := Input.decode_whole_words count bytes size
  let pointed : State := { before with heap }
  have pointedWF : StateWellFormed pointed := {
    heapWellFormed := heapWF
    cellIdsUnique := wellFormed.cellIdsUnique
    cellIdsBelowNext := wellFormed.cellIdsBelowNext
    localsReferenceCells := wellFormed.localsReferenceCells
  }
  let allocated := (pointed.allocateTemporary (.array (signedI32Values words))).2
  let after : State := {
    allocated with i32ArrayViews := allocated.i32ArrayViews ++ [
      { address, root := before.nextCell, projections := [], length := count }]
  }
  refine ⟨words, address, pointed, after, length, rfl, rfl, rfl, ?_, encoded, ?_, ?_, rfl, ?_, rfl, rfl, ?_, ?_⟩
  · change mapRawI32Slice pointed address (Int.ofNat count) = _
    have nonnegative : ¬ (Int.ofNat count < 0) := Int.not_lt.mpr (Int.natCast_nonneg count)
    simp only [mapRawI32Slice, nonnegative, ↓reduceIte, Int.ofNat_eq_natCast, Int.toNat_natCast]
    have protection : heap.protectAsBorrowed address (count * 4) 4 = .ok heap := by
      simpa only [size] using protect
    have read : heap.loadBytes address (count * 4) = .ok bytes := by
      simpa only [size] using loaded
    change (match heap.protectAsBorrowed address (count * 4) 4 with
      | .error reason => Outcome.trapped reason pointed
      | .ok protectedHeap => _) = _
    rw [protection]
    simp only [Int.ofNat_eq_natCast, Int.toNat_natCast, read, decoded]
    rfl
  · exact allocateTemporary_finds_fresh_cell pointed (.array (signedI32Values words)) pointedWF
  · have allocatedWF := allocateTemporary_preserves_well_formed pointed
      (.array (signedI32Values words)) pointedWF
    exact ⟨allocatedWF.heapWellFormed, allocatedWF.cellIdsUnique,
      allocatedWF.cellIdsBelowNext, allocatedWF.localsReferenceCells⟩
  · intro cell old
    exact allocateTemporary_preserves_old_cell pointed (.array (signedI32Values words)) cell old
  · constructor
    intro entry member
    exact ⟨entry, by simp [after, allocated, pointed, State.allocateTemporary, member], rfl⟩
  · intro id
    have sameId : after.cellId? id = before.cellId? id := rfl
    simp only [State.local?, sameId]
    cases found : before.cellId? id with
    | none => rfl
    | some cell =>
        have old := StateWellFormed.cell_lt_next_of_local_binding id cell wellFormed found
        have unchanged := allocateTemporary_preserves_old_cell pointed
          (.array (signedI32Values words)) cell old
        simpa only [Option.bind_some, State.cell?, after, allocated, pointed,
          State.allocateTemporary, State.cellEntry?] using
            congrArg (fun entry : Option Cell => entry.bind Cell.value) unchanged

/-- The source's complete initializer executes, rather than merely accepting
a preconstructed packed buffer. The bound covers its `length + 3` arithmetic. -/
theorem evaluates_wordView (program : Program) (before : State) (text : String) (length : Nat)
    (wellFormed : StateWellFormed before)
    (textLocal : before.local? 2 = some (.string text))
    (lengthLocal : before.local? 3 = some (.signed .i32 length))
    (bounded : length + 3 ≤ 2147483647)
    (padded : (Lanius.World.utf8Bytes text).length = ((length + 3) / 4) * 4) :
    ∃ words : List Int, ∃ after,
      Evaluates program before wordView
        (.slice (.scalar (.signed .i32)) before.nextCell [] 0 words.length) after ∧
      encodeI32Array (signedI32Values words) = .ok (Lanius.World.utf8Bytes text) ∧
      after.cellEntry? before.nextCell = some {
        id := before.nextCell, value := some (.array (signedI32Values words)) } ∧
      StateWellFormed after ∧ after.locals = before.locals ∧
      (∀ cell, cell < before.nextCell → after.cellEntry? cell = before.cellEntry? cell) ∧
      after.nextCell = before.nextCell + 1 ∧ after.world = before.world ∧
      CellDomainExtension before after ∧ (∀ id, after.local? id = before.local? id) := by
  obtain ⟨words, address, pointed, after, count, pointer, locals, cells, raw, encoded,
      contents, afterWF, afterLocals, preserved, nextCell, world, domain, localValues⟩ :=
    string_words before text ((length + 3) / 4) wellFormed padded
  have textResult : Evaluates program before (.local 2) (.string text) before :=
    ⟨1, evalLocal_of_local 0 program before _ _ textLocal⟩
  have pointedLength : pointed.local? 3 = some (.signed .i32 length) := by
    have sameCells : pointed.cell? = before.cell? := by
      funext cell
      simp only [State.cell?, State.cellEntry?, cells]
    simpa only [State.local?, State.cellId?, locals, sameCells] using lengthLocal
  have lengthResult : Evaluates program pointed (.local 3) (.signed .i32 length) pointed :=
    ⟨1, evalLocal_of_local 0 program pointed _ _ pointedLength⟩
  have three : Evaluates program pointed (.value (.signed .i32 3)) (.signed .i32 3) pointed := ⟨1, rfl⟩
  have four : Evaluates program pointed (.value (.signed .i32 4)) (.signed .i32 4) pointed := ⟨1, rfl⟩
  have sum := evaluatesNatI32Add lengthResult three bounded
  have division := evaluatesNatI32Divide (leftValue := length + 3) (rightValue := 4)
    sum four (by decide) (by omega)
  refine ⟨words, after, ?_, encoded, contents, afterWF, afterLocals, preserved,
    nextCell, world, domain, localValues⟩
  rw [count]
  exact evaluatesI32SliceFromRawParts (evaluatesStringDataPtr textResult pointer) division raw

end Lanius.Extraction.CanonicalTokens.Ascii
