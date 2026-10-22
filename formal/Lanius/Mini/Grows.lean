import Lanius.Mini.LowerExpr

/-! Core's heap only grows on the subset: a statement Core runs to completion
leaves the bump cursor `nextAddress` at or above where it was, and creates no
i32 array views. The front pass's theorem bounds the cursor at the end of a
run; this carries the bound back to every point of it. -/

namespace Lanius.Mini

open Lanius.Core (Value)
open Lanius.Semantics (State Completion evalExpr evalExprs execStmt restoreLocals)

theorem SrcType.toCore_ne_unit (ty : SrcType) : ty.toCore ≠ .unit := by
  cases ty <;> simp [SrcType.toCore]

theorem find_coreFuncs (funcs : List SrcFunc) (off i : Nat) (le : off ≤ i) :
    (coreFuncs off funcs).find? (fun function => function.id == i) =
      (funcs[i - off]?).map (SrcFunc.toCore i) := by
  induction funcs generalizing off with
  | nil => simp [coreFuncs]
  | cons head rest ih =>
    simp only [coreFuncs]
    by_cases eq : off = i
    · subst eq
      rw [List.find?_cons_of_pos (by simp [SrcFunc.toCore])]
      simp
    · rw [List.find?_cons_of_neg (by simp [SrcFunc.toCore]; omega), ih (off + 1) (by omega)]
      have : i - off = (i - (off + 1)) + 1 := by omega
      rw [this]
      simp

theorem SrcProgram.function?_toCore (sp : SrcProgram) (i : Nat) :
    sp.toCore.function? i = (sp.funcs[i]?).map (SrcFunc.toCore i) := by
  simp only [Core.Program.function?, SrcProgram.toCore]
  rw [find_coreFuncs _ 0 i (Nat.zero_le _)]
  rfl


def paramBindings (params : List SrcParam) (values : List Value) : List (Nat × Value) :=
  ((params.map fun p => (p.id, p.ty.toCore)).zip values).map fun pair => (pair.1.1, pair.2)

theorem bindParameters_eq (params : List SrcParam) (values : List Value)
    (len : values.length = params.length) :
    Semantics.bindParameters (params.map fun p => (p.id, p.ty.toCore)) values =
      some (paramBindings params values) := by
  simp [Semantics.bindParameters, len, paramBindings]


/-- What a Core call that returned did. -/
theorem call_inv {sp : SrcProgram} {fuel : Nat} {st : State} {callee : Nat} {args : List Core.Expr}
    {v : Value} {st' : State}
    (run : evalExpr (fuel + 1) sp.toCore st (.call callee args) = .done v st') :
    ∃ f values afterArgs completed, evalExprs fuel sp.toCore st args = .done values afterArgs ∧
      sp.funcs[callee]? = some f ∧ values.length = f.params.length ∧
      execStmt fuel sp.toCore (({ afterArgs with locals := [] } : State).bindLocals
        (paramBindings f.params values)) f.body.toCore = .done (.returned (some v)) completed ∧
      st' = restoreLocals afterArgs completed := by
  simp only [evalExpr] at run
  split at run
  · rename_i values afterArgs argsRun
    rw [SrcProgram.function?_toCore] at run
    cases found : sp.funcs[callee]? with
    | none => simp [found] at run
    | some f =>
      simp only [found, Option.map_some, SrcFunc.toCore] at run
      by_cases len : values.length = f.params.length
      · rw [bindParameters_eq _ _ len] at run
        simp only at run
        split at run
        · rename_i value completed bodyRun
          simp only [Semantics.Outcome.done.injEq] at run
          obtain ⟨rfl, rfl⟩ := run
          exact ⟨f, values, afterArgs, completed, argsRun, rfl, len, bodyRun, rfl⟩
        all_goals simp_all [SrcType.toCore_ne_unit]
      · have : Semantics.bindParameters (f.params.map fun p => (p.id, p.ty.toCore)) values = none := by
          simp [Semantics.bindParameters]; omega
        simp [this] at run
  all_goals simp at run

/-! ## Growing -/

/-- From `st` to `st'` the heap cursor did not go down, and no views appeared. -/
def Grows (st st' : State) : Prop :=
  st.i32ArrayViews = [] → st'.i32ArrayViews = [] ∧ st.heap.nextAddress ≤ st'.heap.nextAddress

theorem Grows.refl (st : State) : Grows st st := fun views => ⟨views, Nat.le_refl _⟩

theorem Grows.trans {a b c : State} (first : Grows a b) (second : Grows b c) : Grows a c := fun views =>
  let ⟨v1, n1⟩ := first views
  let ⟨v2, n2⟩ := second v1
  ⟨v2, Nat.le_trans n1 n2⟩

theorem Grows.same {st st' : State} (heap : st'.heap = st.heap)
    (views : st'.i32ArrayViews = st.i32ArrayViews) : Grows st st' :=
  fun v => ⟨views.trans v, by rw [heap]; exact Nat.le_refl _⟩

theorem bindLocals_same : ∀ (bs : List (Nat × Value)) (st : State),
    (st.bindLocals bs).heap = st.heap ∧ (st.bindLocals bs).i32ArrayViews = st.i32ArrayViews
  | [], _ => ⟨rfl, rfl⟩
  | b :: bs, st => bindLocals_same bs (st.bindLocal b.1 b.2)

theorem memAlignUp_ge (a k : Nat) (pos : 0 < k) : a ≤ Memory.alignUp a k := by
  simp only [Memory.alignUp]
  have := Nat.div_add_mod (a + k - 1) k
  have := Nat.mod_lt (a + k - 1) pos
  have : (a + k - 1) / k * k = k * ((a + k - 1) / k) := Nat.mul_comm _ _
  omega

theorem allocate_grows {h h' : Memory.Heap} {size align p : Nat}
    (ok : h.allocate size align = .allocated p h') : h.nextAddress ≤ h'.nextAddress := by
  simp only [Memory.Heap.allocate] at ok
  split at ok
  · simp at ok
  rename_i valid
  split at ok
  · simp at ok
  simp only [Memory.AllocationResult.allocated.injEq] at ok
  obtain ⟨-, rfl⟩ := ok
  have pos : 0 < align := by
    simp only [Memory.validAlignment, Bool.not_eq_true', Bool.not_eq_false, Bool.and_eq_true,
      bne_iff_ne, ne_eq] at valid
    omega
  have := memAlignUp_ge (max h.nextAddress 1) align pos
  exact Nat.le_trans (Nat.le_max_left _ _) (Nat.le_trans this (Nat.le_add_right _ _))

theorem allocate_exhausted {h h' : Memory.Heap} {size align : Nat}
    (ok : h.allocate size align = .exhausted h') : h' = h := by
  simp only [Memory.Heap.allocate] at ok
  split at ok
  · simp at ok
  split at ok
  · simpa using ok.symm
  · simp at ok

theorem storeByte_next {h h' : Memory.Heap} {p o : Nat} {b : UInt8}
    (ok : h.storeByte p o b = .ok h') : h'.nextAddress = h.nextAddress := by
  simp only [Memory.Heap.storeByte] at ok
  split at ok
  · split at ok <;> (try split at ok) <;> simp at ok
  · simp only [Except.ok.injEq] at ok
    rw [← ok]

theorem storeBytesFrom_next : ∀ (bytes : List UInt8) {h h' : Memory.Heap} {p o : Nat},
    Memory.storeBytesFrom h p o bytes = .ok h' → h'.nextAddress = h.nextAddress
  | [], h, h', p, o, ok => by simp [Memory.storeBytesFrom] at ok; rw [ok]
  | b :: rest, h, h', p, o, ok => by
    simp only [Memory.storeBytesFrom] at ok
    cases hs : h.storeByte p o b with
    | error => simp [hs] at ok
    | ok next =>
      simp only [hs] at ok
      rw [storeBytesFrom_next rest ok, storeByte_next hs]

theorem storeBytes_next {h h' : Memory.Heap} {p : Nat} {bytes : List UInt8}
    (ok : h.storeBytes p bytes = .ok h') : h'.nextAddress = h.nextAddress :=
  storeBytesFrom_next bytes ok

theorem foldlM_inv {α β ε : Type} (P : β → Prop) (f : β → α → Except ε β)
    (step : ∀ b a b', P b → f b a = .ok b' → P b') :
    ∀ (l : List α) (b b' : β), P b → l.foldlM f b = .ok b' → P b'
  | [], b, b', hb, ok => by simp only [List.foldlM] at ok; cases ok; exact hb
  | a :: l, b, b', hb, ok => by
    simp only [List.foldlM] at ok
    cases h : f b a with
    | error e => rw [h] at ok; exact absurd ok (by simp [bind, Except.bind])
    | ok b1 =>
      rw [h] at ok
      exact foldlM_inv P f step l b1 b' (step b a b1 hb h) ok

theorem except_bind_ok {α β ε : Type} {x : Except ε α} {f : α → Except ε β} {b : β}
    (ok : x >>= f = .ok b) : ∃ a, x = .ok a ∧ f a = .ok b := by
  cases x with
  | error e => exact absurd ok (by simp [bind, Except.bind])
  | ok a => exact ⟨a, rfl, ok⟩

theorem writeNativeValue_next : ∀ (fuel : Nat) {P : Core.Program} {st : State} {h h' : Memory.Heap}
    {ty : Core.Ty} {a : Nat} {v : Value},
    Semantics.writeNativeValue fuel P st h ty a v = .ok h' → h'.nextAddress = h.nextAddress
  | 0, _, _, _, _, _, _, _, ok => by simp [Semantics.writeNativeValue] at ok
  | fuel + 1, P, st, h, h', ty, a, v, ok => by
    simp only [Semantics.writeNativeValue] at ok
    split at ok
    all_goals first
      | exact storeBytes_next ok
      | skip
    · split at ok
      · simp at ok
      · obtain ⟨w, first, second⟩ := except_bind_ok ok
        rw [storeBytes_next second, storeBytes_next first]
    · split at ok
      · split at ok
        · simp at ok
        · obtain ⟨w, first, second⟩ := except_bind_ok ok
          rw [storeBytes_next second, storeBytes_next first]
      · simp at ok
    · split at ok
      · simp at ok
      · split at ok
        · split at ok
          · simp at ok
          · refine foldlM_inv (fun b => b.nextAddress = h.nextAddress) _ ?_ _ h h' rfl ok
            intro b i b' hb step
            try simp only at step
            split at step
            · split at step
              · split at step
                · rw [writeNativeValue_next fuel step, hb]
                · simp at step
              · simp at step
            · simp at step
        · simp at ok
    · split at ok
      · simp at ok
      · split at ok
        · split at ok
          · split at ok
            · simp at ok
            · obtain ⟨w, first, second⟩ := except_bind_ok ok
              refine foldlM_inv (fun b => b.nextAddress = h.nextAddress) _ ?_ _ w h'
                (storeBytes_next first) second
              intro b i b' hb step
              try simp only at step
              split at step
              · split at step
                · split at step
                  · rw [writeNativeValue_next fuel step, hb]
                  · simp at step
                · simp at step
              · simp at step
          · simp at ok
        · simp at ok
    · simp at ok

theorem protectAsBorrowed_next {h h' : Memory.Heap} {p n a : Nat}
    (ok : h.protectAsBorrowed p n a = .ok h') : h'.nextAddress = h.nextAddress := by
  simp only [Memory.Heap.protectAsBorrowed] at ok
  split at ok
  · simp at ok
  · split at ok
    · simp at ok
    · split at ok
      · simp at ok
      · simp only [Except.ok.injEq] at ok
        rw [← ok]

theorem protectRangeAsBorrowed_next {h h' : Memory.Heap} {p n a : Nat}
    (ok : h.protectRangeAsBorrowed p n a = .ok h') : h'.nextAddress = h.nextAddress := by
  simp only [Memory.Heap.protectRangeAsBorrowed] at ok
  split at ok
  · simp at ok
  · split at ok
    · simp at ok
    · split at ok
      · simp at ok
      · simp only [Except.ok.injEq] at ok
        rw [← ok]

theorem deallocate_next {h h' : Memory.Heap} {p s a : Nat}
    (ok : h.deallocate p s a = .ok h') : h'.nextAddress = h.nextAddress := by
  simp only [Memory.Heap.deallocate] at ok
  split at ok
  · simp only [Except.ok.injEq] at ok
    rw [← ok]
  · split at ok
    · simp at ok
    · split at ok
      · simp at ok
      · split at ok
        · simp at ok
        · split at ok
          · simp at ok
          · simp only [Except.ok.injEq] at ok
            rw [← ok]

/-! ## Pure expressions -/

theorem eval_local_state {P : Core.Program} {fuel : Nat} {st : State} {id : Nat} {v : Value} {st' : State}
    (run : evalExpr fuel P st (.local id) = .done v st') : st' = st := by
  cases fuel with
  | zero => simp [evalExpr] at run
  | succ fuel =>
    simp only [evalExpr] at run
    split at run
    · simp at run
    split at run <;> simp_all

/-- A subset expression leaves the state as it was. -/
theorem SrcExpr.eval_state (e : SrcExpr) {P : Core.Program} :
    ∀ {fuel : Nat} {st : State} {v : Value} {st' : State},
      evalExpr fuel P st e.toCore = .done v st' → st' = st := by
  induction e with
  | int _ | boolean _ | unsigned _ _ =>
    intro fuel st v st' run
    cases fuel with
    | zero => simp [evalExpr] at run
    | succ fuel =>
      simp only [SrcExpr.toCore, evalExpr, Semantics.Outcome.done.injEq] at run
      exact run.2.symm
  | «local» id => intro fuel st v st' run; exact eval_local_state run
  | field id index =>
    intro fuel st v st' run
    cases fuel with
    | zero => simp [evalExpr] at run
    | succ fuel =>
      simp only [SrcExpr.toCore, evalExpr] at run
      split at run
      · rename_i fields next baseRun
        have := eval_local_state baseRun
        subst this
        split at run <;> simp_all
      all_goals simp at run
  | negate operand ih | not operand ih =>
    intro fuel st v st' run
    cases fuel with
    | zero => simp [evalExpr] at run
    | succ fuel =>
      simp only [SrcExpr.toCore, evalExpr] at run
      split at run
      · rename_i w next innerRun
        have := ih innerRun
        subst this
        split at run <;> simp_all
      all_goals simp at run
  | cast ty operand ih =>
    intro fuel st v st' run
    cases fuel with
    | zero => simp [evalExpr] at run
    | succ fuel =>
      simp only [SrcExpr.toCore, evalExpr] at run
      split at run
      · rename_i w next innerRun
        have := ih innerRun
        subst this
        split at run <;> simp_all
      all_goals simp at run
  | apply op left right ihl ihr =>
    intro fuel st v st' run
    cases fuel with
    | zero => simp [evalExpr] at run
    | succ fuel =>
      cases op <;> simp only [SrcExpr.toCore, SrcOp.toCore, evalExpr] at run
      case logicalAnd | logicalOr =>
        split at run
        · simp only [Semantics.Outcome.done.injEq] at run
          rename_i next leftRun
          rw [← run.2]
          exact ihl leftRun
        · rename_i next leftRun
          have := ihl leftRun
          subst this
          exact ihr run
        all_goals simp at run
      all_goals
        split at run
        · rename_i lv next leftRun
          have := ihl leftRun
          subst this
          split at run
          · rename_i rv next' rightRun
            have := ihr rightRun
            subst this
            split at run <;> simp_all
          all_goals simp at run
        all_goals simp at run

/-- Evaluating `e` leaves the state as it was. -/
def PureExpr (P : Core.Program) (e : Core.Expr) : Prop :=
  ∀ {fuel : Nat} {st : State} {v : Value} {st' : State}, evalExpr fuel P st e = .done v st' → st' = st

theorem evalExprs_pure {P : Core.Program} :
    ∀ (es : List Core.Expr), (∀ e ∈ es, PureExpr P e) →
      ∀ {fuel : Nat} {st : State} {vs : List Value} {st' : State}, evalExprs fuel P st es = .done vs st' → st' = st
  | [], _, fuel, st, vs, st', run => by
    cases fuel with
    | zero => simp [evalExprs] at run
    | succ fuel =>
      simp only [evalExprs, Semantics.Outcome.done.injEq] at run
      exact run.2.symm
  | e :: es, pure, fuel, st, vs, st', run => by
    cases fuel with
    | zero => simp [evalExprs] at run
    | succ fuel =>
      simp only [evalExprs] at run
      split at run
      · rename_i v next headRun
        have := pure e (List.mem_cons_self ..) headRun
        subst this
        split at run
        · rename_i vs' done restRun
          simp only [Semantics.Outcome.done.injEq] at run
          rw [← run.2]
          exact evalExprs_pure es (fun x mem => pure x (List.mem_cons_of_mem _ mem)) restRun
        all_goals simp at run
      all_goals simp at run

theorem evalExprs_state {P : Core.Program} (es : List SrcExpr) {fuel : Nat} {st : State}
    {vs : List Value} {st' : State} (run : evalExprs fuel P st (es.map SrcExpr.toCore) = .done vs st') :
    st' = st :=
  evalExprs_pure _ (fun x mem => by
    obtain ⟨e, -, rfl⟩ := List.mem_map.mp mem
    exact e.eval_state) run

/-! ## Statements -/

theorem sync_ok {st : State} (views : st.i32ArrayViews = []) : Semantics.syncI32ViewsToHeap st = .ok st := by
  simp [Semantics.syncI32ViewsToHeap, views, Semantics.syncI32ViewsToHeapFrom]

theorem syncFrom_ok {st : State} (views : st.i32ArrayViews = []) :
    Semantics.syncI32ViewsFromHeap st = .ok st := by
  simp [Semantics.syncI32ViewsFromHeap, views, Semantics.syncI32ViewsFromHeapFrom]

theorem eval_value_state {P : Core.Program} {k : Nat} {st : State} {x v : Value} {st' : State}
    (run : evalExpr k P st (.value x) = .done v st') : st' = st := by
  cases k with
  | zero => simp [evalExpr] at run
  | succ k =>
    simp only [evalExpr, Semantics.Outcome.done.injEq] at run
    exact run.2.symm

theorem assignCell_same {st st' : State} {c : Nat} {v : Value} (ok : st.assignCell c v = some st') :
    st'.heap = st.heap ∧ st'.i32ArrayViews = st.i32ArrayViews := by
  unfold Semantics.State.assignCell at ok
  split at ok
  · simp only [Option.some.injEq] at ok
    rw [← ok]
    exact ⟨rfl, rfl⟩
  · simp at ok

theorem writeResolved_same {st st' : State} {r : Semantics.ResolvedPlace} {v : Value}
    (ok : Semantics.writeResolvedPlace st r v = .ok st') :
    st'.heap = st.heap ∧ st'.i32ArrayViews = st.i32ArrayViews := by
  unfold Semantics.writeResolvedPlace at ok
  split at ok
  · split at ok
    · simp only [Except.ok.injEq] at ok
      subst ok
      exact assignCell_same (by assumption)
    · simp at ok
  · split at ok
    · simp at ok
    · simp at ok
    · split at ok
      · simp at ok
      · split at ok
        · simp only [Except.ok.injEq] at ok
          subst ok
          exact assignCell_same (by assumption)
        · simp at ok

theorem evalPlace_local {P : Core.Program} {k : Nat} {st : State} {id : Nat}
    {r : Semantics.ResolvedPlace} {st' : State}
    (run : Semantics.evalPlace k P st .address (.local id) = .done r st') : st' = st ∧ r.raw = none := by
  cases k with
  | zero => simp [Semantics.evalPlace] at run
  | succ k =>
    simp only [Semantics.evalPlace] at run
    split at run
    · simp at run
    split at run
    · simp at run
    simp only [Semantics.Outcome.done.injEq] at run
    obtain ⟨rfl, rfl⟩ := run
    exact ⟨rfl, rfl⟩

theorem evalPlace_field {P : Core.Program} {k : Nat} {st : State} {id index : Nat}
    {r : Semantics.ResolvedPlace} {st' : State}
    (run : Semantics.evalPlace k P st .address (.field (.local id) index) = .done r st') :
    st' = st ∧ r.raw = none := by
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
        | (simp at run; done)
        | (simp only [Semantics.Outcome.done.injEq] at run
           obtain ⟨rfl, rfl⟩ := run
           exact ⟨rfl, by first | rfl | exact raw⟩)
    all_goals simp at run

/-- `place = e` on a local or a field of one, where evaluating `e` grows. -/
theorem assign_grows {P : Core.Program} {k : Nat} {st : State} {place : Core.Place} {e : Core.Expr}
    {u : Value} {st' : State}
    (placeOk : ∀ {r st1}, Semantics.evalPlace k P st .address place = .done r st1 → st1 = st)
    (value : ∀ {rv st2}, evalExpr k P st e = .done rv st2 → Grows st st2)
    (run : evalExpr (k + 1) P st (.assign .set place e) = .done u st') : Grows st st' := by
  intro views
  simp only [evalExpr] at run
  split at run
  · rename_i resolved afterPlace placeRun
    have := placeOk placeRun
    subst this
    split at run
    · rename_i rv afterValue valueRun
      obtain ⟨views2, next2⟩ := value valueRun views
      split at run
      · simp at run
      rename_i result _
      cases raw : resolved.raw with
      | none =>
        simp only [Semantics.writeResolvedPlaceNative, raw] at run
        split at run
        · rename_i assigned written
          obtain ⟨heap3, views3⟩ := writeResolved_same written
          have synced := sync_ok (st := assigned) (views3.trans views2)
          simp only [synced, ite_self, Semantics.Outcome.done.injEq] at run
          obtain ⟨-, rfl⟩ := run
          exact ⟨views3.trans views2, by rw [heap3]; exact next2⟩
        · simp at run
      | some pair =>
        simp only [Semantics.writeResolvedPlaceNative, raw] at run
        split at run
        · rename_i assigned written
          obtain ⟨heap3, stored, wrapped⟩ := except_bind_ok written
          simp only [pure, Except.pure, Except.ok.injEq] at wrapped
          subst wrapped
          have synced := syncFrom_ok (st := { afterValue with heap := heap3 }) views2
          simp only [synced, ite_self, Semantics.Outcome.done.injEq] at run
          obtain ⟨-, rfl⟩ := run
          exact ⟨views2, by rw [show heap3.nextAddress = afterValue.heap.nextAddress from
            writeNativeValue_next _ stored]; exact next2⟩
        · simp at run
    all_goals simp at run
  all_goals simp at run

theorem let_grows {P : Core.Program} {f : Nat} {body : Core.Stmt}
    (ih : ∀ {st c st'}, execStmt f P st body = .done c st' → Grows st st') {st : State} {id : Nat}
    {v : Value} {c : Completion} {st' : State}
    (run : Semantics.restoreOutcomeLocals st (execStmt f P (st.bindLocal id v) body) = .done c st') :
    Grows st st' := by
  cases bodyRun : execStmt f P (st.bindLocal id v) body with
  | done c' completed =>
    simp only [bodyRun, Semantics.restoreOutcomeLocals, Semantics.Outcome.done.injEq] at run
    obtain ⟨-, rfl⟩ := run
    exact ((Grows.same (bindLocals_same [(id, v)] st).1 (bindLocals_same [(id, v)] st).2).trans
      (ih bodyRun)).trans (Grows.same rfl rfl)
  | trapped => simp [bodyRun, Semantics.restoreOutcomeLocals] at run
  | exited => simp [bodyRun, Semantics.restoreOutcomeLocals] at run
  | outOfFuel => simp [bodyRun, Semantics.restoreOutcomeLocals] at run

theorem matchArms_same {P : Core.Program} {value : Value} :
    ∀ (arms : List SrcArm) (id j : Nat) {k : Nat} {st : State} {v : Value} {st' : State},
      Semantics.evalMatchArms k P st value (coreArms id j arms) = .done v st' →
      st'.heap = st.heap ∧ st'.i32ArrayViews = st.i32ArrayViews
  | [], _, _, k, st, v, st', run => by
    cases k <;> simp [coreArms, Semantics.evalMatchArms] at run
  | arm :: rest, id, j, k, st, v, st', run => by
    cases k with
    | zero => simp [Semantics.evalMatchArms] at run
    | succ k =>
      simp only [coreArms, Semantics.evalMatchArms] at run
      split at run
      · exact matchArms_same rest id (j + 1) run
      · rename_i bindings _
        cases armRun : evalExpr k P (st.bindLocals bindings) arm.value.toCore with
        | done w completed =>
          simp only [armRun, Semantics.restoreOutcomeLocals, Semantics.Outcome.done.injEq] at run
          obtain ⟨-, rfl⟩ := run
          have := arm.value.eval_state armRun
          subst this
          exact bindLocals_same bindings st
        | trapped => simp [armRun, Semantics.restoreOutcomeLocals] at run
        | exited => simp [armRun, Semantics.restoreOutcomeLocals] at run
        | outOfFuel => simp [armRun, Semantics.restoreOutcomeLocals] at run

/-- Every statement with less fuel grows. -/
def GrowsBelow (sp : SrcProgram) (fuel : Nat) : Prop :=
  ∀ m < fuel, ∀ {st : State} {s : SrcStmt} {c : Completion} {st' : State},
    execStmt m sp.toCore st s.toCore = .done c st' → Grows st st'

theorem call_grows {sp : SrcProgram} {k : Nat} (ih : GrowsBelow sp k) {st : State} {callee : Nat}
    {args : List SrcExpr} {v : Value} {st' : State}
    (run : evalExpr k sp.toCore st (.call callee (args.map SrcExpr.toCore)) = .done v st') :
    Grows st st' := by
  cases k with
  | zero => simp [evalExpr] at run
  | succ k =>
    obtain ⟨f, values, afterArgs, completed, argsRun, found, _, bodyRun, rfl⟩ := call_inv run
    have := evalExprs_state args argsRun
    subst this
    have entry := bindLocals_same (paramBindings f.params values) { afterArgs with locals := [] }
    exact ((Grows.same entry.1 entry.2).trans (ih k (Nat.lt_succ_self k) bodyRun)).trans (Grows.same rfl rfl)

theorem alloc_grows {P : Core.Program} {k : Nat} {st : State} {size : SrcExpr} {shift : Nat}
    {v : Value} {st' : State}
    (run : evalExpr k P st (.alloc size.toCore (.value (.unsigned .usize (2 ^ shift)))) = .done v st') :
    Grows st st' := by
  cases k with
  | zero => simp [evalExpr] at run
  | succ k =>
    simp only [evalExpr] at run
    split at run
    · rename_i n afterSize sizeRun
      have := size.eval_state sizeRun
      subst this
      split at run
      · rename_i a afterAlign alignRun
        have := eval_value_state alignRun
        subst this
        split at run
        · rename_i p heap allocated
          simp only [Semantics.Outcome.done.injEq] at run
          obtain ⟨-, rfl⟩ := run
          exact fun views => ⟨views, allocate_grows allocated⟩
        · rename_i heap exhausted
          simp only [Semantics.Outcome.done.injEq] at run
          obtain ⟨-, rfl⟩ := run
          exact Grows.same (allocate_exhausted exhausted) rfl
        · simp at run
      all_goals simp at run
    all_goals simp at run

theorem loadByte_grows {P : Core.Program} {k : Nat} {st : State} {pointer offset : SrcExpr}
    {v : Value} {st' : State}
    (run : evalExpr k P st (.loadByte pointer.toCore offset.toCore) = .done v st') : Grows st st' := by
  intro views
  cases k with
  | zero => simp [evalExpr] at run
  | succ k =>
    simp only [evalExpr] at run
    split at run
    · rename_i p o next argsRun
      have := evalExprs_state [pointer, offset] argsRun
      subst this
      simp only [sync_ok views] at run
      split at run
      · simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨-, rfl⟩ := run
        exact ⟨views, Nat.le_refl _⟩
      · simp at run
    all_goals simp at run

theorem storeByte_grows {P : Core.Program} {k : Nat} {st : State} {pointer offset value : SrcExpr}
    {v : Value} {st' : State}
    (run : evalExpr k P st (.storeByte pointer.toCore offset.toCore value.toCore) = .done v st') :
    Grows st st' := by
  intro views
  cases k with
  | zero => simp [evalExpr] at run
  | succ k =>
    simp only [evalExpr] at run
    split at run
    · rename_i p o b next argsRun
      have := evalExprs_state [pointer, offset, value] argsRun
      subst this
      simp only [sync_ok views] at run
      split at run
      · simp at run
      · rename_i heap stored
        simp only [syncFrom_ok (st := { next with heap }) views, Semantics.Outcome.done.injEq] at run
        obtain ⟨-, rfl⟩ := run
        exact ⟨views, by rw [storeByte_next stored]; exact Nat.le_refl _⟩
    all_goals simp at run

theorem dealloc_grows {P : Core.Program} {k : Nat} {st : State} {pointer size : SrcExpr} {shift : Nat}
    {v : Value} {st' : State}
    (run : evalExpr k P st (.dealloc pointer.toCore size.toCore (.value (.unsigned .usize (2 ^ shift)))) =
      .done v st') : Grows st st' := by
  intro views
  cases k with
  | zero => simp [evalExpr] at run
  | succ k =>
    simp only [evalExpr] at run
    split at run
    · rename_i p s a next argsRun
      have := evalExprs_pure _ (fun x mem => by
        simp only [List.mem_cons, List.not_mem_nil, or_false] at mem
        rcases mem with rfl | rfl | rfl
        · exact pointer.eval_state
        · exact size.eval_state
        · exact eval_value_state) argsRun
      subst this
      simp only [sync_ok views] at run
      split at run
      · rename_i heap freed
        simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨-, rfl⟩ := run
        exact ⟨views, by rw [deallocate_next freed]; exact Nat.le_refl _⟩
      · simp at run
    all_goals simp at run

theorem structValue_state {P : Core.Program} {k : Nat} {st : State} {id : Nat} {es : List SrcExpr}
    {v : Value} {st' : State} (run : evalExpr k P st (.structValue id (es.map SrcExpr.toCore)) = .done v st') :
    st' = st := by
  cases k with
  | zero => simp [evalExpr] at run
  | succ k =>
    simp only [evalExpr] at run
    split at run
    · rename_i vs next argsRun
      simp only [Semantics.Outcome.done.injEq] at run
      rw [← run.2]
      exact evalExprs_state es argsRun
    all_goals simp at run

theorem enumValue_state {P : Core.Program} {k : Nat} {st : State} {id variant : Nat} {es : List SrcExpr}
    {v : Value} {st' : State}
    (run : evalExpr k P st (.enumValue id variant (es.map SrcExpr.toCore)) = .done v st') : st' = st := by
  cases k with
  | zero => simp [evalExpr] at run
  | succ k =>
    simp only [evalExpr] at run
    split at run
    · rename_i vs next argsRun
      simp only [Semantics.Outcome.done.injEq] at run
      rw [← run.2]
      exact evalExprs_state es argsRun
    all_goals simp at run

theorem matchValue_grows {P : Core.Program} {k : Nat} {st : State} {scrutinee id : Nat}
    {arms : List SrcArm} {v : Value} {st' : State}
    (run : evalExpr k P st (.matchValue (.local scrutinee) (coreArms id 0 arms)) = .done v st') :
    Grows st st' := by
  cases k with
  | zero => simp [evalExpr] at run
  | succ k =>
    simp only [evalExpr] at run
    split at run
    · rename_i w next scrutineeRun
      have := eval_local_state scrutineeRun
      subst this
      have := matchArms_same arms id 0 run
      exact Grows.same this.1 this.2
    all_goals simp at run

/-- Making a raw slice only marks heap bytes borrowed. -/
theorem sliceFrom_grows {P : Core.Program} {k : Nat} {st : State} {element : SrcType}
    {pointer length : SrcExpr} {v : Value} {st' : State}
    (run : evalExpr k P st (element.sliceFrom pointer.toCore length.toCore) = .done v st') :
    Grows st st' := by
  cases k with
  | zero => cases element <;> simp [SrcType.sliceFrom, evalExpr] at run
  | succ k =>
    cases element <;> simp only [SrcType.sliceFrom, evalExpr] at run
    all_goals
      split at run
      · rename_i a afterPointer pointerRun
        have := pointer.eval_state pointerRun
        subst this
        split at run
        · rename_i n afterLength lengthRun
          have := length.eval_state lengthRun
          subst this
          simp only [Semantics.mapRawI32Slice, Semantics.mapRawNominalSlice] at run
          repeat' split at run
          all_goals first
            | simp only [Semantics.Outcome.done.injEq] at run
              obtain ⟨-, rfl⟩ := run
              first
                | exact Grows.refl _
                | exact fun views => ⟨views, Nat.le_of_eq (protectAsBorrowed_next (by assumption)).symm⟩
                | exact fun views => ⟨views, Nat.le_of_eq (protectRangeAsBorrowed_next (by assumption)).symm⟩
            | simp at run
        all_goals simp at run
      all_goals simp at run

theorem evalPlace_readLocal {P : Core.Program} {k : Nat} {st : State} {id : Nat}
    {r : Semantics.ResolvedPlace} {st' : State}
    (run : Semantics.evalPlace k P st .read (.local id) = .done r st') : st' = st := by
  cases k with
  | zero => simp [Semantics.evalPlace] at run
  | succ k =>
    simp only [Semantics.evalPlace] at run
    split at run
    · simp at run
    split at run
    · simp at run
    split at run
    · simp at run
    · simp only [Semantics.Outcome.done.injEq] at run
      exact run.2.symm

/-- Reading a slice element changes nothing. -/
theorem index_state {P : Core.Program} {k : Nat} {st : State} {slice : Nat} {index : SrcExpr}
    {v : Value} {st' : State}
    (run : evalExpr k P st (.index (.local slice) index.toCore) = .done v st') : st' = st := by
  cases k with
  | zero => simp [evalExpr] at run
  | succ k =>
    simp only [evalExpr] at run
    split at run
    all_goals first
      | (rename_i baseRun; have := eval_local_state baseRun; subst this)
      | simp at run
    all_goals first
      | (simp at run; done)
      | split at run
        · rename_i iv afterIndex indexRun
          have := index.eval_state indexRun
          subst this
          repeat' split at run
          all_goals first
            | (simp only [Semantics.Outcome.done.injEq] at run; exact run.2.symm)
            | simp at run
        all_goals simp at run

/-- Resolving `slice[index]` for a write changes nothing. -/
theorem evalPlace_index {P : Core.Program} {k : Nat} {st : State} {slice : Nat} {index : SrcExpr}
    {r : Semantics.ResolvedPlace} {st' : State}
    (run : Semantics.evalPlace k P st .address (.index (.local slice) index.toCore) = .done r st') :
    st' = st := by
  cases k with
  | zero => simp [Semantics.evalPlace] at run
  | succ k =>
    simp only [Semantics.evalPlace] at run
    split at run
    · rename_i resolved afterBase baseRun
      have := evalPlace_readLocal baseRun
      subst this
      split at run
      · simp at run
      all_goals
        try split at run
        all_goals first
          | (rename_i iv afterIndex indexRun
             have := index.eval_state indexRun
             subst this
             repeat' split at run
             all_goals first
               | (simp only [Semantics.Outcome.done.injEq] at run; exact run.2.symm)
               | simp at run)
          | simp at run
    all_goals simp at run

/-! ## Effectful expressions -/

/-- Every effectful expression Core completes with at most `k` fuel grows. -/
def EffGrows (sp : SrcProgram) (k : Nat) : Prop :=
  ∀ m ≤ k, ∀ {st : State} {e : SrcEff} {v : Value} {st' : State},
    evalExpr m sp.toCore st e.toCore = .done v st' → Grows st st'

theorem EffGrows.lower {sp : SrcProgram} {k j : Nat} (ih : EffGrows sp k) (le : j ≤ k) : EffGrows sp j :=
  fun m lt => ih m (Nat.le_trans lt le)

theorem effs_grows {sp : SrcProgram} : ∀ (es : List SrcEff) {k : Nat}, EffGrows sp k →
    ∀ {st : State} {vs : List Value} {st' : State},
      evalExprs k sp.toCore st (SrcEff.toCoreList es) = .done vs st' → Grows st st'
  | [], k, _, st, vs, st', run => by
    cases k with
    | zero => simp [evalExprs] at run
    | succ k =>
      simp only [SrcEff.toCoreList, evalExprs, Semantics.Outcome.done.injEq] at run
      rw [← run.2]
      exact Grows.refl _
  | e :: es, k, ih, st, vs, st', run => by
    cases k with
    | zero => simp [evalExprs] at run
    | succ k =>
      simp only [SrcEff.toCoreList, evalExprs] at run
      split at run
      · rename_i v next headRun
        split at run
        · rename_i vs' done restRun
          simp only [Semantics.Outcome.done.injEq] at run
          rw [← run.2]
          exact (ih k (Nat.le_succ k) headRun).trans (effs_grows es (ih.lower (Nat.le_succ k)) restRun)
        all_goals simp at run
      all_goals simp at run

theorem effArms_grows {sp : SrcProgram} {value : Value} :
    ∀ (binders : List (List Nat)) (values : List SrcEff) (id j : Nat) {k : Nat}, EffGrows sp k →
      ∀ {st : State} {v : Value} {st' : State},
        Semantics.evalMatchArms k sp.toCore st value (SrcEff.coreArms id j binders values) = .done v st' →
        Grows st st'
  | [], _, _, _, k, _, st, v, st', run => by
    cases k <;> simp [SrcEff.coreArms, Semantics.evalMatchArms] at run
  | _ :: _, [], _, _, k, _, st, v, st', run => by
    cases k <;> simp [SrcEff.coreArms, Semantics.evalMatchArms] at run
  | bs :: rest, arm :: values, id, j, k, ih, st, v, st', run => by
    cases k with
    | zero => simp [Semantics.evalMatchArms] at run
    | succ k =>
      simp only [SrcEff.coreArms, Semantics.evalMatchArms] at run
      split at run
      · exact effArms_grows rest values id (j + 1) (ih.lower (Nat.le_succ k)) run
      · rename_i bindings _
        cases armRun : evalExpr k sp.toCore (st.bindLocals bindings) arm.toCore with
        | done w completed =>
          simp only [armRun, Semantics.restoreOutcomeLocals, Semantics.Outcome.done.injEq] at run
          obtain ⟨-, rfl⟩ := run
          have entry := bindLocals_same bindings st
          exact ((Grows.same entry.1 entry.2).trans (ih k (Nat.le_succ k) armRun)).trans (Grows.same rfl rfl)
        | trapped => simp [armRun, Semantics.restoreOutcomeLocals] at run
        | exited => simp [armRun, Semantics.restoreOutcomeLocals] at run
        | outOfFuel => simp [armRun, Semantics.restoreOutcomeLocals] at run

/-- Reading a slice element grows as its index does. -/
theorem index_grows {P : Core.Program} {k : Nat} {st : State} {slice : Nat} {index : Core.Expr}
    {v : Value} {st' : State}
    (hi : ∀ {st1 : State} {v1 : Value} {st2 : State}, evalExpr k P st1 index = .done v1 st2 → Grows st1 st2)
    (run : evalExpr (k + 1) P st (.index (.local slice) index) = .done v st') : Grows st st' := by
  simp only [evalExpr] at run
  split at run
  all_goals first
    | (rename_i baseRun; have := eval_local_state baseRun; subst this)
    | simp at run
  all_goals first
    | (simp at run; done)
    | split at run
      · rename_i iv afterIndex indexRun
        have grown := hi indexRun
        repeat' split at run
        all_goals first
          | (simp only [Semantics.Outcome.done.injEq] at run; rw [← run.2]; exact grown)
          | simp at run
      all_goals simp at run

theorem eff_grows_step {sp : SrcProgram} {k : Nat} (ih : GrowsBelow sp (k + 1)) (ihe : EffGrows sp k)
    {st : State} {e : SrcEff} {v : Value} {st' : State}
    (run : evalExpr (k + 1) sp.toCore st e.toCore = .done v st') : Grows st st' := by
  have sub : ∀ {st1 : State} {e1 : SrcEff} {v1 : Value} {st2 : State},
      evalExpr k sp.toCore st1 e1.toCore = .done v1 st2 → Grows st1 st2 := fun r => ihe k (Nat.le_refl _) r
  cases e with
  | ePure e =>
    have := e.eval_state run
    subst this
    exact Grows.refl _
  | eCall callee args =>
    obtain ⟨f, values, afterArgs, completed, argsRun, found, _, bodyRun, rfl⟩ := call_inv run
    have entry := bindLocals_same (paramBindings f.params values) { afterArgs with locals := [] }
    exact ((effs_grows args ihe argsRun).trans ((Grows.same entry.1 entry.2).trans
      (ih k (Nat.lt_succ_self k) bodyRun))).trans (Grows.same rfl rfl)
  | eApply op left right =>
    cases op
    case logicalAnd | logicalOr =>
      simp only [SrcEff.toCore, SrcOp.toCore, evalExpr] at run
      split at run
      · rename_i next leftRun
        simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨-, rfl⟩ := run
        exact sub leftRun
      · rename_i next leftRun
        exact (sub leftRun).trans (sub run)
      all_goals simp at run
    all_goals
      simp only [SrcEff.toCore, SrcOp.toCore, evalExpr] at run
      split at run
      · rename_i vl afterLeft leftRun
        split at run
        · rename_i vr afterRight rightRun
          split at run
          · simp only [Semantics.Outcome.done.injEq] at run
            obtain ⟨-, rfl⟩ := run
            exact (sub leftRun).trans (sub rightRun)
          · simp at run
        all_goals simp at run
      all_goals simp at run
  | eDivide op left right =>
    cases op <;>
    · simp only [SrcEff.toCore, SrcDivOp.toCore, evalExpr] at run
      split at run
      · rename_i vl afterLeft leftRun
        split at run
        · rename_i vr afterRight rightRun
          split at run
          · simp only [Semantics.Outcome.done.injEq] at run
            obtain ⟨-, rfl⟩ := run
            exact (sub leftRun).trans (sub rightRun)
          · simp at run
        all_goals simp at run
      all_goals simp at run
  | eNeg operand | eNot operand | eCast ty operand =>
    simp only [SrcEff.toCore, evalExpr] at run
    split at run
    · rename_i w next operandRun
      split at run
      · simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨-, rfl⟩ := run
        exact sub operandRun
      · simp at run
    all_goals simp at run
  | eIndex slice index =>
    exact index_grows (fun r => sub r) run
  | eStruct ty fields | eVariant ty variant fields =>
    simp only [SrcEff.toCore, evalExpr] at run
    split at run
    · rename_i vs next argsRun
      simp only [Semantics.Outcome.done.injEq] at run
      rw [← run.2]
      exact effs_grows fields ihe argsRun
    all_goals simp at run
  | eMatch scrutinee id binders values =>
    simp only [SrcEff.toCore, evalExpr] at run
    split at run
    · rename_i w next scrutineeRun
      exact (sub scrutineeRun).trans (effArms_grows binders values id 0 ihe run)
    all_goals simp at run

/-- Every effectful expression Core completes grows the heap. -/
theorem eff_grows {sp : SrcProgram} : ∀ k, GrowsBelow sp k → EffGrows sp k
  | 0, _ => fun m le => by
    intro st e v st' run
    rw [Nat.le_zero.mp le] at run
    simp [evalExpr] at run
  | k + 1, ih => fun m le => by
    intro st e v st' run
    rcases Nat.lt_succ_iff_lt_or_eq.mp (Nat.lt_succ_of_le le) with lt | rfl
    · exact eff_grows k (fun j lt' => ih j (Nat.lt_succ_of_lt lt')) m (Nat.le_of_lt_succ lt) run
    · exact eff_grows_step ih (eff_grows k (fun j lt' => ih j (Nat.lt_succ_of_lt lt'))) run

theorem grows_step {sp : SrcProgram} {fuel : Nat} (ih : GrowsBelow sp fuel) {st : State} {s : SrcStmt}
    {c : Completion} {st' : State} (run : execStmt fuel sp.toCore st s.toCore = .done c st') :
    Grows st st' := by
  cases fuel with
  | zero => simp [execStmt] at run
  | succ f =>
    have below : ∀ {st : State} {s : SrcStmt} {c : Completion} {st' : State},
        execStmt f sp.toCore st s.toCore = .done c st' → Grows st st' :=
      fun r => ih f (Nat.lt_succ_self f) r
    have ihf : GrowsBelow sp f := fun m lt => ih m (Nat.lt_succ_of_lt lt)
    cases s with
    | nop =>
      simp only [SrcStmt.toCore, execStmt, Semantics.Outcome.done.injEq] at run
      obtain ⟨-, rfl⟩ := run
      exact Grows.refl _
    | «let» id ty value body =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i v next valueRun
        have := value.eval_state valueRun
        subst this
        exact let_grows (fun r => below (s := body) r) run
      all_goals simp at run
    | letStruct id ty fields body =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i v next valueRun
        have := structValue_state valueRun
        subst this
        exact let_grows (fun r => below (s := body) r) run
      all_goals simp at run
    | letCall id ty callee args body =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i v next valueRun
        exact (call_grows ihf valueRun).trans (let_grows (fun r => below (s := body) r) run)
      all_goals simp at run
    | letEnum id ty variant payload body =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i v next valueRun
        have := enumValue_state valueRun
        subst this
        exact let_grows (fun r => below (s := body) r) run
      all_goals simp at run
    | letMatch id ty scrutinee enumId arms body =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i v next valueRun
        exact (matchValue_grows valueRun).trans (let_grows (fun r => below (s := body) r) run)
      all_goals simp at run
    | set id value =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i u next assignRun
        simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨-, rfl⟩ := run
        cases f with
        | zero => simp [evalExpr] at assignRun
        | succ k =>
          exact assign_grows (fun r => (evalPlace_local r).1)
            (fun r => by have := value.eval_state r; subst this; exact Grows.refl _) assignRun
      all_goals simp at run
    | setField id index value =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i u next assignRun
        simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨-, rfl⟩ := run
        cases f with
        | zero => simp [evalExpr] at assignRun
        | succ k =>
          exact assign_grows (fun r => (evalPlace_field r).1)
            (fun r => by have := value.eval_state r; subst this; exact Grows.refl _) assignRun
      all_goals simp at run
    | setCall id callee args =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i u next assignRun
        simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨-, rfl⟩ := run
        cases f with
        | zero => simp [evalExpr] at assignRun
        | succ k =>
          exact assign_grows (fun r => (evalPlace_local r).1)
            (fun r => call_grows (fun m lt => ihf m (Nat.lt_succ_of_lt lt)) r) assignRun
      all_goals simp at run
    | «then» first second =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i next firstRun
        exact (below (s := first) firstRun).trans (below (s := second) run)
      · rename_i completion next _ firstRun
        simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨-, rfl⟩ := run
        exact below (s := first) firstRun
      all_goals simp at run
    | «if» condition thenBranch elseBranch =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i next conditionRun
        have := condition.eval_state conditionRun
        subst this
        exact below (s := thenBranch) run
      · rename_i next conditionRun
        have := condition.eval_state conditionRun
        subst this
        exact below (s := elseBranch) run
      all_goals simp at run
    | «while» condition body =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i next conditionRun
        have := condition.eval_state conditionRun
        subst this
        simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨-, rfl⟩ := run
        exact Grows.refl _
      · rename_i next conditionRun
        have := condition.eval_state conditionRun
        subst this
        split at run
        · rename_i completed bodyRun
          exact (below (s := body) bodyRun).trans (below (s := .while condition body) run)
        · rename_i completed bodyRun
          exact (below (s := body) bodyRun).trans (below (s := .while condition body) run)
        · rename_i completed bodyRun
          simp only [Semantics.Outcome.done.injEq] at run
          obtain ⟨-, rfl⟩ := run
          exact below (s := body) bodyRun
        · rename_i returned completed bodyRun
          simp only [Semantics.Outcome.done.injEq] at run
          obtain ⟨-, rfl⟩ := run
          exact below (s := body) bodyRun
        all_goals simp at run
      all_goals simp at run
    | «return» value =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i v next valueRun
        have := value.eval_state valueRun
        subst this
        simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨-, rfl⟩ := run
        exact Grows.refl _
      all_goals simp at run
    | letAlloc id size shift body =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i v next valueRun
        exact (alloc_grows valueRun).trans (let_grows (fun r => below (s := body) r) run)
      all_goals simp at run
    | letLoad id pointer offset body =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i v next valueRun
        exact (loadByte_grows valueRun).trans (let_grows (fun r => below (s := body) r) run)
      all_goals simp at run
    | setByte pointer offset value =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i u next storeRun
        simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨-, rfl⟩ := run
        exact storeByte_grows storeRun
      all_goals simp at run
    | free pointer size shift =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i u next freeRun
        simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨-, rfl⟩ := run
        exact dealloc_grows freeRun
      all_goals simp at run
    | letSlice id element pointer length body =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i v next valueRun
        exact (sliceFrom_grows valueRun).trans (let_grows (fun r => below (s := body) r) run)
      all_goals simp at run
    | letIndex id ty slice index body =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i v next valueRun
        have := index_state valueRun
        subst this
        exact let_grows (fun r => below (s := body) r) run
      all_goals simp at run
    | setIndex slice index value =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i u next assignRun
        simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨-, rfl⟩ := run
        cases f with
        | zero => simp [evalExpr] at assignRun
        | succ k =>
          exact assign_grows evalPlace_index
            (fun r => by have := value.eval_state r; subst this; exact Grows.refl _) assignRun
      all_goals simp at run
    | letEval id ty value body =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i v next valueRun
        exact (eff_grows f ihf f (Nat.le_refl _) valueRun).trans (let_grows (fun r => below (s := body) r) run)
      all_goals simp at run
    | setEval id value =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i u next assignRun
        simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨-, rfl⟩ := run
        cases f with
        | zero => simp [evalExpr] at assignRun
        | succ k =>
          exact assign_grows (fun r => (evalPlace_local r).1)
            (fun r => eff_grows (k + 1) ihf k (Nat.le_succ k) r) assignRun
      all_goals simp at run
    | ifEval condition thenBranch elseBranch =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i next conditionRun
        exact (eff_grows f ihf f (Nat.le_refl _) conditionRun).trans (below (s := thenBranch) run)
      · rename_i next conditionRun
        exact (eff_grows f ihf f (Nat.le_refl _) conditionRun).trans (below (s := elseBranch) run)
      all_goals simp at run
    | whileEval condition body =>
      simp only [SrcStmt.toCore, execStmt] at run
      have grown := fun {st1 v1 st2} (r : evalExpr f sp.toCore st1 condition.toCore = .done v1 st2) =>
        eff_grows f ihf f (Nat.le_refl _) r
      split at run
      · rename_i next conditionRun
        simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨-, rfl⟩ := run
        exact grown conditionRun
      · rename_i next conditionRun
        refine (grown conditionRun).trans ?_
        split at run
        · rename_i completed bodyRun
          exact (below (s := body) bodyRun).trans (below (s := .whileEval condition body) run)
        · rename_i completed bodyRun
          exact (below (s := body) bodyRun).trans (below (s := .whileEval condition body) run)
        · rename_i completed bodyRun
          simp only [Semantics.Outcome.done.injEq] at run
          obtain ⟨-, rfl⟩ := run
          exact below (s := body) bodyRun
        · rename_i returned completed bodyRun
          simp only [Semantics.Outcome.done.injEq] at run
          obtain ⟨-, rfl⟩ := run
          exact below (s := body) bodyRun
        all_goals simp at run
      all_goals simp at run
    | returnEval value =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i v next valueRun
        simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨-, rfl⟩ := run
        exact eff_grows f ihf f (Nat.le_refl _) valueRun
      all_goals simp at run
    | discard value =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i u next valueRun
        simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨-, rfl⟩ := run
        exact eff_grows f ihf f (Nat.le_refl _) valueRun
      all_goals simp at run

/-- Every subset statement Core completes grows the heap. -/
theorem grows (sp : SrcProgram) : ∀ fuel, GrowsBelow sp fuel
  | 0 => fun _ lt => absurd lt (Nat.not_lt_zero _)
  | n + 1 => fun m lt => by
    intro st s c st' run
    rcases Nat.lt_succ_iff_lt_or_eq.mp lt with lt | rfl
    · exact grows sp n m lt run
    · exact grows_step (grows sp m) run

theorem execStmt_grows {sp : SrcProgram} {fuel : Nat} {st : State} {s : SrcStmt} {c : Completion}
    {st' : State} (run : execStmt fuel sp.toCore st s.toCore = .done c st') : Grows st st' :=
  grows sp (fuel + 1) fuel (Nat.lt_succ_self _) run

end Lanius.Mini
