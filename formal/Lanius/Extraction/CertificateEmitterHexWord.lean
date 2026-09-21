import Lanius.Semantics.Arithmetic
import Lanius.Semantics.Scalar
import Lanius.Semantics.Aggregate
import Lanius.Extraction.CertificateEmitterProofAutomation
import Lanius.Extraction.CertificateEmitterOutputBuffer

namespace Lanius.Extraction.CertificateEmitterHexWord

open Lanius Lanius.Core Lanius.Extraction Lanius.Semantics
open Lanius.Extraction.CertificateEmitterOutputBuffer

def hexWordGuard : Expr :=
  .binary .logicalOr
    (.binary .lessEqual (.local 2)
      (.unary .negate (.value (.signed .i32 1))))
    (.binary .greater (.local 2)
      (.binary .subtract (.local 1) (.value (.signed .i32 8))))

private theorem setValue_eq_set : ∀ (l : List Value) (i : Nat) (v : Value),
    setValue l i v = l.set i v := by
  intro l
  induction l <;> intro i v <;> cases i <;> simp [setValue, *]

private theorem setValue_getElem?_all (l : List Value) (i j : Nat) (v : Value) :
    (setValue l i v)[j]? = if j < l.length then
      if i = j then some v else l[j]? else none := by
  rw [setValue_eq_set]
  by_cases h : j < l.length
  · have hset : j < (l.set i v).length := by simpa using h
    rw [List.getElem?_eq_getElem hset]
    by_cases hij : i = j <;> simp [h, hij]
  · have hset : ¬ j < (l.set i v).length := by simpa using h
    simp [h]

private theorem setValue_length (l : List Value) (i : Nat) (v : Value) :
    (setValue l i v).length = l.length := by
  rw [setValue_eq_set]
  simp

def hexWordByte (value : Int) (shift : Nat) : Nat :=
  CertificateRoundTrip.wordNat value / 2 ^ shift % 256

def hexWordElements (elements : List Value) (position : Nat) (value : Int) : List Value :=
  hexByteElements
    (hexByteElements
      (hexByteElements
        (hexByteElements elements position (hexWordByte value 24))
        (position + 2) (hexWordByte value 16))
      (position + 4) (hexWordByte value 8))
    (position + 6) (hexWordByte value 0)

theorem hexWordElements_canonical (elements : List Value) (position : Nat) (value : Int)
    (bounds : position + 8 ≤ elements.length) :
    (hexWordElements elements position value).length = elements.length ∧
    ∀ j, j < 8 →
      (hexWordElements elements position value)[position + j]? = some (match j with
        | 0 => .signed .i32 (Int.ofNat (hexByteHighValue (hexWordByte value 24)))
        | 1 => .signed .i32 (Int.ofNat (hexByteLowValue (hexWordByte value 24)))
        | 2 => .signed .i32 (Int.ofNat (hexByteHighValue (hexWordByte value 16)))
        | 3 => .signed .i32 (Int.ofNat (hexByteLowValue (hexWordByte value 16)))
        | 4 => .signed .i32 (Int.ofNat (hexByteHighValue (hexWordByte value 8)))
        | 5 => .signed .i32 (Int.ofNat (hexByteLowValue (hexWordByte value 8)))
        | 6 => .signed .i32 (Int.ofNat (hexByteHighValue (hexWordByte value 0)))
        | 7 => .signed .i32 (Int.ofNat (hexByteLowValue (hexWordByte value 0)))
        | _ => .signed .i32 0) := by
  constructor
  · simp [hexWordElements, hexByteElements, setValue_eq_set]
  · intro j hj
    have cases : j = 0 ∨ j = 1 ∨ j = 2 ∨ j = 3 ∨
        j = 4 ∨ j = 5 ∨ j = 6 ∨ j = 7 := by omega
    have hp2 : position + 2 + 1 ≠ position := by omega
    have hp4 : position + 4 + 1 ≠ position := by omega
    have hp6 : position + 6 + 1 ≠ position := by omega
    rcases cases with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
      simp [hexWordElements, hexByteElements, setValue_getElem?_all, setValue_length,
        hp2, hp4, hp6] <;> omega

/- The outer guard is independent of the loop.  Keeping it as a stable
   expression contract lets the concrete body proof use the same branch rule
   as the byte emitter without carrying evaluator fuel through the loop. -/
theorem hexWordGuard_false_contract
    (program : Program) (state : State) (capacity position : Nat)
    (capacityFound : state.local? 1 =
      some (.signed .i32 (Int.ofNat capacity)))
    (positionFound : state.local? 2 =
      some (.signed .i32 (Int.ofNat position)))
    (formed : state.CellsWellFormed)
    (capacityBound : capacity < 2 ^ 31)
    (positionNonnegative : 0 ≤ position)
    (positionCapacity : position + 8 ≤ capacity) :
    ThresholdPure 7 program state hexWordGuard (.boolean false) state := by
  have low := ThresholdPure.i32LocalLessEqualNegOne program state 2
    (Int.ofNat position) positionFound formed
  have low' : ThresholdPure 4 program state
      (.binary .lessEqual (.local 2)
        (.unary .negate (.value (.signed .i32 1))))
      (.boolean false) state := by
    have nonnegative : ¬ (Int.ofNat position) ≤ (-1 : Int) := by
      intro h
      have nonnegative' : (0 : Int) ≤ Int.ofNat position := Int.natCast_nonneg _
      omega
    have lowDecide : decide ((Int.ofNat position) ≤ (-1 : Int)) = false :=
      decide_eq_false_iff_not.mpr nonnegative
    change ThresholdPure 4 program state
      (.binary .lessEqual (.local 2)
        (.unary .negate (.value (.signed .i32 1))))
      (.boolean (decide ((Int.ofNat position) ≤ (-1 : Int)))) state at low
    rw [lowDecide] at low
    exact low
  have capSub := ThresholdPure.i32LocalSubtractNat program state 1 capacity 8
    capacityFound formed (by omega) capacityBound
  have high : ThresholdPure 3 program state
      (.binary .greater (.local 2)
        (.binary .subtract (.local 1) (.value (.signed .i32 8))))
      (.boolean false) state := ThresholdPure.binary (operation := .greater)
    (ThresholdPure.localValue formed 2 (.signed .i32 (Int.ofNat position)) positionFound)
    capSub
    (by simp)
    (by
      simp only [evalBinaryValue, evalSignedBinary]
      simp only [beq_self_eq_true, if_true]
      have posLe : position ≤ capacity - 8 := by omega
      have posLeInt : (Int.ofNat position) ≤ Int.ofNat (capacity - 8) :=
        Int.ofNat_le.mpr posLe
      have notGreater : ¬ (Int.ofNat (capacity - 8) < Int.ofNat position) :=
        Int.not_lt_of_ge posLeInt
      have notGreater' : ¬ (Int.ofNat position > Int.ofNat (capacity - 8)) := by
        intro h
        exact notGreater h
      have decideFalse :
          decide (Int.ofNat position > Int.ofNat (capacity - 8)) = false :=
        decide_eq_false_iff_not.mpr notGreater'
      rw [decideFalse]
    )
  have high' : ThresholdPure 4 program state
      (.binary .greater (.local 2)
        (.binary .subtract (.local 1) (.value (.signed .i32 8))))
      (.boolean false) state := by
    have posLe : position ≤ capacity - 8 := by omega
    have subEq : (Int.ofNat capacity - Int.ofNat 8) =
        Int.ofNat (capacity - 8) := by
      symm
      exact Int.ofNat_sub (by omega)
    have nonpositive : ¬ (Int.ofNat position) >
        (Int.ofNat capacity - Int.ofNat 8) := by
      rw [subEq]
      exact Int.not_lt_of_ge (Int.ofNat_le.mpr posLe)
    simpa [subEq, nonpositive] using high.weaken (by omega)
  simpa [hexWordGuard] using
    (logicalOrFalse low' high').weaken (by omega)

end Lanius.Extraction.CertificateEmitterHexWord
