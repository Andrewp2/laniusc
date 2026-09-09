import Lanius.Extraction.OutputPacking.Clear

namespace Lanius.Extraction.OutputPacking

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- The source's output cap makes the rounding addition safe in signed i32.
The resulting word count fits the existing 16 MiB workspace. -/
theorem output_word_bounds (length : Nat) (bounded : length ≤ 8388608) :
    length + 3 ≤ 2147483647 ∧ (length + 3) / 4 ≤ 4194304 := by omega

theorem evaluates_output_words (program : Program) (state : State)
    (lengthId : VarId) (length : Nat) (bounded : length ≤ 8388608)
    (read : state.local? lengthId = some (.signed .i32 length)) :
    Evaluates program state
      (.binary .divide (.binary .add (.local lengthId) (.value (.signed .i32 3)))
        (.value (.signed .i32 4)))
      (.signed .i32 ((length + 3) / 4 : Nat)) state := by
  have addition : Evaluates program state
      (.binary .add (.local lengthId) (.value (.signed .i32 3)))
      (.signed .i32 (length + 3 : Nat)) state := by
    apply evaluatesEagerBinary (by decide) (by decide)
      (show Evaluates program state (.local lengthId) (.signed .i32 length) state from
        ⟨1, evalLocal_of_local 0 program state lengthId _ read⟩)
      (show Evaluates program state (.value (.signed .i32 3)) (.signed .i32 3) state from ⟨1, rfl⟩)
    simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalSignedBinary]
    have wrapped := wrapSigned_i32_ofNat program.target _ (output_word_bounds length bounded).1
    simpa [Int.ofNat_eq_natCast, Int.natCast_add] using
      congrArg (fun value => Except.ok (Value.signed .i32 value) : Int → Except Trap Value) wrapped
  apply evaluatesEagerBinary (by decide) (by decide) addition
    (show Evaluates program state (.value (.signed .i32 4)) (.signed .i32 4) state from ⟨1, rfl⟩)
  have divided : truncDiv (length + 3 : Nat) 4 = ((length + 3) / 4 : Nat) := by
    simp only [truncDiv, Int.natCast_nonneg, Int.natAbs_natCast]
    rfl
  simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalSignedBinary,
    show ((4 : Int) == 0) = false from rfl, show ((4 : Int) == -1) = false from rfl,
    Bool.and_false, Bool.false_eq_true, ↓reduceIte, divided]
  have wrapped := wrapSigned_i32_ofNat program.target ((length + 3) / 4) (by omega)
  simpa only [Int.ofNat_eq_natCast] using
    congrArg (fun value => Except.ok (Value.signed .i32 value) : Int → Except Trap Value) wrapped

end Lanius.Extraction.OutputPacking
