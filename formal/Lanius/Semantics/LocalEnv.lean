import Lanius.Semantics.LocalScope
import Lanius.Semantics.ScalarAssignment
import Lanius.Semantics.ProofFacts
import Lanius.Semantics.NaturalArithmetic

namespace Lanius.Semantics

open Lanius.Core

/-- Only the observable stores, with no claim about cells or referents.
Transparency makes lexical bind/restore transport definitional. -/
def DataFrame (before after : State) : Prop :=
  after.heap = before.heap ∧ after.world = before.world ∧ after.i32ArrayViews = before.i32ArrayViews

namespace DataFrame

theorem heap (frame : DataFrame before after) : after.heap = before.heap := frame.1
theorem world (frame : DataFrame before after) : after.world = before.world := frame.2.1
theorem views (frame : DataFrame before after) : after.i32ArrayViews = before.i32ArrayViews := frame.2.2
theorem refl (state : State) : DataFrame state state := ⟨rfl, rfl, rfl⟩
theorem trans (first : DataFrame before middle) (second : DataFrame middle after) :
    DataFrame before after :=
  ⟨second.heap.trans first.heap, second.world.trans first.world, second.views.trans first.views⟩

end DataFrame

/-- Symbolic values of the tracked lexical locals. The map records values,
not the contents of places reached through reference or pointer values. -/
abbrev LocalValues := VarId → Option Value

namespace LocalValues

def empty : LocalValues := fun _ => none

def set (values : LocalValues) (id : VarId) (value : Value) : LocalValues :=
  fun queried => if queried = id then some value else values queried

def bindAll (values : LocalValues) (bindings : List (VarId × Value)) : LocalValues :=
  bindings.foldl (fun result binding => result.set binding.1 binding.2) values

/-- Drop knowledge outside an enclosing scope without reverting its writes. -/
def restrict (values shape : LocalValues) : LocalValues :=
  fun id => if (shape id).isSome then values id else none

@[simp] theorem empty_apply (id : VarId) : empty id = none := rfl

@[simp] theorem set_same (values : LocalValues) (id : VarId) (value : Value) :
    values.set id value id = some value := by simp [set]

@[simp] theorem set_other (values : LocalValues) (id queried : VarId) (value : Value)
    (different : queried ≠ id) : values.set id value queried = values queried := by
  simp [set, different]

theorem before_set {values : LocalValues} {id queried : VarId} {old value result : Value}
    (present : values id = some old) (found : values.set id value queried = some result) :
    ∃ previous, values queried = some previous := by
  by_cases same : queried = id
  · subst queried; exact ⟨old, present⟩
  · exact ⟨result, by simpa [set, same] using found⟩

theorem of_restrict {values shape : LocalValues} {id : VarId} {value : Value}
    (found : values.restrict shape id = some value) :
    values id = some value ∧ ∃ previous, shape id = some previous := by
  cases original : shape id with
  | none => simp [restrict, original] at found
  | some previous => exact ⟨by simpa [restrict, original] using found, previous, rfl⟩

@[simp] theorem restrict_self (values : LocalValues) : values.restrict values = values := by
  funext id
  cases found : values id <;> simp [restrict, found]

@[simp] theorem restrict_empty (shape : LocalValues) : empty.restrict shape = empty := by
  funext id; simp [restrict, empty]

@[simp] theorem restrict_set_fresh (values shape : LocalValues) (id : VarId) (value : Value)
    (fresh : shape id = none) :
    (values.set id value).restrict shape = values.restrict shape := by
  funext queried
  by_cases same : queried = id
  · subst queried; simp [restrict, fresh]
  · simp [restrict, set, same]

@[simp] theorem restrict_set_present (values shape : LocalValues) (id : VarId)
    (old value : Value) (present : shape id = some old) :
    (values.set id value).restrict shape = (values.restrict shape).set id value := by
  funext queried
  by_cases same : queried = id
  · subst queried; simp [restrict, set, present]
  · simp [restrict, set, same]

/-- The membership premise has no existential old-value metavariable, so a
scope can be closed by reducing just its known key lookup. -/
theorem restrict_set_member (values shape : LocalValues) (id : VarId) (value : Value)
    (present : (shape id).isSome = true) :
    (values.set id value).restrict shape = (values.restrict shape).set id value := by
  funext queried
  by_cases same : queried = id
  · subst queried; simp [restrict, set, present]
  · simp [restrict, set, same]

@[simp] theorem set_set (values : LocalValues) (id : VarId) (first second : Value) :
    (values.set id first).set id second = values.set id second := by
  funext queried; simp only [set]; split <;> rfl

theorem set_of_found {values : LocalValues} {id : VarId} {value : Value}
    (found : values id = some value) : values.set id value = values := by
  funext queried
  by_cases same : queried = id
  · subst queried; simp [found]
  · simp [set, same]

@[simp] theorem restrict_extend (values : LocalValues) (id : VarId) (value : Value) :
    values.restrict (values.set id value) = values := by
  funext queried
  by_cases same : queried = id
  · subst queried; simp [restrict]
  · cases old : values queried <;> simp [restrict, set, same, old]

end LocalValues

/-- An arbitrary number of fresh lexical slots and their current symbolic
values. Slot identities are existential and never part of a client invariant.
Distinct tracked names own distinct slots; values themselves may alias through
references, slices, or pointers. Neither their referents nor the heap are framed
by this predicate. Calls must establish their actual cell and store effects. -/
structure LocalEnv (base current : State) (values : LocalValues) : Prop where
  baseFormed : base.CellsWellFormed
  cells : FreshCellFrame base current
  lookup : ∀ {id value}, values id = some value → current.local? id = some value
  fresh : ∀ {id value}, values id = some value →
    ∃ cell, current.cellId? id = some cell ∧ base.nextCell ≤ cell
  separate : ∀ {left right first second}, values left = some first → values right = some second →
    current.cellId? left = current.cellId? right → left = right

namespace LocalEnv

variable {base before ready current completed after : State} {values nextValues : LocalValues}
  {id : VarId}

theorem formed (env : LocalEnv base current values) : current.CellsWellFormed :=
  env.cells.after_cellsWellFormed env.baseFormed

theorem start (formed : base.CellsWellFormed) : LocalEnv base base LocalValues.empty := by
  refine ⟨formed, ⟨[], by simp, Nat.le_refl _, by simp⟩, ?_, ?_, ?_⟩
  all_goals simp [LocalValues.empty]

/-- Clearing names at function entry changes no cells. -/
theorem clear (formed : base.CellsWellFormed) :
    LocalEnv base { base with locals := [] } LocalValues.empty := by
  refine ⟨formed, ⟨[], by simp, Nat.le_refl _, by simp⟩, ?_, ?_, ?_⟩
  all_goals simp [LocalValues.empty]

@[core_local_rule] theorem read (env : LocalEnv base current values)
    (found : values id = some value) : current.local? id = some value := env.lookup found

theorem bind (env : LocalEnv base current values) (id : VarId) (value : Value) :
    LocalEnv base (current.bindLocal id value) (values.set id value) := by
  have formed := env.formed
  refine ⟨env.baseFormed, env.cells.trans (FreshCellFrame.bindLocal current id value), ?_, ?_, ?_⟩
  · intro queried result found
    by_cases same : queried = id
    · subst queried
      have equal : value = result := by simpa using found
      subst result
      exact formed.bindLocal_local id value
    · exact State.bindLocal_local?_of_ne current formed queried id result value (Ne.symm same)
        (env.lookup (by simpa [LocalValues.set, same] using found))
  · intro queried result found
    by_cases same : queried = id
    · subst queried
      exact ⟨current.nextCell, State.bindLocal_cellId _ _ _, env.cells.choose_spec.2.1⟩
    · obtain ⟨cell, slot, fresh⟩ := env.fresh (by simpa [LocalValues.set, same] using found)
      exact ⟨cell, (State.bindLocal_cellId_of_ne current queried id (Ne.symm same) value).trans slot, fresh⟩
  · intro left right first second leftFound rightFound equal
    by_cases leftNew : left = id
    · subst left
      by_cases rightNew : right = id
      · exact rightNew.symm
      · have previous : values right = some second := by
          simpa [LocalValues.set, rightNew] using rightFound
        obtain ⟨cell, slot, _⟩ := env.fresh previous
        have bound := formed.localCellBound slot (env.lookup previous)
        rw [State.bindLocal_cellId, State.bindLocal_cellId_of_ne _ _ _ (Ne.symm rightNew), slot] at equal
        have : current.nextCell = cell := Option.some.inj equal
        exact False.elim ((Nat.ne_of_lt bound) this.symm)
    · by_cases rightNew : right = id
      · subst right
        have previous : values left = some first := by
          simpa [LocalValues.set, leftNew] using leftFound
        obtain ⟨cell, slot, _⟩ := env.fresh previous
        have bound := formed.localCellBound slot (env.lookup previous)
        rw [State.bindLocal_cellId, State.bindLocal_cellId_of_ne _ _ _ (Ne.symm leftNew), slot] at equal
        have : cell = current.nextCell := Option.some.inj equal
        exact False.elim ((Nat.ne_of_lt bound) this)
      · apply env.separate
          (by simpa [LocalValues.set, leftNew] using leftFound)
          (by simpa [LocalValues.set, rightNew] using rightFound)
        simpa only [State.bindLocal_cellId_of_ne _ _ _ (Ne.symm leftNew),
          State.bindLocal_cellId_of_ne _ _ _ (Ne.symm rightNew)] using equal

theorem bindLocals (env : LocalEnv base current values) (bindings : List (VarId × Value)) :
    LocalEnv base (current.bindLocals bindings) (values.bindAll bindings) := by
  induction bindings generalizing current values with
  | nil => simpa only [State.bindLocals, LocalValues.bindAll, List.foldl_nil] using env
  | cons binding rest induction =>
    simpa only [State.bindLocals, LocalValues.bindAll, List.foldl_cons] using
      induction (env.bind binding.1 binding.2)

/-- Retain tracked values under proved cell preservation and lexical lookup
identity. Extra untracked names may be in scope. -/
theorem afterCellsAt (env : LocalEnv base before values)
    (cells : FreshCellFrame before after)
    (same : ∀ {id value}, values id = some value → after.cellId? id = before.cellId? id) :
    LocalEnv base after values := by
  refine ⟨env.baseFormed, env.cells.trans cells, ?_, ?_, ?_⟩
  · exact fun found => cells.localFoundAt (same found) _ (env.lookup found)
  · intro id value found
    obtain ⟨cell, slot, fresh⟩ := env.fresh found
    exact ⟨cell, (same found).trans slot, fresh⟩
  · intro left right first second l r equal
    exact env.separate l r ((same l).symm.trans (equal.trans (same r)))

/-- A proved call frame retains local values even when heap/world effects
occur. This rule cannot be used for a call that writes through a cell alias. -/
theorem afterCells (env : LocalEnv base before values)
    (cells : FreshCellFrame before after) (locals : after.locals = before.locals) :
    LocalEnv base after values := env.afterCellsAt cells (fun _ => by simp only [State.cellId?, locals])

theorem afterBindCells (env : LocalEnv base before values)
    (cells : FreshCellFrame before after)
    (locals : after.locals = (before.bindLocal id value).locals)
    (freshName : values id = none) : LocalEnv base after values := by
  apply env.afterCellsAt cells
  intro queried result found
  have different : id ≠ queried := by
    intro equal; subst queried; rw [freshName] at found; contradiction
  have same : after.cellId? queried = (before.bindLocal id value).cellId? queried := by
    simp only [State.cellId?, locals]
  exact same.trans (State.bindLocal_cellId_of_ne before queried id different value)

theorem afterExpr (env : LocalEnv base before values)
    (run : RunsExpr program before expression result after) (cells : FreshCellFrame before after) :
    LocalEnv base after values := env.afterCells cells run.choose_spec.2

theorem afterStmt (env : LocalEnv base before values)
    (run : RunsStmt program before statement completion after) (cells : FreshCellFrame before after) :
    LocalEnv base after values := env.afterCells cells run.choose_spec.2

theorem assignLocal (env : LocalEnv base before values)
    (found : values id = some previous) (assigned : before.assignLocal id replacement = some after) :
    LocalEnv base after (values.set id replacement) := by
  obtain ⟨cell, slot, fresh⟩ := env.fresh found
  have written := assignLocal_assignCell id cell replacement slot assigned
  have effect := assignCell_effect written
  refine ⟨env.baseFormed, env.cells.assignCellFresh env.baseFormed cell replacement fresh written, ?_, ?_, ?_⟩
  · intro queried result lookup
    by_cases same : queried = id
    · subst queried
      have equal : replacement = result := by simpa using lookup
      subst result
      exact assignLocal_finds_assigned _ _ _ slot assigned
    · have old : values queried = some result := by simpa [LocalValues.set, same] using lookup
      apply assignCell_preserves_other_local_of_cellId _ _ _ written (env.lookup old)
      intro sameCell
      exact same (env.separate old found (sameCell.trans slot.symm))
  · intro queried result lookup
    obtain ⟨old, oldFound⟩ := LocalValues.before_set found lookup
    obtain ⟨oldCell, oldSlot, bound⟩ := env.fresh oldFound
    exact ⟨oldCell, by simpa only [State.cellId?, effect.locals] using oldSlot, bound⟩
  · intro left right first second l r equal
    obtain ⟨oldLeft, oldL⟩ := LocalValues.before_set found l
    obtain ⟨oldRight, oldR⟩ := LocalValues.before_set found r
    exact env.separate oldL oldR (by simpa only [State.cellId?, effect.locals] using equal)

theorem restrict (env : LocalEnv base current values) (shape : LocalValues) :
    LocalEnv base current (values.restrict shape) :=
  ⟨env.baseFormed, env.cells, fun found => env.lookup (LocalValues.of_restrict found).1,
    fun found => env.fresh (LocalValues.of_restrict found).1,
    fun left right same => env.separate (LocalValues.of_restrict left).1 (LocalValues.of_restrict right).1 same⟩

theorem restore (env : LocalEnv base completed values) (caller : State)
    (same : ∀ {id value}, values id = some value → completed.cellId? id = caller.cellId? id) :
    LocalEnv base (restoreLocals caller completed) values := by
  refine ⟨env.baseFormed, env.cells, ?_, ?_, ?_⟩
  · exact fun found => restoreLocals_local?_of_cellId_eq (same found) (env.lookup found)
  · intro id value found
    obtain ⟨cell, slot, fresh⟩ := env.fresh found
    exact ⟨cell, (same found).symm.trans slot, fresh⟩
  · intro left right first second l r equal
    apply env.separate l r
    exact (same l).trans (equal.trans (same r).symm)

/-- End one lexical scope. Values written in enclosing locals are retained;
the temporary's Core identifier must not shadow a tracked enclosing name. -/
theorem restoreScope (env : LocalEnv base completed nextValues)
    (freshName : values id = none)
    (locals : completed.locals = (before.bindLocal id value).locals) :
    LocalEnv base (restoreLocals before completed) (nextValues.restrict values) := by
  apply (env.restrict values).restore before
  intro queried result found
  obtain ⟨_, previous, present⟩ := LocalValues.of_restrict found
  have different : id ≠ queried := by
    intro same; subst queried; rw [freshName] at present; contradiction
  change completed.cellId? queried = before.cellId? queried
  have same : completed.cellId? queried = (before.bindLocal id value).cellId? queried := by
    simp only [State.cellId?, locals]
  exact same.trans (State.bindLocal_cellId_of_ne before queried id different value)

theorem assignI32 (env : LocalEnv base before values)
    (found : values id = some (.signed .i32 old))
    (right : RunsExpr program before expression (.signed .i32 operand) before)
    (operation : evalAssignValue program.target op (some (.signed .i32 old))
      (.signed .i32 operand) = .ok (.signed .i32 replacement)) :
    ∃ after, RunsExpr program before (.assign op (.local id) expression) .unit after ∧
      LocalEnv base after (values.set id (.signed .i32 replacement)) ∧
      DataFrame before after := by
  obtain ⟨cell, slot, _⟩ := env.fresh found
  obtain ⟨after, run, assigned, effect⟩ := RunsExpr.assignI32 slot (env.lookup found) right operation
  exact ⟨after, run, env.assignLocal found assigned, effect.heap, effect.world, effect.views⟩

theorem increment (env : LocalEnv base before values) {index : Nat}
    (found : values id = some (.signed .i32 index)) (fits : index + 1 < 2 ^ 31) :
    ∃ after, RunsExpr program before (.assign .add (.local id) (.value (.signed .i32 1))) .unit after ∧
      LocalEnv base after (values.set id (.signed .i32 (index + 1 : Nat))) ∧
      DataFrame before after := by
  apply env.assignI32 found (.ofStable .value rfl)
  simpa only [evalAssignValue, assignOpBinary?, Int.natCast_add, Int.natCast_one] using
    eval_i32_addNat program.target index 1 fits

/-- Assignment of any Value after an effectful RHS. A changed post-environment
must be proved, not inferred from the old environment. Native-view coherence
is the exact existing evaluator condition, never a scalar-only shortcut. -/
theorem assignSetAfter (env : LocalEnv base before values)
    (found : values id = some old) (readyEnv : LocalEnv base ready nextValues)
    (readyFound : nextValues id = some readyValue)
    (right : RunsExpr program before expression replacement ready)
    (synchronizable : valueMayContainI32ArrayView old = false ∧
      valueMayContainI32ArrayView replacement = false ∨ ready.i32ArrayViews = []) :
    ∃ after, RunsExpr program before (.assign .set (.local id) expression) .unit after ∧
      LocalEnv base after (nextValues.set id replacement) ∧
      DataFrame ready after := by
  obtain ⟨cell, slot, _⟩ := env.fresh found
  obtain ⟨after, run, assigned, effect⟩ := RunsExpr.assignCellAfter slot
    (cellEntry_of_local _ _ _ _ slot (env.lookup found)) right synchronizable
  exact ⟨after, run, readyEnv.assignLocal readyFound assigned, effect.heap, effect.world, effect.views⟩

end LocalEnv

end Lanius.Semantics
