import Lanius.Extraction.Entry.Framing
import Lanius.Extraction.Entry.Header
import Lanius.Extraction.Entry.Storage

namespace Lanius.Extraction.Entry.Framing

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.CompactOutput

structure HeaderRelation (stage : Stage) (header : Header.Stage) : Type where
  output : header.output = stage.output
  position : header.position = stage.position
  capacity : header.capacity = stage.capacity
  outputPosition : stage.output ≠ stage.position
  countOpening : header.count ≠ stage.opening
  countClosing : header.count ≠ stage.closing
  countPosition : header.count ≠ stage.position

def checkHeaderRelation? (stage : Stage) (header : Header.Stage) : Option (HeaderRelation stage header) :=
  if valid : header.output = stage.output ∧ header.position = stage.position ∧ header.capacity = stage.capacity ∧
      stage.output ≠ stage.position ∧ header.count ≠ stage.opening ∧ header.count ≠ stage.closing ∧
      header.count ≠ stage.position then
    some ⟨valid.1, valid.2.1, valid.2.2.1, valid.2.2.2.1, valid.2.2.2.2.1,
      valid.2.2.2.2.2.1, valid.2.2.2.2.2.2⟩
  else none

/-- Compose exact module framing with compact-header emission. The helper's
output and argc premises are recovered from framing's retained state, not
assumed again at the phase boundary. -/
theorem Stage.withHeader (stage : Stage) (text : Text.Checked program byte)
    (supported : Supported stage) (header : Header.Stage)
    (pack : PackHeader.Checked program byte digit word)
    (headerSource : stage.continuation = header.statement pack.source.function.id)
    (relation : HeaderRelation stage header)
    (before : State) (untouched : List Int) (count : Nat)
    (wellFormed : StateWellFormed before)
    (outputRead : before.local? stage.output = some (.slice i32 outputCell [] 0 untouched.length))
    (outputContents : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values untouched)) })
    (countRead : before.local? header.count = some (.signed .i32 (count + 1 : Nat)))
    (countFit : count + 1 ≤ 2147483647)
    (capacityBound : stage.capacity ≤ untouched.length)
    (headerRoom : bytes.length + 16 ≤ stage.capacity)
    (completion : Completion) (post : Lanius.World.State → Prop)
    (continuationRun : ∀ prefixState positionCell, StateWellFormed prefixState →
      CellEffect (CellSet.singleton outputCell) before (restoreLocals before prefixState) →
      (∀ id, id ≠ stage.opening → id ≠ stage.closing → id ≠ stage.position →
        prefixState.cellId? id = before.cellId? id) →
      (Allocation.Registry before → Allocation.Registry prefixState) →
      ∀ middle,
      (Assertion.localPointsTo header.position positionCell (some (.signed .i32 (bytes.length + 16 : Nat)))).holds middle →
      middle.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (Header.contents (Input.copiedBuffer [] untouched bytes) bytes.length count))) } →
      CellEffect (CellSet.union (CellSet.singleton outputCell) (CellSet.singleton positionCell)) prefixState middle →
      (Allocation.Registry prefixState → Allocation.Registry middle) →
      (∃ fresh, middle.i32ArrayViews = before.i32ArrayViews ++ fresh) →
      CellEffect (CellSet.singleton outputCell) before (restoreLocals before middle) →
      (∀ id, id ≠ stage.opening → id ≠ stage.closing → id ≠ stage.position →
        middle.cellId? id = before.cellId? id) →
      middle.local? header.count = some (.signed .i32 (count + 1 : Nat)) →
      middle.cellId? header.count ≠ middle.cellId? header.position →
      middle.local? stage.closing = some (.string stage.suffixText) →
      Prefix.Reaches program.core before (stage.statement text.source.function.id) middle header.continuation →
      ∃ after, Executes program.core middle header.continuation completion after ∧ post after.world) :
    ∃ after, Executes program.core before (stage.statement text.source.function.id) completion after ∧ post after.world := by
  apply stage.executes text supported before untouched wellFormed outputRead outputContents capacityBound completion post
  intro prefixState positionCell prefixWF owned contents effect bindings registered views freshPosition suffixRead framingReached
  have keep {id : VarId} {value : Value} (read : before.local? id = some value)
      (differentValue : value ≠ .array (signedI32Values untouched))
      (notOpening : id ≠ stage.opening) (notClosing : id ≠ stage.closing) (notPosition : id ≠ stage.position) :
      prefixState.local? id = some value :=
    Pointers.preservedLiveLocal effect wellFormed read
      (fun cell found => local_cell_ne_of_distinct_value read outputContents differentValue found)
      (bindings id notOpening notClosing notPosition)
  have countAfter := keep countRead (by intro same; cases same)
    relation.countOpening relation.countClosing relation.countPosition
  have outputAfter := keep outputRead (by intro same; cases same)
    (Ne.symm supported.prefixOutput) (Ne.symm supported.suffixOutput) relation.outputPosition
  have outputLength := Input.copiedBuffer_length [] untouched bytes
    (Nat.le_trans supported.room capacityBound)
  simp only [List.length_nil, Nat.zero_add] at outputLength
  have headerOutput : prefixState.local? header.output = some
      (.slice i32 outputCell [] 0 (Input.copiedBuffer [] untouched bytes).length) := by
    simpa only [relation.output, outputLength] using outputAfter
  have headerPosition : (Assertion.localPointsTo header.position positionCell
      (some (.signed .i32 bytes.length))).holds prefixState := relation.position ▸ owned
  obtain ⟨after, executed, satisfied⟩ := header.executes pack prefixState (Input.copiedBuffer [] untouched bytes)
    bytes.length count prefixWF countAfter countFit headerOutput headerPosition contents
    (relation.capacity.symm ▸ headerRoom) (by simpa only [relation.capacity, outputLength] using capacityBound)
    (relation.capacity.symm ▸ supported.capacityFit) completion post
    (fun middle owned headerContents headerEffect headerRegistry headerViews reached => by
      have fullEffect : CellEffect (CellSet.singleton outputCell) before (restoreLocals before middle) := by
        have first := effect.weaken (CellSet.subset_union_left (right := CellSet.singleton positionCell))
        have second : CellEffect (CellSet.union (CellSet.singleton outputCell) (CellSet.singleton positionCell))
            prefixState (restoreLocals prefixState middle) := by
          simpa only [restoreLocals, ← headerEffect.locals] using headerEffect
        apply (first.transScoped second wellFormed).narrow
        intro cell old written
        simp only [CellSet.union, CellSet.singleton] at written ⊢
        rcases written with equal | equal
        · exact equal
        · subst cell
          exact False.elim (Nat.not_lt_of_ge freshPosition old)
      have fullBindings (id : VarId) (notOpening : id ≠ stage.opening)
          (notClosing : id ≠ stage.closing) (notPosition : id ≠ stage.position) :
          middle.cellId? id = before.cellId? id := by
        simpa only [State.cellId?, headerEffect.locals] using bindings id notOpening notClosing notPosition
      have finalCount := Pointers.preservedLiveLocal fullEffect wellFormed countRead
        (fun cell found => local_cell_ne_of_distinct_value countRead outputContents
          (by intro same; cases same) found)
        (fullBindings _ relation.countOpening relation.countClosing relation.countPosition)
      have countApart : middle.cellId? header.count ≠ middle.cellId? header.position := by
        rw [fullBindings _ relation.countOpening relation.countClosing relation.countPosition, owned.1]
        intro equal
        have old := StateWellFormed.cell_lt_next_of_local_binding _ _ wellFormed equal
        exact Nat.not_lt_of_ge freshPosition old
      have suffixAfter := headerEffect.preserves_local prefixWF suffixRead (by
        intro cell found written
        rcases written with output | position
        · exact local_cell_ne_of_distinct_value suffixRead
            (show prefixState.cellEntry? outputCell = _ from contents) (by intro same; cases same) found output
        · exact local_cell_ne_of_distinct_value suffixRead headerPosition.2 (by intro same; cases same) found position)
      exact continuationRun prefixState positionCell prefixWF effect bindings
        registered middle owned headerContents headerEffect headerRegistry
        (by simpa only [headerViews] using views) fullEffect fullBindings finalCount countApart suffixAfter
        (framingReached.trans (by simpa only [headerSource] using reached)))
  exact ⟨after, headerSource.symm ▸ executed, satisfied⟩

end Lanius.Extraction.Entry.Framing
