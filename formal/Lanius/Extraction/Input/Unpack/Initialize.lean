import Lanius.Extraction.Input.Loop
import Lanius.Extraction.Host.Copy
import Lanius.Separation.SliceStore
import Lanius.Semantics.Prefix

namespace Lanius.Extraction.Input.Unpack

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.Input

structure Stage where
  locals : UnpackLocals
  continuation : Stmt

def Stage.statement (stage : Stage) : Stmt :=
  .letLocal stage.locals.cursor (.scalar (.signed .i32)) (.value (.signed .i32 0))
    (.sequence stage.locals.loop stage.continuation)

structure Stage.Supported (stage : Stage) : Prop where
  output : stage.locals.cursor ≠ stage.locals.output
  packed : stage.locals.cursor ≠ stage.locals.packed
  length : stage.locals.cursor ≠ stage.locals.length
  offset : stage.locals.total ≠ some stage.locals.cursor

def Stage.checkSupported? (stage : Stage) : Option (PLift stage.Supported) :=
  if valid : stage.locals.cursor ≠ stage.locals.output ∧ stage.locals.cursor ≠ stage.locals.packed ∧
      stage.locals.cursor ≠ stage.locals.length ∧ stage.locals.total ≠ some stage.locals.cursor then
    some ⟨⟨valid.1, valid.2.1, valid.2.2.1, valid.2.2.2⟩⟩ else none

def check? (statement : Stmt) : Option (Source.CheckedStatement Stage.statement statement) := do
  let .letLocal _ _ _ (.sequence loop continuation) := statement | none
  let checked ← checkUnpackLoop? loop
  let stage : Stage := ⟨checked.locals, continuation⟩
  let same ← Equality.statement? statement stage.statement
  pure ⟨stage, same.equal⟩

/-- Initialize the real byte cursor and unpack the host-returned bytes.
Scratch contents come from `Copied`, destination storage comes from the
registry, and all inner-loop ownership is constructed here. The continuation
retains the registry, exact copied bytes, and the unchanged packed input. -/
theorem Stage.executes (stage : Stage) (supported : stage.Supported)
    (program : Program) (before : State) (initial : Allocation.Registry before)
    (representable : Host.RepresentableViews before)
    (packed output : I32ArrayView) (bytes : List UInt8)
    (start : Nat) (offsetLocal : stage.locals.Offset before start)
    (copied : Host.Copied packed bytes before)
    (packedMember : packed ∈ before.i32ArrayViews) (outputMember : output ∈ before.i32ArrayViews)
    (distinct : packed.root ≠ output.root)
    (packedLocal : before.local? stage.locals.packed = some
      (.slice (.scalar (.signed .i32)) packed.root [] 0 packed.length))
    (outputLocal : before.local? stage.locals.output = some
      (.slice (.scalar (.signed .i32)) output.root [] 0 output.length))
    (lengthLocal : before.local? stage.locals.length = some (.signed .i32 bytes.length))
    (capacity : start + bytes.length ≤ output.length) (bounded : output.length ≤ 2147483647)
    (post : Completion → State → Prop)
    (continuationRun : ∀ (original : List Int) middle,
      original.length = output.length →
      before.cellEntry? output.root = some { id := output.root, value := some (.array (signedI32Values original)) } →
      Allocation.Registry middle → Host.RepresentableViews middle → Host.Copied packed bytes middle →
      middle.cellEntry? output.root = some {
        id := output.root
        value := some (.array (signedI32Values (original.take start ++ bytes.map (fun byte => (byte.toNat : Int)) ++
          original.drop (start + bytes.length)))) } →
      ModifiesOnly (CellSet.union (CellSet.singleton output.root) (CellSet.singleton before.nextCell))
        (before.bindLocal stage.locals.cursor (.signed .i32 0)) middle →
      (∀ id, id ≠ stage.locals.cursor → ∀ value, (∀ elements, value ≠ .array elements) →
        before.local? id = some value → middle.local? id = some value) →
      Prefix.Reaches program before stage.statement middle stage.continuation →
      ∃ completion after, Executes program middle stage.continuation completion after ∧ post completion (restoreLocals before after)) :
    ∃ completion after, Executes program before stage.statement completion after ∧ post completion after := by
  obtain ⟨original, originalLength, originalContents⟩ := initial.storage outputMember
  obtain ⟨words, raw, packedContents, wordLength, encoded, selected, range⟩ := copied.storage
  let ready := before.bindLocal stage.locals.cursor (.signed .i32 0)
  have registered := initial.bindLocal stage.locals.cursor (.signed .i32 0)
  have packedOld := initial.root_lt_next packedMember
  have outputOld := initial.root_lt_next outputMember
  have startBound : start ≤ original.length := by omega
  have earlierLength : (original.take start).length = start := by simp only [List.length_take, Nat.min_eq_left startBound]
  have totalLength : (original.take start).length + (original.drop start).length = original.length := by
    simp only [List.length_take, List.length_drop]; omega
  let memory : UnpackMemory := {
    outputCell := output.root, packedCell := packed.root, cursorCell := before.nextCell,
    earlier := original.take start, untouched := original.drop start, packedValues := words, storage := raw, bytes,
    encoded, sourceBytes := selected, capacity := by simp only [List.length_drop]; omega,
    bounded := by simpa only [totalLength, originalLength] using bounded,
    output_cursor := Nat.ne_of_lt outputOld, packed_output := distinct,
    packed_cursor := Nat.ne_of_lt packedOld }
  have keep {id : VarId} {value : Value} (different : stage.locals.cursor ≠ id)
      (found : before.local? id = some value) : ready.local? id = some value :=
    (bindLocal_preserves_other_local initial.wellFormed different).trans found
  have readyPacked := keep supported.packed packedLocal
  have readyOutput := keep supported.output outputLocal
  have readyLength := keep supported.length lengthLocal
  have offsetAtEntry : stage.locals.Offset ready start := by
    cases selected : stage.locals.total with
    | none => simpa only [UnpackLocals.Offset, selected] using offsetLocal
    | some id =>
        simp only [UnpackLocals.Offset, selected] at offsetLocal ⊢
        exact keep (by intro same; exact supported.offset (selected.trans (congrArg some same.symm))) offsetLocal
  have keepCell {cell : CellId} (old : cell < before.nextCell) : ready.cellEntry? cell = before.cellEntry? cell :=
    (bindLocal_effect before stage.locals.cursor (.signed .i32 0)).oldCells cell old (by simp [CellSet.empty])
  have keptPacked := (keepCell packedOld).trans packedContents
  have keptOutput := (keepCell outputOld).trans originalContents
  have cursor : (Assertion.localPointsTo stage.locals.cursor before.nextCell (some (.signed .i32 0))).holds ready := by
    constructor
    · simp [ready, State.cellId?, State.bindLocal, State.bindCell]
    · exact bindCell_finds_fresh_cell before stage.locals.cursor (some (.signed .i32 0)) initial.wellFormed
  have invariant : UnpackInvariant memory stage.locals [] ready := by
    refine ⟨registered.wellFormed, ?_, ?_, ?_, keptPacked, cursor, ?_, readyLength, ?_⟩
    · simpa only [memory, totalLength, originalLength] using readyOutput
    · simpa only [memory, copiedBuffer, List.map_nil, List.append_nil, List.length_nil, List.drop_zero,
        List.take_append_drop] using keptOutput
    · simpa only [memory, wordLength] using readyPacked
    · simpa only [memory, earlierLength] using offsetAtEntry
    · intro id member cell found changed
      have names : id = stage.locals.output ∨ id = stage.locals.packed ∨ id = stage.locals.length ∨ stage.locals.total = some id := by
        simpa only [UnpackLocals.stableLocals, List.mem_append, List.mem_cons, List.not_mem_nil, or_false,
          Option.mem_toList, or_assoc] using member
      have stableRead : ∃ value, (∀ elements, value ≠ .array elements) ∧ ready.local? id = some value := by
        rcases names with rfl | rfl | rfl | total
        · refine ⟨_, ?_, readyOutput⟩
          intro elements same; cases same
        · refine ⟨_, ?_, readyPacked⟩
          intro elements same; cases same
        · refine ⟨_, ?_, readyLength⟩
          intro elements same; cases same
        · refine ⟨.signed .i32 start, ?_, ?_⟩
          · intro elements same; cases same
          · simpa only [UnpackLocals.Offset, total] using offsetAtEntry
      have different : stage.locals.cursor ≠ id := by
        rcases names with rfl | rfl | rfl | total
        · exact supported.output
        · exact supported.packed
        · exact supported.length
        · intro same
          exact supported.offset (total.trans (congrArg some same.symm))
      have notCursor : cell ≠ before.nextCell := by
        have originalBinding : before.cellId? id = some cell := by
          simpa only [ready, State.cellId?, State.bindLocal, State.bindCell, State.allocateTemporary,
            List.find?_cons, show (stage.locals.cursor == id) = false from beq_eq_false_iff_ne.mpr different,
            Bool.false_eq_true, ↓reduceIte] using found
        exact Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_local_binding id cell initial.wellFormed originalBinding)
      have notOutput : cell ≠ output.root := by
        obtain ⟨value, notArray, read⟩ := stableRead
        exact local_cell_ne_of_distinct_value read keptOutput (notArray _) found
      exact changed.elim notOutput notCursor
  obtain ⟨middle, loop, complete, effect⟩ :=
    executes_unpacking_loop program memory stage.locals [] bytes ready (by simp [memory]) invariant
  have lengthSame : (copiedBuffer (original.take start) (original.drop start) bytes).length = original.length := by
    simpa only [totalLength] using copiedBuffer_length (original.take start) (original.drop start) bytes memory.capacity
  have middleRegistry := registered.updateArrayAndScalar (CellEffect.ofModifiesOnly effect complete.wellFormed)
    (HeapFrame.ofStoreEffect effect.toStoreEffect) keptOutput complete.outputContents lengthSame cursor.2
  have packedCopied : Host.Copied packed bytes middle :=
    ⟨words, raw, complete.packedContents, wordLength, encoded, selected, range⟩
  have originalRange := representable output outputMember original originalContents
  have updatedRange : ∀ value ∈ copiedBuffer (original.take start) (original.drop start) bytes,
      -2147483648 ≤ value ∧ value ≤ 2147483647 := by
    intro value member
    simp only [copiedBuffer, List.mem_append] at member
    rcases member with (earlier | fresh) | kept
    · exact originalRange value (List.mem_of_mem_take earlier)
    · obtain ⟨byte, _, rfl⟩ := List.mem_map.mp fresh
      have bound := byte.toNat_lt
      omega
    · exact originalRange value (List.mem_of_mem_drop (List.mem_of_mem_drop kept))
  have middleRepresentable := (representable.bindLocal initial stage.locals.cursor (.signed .i32 0)).transport
    registered (CellEffect.ofModifiesOnly effect complete.wellFormed) (HeapFrame.ofStoreEffect effect.toStoreEffect) (by
      intro view member written values contents
      rcases written with atOutput | atCursor
      · change view.root = output.root at atOutput
        have same : signedI32Values (copiedBuffer (original.take start) (original.drop start) bytes) = signedI32Values values := by
          have equal := complete.outputContents.symm.trans (atOutput ▸ contents)
          injection equal with equal
          injection equal with _ arrays
          injection arrays with arrays
          exact Value.array.inj arrays
        exact signedI32Values_injective same ▸ updatedRange
      · change view.root = before.nextCell at atCursor
        exact False.elim (registered.notScalar member (atCursor.symm ▸ cursor.2)))
  obtain ⟨completion, after, continued, satisfied⟩ := continuationRun original middle originalLength originalContents
    middleRegistry middleRepresentable packedCopied (by simpa only [memory, copiedBuffer, List.drop_drop] using complete.outputContents) effect (by
      intro id different value notArray found
      have readyLocal := keep (Ne.symm different) found
      apply effect.preserves_local registered.wellFormed readyLocal
      intro cell binding changed
      have notOutput := local_cell_ne_of_distinct_value readyLocal keptOutput (notArray _) binding
      have originalBinding : before.cellId? id = some cell := by
        simpa [ready, State.cellId?, State.bindLocal, State.bindCell, Ne.symm different] using binding
      have notCursor := Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_local_binding id cell
        initial.wellFormed originalBinding)
      exact changed.elim notOutput notCursor)
    (.letLocal ⟨1, rfl⟩ (.sequence loop .here))
  exact ⟨completion, restoreLocals before after, executesLetLocal (⟨1, rfl⟩ :
    Evaluates program before (.value (.signed .i32 0)) (.signed .i32 0) before)
    (executesSequence loop continued), satisfied⟩

end Lanius.Extraction.Input.Unpack
