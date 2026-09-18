import Lanius.X86.Buffer.Locals
import Lanius.X86.Buffer.Bytes
import Lanius.X86.Source.Encode
import Lanius.Separation.LocalStore

namespace Lanius.X86.Buffer

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.X86.Source

def cursorIndex (id : VarId) (offset : Nat) : Expr :=
  if offset = 0 then read id else .binary .add (read id) (number offset)

structure Cursor (state : State) (output temporary : CellId) (id : VarId)
    (position : Nat) (values : List Int) : Prop where
  wellFormed : StateWellFormed state
  sliceRead : state.local? 0 = some (.slice i32 output [] 0 values.length)
  position : (Assertion.localPointsTo id temporary (some (.signed .i32 position))).holds state
  backing : state.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) }

variable {id : VarId} {position : Nat}

theorem count_prefix (program : Program) (wellFormed : StateWellFormed before)
    (owned : (Assertion.localPointsTo id temporary (some (.signed .i32 position))).holds before)
    (inputs : Locals saved frontier before) (fresh : frontier ≤ temporary)
    (flag : Bool) (bounded : position + flag.toNat ≤ 2147483647)
    (guard : Evaluates program before condition (.boolean flag) before) :
    ∃ after, Executes program before (countPrefix id condition) .next after ∧
      (Assertion.localPointsTo id temporary (some (.signed .i32 (position + flag.toNat : Nat)))).holds after ∧
      Locals saved frontier after ∧ CellEffect (CellSet.singleton temporary) before after ∧ HeapFrame before after := by
  cases flag with
  | false => exact ⟨before, executesIfFalse guard (executesSkip _ _), owned, inputs,
      CellEffect.refl wellFormed, HeapFrame.refl before⟩
  | true =>
      change position + 1 ≤ 2147483647 at bounded
      have operation : evalAssignValue program.target .add (some (.signed .i32 position)) (.signed .i32 1) =
          .ok (.signed .i32 (position + 1 : Nat)) := by
        simp only [evalAssignValue, assignOpBinary?, evalBinaryValue, beq_self_eq_true, if_true, evalSignedBinary]
        rw [wrapSigned_i32_of_nonnegative program.target ((position : Int) + 1) (by omega) (by omega)]
        congr 2
      obtain ⟨after, run, afterOwned, effect, heapFrame⟩ := evaluatesOwnedLocalUpdate wellFormed owned
        (show Evaluates program before (number 1) (.signed .i32 1) before from ⟨1, rfl⟩) operation
      exact ⟨after, executesIfTrue guard (executesSequence (executesExpression run) (executesSkip _ _)), afterOwned,
        inputs.fresh wellFormed effect fresh, effect, heapFrame⟩

theorem Cursor.read (cursor : Cursor before output temporary id position values) :
    before.local? id = some (.signed .i32 position) :=
  Assertion.localPointsTo_local id temporary _ before cursor.position

theorem Cursor.distinct (cursor : Cursor before output temporary id position values) : temporary ≠ output :=
  local_cell_ne_of_distinct_value cursor.read cursor.backing (by intro same; cases same) cursor.position.1

theorem Cursor.index (program : Program) (cursor : Cursor before output temporary id position values)
    (offset : Nat) (bounded : position + offset ≤ 2147483647) :
    Evaluates program before (cursorIndex id offset) (.signed .i32 (position + offset : Nat)) before := by
  by_cases zero : offset = 0
  · simpa only [cursorIndex, zero, ↓reduceIte, Nat.add_zero] using local_evaluates program cursor.read
  · simpa only [cursorIndex, if_neg zero, Source.read, Source.number, Int.ofNat_eq_natCast] using evaluatesNatI32Add (leftValue := position) (rightValue := offset)
      (local_evaluates program cursor.read)
      (show Evaluates program before (number offset) (.signed .i32 offset) before from ⟨1, rfl⟩) bounded

theorem Cursor.store (program : Program) (cursor : Cursor before output temporary id position values)
    (inputs : Locals saved frontier before)
    (notArray : ∀ index : Fin saved.length, ∀ elements, saved.get index ≠ .array elements)
    (offset byte : Nat) (room : position + offset < values.length) (bounded : position + offset ≤ 2147483647)
    (right : Evaluates program before expression (.signed .i32 byte) before) :
    ∃ after, Evaluates program before (.assign .set (.index (.local 0) (cursorIndex id offset)) expression) .unit after ∧
      Cursor after output temporary id position (values.set (position + offset) byte) ∧
      Locals saved frontier after ∧ CellEffect (CellSet.singleton output) before after ∧ HeapFrame before after := by
  obtain ⟨after, run, contents, effect, heapFrame, _⟩ := evaluatesSliceStore program before before
    values 0 (cursorIndex id offset) expression output (position + offset) byte cursor.wellFormed room
    cursor.sliceRead (cursor.index program offset bounded) right (CellEffect.refl cursor.wellFormed) cursor.backing
  refine ⟨after, run, ⟨effect.wellFormed, ?_, ?_, contents⟩,
    inputs.store cursor.wellFormed effect cursor.backing (fun index => notArray index _), effect, heapFrame⟩
  · simpa only [List.length_set] using effect.preserves_local_of_distinct_value cursor.wellFormed
      cursor.sliceRead cursor.backing (by intro same; cases same)
  · exact effect.preserves_localPointsTo cursor.wellFormed cursor.position cursor.distinct

theorem Cursor.advance (program : Program) (cursor : Cursor before output temporary id position values)
    (inputs : Locals saved frontier before) (fresh : frontier ≤ temporary)
    (amount : Nat) (bounded : position + amount ≤ 2147483647) :
    ∃ after, Evaluates program before (.assign .add (.local id) (number amount)) .unit after ∧
      Cursor after output temporary id (position + amount) values ∧ Locals saved frontier after ∧
      CellEffect (CellSet.singleton temporary) before after ∧ HeapFrame before after := by
  have operation : evalAssignValue program.target .add (some (.signed .i32 position)) (.signed .i32 amount) =
      .ok (.signed .i32 (position + amount : Nat)) := by
    simp only [evalAssignValue, assignOpBinary?, evalBinaryValue, beq_self_eq_true, if_true, evalSignedBinary]
    rw [wrapSigned_i32_of_nonnegative program.target ((position : Int) + amount) (by omega) (by omega)]
    congr 2
  obtain ⟨after, run, owned, effect, heapFrame⟩ := evaluatesOwnedLocalUpdate cursor.wellFormed cursor.position
    (show Evaluates program before (number amount) (.signed .i32 amount) before from ⟨1, rfl⟩) operation
  exact ⟨after, run, ⟨effect.wellFormed,
    effect.preserves_local_of_distinct_value cursor.wellFormed cursor.sliceRead cursor.position.2
      (by intro same; cases same), owned,
    effect.preserves_entry cursor.wellFormed cursor.backing (Ne.symm cursor.distinct)⟩,
    inputs.fresh cursor.wellFormed effect fresh, effect, heapFrame⟩

theorem Cursor.increment (program : Program) (cursor : Cursor before output temporary id position values)
    (inputs : Locals saved frontier before) (fresh : frontier ≤ temporary)
    (bounded : position + 1 ≤ 2147483647) :
    ∃ after, Evaluates program before (Source.increment id) .unit after ∧
      Cursor after output temporary id (position + 1) values ∧ Locals saved frontier after ∧
      CellEffect (CellSet.singleton temporary) before after ∧ HeapFrame before after :=
  cursor.advance program inputs fresh 1 bounded

/-- Execute an optional prefix store followed by the actual cursor increment.
The two writes have distinct cells, even when cursor/input values coincide. -/
theorem Cursor.append (program : Program) (cursor : Cursor before output temporary id position values)
    (inputs : Locals saved frontier before) (fresh : frontier ≤ temporary)
    (notArray : ∀ index : Fin saved.length, ∀ elements, saved.get index ≠ .array elements)
    (flag : Bool) (byte : Nat) (room : position + flag.toNat ≤ values.length)
    (bounded : position + flag.toNat ≤ 2147483647)
    (guard : Evaluates program before condition (.boolean flag) before)
    (right : Evaluates program before expression (.signed .i32 byte) before) :
    ∃ after, Executes program before (appendPrefix id condition expression) .next after ∧
      Cursor after output temporary id (position + flag.toNat)
        (writtenBytes values position (if flag then [byte] else [])) ∧
      Locals saved frontier after ∧
      CellEffect (CellSet.union (CellSet.singleton output) (CellSet.singleton temporary)) before after ∧
      HeapFrame before after := by
  cases flag with
  | false =>
      exact ⟨before, executesIfFalse guard (executesSkip _ _), cursor, inputs,
        CellEffect.refl cursor.wellFormed, HeapFrame.refl before⟩
  | true =>
      obtain ⟨stored, store, cursorStored, savedStored, storeEffect, storeHeap⟩ :=
        cursor.store program inputs notArray 0 byte (by change position + 1 ≤ values.length at room; omega)
          (by simpa using Nat.le_trans (Nat.le_succ position) bounded) right
      obtain ⟨after, increment, cursorAfter, savedAfter, incrementEffect, incrementHeap⟩ :=
        cursorStored.increment program savedStored fresh bounded
      exact ⟨after, executesIfTrue guard (executesSequence (executesExpression store)
        (executesSequence (executesExpression increment) (executesSkip _ _))), cursorAfter, savedAfter,
        (storeEffect.weaken CellSet.subset_union_left).trans (incrementEffect.weaken CellSet.subset_union_right),
        storeHeap.trans incrementHeap⟩

end Lanius.X86.Buffer
