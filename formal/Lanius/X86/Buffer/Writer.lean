import Lanius.X86.Buffer.Reservation
import Lanius.CallContracts.CellSpec

namespace Lanius.X86.Buffer.Writer

open Lanius.Core Lanius.Semantics Lanius.Separation Lanius.CallContracts

/-- Logical output of a cursor-threaded emitter, including partial failure.
This is proof data, not another implementation of the compiler. -/
structure Result where
  cursor : Int
  values : List Int

def Result.append (before : Result) (capacity count : Nat) (write : List Int → Nat → List Int) : Result :=
  if reserved capacity before.cursor count then ⟨before.cursor + count, write before.values before.cursor.toNat⟩
  else { before with cursor := -1 }

theorem Result.append_success (before : Result) (capacity count start : Nat)
    (write : List Int → Nat → List Int) (cursor : before.cursor = (start : Int))
    (room : start + count ≤ capacity) :
    before.append capacity count write = ⟨(start + count : Nat), write before.values start⟩ := by
  have enough : reserved capacity before.cursor count = true := by
    simp only [reserved, decide_eq_true_eq]
    omega
  rw [cursor] at enough
  simp only [Result.append, cursor, enough, ↓reduceIte, Int.toNat_natCast, Int.natCast_add]

abbrev Stored (cell : CellId) (values : List Int) (state : State) : Prop :=
  state.cellEntry? cell = some ⟨cell, some (.array (signedI32Values values))⟩

abbrev Spec (program : Program) (function : FunctionId) (arguments : List Value) (cell : CellId)
    (before after : Result) : Prop :=
  CellSpec program function arguments (.signed .i32 after.cursor) (Stored cell before.values)
    (fun _ state => Stored cell after.values state) (CellSet.singleton cell)

/-- Lift an atomic emitter's proved success and rejection contracts once.
Later composition needs no case split for exhausted or already-failed cursors. -/
theorem reserve (before : Result) (capacity count : Nat) (write : List Int → Nat → List Int)
    (success : ∀ start : Nat, before.cursor = (start : Int) → start + count ≤ capacity →
      Spec program function arguments cell before ⟨(start + count : Nat), write before.values start⟩)
    (failure : reserved capacity before.cursor count = false →
      CellSpec program function arguments (.signed .i32 (-1))) :
    Spec program function arguments cell before (before.append capacity count write) := by
  by_cases enough : reserved capacity before.cursor count = true
  · have bounds : 0 ≤ before.cursor ∧ 0 ≤ (count : Int) ∧ before.cursor + count ≤ capacity := of_decide_eq_true enough
    have cursor : before.cursor = (before.cursor.toNat : Int) := (Int.toNat_of_nonneg bounds.1).symm
    simpa only [Result.append, enough, ↓reduceIte, Int.natCast_add, Int.toNat_of_nonneg bounds.1] using
      success before.cursor.toNat cursor (by omega)
  · have rejected : reserved capacity before.cursor count = false := Bool.eq_false_iff.mpr enough
    constructor
    intro caller expressions state wellFormed evaluated backing
    obtain ⟨after, run, _, effect, heap⟩ := (failure rejected).call wellFormed evaluated
    exact ⟨after, by simpa only [Result.append, rejected, Bool.false_eq_true, ↓reduceIte] using run,
      by simpa only [Result.append, rejected, Bool.false_eq_true, ↓reduceIte, Stored] using
        effect.empty_preserves_entry wellFormed backing,
      effect.weaken CellSet.empty_subset, heap⟩

theorem Result.append_length (before : Result) {write : List Int → Nat → List Int}
    (preserves : ∀ values start, (write values start).length = values.length) :
    (before.append capacity count write).values.length = before.values.length := by
  unfold Result.append
  split <;> simp_all

end Lanius.X86.Buffer.Writer
