import verified_compiler.tests.direct_ir_negative_lowering

namespace IRBodyProductionScalar

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
open IRDecimalProof IRDecimalLoopProof IREventStoreProof

/-- ASCII grammar D(D|_D)* and positional magnitude, independently of decoding. -/
inductive DecimalSpelling : List Int → Nat → Prop where
  | digit (value : Nat) (bound : value < 10) : DecimalSpelling [48 + (value : Int)] value
  | append (initial : DecimalSpelling bytes value) (digit : Nat) (bound : digit < 10)
      (separated : Bool) :
      DecimalSpelling (bytes ++ (if separated then [95] else []) ++ [48 + (digit : Int)])
        (value * 10 + digit)

private theorem digitStep (state : Accumulator) (digit : Nat) (bound : digit < 10) :
    step state (48 + (digit : Int)) = match state with
      | .empty => .number digit
      | .number value => appendDigit value digit
      | _ => .rejected := by
  have underscore : 48 + (digit : Int) ≠ 95 := by omega
  have valid : ¬(48 + (digit : Int) < 48 ∨ 57 < 48 + (digit : Int)) := by omega
  have value : (48 + (digit : Int) - 48).toNat = digit := by omega
  simp only [step, if_neg underscore, if_neg valid, value]
  rfl

/-- Bounded grammar-valid magnitudes yield the actual decoder's exact result. -/
theorem DecimalSpelling.decoded (spelled : DecimalSpelling bytes magnitude)
    (bound : magnitude ≤ 2 ^ 31) :
    decode bytes = if magnitude < 2 ^ 31 then .number magnitude else .minimum := by
  induction spelled with
  | digit value digitBound =>
      change step .empty (48 + (value : Int)) = _
      rw [digitStep .empty value digitBound, if_pos (by omega)]
  | @append bytes value initial digit digitBound separated ih =>
      have smaller : value < 2 ^ 31 := by omega
      have previous := ih (by omega)
      rw [if_pos smaller] at previous
      change List.foldl step .empty bytes = .number value at previous
      change List.foldl step .empty (_ ++ _ ++ _) = _
      rw [List.foldl_append, List.foldl_append, previous]
      cases separated <;>
        simp only [Bool.false_eq_true, if_false, if_true,
          List.foldl_cons, List.foldl_nil, show ∀ state, step state 95 = state from fun _ => rfl]
      all_goals
        rw [digitStep _ digit digitBound]
        by_cases small : value * 10 + digit < 2 ^ 31
        · simp only [appendDigit, if_pos small]
        · have exactBound : value * 10 + digit = 2 ^ 31 := by omega
          simp only [appendDigit, if_neg small, if_pos exactBound]

private theorem scanList (text : List Int) (bytes : Nat → Int) (start : Nat) (state : Accumulator)
    (agree : ∀ index, index < text.length → bytes (start + index) = text[index]?.getD 0) :
    scan bytes text.length start state = text.foldl step state := by
  induction text generalizing start state with
  | nil => rfl
  | cons head tail ih =>
      have first := agree 0 (by simp)
      simp only [Nat.add_zero, List.getElem?_cons_zero, Option.getD_some] at first
      rw [List.length_cons, scan, first, List.foldl_cons]
      apply ih
      intro index inside
      have next := agree (index + 1) (by simp only [List.length_cons]; omega)
      simpa only [Nat.add_assoc, Nat.add_left_comm, Nat.add_comm, List.getElem?_cons_succ] using next

theorem spelledScan (input : IRDecimalLoopProof.Input before)
    (spelled : DecimalSpelling text magnitude) (length : text.length = input.length)
    (agree : ∀ index, index < input.length → input.bytes index = text[index]?.getD 0)
    (bound : magnitude ≤ 2 ^ 31) :
    scan input.bytes input.length 0 .empty =
      if magnitude < 2 ^ 31 then .number magnitude else .minimum := by
  have scanned := scanList text input.bytes 0 .empty (by
    intro index inside
    simpa only [Nat.zero_add] using agree index (by omega))
  rw [length] at scanned
  exact scanned.trans (spelled.decoded bound)

/-- Decode original token bytes, then execute the existing actual literal writer. -/
theorem actualDecimalEmission (input : IRIntegerLoweringProof.Input before) (unused : List Value)
    (spelled : DecimalSpelling text magnitude) (length : text.length = input.length)
    (agree : ∀ index, index < input.length → input.bytes index = text[index]?.getD 0)
    (bound : magnitude < 2 ^ 31) (storage : Context before)
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap)
    (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before
      (IRLiteralLoweringProof.integerCall input unused storage.value storage.position)
      (.signed .i32 (storage.position + 1 : Nat)) after ∧
      Appended storage (integer (Int32.ofNat magnitude).toBitVec) before after := by
  have decoded := spelledScan input.toInput spelled length agree (by omega)
  rw [if_pos bound] at decoded
  exact IRLiteralLoweringProof.actualInteger input unused magnitude decoded storage formed unique noViews

theorem actualNegativeEmission (input : IRIntegerLoweringProof.Input before) (unused : List Value)
    (spelled : DecimalSpelling text magnitude) (length : text.length = input.length)
    (agree : ∀ index, index < input.length → input.bytes index = text[index]?.getD 0)
    (bound : magnitude < 2 ^ 31) (storage : IRNegativeLoweringProof.Storage before)
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap)
    (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before
      (IRNegativeLoweringProof.call input unused storage.head.value storage.head.position)
      (.signed .i32 (storage.head.position + 2 : Nat)) after ∧
      MemoryEffect (IRNegativeLoweringProof.effect storage magnitude) before after := by
  have decoded := spelledScan input.toInput spelled length agree (by omega)
  rw [if_pos bound] at decoded
  exact IRNegativeLoweringProof.actualNumber input unused magnitude decoded storage formed unique noViews

theorem actualMinimumEmission (input : IRIntegerLoweringProof.Input before) (unused : List Value)
    (spelled : DecimalSpelling text (2 ^ 31)) (length : text.length = input.length)
    (agree : ∀ index, index < input.length → input.bytes index = text[index]?.getD 0)
    (storage : Context before) (formed : before.CellsWellFormed)
    (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before
      (IRNegativeLoweringProof.call input unused storage.value storage.position)
      (.signed .i32 (storage.position + 1 : Nat)) after ∧
      Appended storage (integer (-2147483648)) before after := by
  have decoded := spelledScan input.toInput spelled length agree (by omega)
  rw [if_neg (by omega : ¬(2 ^ 31 : Nat) < 2 ^ 31)] at decoded
  exact IRNegativeLoweringProof.actualSignedMinimum input unused decoded storage formed unique noViews

#print axioms DecimalSpelling.decoded
#print axioms spelledScan
#print axioms actualDecimalEmission
#print axioms actualNegativeEmission
#print axioms actualMinimumEmission

end IRBodyProductionScalar
