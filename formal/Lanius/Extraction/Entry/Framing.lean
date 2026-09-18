import Lanius.Extraction.CompactOutput.Text.Call
import Lanius.Extraction.ExtractorContract
import Lanius.Extraction.Source.Statement
import Lanius.Semantics.Prefix

namespace Lanius.Extraction.Entry.Framing

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Extraction.CompactOutput

structure Stage where
  opening : VarId
  closing : VarId
  output : VarId
  position : VarId
  prefixText : String
  suffixText : String
  capacity : Nat
  continuation : Stmt

def bytes := Lanius.World.utf8Bytes ExtractorContract.modulePrefix

theorem bytes_length : bytes.length = 146 := by decide +kernel

def Stage.statement (stage : Stage) (textId : FunctionId) : Stmt :=
  .letLocal stage.opening (.scalar .string) (.value (.string stage.prefixText))
    (.letLocal stage.closing (.scalar .string) (.value (.string stage.suffixText))
      (.letLocal stage.position i32
        (.call textId [read stage.output, number stage.capacity, number 0,
          read stage.opening, number bytes.length])
        (.sequence (.ifThenElse (binary .notEqual (read stage.position) (number bytes.length))
          (returned (number 23)) .skip) stage.continuation)))

def check? (textId : FunctionId) (statement : Stmt) :
    Option (Source.CheckedStatement (fun (stage : Stage) => stage.statement textId) statement) :=
  match shape : statement with
  | .letLocal opening _ (.value (.string prefixText))
      (.letLocal closing _ (.value (.string suffixText))
        (.letLocal position _ (.call _ [.local output, .value (.signed .i32 capacity), _, _, _])
          (.sequence _ continuation))) => do
      let stage : Stage := ⟨opening, closing, output, position, prefixText, suffixText, capacity.toNat, continuation⟩
      let same ← Equality.statement? statement (stage.statement textId)
      pure ⟨stage, shape.symm.trans same.equal⟩
  | _ => none

structure Supported (stage : Stage) : Type where
  prefixOutput : stage.opening ≠ stage.output
  suffixOutput : stage.closing ≠ stage.output
  suffixPrefix : stage.closing ≠ stage.opening
  positionClosing : stage.position ≠ stage.closing
  padded : (Lanius.World.utf8Bytes stage.prefixText).length = ((bytes.length + 3) / 4) * 4
  emitted : (Lanius.World.utf8Bytes stage.prefixText).take bytes.length = bytes
  suffixPadded : (Lanius.World.utf8Bytes stage.suffixText).length =
    (((Lanius.World.utf8Bytes ExtractorContract.moduleSuffix).length + 3) / 4) * 4
  suffixEmitted : (Lanius.World.utf8Bytes stage.suffixText).take
    (Lanius.World.utf8Bytes ExtractorContract.moduleSuffix).length =
    Lanius.World.utf8Bytes ExtractorContract.moduleSuffix
  room : bytes.length ≤ stage.capacity
  capacityFit : stage.capacity ≤ 2147483647

def Stage.checkSupported? (stage : Stage) : Option (Supported stage) :=
  if valid : stage.opening ≠ stage.output ∧ stage.closing ≠ stage.output ∧ stage.closing ≠ stage.opening ∧
      stage.position ≠ stage.closing ∧
      (Lanius.World.utf8Bytes stage.prefixText).length = ((bytes.length + 3) / 4) * 4 ∧
      (Lanius.World.utf8Bytes stage.prefixText).take bytes.length = bytes ∧
      (Lanius.World.utf8Bytes stage.suffixText).length =
        (((Lanius.World.utf8Bytes ExtractorContract.moduleSuffix).length + 3) / 4) * 4 ∧
      (Lanius.World.utf8Bytes stage.suffixText).take
        (Lanius.World.utf8Bytes ExtractorContract.moduleSuffix).length =
        Lanius.World.utf8Bytes ExtractorContract.moduleSuffix ∧
      bytes.length ≤ stage.capacity ∧ stage.capacity ≤ 2147483647 then
    let ⟨prefixOutput, suffixOutput, suffixPrefix, positionClosing, padded, emitted,
      suffixPadded, suffixEmitted, room, capacityFit⟩ := valid
    some ⟨prefixOutput, suffixOutput, suffixPrefix, positionClosing, padded, emitted,
      suffixPadded, suffixEmitted, room, capacityFit⟩
  else none

/-- Execute the real framing literals, text call, and success guard. The
continuation begins with the exact opening in its allocated output buffer. -/
theorem Stage.executes (stage : Stage) (text : Text.Checked program byte)
    (supported : Supported stage) (before : State) (untouched : List Int)
    (wellFormed : StateWellFormed before)
    (outputRead : before.local? stage.output = some (.slice i32 outputCell [] 0 untouched.length))
    (outputContents : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values untouched)) })
    (capacityBound : stage.capacity ≤ untouched.length)
    (completion : Completion) (post : Lanius.World.State → Prop)
    (continuationRun : ∀ middle positionCell,
      StateWellFormed middle →
      (Assertion.localPointsTo stage.position positionCell (some (.signed .i32 bytes.length))).holds middle →
      middle.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values (Input.copiedBuffer [] untouched bytes))) } →
      CellEffect (CellSet.singleton outputCell) before (restoreLocals before middle) →
      (∀ id, id ≠ stage.opening → id ≠ stage.closing → id ≠ stage.position →
        middle.cellId? id = before.cellId? id) →
      (Allocation.Registry before → Allocation.Registry middle) →
      (∃ fresh, middle.i32ArrayViews = before.i32ArrayViews ++ fresh) →
      before.nextCell ≤ positionCell →
      middle.local? stage.closing = some (.string stage.suffixText) →
      Prefix.Reaches program.core before (stage.statement text.source.function.id) middle stage.continuation →
      ∃ after, Executes program.core middle stage.continuation completion after ∧ post after.world) :
    ∃ after, Executes program.core before (stage.statement text.source.function.id) completion after ∧
      post after.world := by
  let prefixState := before.bindLocal stage.opening (.string stage.prefixText)
  let ready := prefixState.bindLocal stage.closing (.string stage.suffixText)
  have prefixWF := bindLocal_preserves_well_formed before stage.opening (.string stage.prefixText) wellFormed
  have readyWF := bindLocal_preserves_well_formed prefixState stage.closing (.string stage.suffixText) prefixWF
  have outputReady := (bindLocal_preserves_other_local (value := .string stage.suffixText)
    prefixWF supported.suffixOutput).trans
    ((bindLocal_preserves_other_local (value := .string stage.prefixText)
      wellFormed supported.prefixOutput).trans outputRead)
  have prefixReady := (bindLocal_preserves_other_local (value := .string stage.suffixText)
    prefixWF supported.suffixPrefix).trans (bindLocal_finds_local before stage.opening (.string stage.prefixText) wellFormed)
  have prefixEffect := bindLocal_effect before stage.opening (.string stage.prefixText)
  have suffixEffect := bindLocal_effect prefixState stage.closing (.string stage.suffixText)
  have contentsReady := ((prefixEffect.trans suffixEffect).oldCells outputCell
    (StateWellFormed.cell_lt_next_of_entry wellFormed outputContents) (by simp [CellSet.union, CellSet.empty])).trans outputContents
  obtain ⟨written, call, contents, effect, registered, views⟩ := text.append ready ready stage.prefixText bytes [] untouched
    stage.capacity readyWF contentsReady
    (by simp)
    (by simpa only [List.length_nil, Nat.zero_add] using capacityBound) supported.capacityFit
    (by rw [bytes_length]; decide) supported.padded supported.emitted
    (.cons (local_evaluates program.core (id := stage.output)
      (by simpa only [List.length_nil, Nat.zero_add] using outputReady))
      (.cons (show Evaluates program.core ready (number stage.capacity) (.signed .i32 stage.capacity) ready from ⟨1, rfl⟩)
        (.cons (show Evaluates program.core ready (number 0) (.signed .i32 0) ready from ⟨1, rfl⟩)
          (.cons (local_evaluates program.core prefixReady)
            (.cons (show Evaluates program.core ready (number bytes.length) (.signed .i32 bytes.length) ready from ⟨1, rfl⟩)
              (.nil _ _))))))
  have fits : ([] : List Int).length + bytes.length ≤ stage.capacity := by
    simpa only [List.length_nil, Nat.zero_add] using supported.room
  rw [Text.finalPosition_of_fits fits] at call
  rw [Text.emitted_of_fits fits] at contents
  simp only [List.length_nil, Nat.zero_add] at call contents effect
  let middle := written.bindLocal stage.position (.signed .i32 bytes.length)
  have owned := bindLocal_owns_fresh written stage.position (.signed .i32 bytes.length) effect.wellFormed
  have contentsMiddle := ((bindLocal_effect written stage.position (.signed .i32 bytes.length)).oldCells outputCell
    (StateWellFormed.cell_lt_next_of_entry effect.wellFormed contents) (by simp [CellSet.empty])).trans contents
  have suffixReady : ready.local? stage.closing = some (.string stage.suffixText) :=
    bindLocal_finds_local prefixState stage.closing (.string stage.suffixText) prefixWF
  have suffixWritten := effect.preserves_local_of_distinct_value readyWF suffixReady contentsReady
    (by intro same; cases same)
  have suffixMiddle := (bindLocal_preserves_other_local (value := Value.signed .i32 bytes.length)
    effect.wellFormed supported.positionClosing).trans suffixWritten
  have restored : CellEffect (CellSet.singleton outputCell) before (restoreLocals before middle) := by
    have closedPosition := CellEffect.closeLocal written stage.position (.signed .i32 bytes.length)
      effect.wellFormed (CellEffect.refl (writes := CellSet.singleton outputCell)
        (bindLocal_preserves_well_formed written _ _ effect.wellFormed))
    have closedSuffix := CellEffect.closeLocal prefixState stage.closing (.string stage.suffixText) prefixWF
      (effect.trans closedPosition)
    have closedPrefix := CellEffect.closeLocal before stage.opening (.string stage.prefixText) wellFormed closedSuffix
    simpa only [restoreLocals] using closedPrefix
  have bindings (id : VarId) (notOpening : id ≠ stage.opening) (notClosing : id ≠ stage.closing)
      (notPosition : id ≠ stage.position) : middle.cellId? id = before.cellId? id := by
    simp [middle, State.cellId?, State.bindLocal, State.bindCell, Ne.symm notPosition]
    rw [effect.locals]
    simp [ready, prefixState, State.bindLocal, State.bindCell, Ne.symm notOpening, Ne.symm notClosing]
  have guard : Evaluates program.core middle (binary .notEqual (read stage.position) (number bytes.length))
      (.boolean false) middle := by
    apply evaluatesEagerBinary (by decide) (by decide)
      (local_evaluates program.core (Assertion.localPointsTo_local _ _ _ _ owned))
      (show Evaluates program.core middle (number bytes.length) (.signed .i32 bytes.length) middle from ⟨1, rfl⟩)
    simp [evalBinaryValue, scalarEqual]
  obtain ⟨after, continued, satisfied⟩ := continuationRun middle written.nextCell
    (bindLocal_preserves_well_formed written stage.position (.signed .i32 bytes.length) effect.wellFormed)
    owned contentsMiddle restored bindings
    (fun initial => (registered ((initial.bindLocal stage.opening (.string stage.prefixText)).bindLocal
      stage.closing (.string stage.suffixText))).bindLocal stage.position (.signed .i32 bytes.length))
    views
    (by have fresh := effect.nextCell
        change before.nextCell + 1 + 1 ≤ written.nextCell at fresh
        exact Nat.le_trans (Nat.le_trans (Nat.le_succ _) (Nat.le_succ _)) fresh)
    suffixMiddle
    (.letLocal (show Evaluates program.core before (.value (.string stage.prefixText)) (.string stage.prefixText) before from ⟨1, rfl⟩)
      (.letLocal (show Evaluates program.core prefixState (.value (.string stage.suffixText)) (.string stage.suffixText) prefixState from ⟨1, rfl⟩)
        (.letLocal call (.sequence (executesIfFalse guard (executesSkip _ _)) .here))))
  exact ⟨_, executesLetLocal (show Evaluates program.core before (.value (.string stage.prefixText)) (.string stage.prefixText) before from ⟨1, rfl⟩)
    (executesLetLocal (show Evaluates program.core prefixState (.value (.string stage.suffixText)) (.string stage.suffixText) prefixState from ⟨1, rfl⟩)
      (executesLetLocal call (executesSequence (executesIfFalse guard (executesSkip _ _)) continued))), satisfied⟩

end Lanius.Extraction.Entry.Framing
