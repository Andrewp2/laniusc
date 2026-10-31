import Lanius.Faithful.Safe.Inv
import Lanius.Faithful.Sim.Expr

/-! # Core's heap only grows on the subset, also when a run traps

`Grows st st'` (`Mini/Grows.lean`) for every subset statement and
effectful expression Core runs until it traps (`execStmt_trap_grows`,
`eff_trap_grows`): a trap passes outward the state its part trapped at, or
the state the parts before it completed at. The safety theorems use it to
bound the heap of every state a trapped run went through by its last one. -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State Completion evalExpr evalExprs evalMatchArms execStmt restoreLocals
  restoreOutcomeLocals)

theorem Grows.restore {a b : State} (c : State) (g : Grows a b) : Grows a (restoreLocals c b) := g

theorem Grows.unbind {a b : State} {bs : List (Nat × Value)} (g : Grows (a.bindLocals bs) b) : Grows a b :=
  (Grows.same (bindLocals_same bs a).1 (bindLocals_same bs a).2).trans g

theorem Grows.unbind1 {a b : State} {id : Nat} {v : Value} (g : Grows (a.bindLocal id v) b) : Grows a b :=
  Grows.unbind (bs := [(id, v)]) g

section
variable {P : Core.Program} {k : Nat} {st st' : State} {r : Lanius.Trap}

/-! ## Pure expressions -/

theorem local_trap_state {id : Nat} (run : evalExpr k P st (.local id) = .trapped r st') : st' = st := by
  cases k with
  | zero => simp [evalExpr] at run
  | succ k =>
    simp only [evalExpr] at run
    split at run
    · simp only [Semantics.Outcome.trapped.injEq] at run; exact run.2.symm
    · split at run <;> simp_all

/-- A subset expression that traps does so at the state it started from. -/
theorem _root_.Lanius.Mini.SrcExpr.trap_state (e : SrcExpr) :
    ∀ {k : Nat} {st : State} {r : Lanius.Trap} {st' : State}, evalExpr k P st e.toCore = .trapped r st' → st' = st := by
  induction e with
  | int _ | boolean _ | unsigned _ _ | null | char _ =>
    intro k st r st' run
    exact (value_trap run).elim
  | «local» id => intro k st r st' run; exact local_trap_state run
  | field id index =>
    intro k st r st' run
    cases k with
    | zero => simp [evalExpr] at run
    | succ k =>
      simp only [SrcExpr.toCore, evalExpr] at run
      split at run
      · rename_i baseRun
        have := eval_local_state baseRun
        subst this
        split at run <;> simp_all
      · rename_i baseRun
        have := eval_local_state baseRun
        subst this
        simp only [Semantics.Outcome.trapped.injEq] at run
        exact run.2.symm
      · rename_i baseRun
        simp only [Semantics.Outcome.trapped.injEq] at run
        rw [← run.2]
        exact local_trap_state baseRun
      all_goals simp at run
  | negate operand ih =>
    intro k st r st' run
    obtain ⟨j, -, sub | ⟨w, sub, -⟩⟩ := unary_trap_inv run
    · exact ih sub
    · exact operand.eval_state sub
  | «not» operand ih =>
    intro k st r st' run
    obtain ⟨j, -, sub | ⟨w, sub, -⟩⟩ := unary_trap_inv run
    · exact ih sub
    · exact operand.eval_state sub
  | cast ty operand ih =>
    intro k st r st' run
    obtain ⟨j, -, sub | ⟨w, sub, -⟩⟩ := cast_trap_inv run
    · exact ih sub
    · exact operand.eval_state sub
  | apply op left right ihl ihr =>
    intro k st r st' run
    by_cases isAnd : op = .logicalAnd
    · subst isAnd
      obtain ⟨j, -, lrun | ⟨l, lrun, -⟩ | ⟨s1, lrun, rrun⟩⟩ := logicalAnd_trap_inv run
      · exact ihl lrun
      · exact left.eval_state lrun
      · rw [ihr rrun]; exact left.eval_state lrun
    by_cases isOr : op = .logicalOr
    · subst isOr
      obtain ⟨j, -, lrun | ⟨l, lrun, -⟩ | ⟨s1, lrun, rrun⟩⟩ := logicalOr_trap_inv run
      · exact ihl lrun
      · exact left.eval_state lrun
      · rw [ihr rrun]; exact left.eval_state lrun
    obtain ⟨j, -, lrun | ⟨l, s1, lrun, rrun | ⟨rv, rrun, -⟩⟩⟩ :=
      binary_trap_inv (SrcOp.toCore_ne_and isAnd) (SrcOp.toCore_ne_or isOr) run
    · exact ihl lrun
    · rw [ihr rrun]; exact left.eval_state lrun
    · rw [right.eval_state rrun]; exact left.eval_state lrun

/-- Trapping, `e` leaves the state as it was. -/
def PureT (P : Core.Program) (e : Core.Expr) : Prop :=
  ∀ {fuel : Nat} {st : State} {r : Lanius.Trap} {st' : State}, evalExpr fuel P st e = .trapped r st' → st' = st

theorem exprs_trap_pure : ∀ (es : List Core.Expr), (∀ e ∈ es, PureExpr P e ∧ PureT P e) →
    ∀ {fuel : Nat} {st : State} {r : Lanius.Trap} {st' : State}, evalExprs fuel P st es = .trapped r st' → st' = st
  | [], _, fuel, st, r, st', run => (exprs_nil_trap run).elim
  | e :: es, pure, fuel, st, r, st', run => by
    obtain ⟨j, -, erun | ⟨v, s1, erun, esrun⟩⟩ := exprs_cons_trap_inv run
    · exact (pure e (List.mem_cons_self ..)).2 erun
    · have := (pure e (List.mem_cons_self ..)).1 erun
      subst this
      exact exprs_trap_pure es (fun x mem => pure x (List.mem_cons_of_mem _ mem)) esrun

theorem _root_.Lanius.Mini.SrcExpr.pure (e : SrcExpr) : PureExpr P e.toCore ∧ PureT P e.toCore :=
  ⟨fun run => e.eval_state run, fun run => e.trap_state run⟩

theorem value_pure {x : Value} : PureExpr P (.value x) ∧ PureT P (.value x) :=
  ⟨fun run => eval_value_state run, fun run => (value_trap run).elim⟩

theorem exprs_trap_state (es : List SrcExpr) {k : Nat} {st : State} {r : Lanius.Trap} {st' : State}
    (run : evalExprs k P st (es.map SrcExpr.toCore) = .trapped r st') : st' = st :=
  exprs_trap_pure _ (fun x mem => by
    obtain ⟨e, -, rfl⟩ := List.mem_map.mp mem
    exact e.pure) run

/-! ## Expressions with effects on the heap -/

theorem allocate_trapped {h h' : Memory.Heap} {size align : Nat} {r : Lanius.Trap}
    (ok : h.allocate size align = .trapped r h') : h' = h := by
  simp only [Memory.Heap.allocate] at ok
  split at ok
  · simp only [Memory.AllocationResult.trapped.injEq] at ok
    exact ok.2.symm
  split at ok <;> simp at ok

theorem alloc_trap_grows {size : SrcExpr} {shift : Nat}
    (run : evalExpr k P st (.alloc size.toCore (.value (.unsigned .usize (2 ^ shift)))) = .trapped r st') :
    Grows st st' := by
  cases k with
  | zero => simp [evalExpr] at run
  | succ k =>
    simp only [evalExpr] at run
    split at run
    · rename_i sizeRun
      have := size.eval_state sizeRun
      subst this
      split at run
      · rename_i alignRun
        have := eval_value_state alignRun
        subst this
        split at run
        · simp at run
        · simp at run
        · rename_i trapped
          simp only [Semantics.Outcome.trapped.injEq] at run
          obtain ⟨-, rfl⟩ := run
          exact Grows.same (allocate_trapped trapped) rfl
      · rename_i alignRun
        have := eval_value_state alignRun
        subst this
        simp only [Semantics.Outcome.trapped.injEq] at run
        obtain ⟨-, rfl⟩ := run
        exact Grows.refl _
      · rename_i alignRun
        exact (value_trap alignRun).elim
      all_goals simp at run
    · rename_i sizeRun
      have := size.eval_state sizeRun
      subst this
      simp only [Semantics.Outcome.trapped.injEq] at run
      obtain ⟨-, rfl⟩ := run
      exact Grows.refl _
    · rename_i sizeRun
      simp only [Semantics.Outcome.trapped.injEq] at run
      obtain ⟨-, rfl⟩ := run
      rw [size.trap_state sizeRun]
      exact Grows.refl _
    all_goals simp at run

theorem loadByte_trap_grows {pointer offset : SrcExpr}
    (run : evalExpr k P st (.loadByte pointer.toCore offset.toCore) = .trapped r st') : Grows st st' := by
  intro views
  cases k with
  | zero => simp [evalExpr] at run
  | succ k =>
    simp only [evalExpr] at run
    split at run
    · rename_i argsRun
      have := evalExprs_state [pointer, offset] argsRun
      subst this
      simp only [sync_ok views] at run
      split at run
      · simp at run
      · simp only [Semantics.Outcome.trapped.injEq] at run
        obtain ⟨-, rfl⟩ := run
        exact ⟨views, Nat.le_refl _⟩
    · rename_i argsRun
      have := evalExprs_state [pointer, offset] argsRun
      subst this
      simp only [Semantics.Outcome.trapped.injEq] at run
      obtain ⟨-, rfl⟩ := run
      exact ⟨views, Nat.le_refl _⟩
    · rename_i argsRun
      have := exprs_trap_state [pointer, offset] argsRun
      subst this
      simp only [Semantics.Outcome.trapped.injEq] at run
      obtain ⟨-, rfl⟩ := run
      exact ⟨views, Nat.le_refl _⟩
    all_goals simp at run

theorem storeByte_trap_grows {pointer offset value : SrcExpr}
    (run : evalExpr k P st (.storeByte pointer.toCore offset.toCore value.toCore) = .trapped r st') :
    Grows st st' := by
  intro views
  cases k with
  | zero => simp [evalExpr] at run
  | succ k =>
    simp only [evalExpr] at run
    split at run
    · rename_i argsRun
      have := evalExprs_state [pointer, offset, value] argsRun
      subst this
      simp only [sync_ok views] at run
      split at run
      · simp only [Semantics.Outcome.trapped.injEq] at run
        obtain ⟨-, rfl⟩ := run
        exact ⟨views, Nat.le_refl _⟩
      · rename_i heap stored
        split at run
        · simp at run
        · simp only [Semantics.Outcome.trapped.injEq] at run
          obtain ⟨-, rfl⟩ := run
          exact ⟨views, Nat.le_of_eq (storeByte_next stored).symm⟩
    · rename_i argsRun
      have := evalExprs_state [pointer, offset, value] argsRun
      subst this
      simp only [Semantics.Outcome.trapped.injEq] at run
      obtain ⟨-, rfl⟩ := run
      exact ⟨views, Nat.le_refl _⟩
    · rename_i argsRun
      have := exprs_trap_state [pointer, offset, value] argsRun
      subst this
      simp only [Semantics.Outcome.trapped.injEq] at run
      obtain ⟨-, rfl⟩ := run
      exact ⟨views, Nat.le_refl _⟩
    all_goals simp at run

theorem dealloc_trap_grows {pointer size : SrcExpr} {shift : Nat}
    (run : evalExpr k P st (.dealloc pointer.toCore size.toCore (.value (.unsigned .usize (2 ^ shift)))) =
      .trapped r st') : Grows st st' := by
  intro views
  have pure : ∀ x ∈ [pointer.toCore, size.toCore, Core.Expr.value (.unsigned .usize (2 ^ shift))],
      PureExpr P x ∧ PureT P x := fun x mem => by
    simp only [List.mem_cons, List.not_mem_nil, or_false] at mem
    rcases mem with rfl | rfl | rfl
    · exact pointer.pure
    · exact size.pure
    · exact value_pure
  cases k with
  | zero => simp [evalExpr] at run
  | succ k =>
    simp only [evalExpr] at run
    split at run
    · rename_i argsRun
      have := evalExprs_pure _ (fun x mem => (pure x mem).1) argsRun
      subst this
      simp only [sync_ok views] at run
      split at run
      · simp at run
      · simp only [Semantics.Outcome.trapped.injEq] at run
        obtain ⟨-, rfl⟩ := run
        exact ⟨views, Nat.le_refl _⟩
    · rename_i argsRun
      have := evalExprs_pure _ (fun x mem => (pure x mem).1) argsRun
      subst this
      simp only [Semantics.Outcome.trapped.injEq] at run
      obtain ⟨-, rfl⟩ := run
      exact ⟨views, Nat.le_refl _⟩
    · rename_i argsRun
      have := exprs_trap_pure _ pure argsRun
      subst this
      simp only [Semantics.Outcome.trapped.injEq] at run
      obtain ⟨-, rfl⟩ := run
      exact ⟨views, Nat.le_refl _⟩
    all_goals simp at run

theorem structValue_trap_state {id : Nat} {es : List SrcExpr}
    (run : evalExpr k P st (.structValue id (es.map SrcExpr.toCore)) = .trapped r st') : st' = st := by
  obtain ⟨j, -, argsRun⟩ := structValue_trap_inv run
  exact exprs_trap_state es argsRun

theorem enumValue_trap_state {id variant : Nat} {es : List SrcExpr}
    (run : evalExpr k P st (.enumValue id variant (es.map SrcExpr.toCore)) = .trapped r st') : st' = st := by
  obtain ⟨j, -, argsRun⟩ := enumValue_trap_inv run
  exact exprs_trap_state es argsRun

theorem matchArms_trap_same {value : Value} :
    ∀ (arms : List SrcArm) (id j : Nat) {k : Nat} {st : State} {r : Lanius.Trap} {st' : State},
      evalMatchArms k P st value (coreArms id j arms) = .trapped r st' →
      st'.heap = st.heap ∧ st'.i32ArrayViews = st.i32ArrayViews
  | [], _, _, k, st, r, st', run => by
    obtain ⟨-, rfl⟩ := arms_nil_trap (by simpa [coreArms] using run)
    exact ⟨rfl, rfl⟩
  | arm :: rest, id, j, k, st, r, st', run => by
    simp only [coreArms] at run
    obtain ⟨i, -, ⟨-, restRun⟩ | ⟨bs, s2, -, armRun, rfl⟩⟩ := arms_cons_trap_inv run
    · exact matchArms_trap_same rest id (j + 1) restRun
    · have := arm.value.trap_state armRun
      subst this
      exact bindLocals_same bs st

theorem matchValue_trap_grows {scrutinee id : Nat} {arms : List SrcArm}
    (run : evalExpr k P st (.matchValue (.local scrutinee) (coreArms id 0 arms)) = .trapped r st') :
    Grows st st' := by
  obtain ⟨j, -, srun | ⟨sv, s1, srun, armsRun⟩⟩ := matchValue_trap_inv run
  · rw [local_trap_state srun]; exact Grows.refl _
  · have := eval_local_state srun
    subst this
    have := matchArms_trap_same arms id 0 armsRun
    exact Grows.same this.1 this.2

/-- Trapped arms whose bodies leave the state as it was leave the heap as it was. -/
theorem pureArms_trap_same {value : Value} : ∀ (arms : List (Core.Pattern × Core.Expr)),
    (∀ a ∈ arms, ∀ {k : Nat} {st : State} {r : Lanius.Trap} {st' : State},
      evalExpr k P st a.2 = .trapped r st' → st' = st) →
    ∀ {k : Nat} {st : State} {r : Lanius.Trap} {st' : State},
      evalMatchArms k P st value arms = .trapped r st' → st'.heap = st.heap ∧ st'.i32ArrayViews = st.i32ArrayViews
  | [], _, k, st, r, st', run => by
    obtain ⟨-, rfl⟩ := arms_nil_trap run
    exact ⟨rfl, rfl⟩
  | (pat, body) :: rest, pure, k, st, r, st', run => by
    obtain ⟨i, -, ⟨-, restRun⟩ | ⟨bs, s2, -, armRun, rfl⟩⟩ := arms_cons_trap_inv run
    · exact pureArms_trap_same rest (fun a mem => pure a (List.mem_cons_of_mem _ mem)) restRun
    · have := pure (pat, body) (List.mem_cons_self ..) armRun
      subst this
      exact bindLocals_same bs st

theorem matchPure_trap_grows {scrutinee : Nat} {arms : List (Core.Pattern × Core.Expr)}
    (pure : ∀ a ∈ arms, ∀ {k : Nat} {st : State} {r : Lanius.Trap} {st' : State},
      evalExpr k P st a.2 = .trapped r st' → st' = st)
    (run : evalExpr k P st (.matchValue (.local scrutinee) arms) = .trapped r st') : Grows st st' := by
  obtain ⟨j, -, srun | ⟨sv, s1, srun, armsRun⟩⟩ := matchValue_trap_inv run
  · rw [local_trap_state srun]; exact Grows.refl _
  · have := eval_local_state srun
    subst this
    have := pureArms_trap_same arms pure armsRun
    exact Grows.same this.1 this.2

theorem value_no_trap {x : Value} (run : evalExpr k P st (.value x) = .trapped r st') : False := by
  cases k <;> simp [evalExpr] at run

theorem sliceFrom_trap_grows {element : SrcType} {pointer length : SrcExpr}
    (run : evalExpr k P st (element.sliceFrom pointer.toCore length.toCore) = .trapped r st') :
    Grows st st' := by
  cases k with
  | zero => cases element <;> simp [evalExpr] at run
  | succ k =>
    cases element <;> simp only [SrcType.sliceFrom, evalExpr] at run
    all_goals
      split at run
      · rename_i pointerRun
        have := pointer.eval_state pointerRun
        subst this
        split at run
        · rename_i lengthRun
          have := length.eval_state lengthRun
          subst this
          simp only [Semantics.mapRawI32Slice, Semantics.mapRawNominalSlice] at run
          repeat' split at run
          all_goals first
            | (simp only [Semantics.Outcome.trapped.injEq] at run
               obtain ⟨-, rfl⟩ := run
               exact Grows.refl _)
            | simp at run
        · rename_i lengthRun
          have := length.eval_state lengthRun
          subst this
          simp only [Semantics.Outcome.trapped.injEq] at run
          obtain ⟨-, rfl⟩ := run
          exact Grows.refl _
        · rename_i lengthRun
          simp only [Semantics.Outcome.trapped.injEq] at run
          obtain ⟨-, rfl⟩ := run
          rw [length.trap_state lengthRun]
          exact Grows.refl _
        all_goals simp at run
      · rename_i pointerRun
        have := pointer.eval_state pointerRun
        subst this
        simp only [Semantics.Outcome.trapped.injEq] at run
        obtain ⟨-, rfl⟩ := run
        exact Grows.refl _
      · rename_i pointerRun
        simp only [Semantics.Outcome.trapped.injEq] at run
        obtain ⟨-, rfl⟩ := run
        rw [pointer.trap_state pointerRun]
        exact Grows.refl _
      all_goals simp at run

/-- Reading `slice[index]` that traps grows as its index does. -/
theorem index_trap_grows {slice : Nat} {index : Core.Expr}
    (hi : ∀ {v1 st2}, evalExpr k P st index = .done v1 st2 → Grows st st2)
    (hiT : ∀ {r1 st2}, evalExpr k P st index = .trapped r1 st2 → Grows st st2)
    (run : evalExpr (k + 1) P st (.index (.local slice) index) = .trapped r st') : Grows st st' := by
  simp only [evalExpr] at run
  split at run
  all_goals first
    | (rename_i baseRun; have := eval_local_state baseRun; subst this)
    | (rename_i baseRun
       simp only [Semantics.Outcome.trapped.injEq] at run
       obtain ⟨-, rfl⟩ := run
       rw [local_trap_state baseRun]
       exact Grows.refl _)
    | simp at run
  all_goals first
    | (simp only [Semantics.Outcome.trapped.injEq] at run
       obtain ⟨-, rfl⟩ := run
       exact Grows.refl _)
    | (split at run
       all_goals first
         | (rename_i indexRun
            have grown := hi indexRun
            repeat' split at run
            all_goals first
              | (simp only [Semantics.Outcome.trapped.injEq] at run; obtain ⟨-, rfl⟩ := run; exact grown)
              | simp at run)
         | (rename_i indexRun
            simp only [Semantics.Outcome.trapped.injEq] at run
            obtain ⟨-, rfl⟩ := run
            exact hiT indexRun)
         | simp at run)
    | simp at run

theorem index_trap_state {slice : Nat} {index : SrcExpr}
    (run : evalExpr k P st (.index (.local slice) index.toCore) = .trapped r st') : Grows st st' := by
  cases k with
  | zero => simp [evalExpr] at run
  | succ k =>
    exact index_trap_grows (fun r => by rw [index.eval_state r]; exact Grows.refl _)
      (fun r => by rw [index.trap_state r]; exact Grows.refl _) run

theorem stride_trap_state {slice : Nat}
    (run : evalExpr k P st (.intrinsic .sliceStride (.local slice)) = .trapped r st') : st' = st := by
  cases k with
  | zero => simp [evalExpr] at run
  | succ k =>
    simp only [evalExpr] at run
    split at run
    · rename_i localRun
      have := eval_local_state localRun
      subst this
      repeat' split at run
      all_goals first
        | (simp only [Semantics.Outcome.trapped.injEq] at run; exact run.2.symm)
        | simp at run
    · rename_i localRun
      simp only [Semantics.Outcome.trapped.injEq] at run
      rw [← run.2]
      exact local_trap_state localRun
    all_goals simp at run

theorem assert_trap_grows {e : Core.Expr}
    (hd : ∀ {j v st2}, j < k → evalExpr j P st e = .done v st2 → Grows st st2)
    (ht : ∀ {j r1 st2}, j < k → evalExpr j P st e = .trapped r1 st2 → Grows st st2)
    (run : evalExpr k P st (.intrinsic .assert e) = .trapped r st') : Grows st st' := by
  obtain ⟨j, rfl, erun | ⟨v, erun, -⟩⟩ := assert_trap_inv run
  · exact ht (Nat.lt_succ_self j) erun
  · exact hd (Nat.lt_succ_self j) erun

/-! ## Places and assignments -/

theorem evalPlace_local_trap {acc : Semantics.PlaceAccess} {id : Nat} {r1 : Lanius.Trap}
    (run : Semantics.evalPlace k P st acc (.local id) = .trapped r1 st') : st' = st := by
  cases k with
  | zero => simp [Semantics.evalPlace] at run
  | succ k =>
    simp only [Semantics.evalPlace] at run
    repeat' split at run
    all_goals first
      | (simp only [Semantics.Outcome.trapped.injEq] at run; exact run.2.symm)
      | simp at run

theorem evalPlace_field_trap {id index : Nat} {r1 : Lanius.Trap}
    (run : Semantics.evalPlace k P st .address (.field (.local id) index) = .trapped r1 st') : st' = st := by
  cases k with
  | zero => simp [Semantics.evalPlace] at run
  | succ k =>
    simp only [Semantics.evalPlace] at run
    split at run
    · rename_i resolved next baseRun
      obtain ⟨rfl, raw⟩ := evalPlace_local baseRun
      rw [raw] at run
      simp only at run
      repeat' split at run
      all_goals first
        | (simp only [Semantics.Outcome.trapped.injEq] at run; exact run.2.symm)
        | simp at run
    · rename_i baseRun
      simp only [Semantics.Outcome.trapped.injEq] at run
      rw [← run.2]
      exact evalPlace_local_trap baseRun
    all_goals simp at run

/-- Resolving `slice[index]` for a write that traps grows as its index does. -/
theorem evalPlace_index_trap {slice : Nat} {index : Core.Expr} {r1 : Lanius.Trap}
    (hi : ∀ {v st2}, evalExpr k P st index = .done v st2 → Grows st st2)
    (hiT : ∀ {r2 st2}, evalExpr k P st index = .trapped r2 st2 → Grows st st2)
    (run : Semantics.evalPlace (k + 1) P st .address (.index (.local slice) index) = .trapped r1 st') :
    Grows st st' := by
  simp only [Semantics.evalPlace] at run
  split at run
  · rename_i resolved afterBase baseRun
    have := evalPlace_readLocal baseRun
    subst this
    split at run
    all_goals first
      | (simp only [Semantics.Outcome.trapped.injEq] at run
         obtain ⟨-, rfl⟩ := run
         exact Grows.refl _)
      | (split at run
         all_goals first
           | (rename_i indexRun
              have grown := hi indexRun
              repeat' split at run
              all_goals first
                | (simp only [Semantics.Outcome.trapped.injEq] at run; obtain ⟨-, rfl⟩ := run; exact grown)
                | simp at run)
           | (rename_i indexRun
              simp only [Semantics.Outcome.trapped.injEq] at run
              obtain ⟨-, rfl⟩ := run
              exact hiT indexRun)
           | simp at run)
  · rename_i baseRun
    simp only [Semantics.Outcome.trapped.injEq] at run
    obtain ⟨-, rfl⟩ := run
    rw [evalPlace_local_trap baseRun]
    exact Grows.refl _
  all_goals simp at run

/-- `place = e` that traps, where resolving `place` and evaluating `e` grow,
done or trapped. -/
theorem assign_trap_grows {place : Core.Place} {e : Core.Expr}
    (placeOk : ∀ {r1 st1}, Semantics.evalPlace k P st .address place = .done r1 st1 → Grows st st1)
    (placeT : ∀ {r1 st1}, Semantics.evalPlace k P st .address place = .trapped r1 st1 → Grows st st1)
    (value : ∀ {st1 rv st2}, evalExpr k P st1 e = .done rv st2 → Grows st1 st2)
    (valueT : ∀ {st1 r1 st2}, evalExpr k P st1 e = .trapped r1 st2 → Grows st1 st2)
    (run : evalExpr (k + 1) P st (.assign .set place e) = .trapped r st') : Grows st st' := by
  simp only [evalExpr] at run
  split at run
  · rename_i resolved afterPlace placeRun
    have g1 := placeOk placeRun
    split at run
    · rename_i rv afterValue valueRun
      have g2 := g1.trans (value valueRun)
      split at run
      · simp only [Semantics.Outcome.trapped.injEq] at run
        obtain ⟨-, rfl⟩ := run
        exact g2
      rename_i result _
      intro views
      obtain ⟨views2, next2⟩ := g2 views
      cases raw : resolved.raw with
      | none =>
        simp only [Semantics.writeResolvedPlaceNative, raw] at run
        split at run
        · rename_i assigned written
          obtain ⟨heap3, views3⟩ := writeResolved_same written
          have synced := sync_ok (st := assigned) (views3.trans views2)
          simp only [synced, ite_self] at run
          simp at run
        · simp only [Semantics.Outcome.trapped.injEq] at run
          obtain ⟨-, rfl⟩ := run
          exact ⟨views2, next2⟩
      | some pair =>
        simp only [Semantics.writeResolvedPlaceNative, raw] at run
        split at run
        · rename_i assigned written
          obtain ⟨heap3, stored, wrapped⟩ := except_bind_ok written
          simp only [pure, Except.pure, Except.ok.injEq] at wrapped
          subst wrapped
          have synced := syncFrom_ok (st := { afterValue with heap := heap3 }) views2
          simp only [synced, ite_self] at run
          simp at run
        · simp only [Semantics.Outcome.trapped.injEq] at run
          obtain ⟨-, rfl⟩ := run
          exact ⟨views2, next2⟩
    · rename_i valueRun
      simp only [Semantics.Outcome.trapped.injEq] at run
      obtain ⟨-, rfl⟩ := run
      exact g1.trans (valueT valueRun)
    all_goals simp at run
  · rename_i placeRun
    simp only [Semantics.Outcome.trapped.injEq] at run
    obtain ⟨-, rfl⟩ := run
    exact placeT placeRun
  all_goals simp at run

theorem letLocal_trap_grows {f : Nat} {id : Nat} {ty : Core.Ty} {init : Core.Expr} {body : Core.Stmt}
    (initD : ∀ {v s1}, evalExpr f P st init = .done v s1 → Grows st s1)
    (initT : ∀ {r1 s1}, evalExpr f P st init = .trapped r1 s1 → Grows st s1)
    (bodyT : ∀ {s r1 s2}, execStmt f P s body = .trapped r1 s2 → Grows s s2)
    (run : execStmt (f + 1) P st (.letLocal id ty init body) = .trapped r st') : Grows st st' := by
  obtain ⟨j, hj, irun | ⟨v, s1, s2, irun, brun, rfl⟩⟩ := letLocal_trap_inv run
  · obtain rfl : f = j := Nat.succ.inj hj
    exact initT irun
  · obtain rfl : f = j := Nat.succ.inj hj
    exact (initD irun).trans (Grows.restore s1 (Grows.unbind1 (bodyT brun)))

end

/-! ## Statements and effectful expressions -/

/-- Trapped runs of every subset statement with less fuel grow. -/
def GrowsBelowT (sp : SrcProgram) (fuel : Nat) : Prop :=
  ∀ m < fuel, ∀ {st : State} {s : SrcStmt} {r : Lanius.Trap} {st' : State},
    execStmt m sp.toCore st s.toCore = .trapped r st' → Grows st st'

/-- Trapped runs of every effectful expression with at most `k` fuel grow. -/
def EffGrowsT (sp : SrcProgram) (k : Nat) : Prop :=
  ∀ m ≤ k, ∀ {st : State} {e : SrcEff} {r : Lanius.Trap} {st' : State},
    evalExpr m sp.toCore st e.toCore = .trapped r st' → Grows st st'

theorem EffGrowsT.lower {sp : SrcProgram} {k j : Nat} (ih : EffGrowsT sp k) (le : j ≤ k) : EffGrowsT sp j :=
  fun m lt => ih m (Nat.le_trans lt le)

section
variable {sp : SrcProgram} {st st' : State} {r : Lanius.Trap}

/-- A call that traps, whose arguments grow done or trapped. -/
theorem call_trap_grows {k : Nat} (ih : GrowsBelow sp k) (ihT : GrowsBelowT sp k)
    {callee : Nat} {args : List Core.Expr}
    (argsDone : ∀ {j vs s}, j < k → evalExprs j sp.toCore st args = .done vs s → Grows st s)
    (argsTrap : ∀ {j r s}, j < k → evalExprs j sp.toCore st args = .trapped r s → Grows st s)
    (run : evalExpr k sp.toCore st (.call callee args) = .trapped r st') : Grows st st' := by
  obtain ⟨j, rfl, h⟩ := call_trap_inv run
  rcases h with argsRun | ⟨values, afterArgs, argsRun, h⟩
  · exact argsTrap (Nat.lt_succ_self j) argsRun
  cases h with
  | inl h => rw [h.1]; exact argsDone (Nat.lt_succ_self j) argsRun
  | inr h =>
    obtain ⟨f, completed, -, -, same, bodyRun⟩ := h
    rw [same]
    have entry := bindLocals_same (paramBindings f.params values) { afterArgs with locals := [] }
    refine (argsDone (Nat.lt_succ_self j) argsRun).trans
      (Grows.restore afterArgs ((Grows.same entry.1 entry.2).trans ?_))
    rcases bodyRun with bodyRun | ⟨c, bodyRun, -⟩
    · exact ihT j (Nat.lt_succ_self j) bodyRun
    · exact ih j (Nat.lt_succ_self j) bodyRun

theorem srcCall_trap_grows {k : Nat} (ih : GrowsBelow sp k) (ihT : GrowsBelowT sp k) {callee : Nat}
    {args : List SrcExpr} (run : evalExpr k sp.toCore st (.call callee (args.map SrcExpr.toCore)) = .trapped r st') :
    Grows st st' :=
  call_trap_grows ih ihT (fun _ r => by rw [evalExprs_state args r]; exact Grows.refl _)
    (fun _ r => by rw [exprs_trap_state args r]; exact Grows.refl _) run

theorem effs_trap_grows : ∀ (es : List SrcEff) {k : Nat}, EffGrows sp k → EffGrowsT sp k →
    ∀ {st : State} {r : Lanius.Trap} {st' : State},
      evalExprs k sp.toCore st (SrcEff.toCoreList es) = .trapped r st' → Grows st st'
  | [], k, _, _, st, r, st', run => by
    simp only [SrcEff.toCoreList] at run
    exact (exprs_nil_trap run).elim
  | e :: es, k, ih, ihT, st, r, st', run => by
    simp only [SrcEff.toCoreList] at run
    obtain ⟨j, rfl, erun | ⟨v, s1, erun, esrun⟩⟩ := exprs_cons_trap_inv run
    · exact ihT j (Nat.le_succ j) erun
    · exact (ih j (Nat.le_succ j) erun).trans
        (effs_trap_grows es (ih.lower (Nat.le_succ j)) (ihT.lower (Nat.le_succ j)) esrun)

theorem effArms_trap_grows {value : Value} :
    ∀ (binders : List (List Nat)) (values : List SrcEff) (id j : Nat) {k : Nat}, EffGrowsT sp k →
      ∀ {st : State} {r : Lanius.Trap} {st' : State},
        evalMatchArms k sp.toCore st value (SrcEff.coreArms id j binders values) = .trapped r st' →
        Grows st st'
  | [], _, _, _, k, _, st, r, st', run => by
    simp only [SrcEff.coreArms] at run
    obtain ⟨-, rfl⟩ := arms_nil_trap run
    exact Grows.refl _
  | _ :: _, [], _, _, k, _, st, r, st', run => by
    simp only [SrcEff.coreArms] at run
    obtain ⟨-, rfl⟩ := arms_nil_trap run
    exact Grows.refl _
  | bs :: rest, arm :: values, id, j, k, ihT, st, r, st', run => by
    simp only [SrcEff.coreArms] at run
    obtain ⟨i, rfl, ⟨-, restRun⟩ | ⟨bindings, s2, -, armRun, rfl⟩⟩ := arms_cons_trap_inv run
    · exact effArms_trap_grows rest values id (j + 1) (ihT.lower (Nat.le_succ i)) restRun
    · exact Grows.restore st (Grows.unbind (ihT i (Nat.le_succ i) armRun))

theorem eff_trap_step {k : Nat} (ih : GrowsBelow sp (k + 1)) (ihT : GrowsBelowT sp (k + 1))
    (ihe : EffGrows sp k) (iheT : EffGrowsT sp k) {e : SrcEff}
    (run : evalExpr (k + 1) sp.toCore st e.toCore = .trapped r st') : Grows st st' := by
  have sub : ∀ {st1 : State} {e1 : SrcEff} {v1 : Value} {st2 : State},
      evalExpr k sp.toCore st1 e1.toCore = .done v1 st2 → Grows st1 st2 := fun r => ihe k (Nat.le_refl _) r
  have subT : ∀ {st1 : State} {e1 : SrcEff} {r1 : Lanius.Trap} {st2 : State},
      evalExpr k sp.toCore st1 e1.toCore = .trapped r1 st2 → Grows st1 st2 := fun r => iheT k (Nat.le_refl _) r
  cases e with
  | ePure e =>
    rw [e.trap_state run]
    exact Grows.refl _
  | eCall callee args =>
    simp only [SrcEff.toCore] at run
    exact call_trap_grows ih ihT (fun lt r => effs_grows args (ihe.lower (Nat.le_of_lt_succ lt)) r)
      (fun lt r => effs_trap_grows args (ihe.lower (Nat.le_of_lt_succ lt)) (iheT.lower (Nat.le_of_lt_succ lt)) r) run
  | eApply op left right =>
    by_cases isAnd : op = .logicalAnd
    · subst isAnd
      simp only [SrcEff.toCore, SrcOp.toCore] at run
      obtain ⟨j, hj, lrun | ⟨l, lrun, -⟩ | ⟨s1, lrun, rrun⟩⟩ := logicalAnd_trap_inv run
      all_goals obtain rfl : k = j := Nat.succ.inj hj
      · exact subT lrun
      · exact sub lrun
      · exact (sub lrun).trans (subT rrun)
    by_cases isOr : op = .logicalOr
    · subst isOr
      simp only [SrcEff.toCore, SrcOp.toCore] at run
      obtain ⟨j, hj, lrun | ⟨l, lrun, -⟩ | ⟨s1, lrun, rrun⟩⟩ := logicalOr_trap_inv run
      all_goals obtain rfl : k = j := Nat.succ.inj hj
      · exact subT lrun
      · exact sub lrun
      · exact (sub lrun).trans (subT rrun)
    simp only [SrcEff.toCore] at run
    obtain ⟨j, hj, lrun | ⟨l, s1, lrun, rrun | ⟨rv, rrun, -⟩⟩⟩ :=
      binary_trap_inv (SrcOp.toCore_ne_and isAnd) (SrcOp.toCore_ne_or isOr) run
    all_goals obtain rfl : k = j := Nat.succ.inj hj
    · exact subT lrun
    · exact (sub lrun).trans (subT rrun)
    · exact (sub lrun).trans (sub rrun)
  | eDivide op left right =>
    simp only [SrcEff.toCore] at run
    obtain ⟨j, hj, lrun | ⟨l, s1, lrun, rrun | ⟨rv, rrun, -⟩⟩⟩ :=
      binary_trap_inv (by cases op <;> simp [SrcDivOp.toCore]) (by cases op <;> simp [SrcDivOp.toCore]) run
    all_goals obtain rfl : k = j := Nat.succ.inj hj
    · exact subT lrun
    · exact (sub lrun).trans (subT rrun)
    · exact (sub lrun).trans (sub rrun)
  | eNeg operand =>
    simp only [SrcEff.toCore] at run
    obtain ⟨j, hj, orun | ⟨w, orun, -⟩⟩ := unary_trap_inv run
    all_goals obtain rfl : k = j := Nat.succ.inj hj
    · exact subT orun
    · exact sub orun
  | eNot operand =>
    simp only [SrcEff.toCore] at run
    obtain ⟨j, hj, orun | ⟨w, orun, -⟩⟩ := unary_trap_inv run
    all_goals obtain rfl : k = j := Nat.succ.inj hj
    · exact subT orun
    · exact sub orun
  | eCast ty operand =>
    simp only [SrcEff.toCore] at run
    obtain ⟨j, hj, orun | ⟨w, orun, -⟩⟩ := cast_trap_inv run
    all_goals obtain rfl : k = j := Nat.succ.inj hj
    · exact subT orun
    · exact sub orun
  | eIndex slice index =>
    simp only [SrcEff.toCore] at run
    exact index_trap_grows (fun r => sub r) (fun r => subT r) run
  | eStride slice =>
    simp only [SrcEff.toCore] at run
    rw [stride_trap_state run]
    exact Grows.refl _
  | eStruct ty fields =>
    simp only [SrcEff.toCore] at run
    obtain ⟨j, hj, argsRun⟩ := structValue_trap_inv run
    obtain rfl : k = j := Nat.succ.inj hj
    exact effs_trap_grows fields ihe iheT argsRun
  | eVariant ty variant fields =>
    simp only [SrcEff.toCore] at run
    obtain ⟨j, hj, argsRun⟩ := enumValue_trap_inv run
    obtain rfl : k = j := Nat.succ.inj hj
    exact effs_trap_grows fields ihe iheT argsRun
  | eMatch scrutinee ety ty binders values =>
    simp only [SrcEff.toCore] at run
    obtain ⟨j, hj, srun | ⟨sv, s1, srun, armsRun⟩⟩ := matchValue_trap_inv run
    all_goals obtain rfl : k = j := Nat.succ.inj hj
    · exact subT srun
    · exact (sub srun).trans (effArms_trap_grows binders values ety.typeId 0 iheT armsRun)

/-- Every effectful expression Core runs until it traps grows the heap. -/
theorem eff_trap_grows : ∀ k, GrowsBelow sp k → GrowsBelowT sp k → EffGrowsT sp k
  | 0, _, _ => fun m le => by
    intro st e r st' run
    rw [Nat.le_zero.mp le] at run
    simp [evalExpr] at run
  | k + 1, ih, ihT => fun m le => by
    intro st e r st' run
    have ih' : GrowsBelow sp k := fun j lt' => ih j (Nat.lt_succ_of_lt lt')
    have ihT' : GrowsBelowT sp k := fun j lt' => ihT j (Nat.lt_succ_of_lt lt')
    rcases Nat.lt_succ_iff_lt_or_eq.mp (Nat.lt_succ_of_le le) with lt | rfl
    · exact eff_trap_grows k ih' ihT' m (Nat.le_of_lt_succ lt) run
    · exact eff_trap_step ih ihT (eff_grows k ih') (eff_trap_grows k ih' ihT') run

theorem grows_trap_step {fuel : Nat} (ih : GrowsBelow sp fuel) (ihT : GrowsBelowT sp fuel) {s : SrcStmt}
    (run : execStmt fuel sp.toCore st s.toCore = .trapped r st') : Grows st st' := by
  cases fuel with
  | zero => simp [execStmt] at run
  | succ f =>
    have below : ∀ {st : State} {s : SrcStmt} {c : Completion} {st' : State},
        execStmt f sp.toCore st s.toCore = .done c st' → Grows st st' :=
      fun r => ih f (Nat.lt_succ_self f) r
    have belowT : ∀ {st : State} {s : SrcStmt} {r : Lanius.Trap} {st' : State},
        execStmt f sp.toCore st s.toCore = .trapped r st' → Grows st st' :=
      fun r => ihT f (Nat.lt_succ_self f) r
    have ihf : GrowsBelow sp f := fun m lt => ih m (Nat.lt_succ_of_lt lt)
    have ihfT : GrowsBelowT sp f := fun m lt => ihT m (Nat.lt_succ_of_lt lt)
    have effD := eff_grows f ihf
    have effT := eff_trap_grows f ihf ihfT
    have pureD : ∀ {e : SrcExpr} {k st v st'}, evalExpr k sp.toCore st e.toCore = .done v st' → Grows st st' :=
      fun {e k st v st'} r => by rw [e.eval_state r]; exact Grows.refl _
    have pureT : ∀ {e : SrcExpr} {k st r st'}, evalExpr k sp.toCore st e.toCore = .trapped r st' → Grows st st' :=
      fun {e k st r st'} run => by rw [e.trap_state run]; exact Grows.refl _
    cases s with
    | nop => exact (skip_trap run).elim
    | «let» id ty value body =>
      exact letLocal_trap_grows (fun r => pureD r) (fun r => pureT r) (fun r => belowT (s := body) r) run
    | letStruct id ty fields body =>
      exact letLocal_trap_grows (fun r => by rw [structValue_state r]; exact Grows.refl _)
        (fun r => by rw [structValue_trap_state r]; exact Grows.refl _) (fun r => belowT (s := body) r) run
    | letCall id ty callee args body =>
      exact letLocal_trap_grows (fun r => call_grows ihf r) (fun r => srcCall_trap_grows ihf ihfT r)
        (fun r => belowT (s := body) r) run
    | letEnum id ty variant payload body =>
      exact letLocal_trap_grows (fun r => by rw [enumValue_state r]; exact Grows.refl _)
        (fun r => by rw [enumValue_trap_state r]; exact Grows.refl _) (fun r => belowT (s := body) r) run
    | letMatch id ty scrutinee enumId arms body =>
      exact letLocal_trap_grows (fun r => matchValue_grows r) (fun r => matchValue_trap_grows r)
        (fun r => belowT (s := body) r) run
    | letAlloc id size shift body =>
      exact letLocal_trap_grows (fun r => alloc_grows r) (fun r => alloc_trap_grows r)
        (fun r => belowT (s := body) r) run
    | letLoad id pointer offset body =>
      exact letLocal_trap_grows (fun r => loadByte_grows r) (fun r => loadByte_trap_grows r)
        (fun r => belowT (s := body) r) run
    | letSlice id element pointer length body =>
      exact letLocal_trap_grows (fun r => sliceFrom_grows r) (fun r => sliceFrom_trap_grows r)
        (fun r => belowT (s := body) r) run
    | letIndex id ty slice index body =>
      exact letLocal_trap_grows (fun r => by rw [index_state r]; exact Grows.refl _)
        (fun r => index_trap_state r) (fun r => belowT (s := body) r) run
    | letEval id ty value body =>
      exact letLocal_trap_grows (fun r => effD f (Nat.le_refl _) r) (fun r => effT f (Nat.le_refl _) r)
        (fun r => belowT (s := body) r) run
    | set id value =>
      obtain ⟨j, hj, erun⟩ := expression_trap_inv run
      obtain rfl : f = j := Nat.succ.inj hj
      cases f with
      | zero => simp [evalExpr] at erun
      | succ k =>
        exact assign_trap_grows (fun r => by rw [(evalPlace_local r).1]; exact Grows.refl _)
          (fun r => by rw [evalPlace_local_trap r]; exact Grows.refl _) (fun r => pureD r) (fun r => pureT r) erun
    | setField id index value =>
      obtain ⟨j, hj, erun⟩ := expression_trap_inv run
      obtain rfl : f = j := Nat.succ.inj hj
      cases f with
      | zero => simp [evalExpr] at erun
      | succ k =>
        exact assign_trap_grows (fun r => by rw [(evalPlace_field r).1]; exact Grows.refl _)
          (fun r => by rw [evalPlace_field_trap r]; exact Grows.refl _) (fun r => pureD r) (fun r => pureT r) erun
    | setCall id callee args =>
      obtain ⟨j, hj, erun⟩ := expression_trap_inv run
      obtain rfl : f = j := Nat.succ.inj hj
      cases f with
      | zero => simp [evalExpr] at erun
      | succ k =>
        have ihk : GrowsBelow sp k := fun m lt => ihf m (Nat.lt_succ_of_lt lt)
        have ihkT : GrowsBelowT sp k := fun m lt => ihfT m (Nat.lt_succ_of_lt lt)
        exact assign_trap_grows (fun r => by rw [(evalPlace_local r).1]; exact Grows.refl _)
          (fun r => by rw [evalPlace_local_trap r]; exact Grows.refl _) (fun r => call_grows ihk r)
          (fun r => srcCall_trap_grows ihk ihkT r) erun
    | setIndex slice index value =>
      obtain ⟨j, hj, erun⟩ := expression_trap_inv run
      obtain rfl : f = j := Nat.succ.inj hj
      cases f with
      | zero => simp [evalExpr] at erun
      | succ k =>
        refine assign_trap_grows (fun r => by rw [evalPlace_index r]; exact Grows.refl _) (fun r => ?_)
          (fun r => pureD r) (fun r => pureT r) erun
        cases k with
        | zero => simp [Semantics.evalPlace] at r
        | succ k => exact evalPlace_index_trap (fun r => pureD r) (fun r => pureT r) r
    | setEval id value =>
      obtain ⟨j, hj, erun⟩ := expression_trap_inv run
      obtain rfl : f = j := Nat.succ.inj hj
      cases f with
      | zero => simp [evalExpr] at erun
      | succ k =>
        exact assign_trap_grows (fun r => by rw [(evalPlace_local r).1]; exact Grows.refl _)
          (fun r => by rw [evalPlace_local_trap r]; exact Grows.refl _)
          (fun r => effD k (Nat.le_succ k) r) (fun r => effT k (Nat.le_succ k) r) erun
    | setIndexEval slice index value =>
      obtain ⟨j, hj, erun⟩ := expression_trap_inv run
      obtain rfl : f = j := Nat.succ.inj hj
      cases f with
      | zero => simp [evalExpr] at erun
      | succ k =>
        cases k with
        | zero => simp [evalExpr, Semantics.evalPlace] at erun
        | succ k =>
          exact assign_trap_grows
            (fun r => evalPlace_index_grows (fun r => effD k (by omega) r) r)
            (fun r => evalPlace_index_trap (fun r => effD k (by omega) r) (fun r => effT k (by omega) r) r)
            (fun r => effD (k + 1) (Nat.le_succ _) r) (fun r => effT (k + 1) (Nat.le_succ _) r) erun
    | setFieldEval id index value =>
      obtain ⟨j, hj, erun⟩ := expression_trap_inv run
      obtain rfl : f = j := Nat.succ.inj hj
      cases f with
      | zero => simp [evalExpr] at erun
      | succ k =>
        exact assign_trap_grows (fun r => by rw [(evalPlace_field r).1]; exact Grows.refl _)
          (fun r => by rw [evalPlace_field_trap r]; exact Grows.refl _)
          (fun r => effD k (Nat.le_succ k) r) (fun r => effT k (Nat.le_succ k) r) erun
    | setByte pointer offset value =>
      obtain ⟨j, -, erun⟩ := expression_trap_inv run
      exact storeByte_trap_grows erun
    | free pointer size shift =>
      obtain ⟨j, -, erun⟩ := expression_trap_inv run
      exact dealloc_trap_grows erun
    | discard value =>
      obtain ⟨j, hj, erun⟩ := expression_trap_inv run
      obtain rfl : f = j := Nat.succ.inj hj
      exact effT f (Nat.le_refl _) erun
    | assert condition =>
      obtain ⟨j, hj, erun⟩ := expression_trap_inv run
      obtain rfl : f = j := Nat.succ.inj hj
      exact assert_trap_grows (fun lt r => effD _ (Nat.le_of_lt lt) r) (fun lt r => effT _ (Nat.le_of_lt lt) r) erun
    | «then» first second =>
      obtain ⟨j, hj, frun | ⟨s1, frun, srun⟩⟩ := sequence_trap_inv run
      all_goals obtain rfl : f = j := Nat.succ.inj hj
      · exact belowT (s := first) frun
      · exact (below (s := first) frun).trans (belowT (s := second) srun)
    | «if» condition thenBranch elseBranch =>
      obtain ⟨j, hj, crun | ⟨v, crun, -⟩ | ⟨x, s1, crun, brun⟩⟩ := if_trap_inv run
      all_goals obtain rfl : f = j := Nat.succ.inj hj
      · exact pureT crun
      · exact pureD crun
      · refine (pureD crun).trans ?_
        cases x
        · exact belowT (s := elseBranch) brun
        · exact belowT (s := thenBranch) brun
    | ifEval condition thenBranch elseBranch =>
      obtain ⟨j, hj, crun | ⟨v, crun, -⟩ | ⟨x, s1, crun, brun⟩⟩ := if_trap_inv run
      all_goals obtain rfl : f = j := Nat.succ.inj hj
      · exact effT f (Nat.le_refl _) crun
      · exact effD f (Nat.le_refl _) crun
      · refine (effD f (Nat.le_refl _) crun).trans ?_
        cases x
        · exact belowT (s := elseBranch) brun
        · exact belowT (s := thenBranch) brun
    | «while» condition body =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · simp at run
      · rename_i conditionRun
        refine (pureD conditionRun).trans ?_
        split at run
        all_goals first
          | (simp at run; done)
          | (rename_i completed bodyRun
             simp only [Semantics.Outcome.trapped.injEq] at run
             obtain ⟨-, rfl⟩ := run
             exact belowT (s := body) bodyRun)
          | (rename_i completed bodyRun
             exact (below (s := body) bodyRun).trans (belowT (s := .while condition body) run))
      · rename_i conditionRun
        simp only [Semantics.Outcome.trapped.injEq] at run
        obtain ⟨-, rfl⟩ := run
        exact pureD conditionRun
      · rename_i conditionRun
        simp only [Semantics.Outcome.trapped.injEq] at run
        obtain ⟨-, rfl⟩ := run
        exact pureT conditionRun
      all_goals simp at run
    | whileEval condition body =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · simp at run
      · rename_i conditionRun
        refine (effD f (Nat.le_refl _) conditionRun).trans ?_
        split at run
        all_goals first
          | (simp at run; done)
          | (rename_i completed bodyRun
             simp only [Semantics.Outcome.trapped.injEq] at run
             obtain ⟨-, rfl⟩ := run
             exact belowT (s := body) bodyRun)
          | (rename_i completed bodyRun
             exact (below (s := body) bodyRun).trans (belowT (s := .whileEval condition body) run))
      · rename_i conditionRun
        simp only [Semantics.Outcome.trapped.injEq] at run
        obtain ⟨-, rfl⟩ := run
        exact effD f (Nat.le_refl _) conditionRun
      · rename_i conditionRun
        simp only [Semantics.Outcome.trapped.injEq] at run
        obtain ⟨-, rfl⟩ := run
        exact effT f (Nat.le_refl _) conditionRun
      all_goals simp at run
    | «return» value =>
      obtain ⟨j, -, vrun⟩ := return_trap_inv run
      exact pureT vrun
    | returnEval value =>
      obtain ⟨j, hj, vrun⟩ := return_trap_inv run
      obtain rfl : f = j := Nat.succ.inj hj
      exact effT f (Nat.le_refl _) vrun
    | returnUnit => exact (returnUnit_trap run).elim
    | «break» => exact (breakLoop_trap run).elim
    | «continue» => exact (continueLoop_trap run).elim
    | matchArm scrutinee enumId variant binds binder ty body rest =>
      have testD : ∀ a ∈ [(Core.Pattern.enumVariant enumId variant (if binds then [.wildcard] else []),
          Core.Expr.value (.boolean true)), (Core.Pattern.wildcard, Core.Expr.value (.boolean false))],
          ∀ {k : Nat} {st : State} {v : Value} {st' : State}, evalExpr k sp.toCore st a.2 = .done v st' → st' = st := by
        intro a mem
        simp only [List.mem_cons, List.not_mem_nil, or_false] at mem
        rcases mem with rfl | rfl
        · exact value_state _
        · exact value_state _
      have testT : ∀ a ∈ [(Core.Pattern.enumVariant enumId variant (if binds then [.wildcard] else []),
          Core.Expr.value (.boolean true)), (Core.Pattern.wildcard, Core.Expr.value (.boolean false))],
          ∀ {k : Nat} {st : State} {r : Lanius.Trap} {st' : State},
            evalExpr k sp.toCore st a.2 = .trapped r st' → st' = st := by
        intro a mem
        simp only [List.mem_cons, List.not_mem_nil, or_false] at mem
        rcases mem with rfl | rfl
        · exact fun r => (value_no_trap r).elim
        · exact fun r => (value_no_trap r).elim
      obtain ⟨j, hj, crun | ⟨v, crun, -⟩ | ⟨x, s1, crun, brun⟩⟩ := if_trap_inv run
      all_goals obtain rfl : f = j := Nat.succ.inj hj
      · exact matchPure_trap_grows testT crun
      · exact matchPure_grows testD crun
      · refine (matchPure_grows testD crun).trans ?_
        cases x
        · exact belowT (s := rest) brun
        · simp only [↓reduceIte] at brun
          split at brun
          · cases f with
            | zero => simp [execStmt] at brun
            | succ g =>
              have bindD : ∀ a ∈ [(Core.Pattern.enumVariant enumId variant [.bind binder], Core.Expr.local binder)],
                  ∀ {k : Nat} {st : State} {v : Value} {st' : State},
                    evalExpr k sp.toCore st a.2 = .done v st' → st' = st := by
                intro a mem
                simp only [List.mem_cons, List.not_mem_nil, or_false] at mem
                subst mem
                exact fun r => eval_local_state r
              have bindT : ∀ a ∈ [(Core.Pattern.enumVariant enumId variant [.bind binder], Core.Expr.local binder)],
                  ∀ {k : Nat} {st : State} {r : Lanius.Trap} {st' : State},
                    evalExpr k sp.toCore st a.2 = .trapped r st' → st' = st := by
                intro a mem
                simp only [List.mem_cons, List.not_mem_nil, or_false] at mem
                subst mem
                exact fun r => local_trap_state r
              exact letLocal_trap_grows (fun r => matchPure_grows bindD r) (fun r => matchPure_trap_grows bindT r)
                (fun r => ihfT g (Nat.lt_succ_self g) (s := body) r) brun
          · exact belowT (s := body) brun

/-- Every subset statement Core runs until it traps grows the heap. -/
theorem grows_trap (sp : SrcProgram) : ∀ fuel, GrowsBelowT sp fuel
  | 0 => fun _ lt => absurd lt (Nat.not_lt_zero _)
  | n + 1 => fun m lt => by
    intro st s r st' run
    rcases Nat.lt_succ_iff_lt_or_eq.mp lt with lt | rfl
    · exact grows_trap sp n m lt run
    · exact grows_trap_step (grows sp m) (grows_trap sp m) run

theorem execStmt_trap_grows {fuel : Nat} {s : SrcStmt}
    (run : execStmt fuel sp.toCore st s.toCore = .trapped r st') : Grows st st' :=
  grows_trap sp (fuel + 1) fuel (Nat.lt_succ_self _) run

theorem eff_trap_grows' {fuel : Nat} {e : SrcEff}
    (run : evalExpr fuel sp.toCore st e.toCore = .trapped r st') : Grows st st' :=
  eff_trap_grows fuel (grows sp fuel) (grows_trap sp fuel) fuel (Nat.le_refl _) run

end

end Lanius.Faithful
