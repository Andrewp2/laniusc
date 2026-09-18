import Lanius.X86.Buffer.Word
import Lanius.X86.Source.Patch
import Lanius.X86.Relative.Core

namespace Lanius.X86.Buffer

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source

def patchBad (length field target : Int) : Bool :=
  !reserved length field 4 || decide (target < 0) || decide (length < target)

private theorem or_after
    (left : Evaluates program before a (.boolean x) middle)
    (right : Evaluates program middle b (.boolean y) middle) :
    Evaluates program before (.binary .logicalOr a b) (.boolean (x || y)) middle := by
  cases x <;> simp only [Bool.false_or, Bool.true_or]
  · exact evaluatesLogicalOrFalse left right
  · exact evaluatesLogicalOrTrue left

private theorem negative_one (program : Program) (state : State) :
    Evaluates program state negativeOne (.signed .i32 (-1)) state := by
  apply evaluatesUnary (show Evaluates program state (number 1) (.signed .i32 1) state from ⟨1, rfl⟩)
  simp [evalUnaryValue, wrapSigned, signedModulus, signedSignBit, SignedIntTy.bits]

theorem patch_guard (fits : CheckedFits program) (length field target : Int)
    (wellFormed : StateWellFormed before) (lengthBound : length ≤ 2147483647)
    (lengthRead : before.local? 1 = some (.signed .i32 length))
    (fieldRead : before.local? 2 = some (.signed .i32 field))
    (targetRead : before.local? 3 = some (.signed .i32 target)) :
    ∃ after, Evaluates program.core before (patchGuard fits.source.function.id)
        (.boolean (patchBad length field target)) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  have arguments : ArgumentsEvaluateTo program.core before [read 1, read 2, number 4]
      (fitsValues length field 4) before :=
    .cons (local_evaluates program.core lengthRead) (.cons (local_evaluates program.core fieldRead)
      (.cons ⟨1, rfl⟩ (.nil _ _)))
  obtain ⟨after, fit, effect, heapFrame⟩ := fits_call fits length field 4 wellFormed lengthBound arguments
  have negated : Evaluates program.core before
      (.unary .logicalNot (.call fits.source.function.id [read 1, read 2, number 4]))
      (.boolean (!reserved length field 4)) after := by
    apply evaluatesUnary fit
    rfl
  have targetAfter := effect.empty_preserves_local wellFormed targetRead
  have lengthAfter := effect.empty_preserves_local wellFormed lengthRead
  have negative : Evaluates program.core after (.binary .less (read 3) (number 0))
      (.boolean (decide (target < 0))) after := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program.core targetAfter)
      (show Evaluates program.core after (number 0) (.signed .i32 0) after from ⟨1, rfl⟩)
    simp [evalBinaryValue, evalSignedBinary]
  have beyond : Evaluates program.core after (.binary .greater (read 3) (read 1))
      (.boolean (decide (length < target))) after := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program.core targetAfter)
      (local_evaluates program.core lengthAfter)
    simp [evalBinaryValue, evalSignedBinary]
  exact ⟨after, or_after (or_after negated negative) beyond, effect, heapFrame⟩

def patchValues (output : Value) (length field target : Int) : List Value :=
  [output, .signed .i32 length, .signed .i32 field, .signed .i32 target]

def patchBindings (output : Value) (length field target : Int) : List (VarId × Value) :=
  parameterBindings (fun index : Fin 4 => (patchValues output length field target).get index)

/-- Invalid fields/targets return -1 without dereferencing the output. The
guard's real fits call is executed, including its fresh parameter cells. -/
theorem patch_reject (checked : CheckedPatch program fits word) (output : Value)
    (length field target : Int) (wellFormed : StateWellFormed before)
    (lengthBound : length ≤ 2147483647) (bad : patchBad length field target = true)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (patchValues output length field target) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (-1)) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let bindings := patchBindings output length field target
  let callee := enterCall before bindings
  have locals (index : Fin 4) : callee.local? index.val =
      some ((patchValues output length field target).get index) :=
    enterCall_parameterBindings_matches wellFormed index
  obtain ⟨middle, guard, effect, heapFrame⟩ := patch_guard fits length field target
    (enterCall_preserves_wellFormed wellFormed) lengthBound
    (locals ⟨1, by decide⟩) (locals ⟨2, by decide⟩) (locals ⟨3, by decide⟩)
  rw [bad] at guard
  have run : Executes program.core callee
      (patchBody fits.source.function.id word.source.function.id)
      (.returned (some (.signed .i32 (-1)))) middle :=
    executesSequenceReturned (executesIfTrue guard
      (executesSequenceReturned (executesReturnValue (negative_one program.core middle))))
  have called := checked.call wellFormed argumentsResult (bindings := bindings) rfl run effect
  exact ⟨restoreLocals before middle, called.1, called.2, HeapFrame.closeCall before bindings heapFrame⟩

/-- The actual patcher composes its checked reservation and word-store
callees. Success changes precisely the requested four-byte displacement. -/
theorem patch_success (checked : CheckedPatch program fits word)
    (length field target : Nat) (wellFormed : StateWellFormed before)
    (room : field + 4 ≤ length) (capacity : length ≤ values.length)
    (lengthBound : length ≤ 2147483647) (targetBound : target ≤ length)
    (backing : before.cellEntry? cell = some {
      id := cell, value := some (.array (signedI32Values values)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (patchValues (.slice i32 cell [] 0 values.length) length field target) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (field + 4 : Nat)) after ∧
      after.cellEntry? cell = some {
        id := cell, value := some (.array (signedI32Values
          (writtenWord values field (relativeDisplacement (field + 4) target)))) } ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  let output : Value := .slice i32 cell [] 0 values.length
  let bindings := patchBindings output length field target
  let callee := enterCall before bindings
  have calleeWF := enterCall_preserves_wellFormed wellFormed (bindings := bindings)
  have locals (index : Fin 4) : callee.local? index.val =
      some ((patchValues output length field target).get index) :=
    enterCall_parameterBindings_matches wellFormed index
  have calleeBacking := ((enterCall_effect before bindings).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  obtain ⟨middle, guard, guardEffect, guardHeap⟩ := patch_guard fits length field target
    calleeWF (Int.ofNat_le.mpr lengthBound)
    (locals ⟨1, by decide⟩) (locals ⟨2, by decide⟩) (locals ⟨3, by decide⟩)
  have good : patchBad length field target = false := by
    have reserved : reserved length field 4 = true := by
      simp only [Buffer.reserved, decide_eq_true_eq]
      omega
    simp only [patchBad, reserved, Bool.not_true, Bool.false_or, Bool.or_eq_false_iff,
      decide_eq_false_iff_not]
    omega
  rw [good] at guard
  have outputRead := guardEffect.empty_preserves_local calleeWF (locals ⟨0, by decide⟩)
  have fieldRead := guardEffect.empty_preserves_local calleeWF (locals ⟨2, by decide⟩)
  have targetRead := guardEffect.empty_preserves_local calleeWF (locals ⟨3, by decide⟩)
  have next : Evaluates program.core middle (.binary .add (read 2) (number 4))
      (.signed .i32 (field + 4 : Nat)) middle :=
    evaluatesNatI32Add (local_evaluates program.core fieldRead) ⟨1, rfl⟩ (by omega)
  have displacement := relative_evaluates (field + 4) target (by omega) (by omega)
    (local_evaluates program.core targetRead) next
  have wordArguments : ArgumentsEvaluateTo program.core middle
      [read 0, read 2, .binary .subtract (read 3) (.binary .add (read 2) (number 4))]
      (wordValues output field (relativeDisplacement (field + 4) target)) middle :=
    .cons (local_evaluates program.core outputRead) (.cons (local_evaluates program.core fieldRead)
      (.cons displacement (.nil _ _)))
  obtain ⟨completed, write, contents, writeEffect, writeHeap⟩ := word_call word field
    (relativeDisplacement (field + 4) target) guardEffect.wellFormed (by omega) (by omega)
    (guardEffect.empty_preserves_entry calleeWF calleeBacking) wordArguments
  have run : Executes program.core callee
      (patchBody fits.source.function.id word.source.function.id)
      (.returned (some (.signed .i32 (field + 4 : Nat)))) completed :=
    executesSequence (executesIfFalse guard (executesSkip _ _))
      (executesSequenceReturned (executesReturnValue write))
  have effect := (guardEffect.weaken (larger := CellSet.singleton cell) CellSet.empty_subset).trans writeEffect
  have called := checked.call wellFormed argumentsResult (bindings := bindings) rfl run effect
  exact ⟨restoreLocals before completed, called.1, contents, called.2,
    HeapFrame.closeCall before bindings (guardHeap.trans writeHeap)⟩

/-- End-to-end relocation contract for the actual checked Lanius patcher:
read its resulting buffer, decode the displacement, and recover the requested
image offset at every base. The four-byte field is the only changed region. -/
theorem patch_lands (checked : CheckedPatch program fits word)
    (length field target : Nat) (wellFormed : StateWellFormed before)
    (room : field + 4 ≤ length) (capacity : length ≤ values.length)
    (lengthBound : length ≤ 2147483647) (targetBound : target ≤ length)
    (backing : before.cellEntry? cell = some {
      id := cell, value := some (.array (signedI32Values values)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (patchValues (.slice i32 cell [] 0 values.length) length field target) before) :
    ∃ after emitted, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (field + 4 : Nat)) after ∧
      after.cellEntry? cell = some {
        id := cell, value := some (.array (signedI32Values emitted)) } ∧
      (∀ base : Int, nearTarget (BitVec.ofInt 64 (base + (field + 4 : Nat)))
        (BitVec.ofInt 32 (decodeI32 (byteSlice emitted field 4))) =
          BitVec.ofInt 64 (base + target)) ∧
      emitted.length = values.length ∧
      (∀ index, index < field ∨ field + 4 ≤ index → emitted[index]? = values[index]?) ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  obtain ⟨after, run, contents, effect, heapFrame⟩ :=
    patch_success checked length field target wellFormed room capacity lengthBound targetBound backing argumentsResult
  exact ⟨after, writtenWord values field (relativeDisplacement (field + 4) target),
    run, contents, fun base => writtenWord_target base field target (by omega) (by omega) (by omega),
    writtenWord_length, fun _ outside => writtenWord_frame outside, effect, heapFrame⟩

end Lanius.X86.Buffer
