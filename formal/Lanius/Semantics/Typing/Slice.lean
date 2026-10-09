import Lanius.Semantics.Typing.Target
import Lanius.Semantics.StmtList

namespace Lanius.Semantics

open Lanius.Core Lanius.Typing

/-- A cell slice follows a declared array path and lies inside its fixed
    extent. Native/raw slices require their separate heap/layout invariant. -/
inductive CellSliceValid (program : Program) (types : CellTypes) (state : State) :
    Value → Ty → Prop where
  | slice (target : CellTargetValid program types state cell projections (.array element count))
      (bounds : start + length ≤ count) :
      CellSliceValid program types state (.slice element cell projections start length) element

variable {slice : Value}

/-- Place-shaped array conversion aliases the original cell and derives its
    descriptor length from the typed root. Temporary/raw storage is separate. -/
theorem CellTargetValid.arrayToSliceLocal
    (target : CellTargetValid program types state cell [] (.array element count))
    (store : state.CellsHaveTypes program types) (binding : state.cellId? localId = some cell) :
    RunsExpr program state (.arrayToSlice element (.local localId)) (.slice element cell [] 0 count) state ∧
      CellSliceValid program types state (.slice element cell [] 0 count) element := by
  obtain ⟨rootType, declared, path, initialized⟩ := target
  cases path
  obtain ⟨contents, stored, typed⟩ := store cell (.array element count) declared
  cases contents with
  | none => simp [State.cell?, stored] at initialized
  | some root => cases typed with
    | array values element size elements =>
      have found : state.local? localId = some (.array values) := by simp [State.local?, binding, State.cell?, stored]
      refine ⟨RunsExpr.ofEval (fuel := 2) ?_, .slice ⟨_, declared, .root, initialized⟩ (by omega)⟩
      rw [evalExpr.eq_def]
      simp only [expressionPlace?, evalPlace_local_of_local? 0 program state .read localId cell _ binding found, size]

theorem CellSliceValid.typed (valid : CellSliceValid program types state slice element) :
    ValueHasType program slice (.slice element) := by
  cases valid
  exact .slice _ _ _ _ _

theorem CellSliceValid.retained (valid : CellSliceValid program types before slice element)
    (frame : FreshCellFrame before after) : CellSliceValid program types after slice element := by
  cases valid with
  | slice target bounds => exact .slice (target.retained frame) bounds

theorem CellSliceValid.cellEffect (valid : CellSliceValid program types before slice element)
    (effect : CellEffect before after cell replacement) : CellSliceValid program types after slice element := by
  cases valid with
  | slice target bounds => exact .slice (target.cellEffect effect) bounds

/-- A valid descriptor yields exactly its declared length of typed elements,
    after any typed mutation of its root. No successful read is assumed. -/
theorem CellSliceValid.read
    (valid : CellSliceValid program types state (.slice element cell projections start length) element)
    (store : state.CellsHaveTypes program types) :
    ∃ values, sliceValues state cell projections start length = .ok values ∧
      values.length = length ∧ ValuesHaveTypes program values (List.replicate length element) := by
  cases valid with
  | @slice cell projections element count start length target bounds =>
    obtain ⟨root, read, typed⟩ := target.read store
    cases typed with
    | array values element size elements =>
      have room : length ≤ values.length - start := by omega
      refine ⟨(values.drop start).take length, ?_, ?_, ?_⟩
      · simp only [sliceValues, read, if_pos (show start + length ≤ values.length from by omega)]
      · simp only [List.length_take, List.length_drop, Nat.min_eq_left room]
      · simpa only [List.drop_replicate, List.take_replicate,
          Nat.min_eq_left (show length ≤ count - start from by omega)] using
          (elements.drop start).take length

theorem CellSliceValid.index
    (valid : CellSliceValid program types state (.slice element cell projections start length) element)
    (store : state.CellsHaveTypes program types) (bound : position < length) :
    ∃ values value, sliceValues state cell projections start length = .ok values ∧
      values[position]? = some value ∧ ValueHasType program value element := by
  obtain ⟨values, read, size, typed⟩ := valid.read store
  obtain ⟨value, found, valueTyped⟩ := typed.get (index := position) (type := element) (by simp [bound])
  exact ⟨values, value, read, found, valueTyped⟩

/-- Base and index expressions may have effects. Validate backing storage
    after both have run, so indexing never uses a stale pre-index snapshot. -/
theorem RunsExpr.cellSliceIndexTyped
    (base : RunsExpr program before expression (.slice element cell projections start length) middle)
    (index : RunsExpr program middle indexExpression (.signed .i32 (position : Nat)) ready)
    (store : ready.CellsHaveTypes program types)
    (valid : CellSliceValid program types ready (.slice element cell projections start length) element)
    (bound : position < length) :
    ∃ value, RunsExpr program before (.index expression indexExpression) value ready ∧ ValueHasType program value element := by
  obtain ⟨values, value, read, found, typed⟩ := valid.index store bound
  obtain ⟨baseFuel, baseRun, baseLocals⟩ := base
  obtain ⟨indexFuel, indexRun, indexLocals⟩ := index
  refine ⟨value, ⟨max baseFuel indexFuel + 1, ?_, indexLocals.trans baseLocals⟩, typed⟩
  intro fuel enough
  rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def]
  simp only [baseRun (fuel - 1) (by omega), indexRun (fuel - 1) (by omega), integerIndex,
    Int.not_lt_of_ge (Int.natCast_nonneg position), ↓reduceIte, Int.toNat_natCast, if_pos bound, read, found]

#print axioms CellSliceValid.read
#print axioms RunsExpr.cellSliceIndexTyped

end Lanius.Semantics
