import Lanius.Extraction.CompactOutput.PackHeader
import Lanius.Extraction.CompactOutput.Buffer
import Lanius.Separation.LocalCall
import Lanius.Extraction.Source.Statement
import Lanius.Extraction.Allocation.Transport
import Lanius.Semantics.Prefix

namespace Lanius.Extraction.Entry.Header

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Extraction.CompactOutput

structure Stage where
  count : VarId
  output : VarId
  position : VarId
  capacity : Nat
  continuation : Stmt

def Stage.call (stage : Stage) (function : FunctionId) : Expr :=
  .call function [binary .subtract (read stage.count) (number 1),
    read stage.output, number stage.capacity, read stage.position]

def Stage.statement (stage : Stage) (function : FunctionId) : Stmt :=
  .sequence (.expression (.assign .set (.local stage.position) (stage.call function)))
    (.sequence (.ifThenElse (binary .lessEqual (read stage.position) negativeOne)
      (returned (number 26)) .skip) stage.continuation)

def check? (function : FunctionId) (statement : Stmt) :
    Option (Source.CheckedStatement (fun (stage : Stage) => stage.statement function) statement) :=
  match shape : statement with
  | .sequence (.expression (.assign .set (.local position)
      (.call _ [.binary .subtract (.local count) _, .local output, .value (.signed .i32 capacity), _])))
      (.sequence _ continuation) => do
      let stage : Stage := ⟨count, output, position, capacity.toNat, continuation⟩
      let same ← Equality.statement? statement (stage.statement function)
      pure ⟨stage, shape.symm.trans same.equal⟩
  | _ => none

def contents (original : List Int) (position count : Nat) : List Int :=
  original.take position ++ (PackHeader.encoding count).map Int.ofNat ++ original.drop (position + 16)

theorem encoding_length (count : Nat) : (PackHeader.encoding count).length = 16 := by
  simp [PackHeader.encoding, hexDigits_length]

theorem contents_length (room : position + 16 ≤ original.length) :
    (contents original position count).length = original.length := by
  simp only [contents, List.length_append, List.length_take, List.length_map,
    encoding_length, List.length_drop]
  omega

/-- The initial compact header records version one and argc minus the
executable itself, updates the real output cursor, and passes its error guard. -/
theorem Stage.executes (stage : Stage) (header : PackHeader.Checked program byte digit word)
    (before : State) (original : List Int) (position count : Nat)
    (wellFormed : StateWellFormed before)
    (countRead : before.local? stage.count = some (.signed .i32 (count + 1 : Nat)))
    (countFit : count + 1 ≤ 2147483647)
    (outputRead : before.local? stage.output = some (.slice i32 outputCell [] 0 original.length))
    (positionOwned : (Assertion.localPointsTo stage.position positionCell (some (.signed .i32 position))).holds before)
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) })
    (room : position + 16 ≤ stage.capacity)
    (capacityBound : stage.capacity ≤ original.length) (capacityFit : stage.capacity ≤ 2147483647)
    (completion : Completion) (post : Lanius.World.State → Prop)
    (continuationRun : ∀ middle,
      (Assertion.localPointsTo stage.position positionCell (some (.signed .i32 (position + 16 : Nat)))).holds middle →
      middle.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values (contents original position count))) } →
      CellEffect (CellSet.union (CellSet.singleton outputCell) (CellSet.singleton positionCell)) before middle →
      (Allocation.Registry before → Allocation.Registry middle) →
      middle.i32ArrayViews = before.i32ArrayViews →
      Prefix.Reaches program.core before (stage.statement header.source.function.id) middle stage.continuation →
      ∃ after, Executes program.core middle stage.continuation completion after ∧ post after.world) :
    ∃ after, Executes program.core before (stage.statement header.source.function.id) completion after ∧ post after.world := by
  have outputPosition : outputCell ≠ positionCell := by
    intro same; rw [same, positionOwned.2] at backing; cases backing
  have countResult := evaluatesNatI32Subtract (leftValue := count + 1) (rightValue := 1)
    (local_evaluates program.core countRead)
    (show Evaluates program.core before (number 1) (.signed .i32 1) before from evaluatesValue)
    (by omega) (by omega)
  simp only [Nat.add_sub_cancel] at countResult
  obtain ⟨written, call, output, effect, heapFrame⟩ := header.write count stage.capacity position wellFormed
    (by omega) capacityBound capacityFit backing
    (.cons countResult (.cons (local_evaluates program.core outputRead)
      (.cons (show Evaluates program.core before (number stage.capacity) (.signed .i32 stage.capacity) before from evaluatesValue)
        (.cons (local_evaluates program.core (Assertion.localPointsTo_local _ _ _ _ positionOwned)) (.nil _ _)))))
  have appended := appendAll_success stage.capacity position (PackHeader.encoding count) original
    (by simpa only [encoding_length] using room) capacityBound
  simp only [encoding_length] at appended
  rw [appended] at call output
  simp only [AppendOutcome.position, AppendOutcome.contents] at call output
  have stillOwned := effect.preserves_localPointsTo wellFormed positionOwned
    (by simpa [CellSet.singleton, eq_comm] using outputPosition)
  obtain ⟨middle, assigned, owned, combined, assignmentEffect, assignmentHeap, _⟩ :=
    evaluatesOwnedLocalSet positionOwned call effect stillOwned
  have outputMiddle := assignmentEffect.preserves_entry effect.wellFormed output outputPosition
  have guard : Evaluates program.core middle (binary .lessEqual (read stage.position) negativeOne)
      (.boolean false) middle := by
    apply evaluatesEagerBinary (by decide) (by decide)
      (local_evaluates program.core (Assertion.localPointsTo_local _ _ _ _ owned))
      (negativeOne_evaluates program.core middle)
    simp [evalBinaryValue, evalSignedBinary]
    omega
  obtain ⟨after, continued, satisfied⟩ := continuationRun middle owned outputMiddle combined
    (fun initial => initial.updateArrayAndScalar combined (heapFrame.trans assignmentHeap) backing
      outputMiddle (contents_length (by omega)) positionOwned.2)
    (heapFrame.trans assignmentHeap).views
    (.sequence (executesExpression assigned) (.sequence (executesIfFalse guard (executesSkip _ _)) .here))
  exact ⟨after, executesSequence (executesExpression assigned)
    (executesSequence (executesIfFalse guard (executesSkip _ _)) continued), satisfied⟩

end Lanius.Extraction.Entry.Header
