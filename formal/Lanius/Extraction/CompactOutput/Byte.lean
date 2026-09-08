import Lanius.Extraction.CompactOutput.Source
import Lanius.FunctionalViewCoreSimulation
import Lanius.Separation.SliceStore

namespace Lanius.Extraction.CompactOutput

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core

theorem local_evaluates (program : Program) {id : VarId} (found : before.local? id = some value) :
    Evaluates program before (read id) value before :=
  ⟨1, evalLocal_of_local 0 program before id value found⟩

theorem negativeOne_evaluates (program : Program) (state : State) :
    Evaluates program state negativeOne (.signed .i32 (-1)) state := by
  apply evaluatesUnary (show Evaluates program state (number 1) (.signed .i32 1) state from ⟨1, rfl⟩)
  simp [evalUnaryValue, wrapSigned, signedModulus, signedSignBit, SignedIntTy.bits]

private theorem le_evaluates
    (left : Evaluates program before a (.signed .i32 x) before)
    (right : Evaluates program before b (.signed .i32 y) before) :
    Evaluates program before (binary .lessEqual a b) (.boolean (decide (x ≤ y))) before := by
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary]

private theorem ge_evaluates
    (left : Evaluates program before a (.signed .i32 x) before)
    (right : Evaluates program before b (.signed .i32 y) before) :
    Evaluates program before (binary .greaterEqual a b) (.boolean (decide (y ≤ x))) before := by
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary]

def byteBad (capacity position value : Int) : Bool :=
  decide (position ≤ -1) || decide (capacity ≤ position) || decide (value ≤ -1) || decide (256 ≤ value)

theorem byte_guard (program : Program)
    (capacityRead : before.local? 1 = some (.signed .i32 capacity))
    (positionRead : before.local? 2 = some (.signed .i32 position))
    (valueRead : before.local? 3 = some (.signed .i32 value)) :
    Evaluates program before byteGuard (.boolean (byteBad capacity position value)) before := by
  exact evaluatesPureLogicalOr (evaluatesPureLogicalOr (evaluatesPureLogicalOr
    (le_evaluates (local_evaluates program positionRead) (negativeOne_evaluates program before))
    (ge_evaluates (local_evaluates program positionRead) (local_evaluates program capacityRead)))
    (le_evaluates (local_evaluates program valueRead) (negativeOne_evaluates program before)))
    (ge_evaluates (local_evaluates program valueRead) ⟨1, rfl⟩)

/-- One byte changes one cell element. Logical capacity may be smaller than
the backing allocation; both sides of the written element are preserved. -/
theorem byte_body (program : Program) (position capacity value : Nat)
    (wellFormed : StateWellFormed before) (room : position < capacity)
    (capacityBound : capacity ≤ original.length) (capacityFit : capacity ≤ 2147483647)
    (byteBound : value < 256)
    (sliceRead : before.local? 0 = some (.slice i32 outputCell [] 0 original.length))
    (capacityRead : before.local? 1 = some (.signed .i32 capacity))
    (positionRead : before.local? 2 = some (.signed .i32 position))
    (valueRead : before.local? 3 = some (.signed .i32 value))
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) }) :
    ∃ after, Executes program before byteBody (.returned (some (.signed .i32 (position + 1 : Nat)))) after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values (original.set position value))) } ∧
      CellEffect (CellSet.singleton outputCell) before after := by
  have guard := byte_guard program capacityRead positionRead valueRead
  have passed : byteBad capacity position value = false := by
    have a : ¬ ((position : Int) ≤ -1) := by omega
    have b : ¬ ((capacity : Int) ≤ position) := by omega
    have c : ¬ ((value : Int) ≤ -1) := by omega
    have d : ¬ (256 ≤ (value : Int)) := by omega
    simp [byteBad, a, b, c, d]
  rw [passed] at guard
  obtain ⟨after, store, contents, effect⟩ := evaluatesSliceStore program before before original 0
    (read 2) (read 3) outputCell position value wellFormed (by omega) sliceRead
    (local_evaluates program positionRead) (local_evaluates program valueRead)
    (CellEffect.refl wellFormed) backing
  have positionAfter := effect.preserves_local_of_distinct_value wellFormed positionRead backing
    (by intro same; cases same)
  have next := evaluatesNatI32Add (leftValue := position) (rightValue := 1) (local_evaluates program positionAfter)
    (show Evaluates program after (number 1) (.signed .i32 1) after from ⟨1, rfl⟩) (by omega)
  exact ⟨after, executesSequence (executesIfFalse guard (executesSkip _ _))
    (executesSequence (executesExpression store) (executesSequenceReturned (executesReturnValue next))),
    contents, effect⟩

def byteValues (output : Value) (capacity position value : Int) : List Value :=
  [output, .signed .i32 capacity, .signed .i32 position, .signed .i32 value]

def byteBindings (output : Value) (capacity position value : Int) : List (VarId × Value) :=
  parameterBindings (fun index : Fin 4 => (byteValues output capacity position value).get index)

theorem CheckedByte.append (checked : CheckedByte program) (position capacity value : Nat)
    (wellFormed : StateWellFormed before) (room : position < capacity)
    (capacityBound : capacity ≤ original.length) (capacityFit : capacity ≤ 2147483647)
    (byteBound : value < 256)
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (byteValues (.slice i32 outputCell [] 0 original.length) capacity position value) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (position + 1 : Nat)) after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values (original.set position value))) } ∧
      CellEffect (CellSet.singleton outputCell) before after := by
  let bindings := byteBindings (.slice i32 outputCell [] 0 original.length) capacity position value
  have locals (index : Fin 4) : (enterCall before bindings).local? index.val = some
      ((byteValues (.slice i32 outputCell [] 0 original.length) capacity position value).get index) :=
    enterCall_parameterBindings_matches wellFormed index
  have calleeBacking := ((enterCall_effect before bindings).oldCells outputCell
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  obtain ⟨completed, run, contents, effect⟩ := byte_body program.core position capacity value
    (enterCall_preserves_wellFormed wellFormed) room capacityBound capacityFit byteBound
    (locals ⟨0, by decide⟩) (locals ⟨1, by decide⟩) (locals ⟨2, by decide⟩) (locals ⟨3, by decide⟩) calleeBacking
  have called := checked.call wellFormed argumentsResult (bindings := bindings) rfl run effect
  exact ⟨restoreLocals before completed, called.1, contents, called.2⟩

/-- Invalid positions (including the sticky -1 sentinel), capacity exhaustion,
and invalid byte values return -1 before any buffer access or write. -/
theorem CheckedByte.reject (checked : CheckedByte program) (output : Value) (capacity position value : Int)
    (wellFormed : StateWellFormed before) (bad : byteBad capacity position value = true)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments (byteValues output capacity position value) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments) (.signed .i32 (-1)) after ∧
      CellEffect CellSet.empty before after := by
  let bindings := byteBindings output capacity position value
  let callee := enterCall before bindings
  have locals (index : Fin 4) : callee.local? index.val = some ((byteValues output capacity position value).get index) :=
    enterCall_parameterBindings_matches wellFormed index
  have guard := byte_guard program.core (locals ⟨1, by decide⟩) (locals ⟨2, by decide⟩) (locals ⟨3, by decide⟩)
  rw [bad] at guard
  have run : Executes program.core callee byteBody (.returned (some (.signed .i32 (-1)))) callee :=
    executesSequenceReturned (executesIfTrue guard
      (executesSequenceReturned (executesReturnValue (negativeOne_evaluates program.core callee))))
  exact ⟨restoreLocals before callee, checked.call wellFormed argumentsResult (bindings := bindings) rfl run
    (CellEffect.refl (enterCall_preserves_wellFormed wellFormed))⟩

end Lanius.Extraction.CompactOutput
