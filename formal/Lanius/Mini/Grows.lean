module

public import Lanius.Mini.LowerExpr
public import Lanius.Mini.Views
-- import all uses: Lanius.Mini.Compiler
import all Lanius.Mini.Compiler.P.BinOp_folds
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.SrcType_same
import all Lanius.Mini.Compiler.P.Stmt_kills
import all Lanius.Mini.Compiler.P.arrayCallSig
import all Lanius.Mini.Compiler.P.conjunction
import all Lanius.Mini.Compiler.P.longer
import all Lanius.Mini.Compiler.P.lowerApply
-- end import all uses

@[expose] public section

/-! Core's heap only grows on the subset: a statement Core runs to completion
leaves the bump cursor `nextAddress` at or above where it was, and creates no
i32 array views. The front pass's theorem bounds the cursor at the end of a
run; this carries the bound back to every point of it. -/

namespace Lanius.Mini

open Lanius.Core (Value)
open Lanius.Semantics (State Completion evalExpr evalExprs execStmt restoreLocals)

theorem SrcType.toCore_eq_unit {ty : SrcType} (h : ty.toCore = .unit) : ty = .unit := by
  cases ty <;> simp_all [SrcType.toCore]

/-- How a call's value comes from its callee body's completion: the value
returned, or `.unit` when a unit function ends or runs `return;`. -/
def CallResult (ret : SrcType) : Completion → Value → Prop
  | .next, v => ret = .unit ∧ v = .unit
  | .returned (some w), v => v = w
  | .returned none, v => ret = .unit ∧ v = .unit
  | .breakLoop, _ => False
  | .continueLoop, _ => False

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

theorem hostFuncs_find (i : Nat) :
    hostFuncs.find? (fun function => function.id == i) = (hostService? i).map (hostFunc i) := by
  unfold hostFuncs hostService?
  by_cases a : i = hostBase
  · subst a
    simp [hostFunc]
  · by_cases b : i = hostBase + 1
    · subst b
      simp [hostFunc, hostBase]
    · by_cases c : i = hostBase + 2
      · subst c
        simp [hostFunc, hostBase]
      · by_cases d : i = hostBase + 3
        · subst d
          simp [hostFunc, hostBase]
        · by_cases e : i = hostBase + 4
          · subst e
            simp [hostFunc, hostBase]
          · by_cases f : i = hostBase + 5
            · subst f
              simp [hostFunc, hostBase]
            · by_cases g : i = hostBase + 6
              · subst g
                simp [hostFunc, hostBase]
              · by_cases h : i = hostBase + 7
                · subst h
                  simp [hostFunc, hostBase]
                · by_cases j : i = hostBase + 8
                  · subst j
                    simp [hostFunc, hostBase]
                  · by_cases k : i = hostBase + 9
                    · subst k
                      simp [hostFunc, hostBase]
                    · simp [hostFunc, a, b, c, d, e, f, g, h, j, k, Ne.symm a, Ne.symm b, Ne.symm c, Ne.symm d,
                        Ne.symm e, Ne.symm f, Ne.symm g, Ne.symm h, Ne.symm j, Ne.symm k]

/-- A function of the program, or else a host function. -/
theorem SrcProgram.function?_toCore (sp : SrcProgram) (i : Nat) :
    sp.toCore.function? i = match sp.funcs[i]? with
      | some f => some (f.toCore i)
      | none => (hostService? i).map (hostFunc i) := by
  simp only [Core.Program.function?, SrcProgram.toCore, List.find?_append]
  rw [find_coreFuncs _ 0 i (Nat.zero_le _), hostFuncs_find, Nat.sub_zero]
  cases sp.funcs[i]? <;> rfl


theorem bindParameters_eq (params : List SrcParam) (values : List Value)
    (len : values.length = params.length) :
    Semantics.bindParameters (params.map fun p => (p.id, p.ty.toCore)) values =
      some (paramBindings params values) := by
  simp [Semantics.bindParameters, len, paramBindings]


/-- What a Core call of one of the program's functions that returned did. -/
theorem call_inv {sp : SrcProgram} {fuel : Nat} {st : State} {callee : Nat} {args : List Core.Expr}
    {v : Value} {st' : State} (inside : callee < sp.funcs.length)
    (run : evalExpr (fuel + 1) sp.toCore st (.call callee args) = .done v st') :
    ∃ f values afterArgs completed c, evalExprs fuel sp.toCore st args = .done values afterArgs ∧
      sp.funcs[callee]? = some f ∧ values.length = f.params.length ∧
      execStmt fuel sp.toCore (({ afterArgs with locals := [] } : State).bindLocals
        (paramBindings f.params values)) f.body.toCore = .done c completed ∧ CallResult f.ret c v ∧
      st' = restoreLocals afterArgs completed := by
  simp only [evalExpr] at run
  split at run
  · rename_i values afterArgs argsRun
    rw [SrcProgram.function?_toCore] at run
    cases found : sp.funcs[callee]? with
    | none => exact absurd (List.getElem?_eq_none_iff.mp found) (by omega)
    | some f =>
      simp only [found, SrcFunc.toCore] at run
      by_cases len : values.length = f.params.length
      · rw [bindParameters_eq _ _ len] at run
        simp only at run
        split at run
        · rename_i value completed bodyRun
          simp only [Semantics.Outcome.done.injEq] at run
          obtain ⟨rfl, rfl⟩ := run
          exact ⟨f, values, afterArgs, completed, _, argsRun, rfl, len, bodyRun, rfl, rfl⟩
        · rename_i completed bodyRun
          split at run
          · rename_i isUnit
            simp only [Semantics.Outcome.done.injEq] at run
            obtain ⟨rfl, rfl⟩ := run
            exact ⟨f, values, afterArgs, completed, _, argsRun, rfl, len, bodyRun,
              ⟨SrcType.toCore_eq_unit isUnit, rfl⟩, rfl⟩
          · simp at run
        · rename_i completed bodyRun
          split at run
          · rename_i isUnit
            simp only [Semantics.Outcome.done.injEq] at run
            obtain ⟨rfl, rfl⟩ := run
            exact ⟨f, values, afterArgs, completed, _, argsRun, rfl, len, bodyRun,
              ⟨SrcType.toCore_eq_unit isUnit, rfl⟩, rfl⟩
          · simp at run
        all_goals simp at run
      · have : Semantics.bindParameters (f.params.map fun p => (p.id, p.ty.toCore)) values = none := by
          simp [Semantics.bindParameters]; omega
        simp [this] at run
  all_goals simp at run

/-! ## Growing -/

/-- From `st` to `st'` the heap cursor did not go down, and the views only
grew at their end (`mapI32ArrayView` appends one). -/
structure Grows (st st' : State) : Prop where
  next : st.heap.nextAddress ≤ st'.heap.nextAddress
  views : ∃ more, st'.i32ArrayViews = st.i32ArrayViews ++ more

theorem Grows.refl (st : State) : Grows st st := ⟨Nat.le_refl _, [], by simp⟩

theorem Grows.trans {a b c : State} (first : Grows a b) (second : Grows b c) : Grows a c := by
  obtain ⟨m1, e1⟩ := first.views
  obtain ⟨m2, e2⟩ := second.views
  exact ⟨Nat.le_trans first.next second.next, m1 ++ m2, by rw [e2, e1, List.append_assoc]⟩

theorem Grows.same {st st' : State} (heap : st'.heap = st.heap)
    (views : st'.i32ArrayViews = st.i32ArrayViews) : Grows st st' :=
  ⟨by rw [heap]; exact Nat.le_refl _, [], by rw [views, List.append_nil]⟩

/-- The heap's cursor did not go down and the views are the same. -/
theorem Grows.heap {st st' : State} (next : st.heap.nextAddress ≤ st'.heap.nextAddress)
    (views : st'.i32ArrayViews = st.i32ArrayViews) : Grows st st' :=
  ⟨next, [], by rw [views, List.append_nil]⟩

/-- A view of `st` is one of `st'`. -/
theorem Grows.mem {st st' : State} (g : Grows st st') {v : Semantics.I32ArrayView} (mem : v ∈ st.i32ArrayViews) :
    v ∈ st'.i32ArrayViews := by
  obtain ⟨more, e⟩ := g.views
  rw [e]
  exact List.mem_append_left _ mem

theorem bindLocals_same : ∀ (bs : List (Nat × Value)) (st : State),
    (st.bindLocals bs).heap = st.heap ∧ (st.bindLocals bs).i32ArrayViews = st.i32ArrayViews
  | [], _ => ⟨rfl, rfl⟩
  | b :: bs, st => bindLocals_same bs (st.bindLocal b.1 b.2)

theorem bindLocals_world : ∀ (bs : List (Nat × Value)) (st : State), (st.bindLocals bs).world = st.world
  | [], _ => rfl
  | b :: bs, st => bindLocals_world bs (st.bindLocal b.1 b.2)

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
      · split at ok
        · simp at ok
        · obtain ⟨w1, s1, r1⟩ := except_bind_ok ok
          obtain ⟨l1, -, r2⟩ := except_bind_ok r1
          obtain ⟨w2, s2, r3⟩ := except_bind_ok r2
          obtain ⟨l2, -, s3⟩ := except_bind_ok r3
          rw [storeBytes_next s3, storeBytes_next s2, storeBytes_next s1]
    · split at ok
      · split at ok
        · simp at ok
        · obtain ⟨w1, s1, r1⟩ := except_bind_ok ok
          obtain ⟨l1, -, r2⟩ := except_bind_ok r1
          obtain ⟨w2, s2, r3⟩ := except_bind_ok r2
          obtain ⟨l2, -, s3⟩ := except_bind_ok r3
          rw [storeBytes_next s3, storeBytes_next s2, storeBytes_next s1]
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
                · obtain ⟨l, -, w⟩ := except_bind_ok step
                  rw [writeNativeValue_next fuel w, hb]
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
                  · obtain ⟨l, -, w⟩ := except_bind_ok step
                    rw [writeNativeValue_next fuel w, hb]
                  · simp at step
                · simp at step
              · simp at step
          · simp at ok
        · simp at ok
    · simp at ok

theorem writeNativeValue_stores : ∀ (fuel : Nat) {P : Core.Program} {st : State} {h h' : Memory.Heap}
    {ty : Core.Ty} {a : Nat} {v : Value},
    Semantics.writeNativeValue fuel P st h ty a v = .ok h' → Views.Stores h h'
  | 0, _, _, _, _, _, _, _, ok => by simp [Semantics.writeNativeValue] at ok
  | fuel + 1, P, st, h, h', ty, a, v, ok => by
    simp only [Semantics.writeNativeValue] at ok
    split at ok
    all_goals first
      | exact Views.Stores.storeBytes ok
      | skip
    · split at ok
      · simp at ok
      · split at ok
        · simp at ok
        · obtain ⟨w1, s1, r1⟩ := except_bind_ok ok
          obtain ⟨l1, -, r2⟩ := except_bind_ok r1
          obtain ⟨w2, s2, r3⟩ := except_bind_ok r2
          obtain ⟨l2, -, s3⟩ := except_bind_ok r3
          exact ((Views.Stores.storeBytes s1).trans (Views.Stores.storeBytes s2)).trans (Views.Stores.storeBytes s3)
    · split at ok
      · split at ok
        · simp at ok
        · obtain ⟨w1, s1, r1⟩ := except_bind_ok ok
          obtain ⟨l1, -, r2⟩ := except_bind_ok r1
          obtain ⟨w2, s2, r3⟩ := except_bind_ok r2
          obtain ⟨l2, -, s3⟩ := except_bind_ok r3
          exact ((Views.Stores.storeBytes s1).trans (Views.Stores.storeBytes s2)).trans (Views.Stores.storeBytes s3)
      · simp at ok
    · split at ok
      · simp at ok
      · split at ok
        · split at ok
          · simp at ok
          · refine foldlM_inv (fun b => Views.Stores h b) _ ?_ _ h h' (Views.Stores.refl h) ok
            intro b i b' hb step
            try simp only at step
            split at step
            · split at step
              · split at step
                · obtain ⟨l, -, w⟩ := except_bind_ok step
                  exact hb.trans (writeNativeValue_stores fuel w)
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
              refine foldlM_inv (fun b => Views.Stores h b) _ ?_ _ w h'
                (Views.Stores.storeBytes first) second
              intro b i b' hb step
              try simp only at step
              split at step
              · split at step
                · split at step
                  · obtain ⟨l, -, w⟩ := except_bind_ok step
                    exact hb.trans (writeNativeValue_stores fuel w)
                  · simp at step
                · simp at step
              · simp at step
          · simp at ok
        · simp at ok
    · simp at ok

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
  | int _ | boolean _ | unsigned _ _ | null | char _ | float _ _ =>
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

theorem sync_ok {st : State} (hold : Views.ViewsHold st) : Semantics.syncI32ViewsToHeap st = .ok st :=
  Views.syncTo_ok hold

theorem syncFrom_ok {st : State} (hold : Views.ViewsHold st) :
    Semantics.syncI32ViewsFromHeap st = .ok st :=
  Views.syncFrom_ok hold

/-- Core's sync to the heap stores into blocks: only the heap's bytes change. -/
theorem syncToFrom_heap : ∀ (views : List Semantics.I32ArrayView) {st st' : State},
    Semantics.syncI32ViewsToHeapFrom views st = .ok st' →
      st' = { st with heap := st'.heap } ∧ st'.heap.nextAddress = st.heap.nextAddress
  | [], st, st', ok => by
    simp only [Semantics.syncI32ViewsToHeapFrom, Except.ok.injEq] at ok
    subst ok; exact ⟨rfl, rfl⟩
  | v :: rest, st, st', ok => by
    simp only [Semantics.syncI32ViewsToHeapFrom] at ok
    split at ok
    · split at ok
      · simp at ok
      · split at ok
        · simp at ok
        · split at ok
          · simp at ok
          · rename_i heap stored
            obtain ⟨same, next⟩ := syncToFrom_heap rest ok
            refine ⟨?_, by rw [next, storeBytes_next stored]⟩
            rw [same]
    all_goals simp at ok

theorem syncTo_heap {st st' : State} (ok : Semantics.syncI32ViewsToHeap st = .ok st') :
    st' = { st with heap := st'.heap } ∧ st'.heap.nextAddress = st.heap.nextAddress :=
  syncToFrom_heap _ ok

/-- Core's sync from the heap writes the views' cells: the heap and the
views stay. -/
theorem syncFromFrom_same : ∀ (views : List Semantics.I32ArrayView) {st st' : State},
    Semantics.syncI32ViewsFromHeapFrom views st = .ok st' →
      st'.heap = st.heap ∧ st'.i32ArrayViews = st.i32ArrayViews
  | [], st, st', ok => by
    simp only [Semantics.syncI32ViewsFromHeapFrom, Except.ok.injEq] at ok
    subst ok; exact ⟨rfl, rfl⟩
  | v :: rest, st, st', ok => by
    simp only [Semantics.syncI32ViewsFromHeapFrom] at ok
    split at ok
    · simp at ok
    · split at ok
      · simp at ok
      · split at ok
        · simp at ok
        · rename_i next written
          obtain ⟨h1, v1⟩ := syncFromFrom_same rest ok
          obtain ⟨h2, v2⟩ := writeResolved_same written
          exact ⟨h1.trans h2, v1.trans v2⟩

theorem syncFrom_same {st st' : State} (ok : Semantics.syncI32ViewsFromHeap st = .ok st') :
    st'.heap = st.heap ∧ st'.i32ArrayViews = st.i32ArrayViews :=
  syncFromFrom_same _ ok

/-- A host call from `st` returned `v`: Core synced the views to the heap,
the world call returned, and Core read the views' cells back from the heap. -/
def HostReturns (st : State) (service : Core.HostService) (values : List Value) (v : Value) (st' : State) :
    Prop :=
  ∃ synced heap world, Semantics.syncI32ViewsToHeap st = .ok synced ∧
    World.call synced.heap synced.world service values = .returned v heap world ∧
    Semantics.syncI32ViewsFromHeap { synced with heap, world } = .ok st'

/-- Under `ViewsHold`, the first sync changes nothing. -/
theorem HostReturns.held {st : State} {service : Core.HostService} {values : List Value} {v : Value}
    {st' : State} (returns : HostReturns st service values v st') (hold : Views.ViewsHold st) :
    ∃ heap world, World.call st.heap st.world service values = .returned v heap world ∧
      Semantics.syncI32ViewsFromHeap { st with heap, world } = .ok st' := by
  obtain ⟨synced, heap, world, ok, called, back⟩ := returns
  rw [sync_ok hold, Except.ok.injEq] at ok
  subst ok
  exact ⟨heap, world, called, back⟩

/-- What a Core call that returned did: one of the program's functions ran,
or a host function did. -/
theorem call_cases {sp : SrcProgram} {fuel : Nat} {st : State} {callee : Nat} {args : List Core.Expr}
    {v : Value} {st' : State}
    (run : evalExpr (fuel + 1) sp.toCore st (.call callee args) = .done v st') :
    ∃ values afterArgs, evalExprs fuel sp.toCore st args = .done values afterArgs ∧
      ((callee < sp.funcs.length ∧ ∃ f completed c, sp.funcs[callee]? = some f ∧ values.length = f.params.length ∧
        execStmt fuel sp.toCore (({ afterArgs with locals := [] } : State).bindLocals
          (paramBindings f.params values)) f.body.toCore = .done c completed ∧ CallResult f.ret c v ∧
        st' = restoreLocals afterArgs completed) ∨
       (sp.funcs.length ≤ callee ∧ ∃ service, hostService? callee = some service ∧
        HostReturns afterArgs service values v st')) := by
  by_cases inside : callee < sp.funcs.length
  · obtain ⟨f, values, afterArgs, completed, c, a, b, d, e, g, i⟩ := call_inv inside run
    exact ⟨values, afterArgs, a, .inl ⟨inside, f, completed, c, b, d, e, g, i⟩⟩
  · simp only [evalExpr] at run
    split at run
    · rename_i values afterArgs argsRun
      refine ⟨values, afterArgs, argsRun, .inr ⟨by omega, ?_⟩⟩
      rw [SrcProgram.function?_toCore, List.getElem?_eq_none (by omega)] at run
      cases hs : hostService? callee with
      | none => simp [hs] at run
      | some service =>
        refine ⟨service, rfl, ?_⟩
        simp only [hs, Option.map_some, hostFunc] at run
        split at run
        · simp at run
        rotate_left
        · rename_i same _
          simp at same
        · split at run
          · simp at run
          rename_i synced syncedOk
          cases called : World.call synced.heap synced.world service values with
          | returned value heap world =>
            rw [called] at run
            simp only [Semantics.worldCallOutcome] at run
            split at run
            · rename_i next fromOk
              simp only [Semantics.Outcome.done.injEq] at run
              obtain ⟨rfl, rfl⟩ := run
              exact ⟨synced, heap, world, syncedOk, called, fromOk⟩
            · simp at run
          | exited => rw [called] at run; simp [Semantics.worldCallOutcome] at run; split at run <;> simp at run
          | unavailable => rw [called] at run; simp [Semantics.worldCallOutcome] at run
          | trapped => rw [called] at run; simp [Semantics.worldCallOutcome] at run
          | typeMismatch => rw [called] at run; simp [Semantics.worldCallOutcome] at run
    all_goals simp at run

theorem eval_value_state {P : Core.Program} {k : Nat} {st : State} {x v : Value} {st' : State}
    (run : evalExpr k P st (.value x) = .done v st') : st' = st := by
  cases k with
  | zero => simp [evalExpr] at run
  | succ k =>
    simp only [evalExpr, Semantics.Outcome.done.injEq] at run
    exact run.2.symm

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

/-- A raw store keeps the heap's size: a byte view's byte or a native value. -/
theorem writeRawNative_next {P : Core.Program} {st : State} {place : Semantics.ResolvedPlace} {ty : Core.Ty}
    {a : Nat} {v : Value} {h' : Memory.Heap} (stored : Semantics.writeRawNative P st place ty a v = .ok h') :
    h'.nextAddress = st.heap.nextAddress := by
  simp only [Semantics.writeRawNative] at stored
  split at stored
  · simp only [Semantics.storeRawByte] at stored
    split at stored
    · exact storeBytes_next stored
    · simp at stored
  · exact writeNativeValue_next _ stored

/-- A raw store keeps each owned block owned, below the next address. -/
theorem writeRawNative_stores {P : Core.Program} {st : State} {place : Semantics.ResolvedPlace} {ty : Core.Ty}
    {a : Nat} {v : Value} {h' : Memory.Heap} (stored : Semantics.writeRawNative P st place ty a v = .ok h') :
    Views.Stores st.heap h' := by
  simp only [Semantics.writeRawNative] at stored
  split at stored
  · simp only [Semantics.storeRawByte] at stored
    split at stored
    · exact Views.Stores.storeBytes stored
    · simp at stored
  · exact writeNativeValue_stores _ stored

/-- A write of a resolved place keeps the heap's size and the views. -/
theorem writeNative_grows {P : Core.Program} {st st' : State} {place : Semantics.ResolvedPlace} {v : Value}
    (ok : Semantics.writeResolvedPlaceNative P st place v = .ok st') :
    st'.heap.nextAddress = st.heap.nextAddress ∧ st'.i32ArrayViews = st.i32ArrayViews := by
  cases raw : place.raw with
  | none =>
    simp only [Semantics.writeResolvedPlaceNative, raw] at ok
    obtain ⟨heap, views⟩ := writeResolved_same ok
    exact ⟨by rw [heap], views⟩
  | some pair =>
    simp only [Semantics.writeResolvedPlaceNative, raw] at ok
    obtain ⟨heap, stored, wrapped⟩ := except_bind_ok ok
    simp only [pure, Except.pure, Except.ok.injEq] at wrapped
    subst wrapped
    exact ⟨writeRawNative_next stored, rfl⟩

/-- The sync after an assignment keeps the heap's size and the views. -/
theorem synchronized_grows {resolved : Semantics.ResolvedPlace} {result : Value} {assigned coherent : State}
    (ok : (if resolved.viewFreeRootWrite result then (Except.ok assigned : Except Lanius.Trap State)
      else match resolved.raw with
        | none => Semantics.syncI32ViewsToHeap assigned
        | some _ => Semantics.syncI32ViewsFromHeap assigned) = .ok coherent) :
    coherent.heap.nextAddress = assigned.heap.nextAddress ∧ coherent.i32ArrayViews = assigned.i32ArrayViews := by
  split at ok
  · simp only [Except.ok.injEq] at ok; subst ok; exact ⟨rfl, rfl⟩
  · split at ok
    · obtain ⟨same, next⟩ := syncTo_heap ok
      exact ⟨next, by rw [same]⟩
    · obtain ⟨heap, views⟩ := syncFrom_same ok
      exact ⟨by rw [heap], views⟩

/-- `place = e` on a local or a field of one, where evaluating `e` grows. -/
theorem assign_grows {P : Core.Program} {k : Nat} {st : State} {place : Core.Place} {e : Core.Expr}
    {u : Value} {st' : State}
    (placeOk : ∀ {r st1}, Semantics.evalPlace k P st .address place = .done r st1 → st1 = st)
    (value : ∀ {rv st2}, evalExpr k P st e = .done rv st2 → Grows st st2)
    (run : evalExpr (k + 1) P st (.assign .set place e) = .done u st') : Grows st st' := by
  simp only [evalExpr] at run
  split at run
  · rename_i resolved afterPlace placeRun
    have := placeOk placeRun
    subst this
    split at run
    · rename_i rv afterValue valueRun
      have g2 := value valueRun
      split at run
      · simp at run
      rename_i result _
      split at run
      · rename_i assigned written
        split at run
        · rename_i coherent synced
          simp only [Semantics.Outcome.done.injEq] at run
          obtain ⟨-, rfl⟩ := run
          obtain ⟨n3, v3⟩ := synchronized_grows synced
          obtain ⟨n4, v4⟩ := writeNative_grows written
          exact g2.trans (Grows.heap (st := afterValue) (st' := coherent) (Nat.le_of_eq (n3.trans n4).symm) (v3.trans v4))
        · simp at run
      · simp at run
    all_goals simp at run
  all_goals simp at run

/-- An assignment whose place and value may grow the heap. -/
theorem assign_grows_eff {P : Core.Program} {k : Nat} {st : State} {place : Core.Place} {e : Core.Expr}
    {u : Value} {st' : State}
    (placeOk : ∀ {r st1}, Semantics.evalPlace k P st .address place = .done r st1 → Grows st st1)
    (value : ∀ {st1 rv st2}, evalExpr k P st1 e = .done rv st2 → Grows st1 st2)
    (run : evalExpr (k + 1) P st (.assign .set place e) = .done u st') : Grows st st' := by
  simp only [evalExpr] at run
  split at run
  · rename_i resolved afterPlace placeRun
    have g1 := placeOk placeRun
    split at run
    · rename_i rv afterValue valueRun
      have g2 := value valueRun
      split at run
      · simp at run
      rename_i result _
      split at run
      · rename_i assigned written
        split at run
        · rename_i coherent synced
          simp only [Semantics.Outcome.done.injEq] at run
          obtain ⟨-, rfl⟩ := run
          obtain ⟨n3, v3⟩ := synchronized_grows synced
          obtain ⟨n4, v4⟩ := writeNative_grows written
          exact g1.trans (g2.trans (Grows.heap (st := afterValue) (st' := coherent) (Nat.le_of_eq (n3.trans n4).symm) (v3.trans v4)))
        · simp at run
      · simp at run
    all_goals simp at run
  all_goals simp at run

/-- After the place and the value of `place = e`: the write and the sync grow. -/
theorem assign_after_grows {P : Core.Program} {k : Nat} {st : State} {place : Core.Place} {e : Core.Expr}
    {u : Value} {st' : State} (run : evalExpr (k + 1) P st (.assign .set place e) = .done u st')
    {r : Semantics.ResolvedPlace} {st1 : State} (placeRun : Semantics.evalPlace k P st .address place = .done r st1)
    {rv : Value} {st2 : State} (valueRun : evalExpr k P st1 e = .done rv st2) : Grows st2 st' := by
  simp only [evalExpr, placeRun, valueRun] at run
  split at run
  · simp at run
  rename_i result _
  split at run
  · rename_i assigned written
    split at run
    · rename_i coherent synced
      simp only [Semantics.Outcome.done.injEq] at run
      obtain ⟨-, rfl⟩ := run
      obtain ⟨n3, v3⟩ := synchronized_grows synced
      obtain ⟨n4, v4⟩ := writeNative_grows written
      exact Grows.heap (st := st2) (st' := coherent) (Nat.le_of_eq (n3.trans n4).symm) (v3.trans v4)
    · simp at run
  · simp at run

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

theorem matchArms_world {P : Core.Program} {value : Value} :
    ∀ (arms : List SrcArm) (id j : Nat) {k : Nat} {st : State} {v : Value} {st' : State},
      Semantics.evalMatchArms k P st value (coreArms id j arms) = .done v st' →
      st'.world = st.world
  | [], _, _, k, st, v, st', run => by
    cases k <;> simp [coreArms, Semantics.evalMatchArms] at run
  | arm :: rest, id, j, k, st, v, st', run => by
    cases k with
    | zero => simp [Semantics.evalMatchArms] at run
    | succ k =>
      simp only [coreArms, Semantics.evalMatchArms] at run
      split at run
      · exact matchArms_world rest id (j + 1) run
      · rename_i bindings _
        cases armRun : evalExpr k P (st.bindLocals bindings) arm.value.toCore with
        | done w completed =>
          simp only [armRun, Semantics.restoreOutcomeLocals, Semantics.Outcome.done.injEq] at run
          obtain ⟨-, rfl⟩ := run
          have := arm.value.eval_state armRun
          subst this
          exact bindLocals_world bindings st
        | trapped => simp [armRun, Semantics.restoreOutcomeLocals] at run
        | exited => simp [armRun, Semantics.restoreOutcomeLocals] at run
        | outOfFuel => simp [armRun, Semantics.restoreOutcomeLocals] at run

/-- Every statement with less fuel grows. -/
def GrowsBelow (sp : SrcProgram) (fuel : Nat) : Prop :=
  ∀ m < fuel, ∀ {st : State} {s : SrcStmt} {c : Completion} {st' : State},
    execStmt m sp.toCore st s.toCore = .done c st' → Grows st st'

/-! ## Host calls -/

set_option maxHeartbeats 400000 in
/-- What `write_stdout` or `write_stderr` did when it returned. -/
theorem call_writeOut_inv {service : Core.HostService} (which : service = .writeStdout ∨ service = .writeStderr)
    {heap : Memory.Heap} {world : World.State} {values : List Value} {v : Value} {heap' : Memory.Heap}
    {world' : World.State} (h : World.call heap world service values = .returned v heap' world') :
    ∃ p n bytes, values = [.pointer p, .unsigned .usize n] ∧ heap.loadBytes p n = .ok bytes ∧
      v = World.i32Result bytes.length ∧ heap' = heap ∧
      world' = (if service = .writeStdout then
        { World.record world service with standardOutput := (World.record world service).standardOutput ++ bytes }
      else { World.record world service with standardError := (World.record world service).standardError ++ bytes }) := by
  rcases which with rfl | rfl <;>
  · match values, h with
    | [], h => simp [World.call, World.callSimple] at h
    | [a], h => cases a <;> simp [World.call, World.callSimple] at h
    | a :: b :: c :: rest, h => cases a <;> simp [World.call, World.callSimple] at h
    | [a, b], h =>
      cases a with
      | pointer p =>
        cases b with
        | unsigned k n =>
          cases k
          all_goals simp only [World.call, World.callSimple] at h
          all_goals first
            | (split at h
               · simp at h
               · rename_i bytes loaded
                 simp only [World.EffectResult.returned.injEq] at h
                 obtain ⟨rfl, rfl, rfl⟩ := h
                 exact ⟨p, n, bytes, rfl, loaded, rfl, rfl, by simp⟩)
            | simp at h
        | _ => simp [World.call, World.callSimple] at h
      | _ => simp [World.call, World.callSimple] at h

/-- What `write_byte` did when it returned. -/
theorem call_writeByte_inv {heap : Memory.Heap} {world : World.State} {values : List Value} {v : Value}
    {heap' : Memory.Heap} {world' : World.State}
    (h : World.call heap world .writeByte values = .returned v heap' world') :
    ∃ handle value, values = [.signed .i32 handle, .signed .i32 value] ∧ heap' = heap ∧
      ((World.writeBytes (World.record world .writeByte) handle [UInt8.ofNat (value % 256).toNat] = some world' ∧
          v = World.i32Result 1) ∨
        (World.writeBytes (World.record world .writeByte) handle [UInt8.ofNat (value % 256).toNat] = none ∧
          ((World.writeFileBytes (World.record world .writeByte) handle [UInt8.ofNat (value % 256).toNat] =
              some world' ∧ v = World.i32Result 1) ∨
            (World.writeFileBytes (World.record world .writeByte) handle [UInt8.ofNat (value % 256).toNat] = none ∧
              v = World.i32Result (-1) ∧ world' = World.record world .writeByte)))) := by
  match values, h with
  | [], h => simp [World.call, World.callSimple] at h
  | [a], h => cases a <;> simp [World.call, World.callSimple] at h
  | a :: b :: c :: rest, h => cases a <;> simp [World.call, World.callSimple] at h
  | [a, b], h =>
    cases a with
    | signed k handle =>
      cases b with
      | signed k' value =>
        cases k <;> cases k'
        all_goals simp only [World.call, World.callSimple] at h
        all_goals first
          | (refine ⟨handle, value, rfl, ?_⟩
             cases wb : World.writeBytes (World.record world .writeByte) handle [UInt8.ofNat (value % 256).toNat] with
             | some w =>
               simp only [wb, World.EffectResult.returned.injEq] at h
               obtain ⟨rfl, rfl, rfl⟩ := h
               exact ⟨rfl, .inl ⟨rfl, rfl⟩⟩
             | none =>
               simp only [wb] at h
               cases wf : World.writeFileBytes (World.record world .writeByte) handle [UInt8.ofNat (value % 256).toNat] with
               | some w =>
                 simp only [wf, World.EffectResult.returned.injEq] at h
                 obtain ⟨rfl, rfl, rfl⟩ := h
                 exact ⟨rfl, .inr ⟨rfl, .inl ⟨rfl, rfl⟩⟩⟩
               | none =>
                 simp only [wf, World.EffectResult.returned.injEq] at h
                 obtain ⟨rfl, rfl, rfl⟩ := h
                 exact ⟨rfl, .inr ⟨rfl, .inr ⟨rfl, rfl, rfl⟩⟩⟩)
          | simp at h
      | _ => simp [World.call, World.callSimple] at h
    | _ => simp [World.call, World.callSimple] at h

/-- What `write_text` did when it returned: wrote the text's UTF-8 bytes to
standard output or error and returned their count, wrote them to a file, or
returned -1. -/
theorem call_writeText_inv {heap : Memory.Heap} {world : World.State} {values : List Value} {v : Value}
    {heap' : Memory.Heap} {world' : World.State}
    (h : World.call heap world .writeText values = .returned v heap' world') :
    ∃ handle text, values = [.signed .i32 handle, .string text] ∧ heap' = heap ∧
      ((World.writeBytes (World.record world .writeText) handle (World.utf8Bytes text) = some world' ∧
          v = World.i32Result (World.utf8Bytes text).length) ∨
        (World.writeBytes (World.record world .writeText) handle (World.utf8Bytes text) = none ∧
          ((World.writeFileBytes (World.record world .writeText) handle (World.utf8Bytes text) =
              some world' ∧ v = World.i32Result (World.utf8Bytes text).length) ∨
            (World.writeFileBytes (World.record world .writeText) handle (World.utf8Bytes text) = none ∧
              v = World.i32Result (-1) ∧ world' = World.record world .writeText)))) := by
  match values, h with
  | [], h => simp [World.call, World.callSimple] at h
  | [a], h => cases a <;> simp [World.call, World.callSimple] at h
  | a :: b :: c :: rest, h => cases a <;> simp [World.call, World.callSimple] at h
  | [a, b], h =>
    cases a with
    | signed k handle =>
      cases b with
      | string text =>
        cases k
        all_goals simp only [World.call, World.callSimple] at h
        all_goals first
          | (refine ⟨handle, text, rfl, ?_⟩
             cases wb : World.writeBytes (World.record world .writeText) handle (World.utf8Bytes text) with
             | some w =>
               simp only [wb, World.EffectResult.returned.injEq] at h
               obtain ⟨rfl, rfl, rfl⟩ := h
               exact ⟨rfl, .inl ⟨rfl, rfl⟩⟩
             | none =>
               simp only [wb] at h
               cases wf : World.writeFileBytes (World.record world .writeText) handle (World.utf8Bytes text) with
               | some w =>
                 simp only [wf, World.EffectResult.returned.injEq] at h
                 obtain ⟨rfl, rfl, rfl⟩ := h
                 exact ⟨rfl, .inr ⟨rfl, .inl ⟨rfl, rfl⟩⟩⟩
               | none =>
                 simp only [wf, World.EffectResult.returned.injEq] at h
                 obtain ⟨rfl, rfl, rfl⟩ := h
                 exact ⟨rfl, .inr ⟨rfl, .inr ⟨rfl, rfl, rfl⟩⟩⟩)
          | simp at h
      | _ => simp [World.call, World.callSimple] at h
    | _ => simp [World.call, World.callSimple] at h

/-- What `write_newline` did when it returned: as `write_byte` of 10. -/
theorem call_writeNewline_inv {heap : Memory.Heap} {world : World.State} {values : List Value} {v : Value}
    {heap' : Memory.Heap} {world' : World.State}
    (h : World.call heap world .writeNewline values = .returned v heap' world') :
    ∃ handle, values = [.signed .i32 handle] ∧ heap' = heap ∧
      ((World.writeBytes (World.record world .writeNewline) handle [10] = some world' ∧ v = World.i32Result 1) ∨
        (World.writeBytes (World.record world .writeNewline) handle [10] = none ∧
          ((World.writeFileBytes (World.record world .writeNewline) handle [10] = some world' ∧
              v = World.i32Result 1) ∨
            (World.writeFileBytes (World.record world .writeNewline) handle [10] = none ∧
              v = World.i32Result (-1) ∧ world' = World.record world .writeNewline)))) := by
  match values, h with
  | [], h => simp [World.call, World.callSimple] at h
  | a :: b :: rest, h => cases a <;> simp [World.call, World.callSimple] at h
  | [a], h =>
    cases a with
    | signed k handle =>
      cases k
      all_goals simp only [World.call, World.callSimple] at h
      all_goals first
        | (refine ⟨handle, rfl, ?_⟩
           cases wb : World.writeBytes (World.record world .writeNewline) handle [10] with
           | some w =>
             simp only [wb, World.EffectResult.returned.injEq] at h
             obtain ⟨rfl, rfl, rfl⟩ := h
             exact ⟨rfl, .inl ⟨rfl, rfl⟩⟩
           | none =>
             simp only [wb] at h
             cases wf : World.writeFileBytes (World.record world .writeNewline) handle [10] with
             | some w =>
               simp only [wf, World.EffectResult.returned.injEq] at h
               obtain ⟨rfl, rfl, rfl⟩ := h
               exact ⟨rfl, .inr ⟨rfl, .inl ⟨rfl, rfl⟩⟩⟩
             | none =>
               simp only [wf, World.EffectResult.returned.injEq] at h
               obtain ⟨rfl, rfl, rfl⟩ := h
               exact ⟨rfl, .inr ⟨rfl, .inr ⟨rfl, rfl, rfl⟩⟩⟩)
        | simp at h
    | _ => simp [World.call, World.callSimple] at h

/-- What `read_stdin` did when it returned: stored the next bytes of
standard input, as many as asked for or all that are left. -/
theorem call_readStdin_inv {heap : Memory.Heap} {world : World.State} {values : List Value} {v : Value}
    {heap' : Memory.Heap} {world' : World.State}
    (h : World.call heap world .readStdin values = .returned v heap' world') :
    ∃ p n, values = [.pointer p, .unsigned .usize n] ∧
      heap.storeBytes p (world.standardInput.take n) = .ok heap' ∧
      v = World.i32Result (world.standardInput.take n).length ∧
      world' = { World.record world .readStdin with standardInput := world.standardInput.drop n } := by
  match values, h with
  | [], h => simp [World.call, World.callSimple] at h
  | [a], h => cases a <;> simp [World.call, World.callSimple] at h
  | a :: b :: c :: rest, h => cases a <;> simp [World.call, World.callSimple] at h
  | [a, b], h =>
    cases a with
    | pointer p =>
      cases b with
      | unsigned k n =>
        cases k
        all_goals simp only [World.call, World.callSimple] at h
        all_goals first
          | (split at h
             · simp at h
             · rename_i copied stored
               simp only [World.EffectResult.returned.injEq] at h
               obtain ⟨rfl, rfl, rfl⟩ := h
               refine ⟨p, n, rfl, stored, rfl, ?_⟩
               simp only [World.record, List.length_take]
               congr 1
               rcases Nat.le_total n world.standardInput.length with le | le
               · rw [Nat.min_eq_left le]
               · rw [Nat.min_eq_right le, List.drop_eq_nil_of_le le, List.drop_eq_nil_of_le (Nat.le_refl _)])
          | simp at h
      | _ => simp [World.call, World.callSimple] at h
    | _ => simp [World.call, World.callSimple] at h

/-- What `sleep_ms_i32` did when it returned: -1 for a negative count, else
0 with the clocks advanced; the heap as it was. -/
theorem call_sleepMsI32_inv {heap : Memory.Heap} {world : World.State} {values : List Value} {v : Value}
    {heap' : Memory.Heap} {world' : World.State}
    (h : World.call heap world .sleepMsI32 values = .returned v heap' world') :
    ∃ ms, values = [.signed .i32 ms] ∧ heap' = heap ∧
      (ms < 0 ∧ v = World.i32Result (-1) ∧ world' = World.record world .sleepMsI32 ∨
        0 ≤ ms ∧ v = World.i32Result 0 ∧ world' = (World.record world .sleepMsI32).afterSleepMs ms.toNat) := by
  match values, h with
  | [], h => simp [World.call, World.callSimple] at h
  | a :: b :: rest, h =>
    cases a with
    | signed k x => cases k <;> simp [World.call, World.callSimple] at h
    | _ => simp [World.call, World.callSimple] at h
  | [a], h =>
    cases a with
    | signed k ms =>
      cases k
      all_goals first
        | (by_cases neg : ms < 0
           · simp only [World.call, World.callSimple, neg, ↓reduceIte, World.EffectResult.returned.injEq] at h
             obtain ⟨rfl, rfl, rfl⟩ := h
             exact ⟨ms, rfl, rfl, .inl ⟨neg, rfl, rfl⟩⟩
           · simp only [World.call, World.callSimple, neg, ↓reduceIte, World.EffectResult.returned.injEq] at h
             obtain ⟨rfl, rfl, rfl⟩ := h
             exact ⟨ms, rfl, rfl, .inr ⟨Int.not_lt.mp neg, rfl, rfl⟩⟩)
        | simp [World.call, World.callSimple] at h
    | _ => simp [World.call, World.callSimple] at h

/-- What `monotonic_read` did when it returned: -1 for a buffer below 16 bytes, else
0 with the clock's next reading stored at the pointer. -/
theorem call_monotonicRead_inv {heap : Memory.Heap} {world : World.State} {values : List Value} {v : Value}
    {heap' : Memory.Heap} {world' : World.State}
    (h : World.call heap world .monotonicRead values = .returned v heap' world') :
    ∃ p n, values = [.pointer p, .unsigned .usize n] ∧
      (n < 16 ∧ v = World.i32Result (-1) ∧ heap' = heap ∧ world' = World.record world .monotonicRead ∨
        16 ≤ n ∧ ∃ reading rest, world.monotonicReadings = reading :: rest ∧
          heap.storeBytes p (World.timespecBytes reading.1 reading.2) = .ok heap' ∧ v = World.i32Result 0 ∧
          world' = { World.record world .monotonicRead with monotonicReadings := rest }) := by
  match values, h with
  | [], h => simp [World.call, World.callSimple] at h
  | [a], h => cases a <;> simp [World.call, World.callSimple] at h
  | a :: b :: c :: rest, h => cases a <;> simp [World.call, World.callSimple] at h
  | [a, b], h =>
    cases a with
    | pointer p =>
      cases b with
      | unsigned k n =>
        cases k
        all_goals simp only [World.call, World.callSimple] at h
        all_goals first
          | (refine ⟨p, n, rfl, ?_⟩
             split at h
             · rename_i small
               simp only [World.EffectResult.returned.injEq] at h
               obtain ⟨rfl, rfl, rfl⟩ := h
               exact .inl ⟨small, rfl, rfl, rfl⟩
             · rename_i big
               split at h
               · simp at h
               · rename_i reading rest readings
                 split at h
                 · simp at h
                 · rename_i copied stored
                   simp only [World.EffectResult.returned.injEq] at h
                   obtain ⟨rfl, rfl, rfl⟩ := h
                   exact .inr ⟨by omega, reading, rest, readings, stored, rfl, rfl⟩)
          | simp at h
      | _ => simp [World.call, World.callSimple] at h
    | _ => simp [World.call, World.callSimple] at h

/-- What `system_read` did when it returned: -1 for a buffer below 16 bytes, else
0 with the clock's next reading stored at the pointer. -/
theorem call_systemRead_inv {heap : Memory.Heap} {world : World.State} {values : List Value} {v : Value}
    {heap' : Memory.Heap} {world' : World.State}
    (h : World.call heap world .systemRead values = .returned v heap' world') :
    ∃ p n, values = [.pointer p, .unsigned .usize n] ∧
      (n < 16 ∧ v = World.i32Result (-1) ∧ heap' = heap ∧ world' = World.record world .systemRead ∨
        16 ≤ n ∧ ∃ reading rest, world.systemReadings = reading :: rest ∧
          heap.storeBytes p (World.timespecBytes reading.1 reading.2) = .ok heap' ∧ v = World.i32Result 0 ∧
          world' = { World.record world .systemRead with systemReadings := rest }) := by
  match values, h with
  | [], h => simp [World.call, World.callSimple] at h
  | [a], h => cases a <;> simp [World.call, World.callSimple] at h
  | a :: b :: c :: rest, h => cases a <;> simp [World.call, World.callSimple] at h
  | [a, b], h =>
    cases a with
    | pointer p =>
      cases b with
      | unsigned k n =>
        cases k
        all_goals simp only [World.call, World.callSimple] at h
        all_goals first
          | (refine ⟨p, n, rfl, ?_⟩
             split at h
             · rename_i small
               simp only [World.EffectResult.returned.injEq] at h
               obtain ⟨rfl, rfl, rfl⟩ := h
               exact .inl ⟨small, rfl, rfl, rfl⟩
             · rename_i big
               split at h
               · simp at h
               · rename_i reading rest readings
                 split at h
                 · simp at h
                 · rename_i copied stored
                   simp only [World.EffectResult.returned.injEq] at h
                   obtain ⟨rfl, rfl, rfl⟩ := h
                   exact .inr ⟨by omega, reading, rest, readings, stored, rfl, rfl⟩)
          | simp at h
      | _ => simp [World.call, World.callSimple] at h
    | _ => simp [World.call, World.callSimple] at h

/-- What `fill_secure_bytes` did when it returned: the next `n` secure bytes
stored at the pointer, and `n`. -/
theorem call_fillSecureBytes_inv {heap : Memory.Heap} {world : World.State} {values : List Value} {v : Value}
    {heap' : Memory.Heap} {world' : World.State}
    (h : World.call heap world .fillSecureBytes values = .returned v heap' world') :
    ∃ p n, values = [.pointer p, .unsigned .usize n] ∧ n ≤ world.secureByteStream.length ∧
      heap.storeBytes p (world.secureByteStream.take n) = .ok heap' ∧ v = World.i32Result n ∧
      world' = { World.record world .fillSecureBytes with secureByteStream := world.secureByteStream.drop n } := by
  match values, h with
  | [], h => simp [World.call, World.callSimple] at h
  | [a], h => cases a <;> simp [World.call, World.callSimple] at h
  | a :: b :: c :: rest, h => cases a <;> simp [World.call, World.callSimple] at h
  | [a, b], h =>
    cases a with
    | pointer p =>
      cases b with
      | unsigned k n =>
        cases k
        all_goals simp only [World.call, World.callSimple] at h
        all_goals first
          | (split at h
             · simp at h
             · rename_i enough
               split at h
               · simp at h
               · rename_i copied stored
                 simp only [World.EffectResult.returned.injEq] at h
                 obtain ⟨rfl, rfl, rfl⟩ := h
                 exact ⟨p, n, rfl, by simp [World.record] at enough; omega, stored, rfl, rfl⟩)
          | simp at h
      | _ => simp [World.call, World.callSimple] at h
    | _ => simp [World.call, World.callSimple] at h

/-- `monotonic_read`, `system_read` or `fill_secure_bytes` on a pointer and a
count returns, or traps at the end of a stream or as the heap's store does. -/
theorem stores_outcome {service : Core.HostService}
    (which : service = .monotonicRead ∨ service = .systemRead ∨ service = .fillSecureBytes)
    (heap : Memory.Heap) (world : World.State) (p n : Nat) :
    (∃ v heap' world', World.call heap world service [.pointer p, .unsigned .usize n] = .returned v heap' world') ∨
    (∃ r world', World.call heap world service [.pointer p, .unsigned .usize n] = .trapped r heap world' ∧
      (r = .clockExhausted ∨ r = .entropyExhausted ∨ ∃ bytes, heap.storeBytes p bytes = .error r)) := by
  rcases which with rfl | rfl | rfl <;>
  · simp only [World.call, World.callSimple]
    repeat' split
    all_goals first
      | exact .inl ⟨_, _, _, rfl⟩
      | exact .inr ⟨_, _, rfl, .inl rfl⟩
      | exact .inr ⟨_, _, rfl, .inr (.inl rfl)⟩
      | exact .inr ⟨_, _, rfl, .inr (.inr ⟨_, by assumption⟩)⟩

/-- The services of the host functions. -/
theorem hostService?_some {id : Nat} {service : Core.HostService} (hs : hostService? id = some service) :
    service = .writeByte ∨ service = .writeStdout ∨ service = .writeStderr ∨ service = .readStdin ∨
      service = .sleepMsI32 ∨ service = .monotonicRead ∨ service = .systemRead ∨ service = .fillSecureBytes ∨
      service = .writeText ∨ service = .writeNewline := by
  unfold hostService? at hs
  repeat' split at hs
  all_goals first | (cases hs; simp) | cases hs

/-- The clock reads and `fill_secure_bytes`, when they return: the heap as
it was, or after one store. -/
theorem call_stores_next {service : Core.HostService}
    (which : service = .monotonicRead ∨ service = .systemRead ∨ service = .fillSecureBytes)
    {heap : Memory.Heap} {world : World.State} {values : List Value} {v : Value} {heap' : Memory.Heap}
    {world' : World.State} (h : World.call heap world service values = .returned v heap' world') :
    heap'.nextAddress = heap.nextAddress := by
  rcases which with rfl | rfl | rfl <;>
  · match values, h with
    | [], h => simp [World.call, World.callSimple] at h
    | [a], h => cases a <;> simp [World.call, World.callSimple] at h
    | a :: b :: c :: rest, h => cases a <;> simp [World.call, World.callSimple] at h
    | [a, b], h =>
      cases a with
      | pointer p =>
        cases b with
        | unsigned k n =>
          cases k
          all_goals simp only [World.call, World.callSimple] at h
          all_goals first
            | (repeat' split at h
               all_goals first
                 | (simp only [World.EffectResult.returned.injEq] at h
                    obtain ⟨-, rfl, -⟩ := h
                    first | rfl | exact storeBytes_next (by assumption))
                 | simp at h)
            | simp at h
        | _ => simp [World.call, World.callSimple] at h
      | _ => simp [World.call, World.callSimple] at h

/-- The host functions that store nothing leave Core's heap as it was. -/
theorem hostCall_heap {service : Core.HostService}
    (keeps : service = .writeByte ∨ service = .writeStdout ∨ service = .writeStderr ∨ service = .sleepMsI32)
    {heap : Memory.Heap} {world : World.State} {values : List Value} {v : Value} {heap' : Memory.Heap}
    {world' : World.State} (h : World.call heap world service values = .returned v heap' world') : heap' = heap := by
  rcases keeps with rfl | rfl | rfl | rfl
  · obtain ⟨_, _, _, same, _⟩ := call_writeByte_inv h
    exact same
  · obtain ⟨_, _, _, _, _, _, same, _⟩ := call_writeOut_inv (.inl rfl) h
    exact same
  · obtain ⟨_, _, _, _, _, _, same, _⟩ := call_writeOut_inv (.inr rfl) h
    exact same
  · obtain ⟨_, _, same, _⟩ := call_sleepMsI32_inv h
    exact same

/-- `write_text` and `write_newline`, when they return, leave Core's heap as it was. -/
theorem textCall_heap {service : Core.HostService} (which : service = .writeText ∨ service = .writeNewline)
    {heap : Memory.Heap} {world : World.State} {values : List Value} {v : Value} {heap' : Memory.Heap}
    {world' : World.State} (h : World.call heap world service values = .returned v heap' world') : heap' = heap := by
  rcases which with rfl | rfl <;>
  · simp only [World.call] at h
    repeat' split at h
    all_goals first
      | contradiction
      | (simp only [World.EffectResult.returned.injEq] at h; exact h.2.1.symm)
      | simp at h

/-- The host functions keep Core's next free address. -/
theorem hostCall_next {id : Nat} {service : Core.HostService} (hs : hostService? id = some service)
    {heap : Memory.Heap} {world : World.State} {values : List Value} {v : Value} {heap' : Memory.Heap}
    {world' : World.State} (h : World.call heap world service values = .returned v heap' world') :
    heap'.nextAddress = heap.nextAddress := by
  rcases hostService?_some hs with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
  · rw [hostCall_heap (.inl rfl) h]
  · rw [hostCall_heap (.inr (.inl rfl)) h]
  · rw [hostCall_heap (.inr (.inr (.inl rfl))) h]
  · obtain ⟨p, n, -, stored, -⟩ := call_readStdin_inv h
    exact storeBytes_next stored
  · rw [hostCall_heap (.inr (.inr (.inr rfl))) h]
  · exact call_stores_next (.inl rfl) h
  · exact call_stores_next (.inr (.inl rfl)) h
  · exact call_stores_next (.inr (.inr rfl)) h
  · rw [textCall_heap (.inl rfl) h]
  · rw [textCall_heap (.inr rfl) h]

/-- The clock reads and `fill_secure_bytes`, when they return: the heap as
it was, or after one store. -/
theorem call_stores_stores {service : Core.HostService}
    (which : service = .monotonicRead ∨ service = .systemRead ∨ service = .fillSecureBytes)
    {heap : Memory.Heap} {world : World.State} {values : List Value} {v : Value} {heap' : Memory.Heap}
    {world' : World.State} (h : World.call heap world service values = .returned v heap' world') :
    Views.Stores heap heap' := by
  rcases which with rfl | rfl | rfl <;>
  · match values, h with
    | [], h => simp [World.call, World.callSimple] at h
    | [a], h => cases a <;> simp [World.call, World.callSimple] at h
    | a :: b :: c :: rest, h => cases a <;> simp [World.call, World.callSimple] at h
    | [a, b], h =>
      cases a with
      | pointer p =>
        cases b with
        | unsigned k n =>
          cases k
          all_goals simp only [World.call, World.callSimple] at h
          all_goals first
            | (repeat' split at h
               all_goals first
                 | (simp only [World.EffectResult.returned.injEq] at h
                    obtain ⟨-, rfl, -⟩ := h
                    first | exact Views.Stores.refl _ | exact Views.Stores.storeBytes (by assumption))
                 | simp at h)
            | simp at h
        | _ => simp [World.call, World.callSimple] at h
      | _ => simp [World.call, World.callSimple] at h

/-- The host functions keep each owned block owned, below the next address. -/
theorem hostCall_stores {id : Nat} {service : Core.HostService} (hs : hostService? id = some service)
    {heap : Memory.Heap} {world : World.State} {values : List Value} {v : Value} {heap' : Memory.Heap}
    {world' : World.State} (h : World.call heap world service values = .returned v heap' world') :
    Views.Stores heap heap' := by
  rcases hostService?_some hs with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
  · rw [hostCall_heap (.inl rfl) h]; exact Views.Stores.refl _
  · rw [hostCall_heap (.inr (.inl rfl)) h]; exact Views.Stores.refl _
  · rw [hostCall_heap (.inr (.inr (.inl rfl))) h]; exact Views.Stores.refl _
  · obtain ⟨p, n, -, stored, -⟩ := call_readStdin_inv h
    exact Views.Stores.storeBytes stored
  · rw [hostCall_heap (.inr (.inr (.inr rfl))) h]; exact Views.Stores.refl _
  · exact call_stores_stores (.inl rfl) h
  · exact call_stores_stores (.inr (.inl rfl)) h
  · exact call_stores_stores (.inr (.inr rfl)) h
  · rw [textCall_heap (.inl rfl) h]; exact Views.Stores.refl _
  · rw [textCall_heap (.inr rfl) h]; exact Views.Stores.refl _

theorem host_grows {id : Nat} {service : Core.HostService} (hs : hostService? id = some service)
    {st : State} {values : List Value} {v : Value} {st' : State} (returns : HostReturns st service values v st') :
    Grows st st' := by
  obtain ⟨synced, heap, world, ok, called, back⟩ := returns
  obtain ⟨same, next⟩ := syncTo_heap ok
  obtain ⟨heap', views'⟩ := syncFrom_same back
  refine Grows.heap ?_ ?_
  · rw [heap']
    show st.heap.nextAddress ≤ heap.nextAddress
    rw [hostCall_next hs called, next]
    exact Nat.le_refl _
  · rw [views', same]

theorem numberedParams_length : ∀ (n : Nat) (tys : List Core.Ty), (numberedParams n tys).length = tys.length
  | _, [] => rfl
  | n, _ :: rest => by simp [numberedParams, numberedParams_length (n + 1) rest]

/-- A host call whose arguments evaluated, to as many values as it has
parameters, and left no views:
Core's world call's outcome. -/
theorem host_call_eval {sp : SrcProgram} {fuel : Nat} {st : State} {callee : Nat} {args : List Core.Expr}
    {values : List Value} {afterArgs : State} {service : Core.HostService}
    (outside : sp.funcs.length ≤ callee) (hs : hostService? callee = some service)
    (len : values.length = service.parameterTypes.length)
    (argsRun : evalExprs fuel sp.toCore st args = .done values afterArgs) (views : Views.ViewsHold afterArgs) :
    evalExpr (fuel + 1) sp.toCore st (.call callee args) =
      Semantics.worldCallOutcome callee afterArgs (World.call afterArgs.heap afterArgs.world service values) := by
  have bound : Semantics.bindParameters (numberedParams 0 service.parameterTypes) values =
      some (((numberedParams 0 service.parameterTypes).zip values).map fun pair => (pair.1.1, pair.2)) := by
    rw [Semantics.bindParameters, numberedParams_length, len]
    simp
  simp only [evalExpr, argsRun]
  rw [SrcProgram.function?_toCore, List.getElem?_eq_none outside, hs]
  simp only [Option.map_some, hostFunc, bound, sync_ok views]

theorem worldCall_returned {id : Nat} {st : State} {v : Value} {heap : Memory.Heap} {world : World.State}
    {st' : State} (back : Semantics.syncI32ViewsFromHeap { st with heap, world } = .ok st') :
    Semantics.worldCallOutcome id st (.returned v heap world) = .done v st' := by
  simp only [Semantics.worldCallOutcome, back]

/-- `write_byte` on two `i32`s returns. -/
theorem writeByte_returns (heap : Memory.Heap) (world : World.State) (a b : Int) :
    ∃ v world', World.call heap world .writeByte [.signed .i32 a, .signed .i32 b] = .returned v heap world' := by
  cases wb : World.writeBytes (World.record world .writeByte) a [UInt8.ofNat (b % 256).toNat] with
  | some w => exact ⟨_, _, by simp [World.call, World.callSimple, wb] <;> first | exact ⟨rfl, rfl⟩ | rfl⟩
  | none =>
    cases wf : World.writeFileBytes (World.record world .writeByte) a [UInt8.ofNat (b % 256).toNat] with
    | some w => exact ⟨_, _, by simp [World.call, World.callSimple, wb, wf] <;> first | exact ⟨rfl, rfl⟩ | rfl⟩
    | none => exact ⟨_, _, by simp [World.call, World.callSimple, wb, wf] <;> first | exact ⟨rfl, rfl⟩ | rfl⟩

/-- `write_text` on an `i32` and a string returns. -/
theorem writeText_returns (heap : Memory.Heap) (world : World.State) (a : Int) (text : String) :
    ∃ v world', World.call heap world .writeText [.signed .i32 a, .string text] = .returned v heap world' := by
  cases wb : World.writeBytes (World.record world .writeText) a (World.utf8Bytes text) with
  | some w => exact ⟨_, _, by simp [World.call, World.callSimple, wb] <;> first | exact ⟨rfl, rfl⟩ | rfl⟩
  | none =>
    cases wf : World.writeFileBytes (World.record world .writeText) a (World.utf8Bytes text) with
    | some w => exact ⟨_, _, by simp [World.call, World.callSimple, wb, wf] <;> first | exact ⟨rfl, rfl⟩ | rfl⟩
    | none => exact ⟨_, _, by simp [World.call, World.callSimple, wb, wf] <;> first | exact ⟨rfl, rfl⟩ | rfl⟩

/-- `write_newline` on an `i32` returns. -/
theorem writeNewline_returns (heap : Memory.Heap) (world : World.State) (a : Int) :
    ∃ v world', World.call heap world .writeNewline [.signed .i32 a] = .returned v heap world' := by
  cases wb : World.writeBytes (World.record world .writeNewline) a [10] with
  | some w => exact ⟨_, _, by simp [World.call, World.callSimple, wb] <;> first | exact ⟨rfl, rfl⟩ | rfl⟩
  | none =>
    cases wf : World.writeFileBytes (World.record world .writeNewline) a [10] with
    | some w => exact ⟨_, _, by simp [World.call, World.callSimple, wb, wf] <;> first | exact ⟨rfl, rfl⟩ | rfl⟩
    | none => exact ⟨_, _, by simp [World.call, World.callSimple, wb, wf] <;> first | exact ⟨rfl, rfl⟩ | rfl⟩

/-- `sleep_ms_i32` on an `i32` returns. -/
theorem sleepMsI32_returns (heap : Memory.Heap) (world : World.State) (ms : Int) :
    ∃ v world', World.call heap world .sleepMsI32 [.signed .i32 ms] = .returned v heap world' := by
  by_cases neg : ms < 0
  · exact ⟨World.i32Result (-1), World.record world .sleepMsI32,
      by simp only [World.call, World.callSimple, neg, ↓reduceIte]⟩
  · exact ⟨World.i32Result 0, (World.record world .sleepMsI32).afterSleepMs ms.toNat,
      by simp only [World.call, World.callSimple, neg, ↓reduceIte]⟩

/-- `write_stdout` or `write_stderr` on a pointer and a count returns, or
traps as the heap's load of the bytes does. -/
theorem writeOut_outcome {service : Core.HostService} (which : service = .writeStdout ∨ service = .writeStderr)
    (heap : Memory.Heap) (world : World.State) (p n : Nat) :
    (∃ v world', World.call heap world service [.pointer p, .unsigned .usize n] = .returned v heap world') ∨
    (∃ r world', World.call heap world service [.pointer p, .unsigned .usize n] = .trapped r heap world' ∧
      heap.loadBytes p n = .error r) := by
  rcases which with rfl | rfl <;>
  · cases lb : heap.loadBytes p n with
    | error r => exact .inr ⟨r, _, by simp [World.call, World.callSimple, lb] <;> rfl, rfl⟩
    | ok bytes => exact .inl ⟨_, _, by simp [World.call, World.callSimple, lb] <;> exact ⟨rfl, rfl⟩⟩

/-- `read_stdin` on a pointer and a count returns, or traps as the heap's
store of the bytes does. -/
theorem readStdin_outcome (heap : Memory.Heap) (world : World.State) (p n : Nat) :
    (∃ v heap' world', World.call heap world .readStdin [.pointer p, .unsigned .usize n] = .returned v heap' world') ∨
    (∃ r world', World.call heap world .readStdin [.pointer p, .unsigned .usize n] = .trapped r heap world' ∧
      heap.storeBytes p (world.standardInput.take n) = .error r) := by
  cases sb : heap.storeBytes p (world.standardInput.take n) with
  | error r => exact .inr ⟨r, _, by simp [World.call, World.callSimple, World.record, sb] <;> rfl, rfl⟩
  | ok copied => exact .inl ⟨_, _, _, by simp [World.call, World.callSimple, World.record, sb] <;> exact ⟨rfl, rfl, rfl⟩⟩

/-- The heap a world call's result carries. -/
def resultHeap : World.EffectResult → Memory.Heap
  | .returned _ h _ => h
  | .exited _ h _ => h
  | .unavailable _ h _ => h
  | .trapped _ h _ => h
  | .typeMismatch h _ => h

set_option maxHeartbeats 400000 in
/-- A host call that did not return leaves the heap as it was. -/
theorem hostCall_resultHeap {id : Nat} {service : Core.HostService} (hs : hostService? id = some service)
    (heap : Memory.Heap) (world : World.State) (values : List Value)
    (stopped : ∀ v heap' world', World.call heap world service values ≠ .returned v heap' world') :
    resultHeap (World.call heap world service values) = heap := by
  rcases hostService?_some hs with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
  · simp only [World.call] at stopped ⊢
    repeat' split
    all_goals first | rfl | contradiction | simp_all

/-- A host call that trapped after its arguments: the heap as it was. -/
theorem host_trap_grows {sp : SrcProgram} {fuel : Nat} {st : State} {callee : Nat} {args : List Core.Expr}
    {values : List Value} {afterArgs : State} {r : Lanius.Trap} {st' : State}
    (outside : sp.funcs.length ≤ callee) (argsRun : evalExprs fuel sp.toCore st args = .done values afterArgs)
    (run : evalExpr (fuel + 1) sp.toCore st (.call callee args) = .trapped r st') : Grows afterArgs st' := by
  simp only [evalExpr, argsRun] at run
  rw [SrcProgram.function?_toCore, List.getElem?_eq_none outside] at run
  cases hs : hostService? callee with
  | none =>
    simp only [hs, Option.map_none, Semantics.Outcome.trapped.injEq] at run
    rw [← run.2]
    exact Grows.refl _
  | some service =>
    simp only [hs, Option.map_some, hostFunc] at run
    split at run
    · simp only [Semantics.Outcome.trapped.injEq] at run
      rw [← run.2]
      exact Grows.refl _
    all_goals try (rename_i same _; simp at same; done)
    split at run
    · simp only [Semantics.Outcome.trapped.injEq] at run
      rw [← run.2]
      exact Grows.refl _
    rename_i synced syncedOk
    obtain ⟨same, next⟩ := syncTo_heap syncedOk
    have g0 : Grows afterArgs synced := Grows.heap (Nat.le_of_eq next.symm) (by rw [same])
    refine g0.trans ?_
    cases called : World.call synced.heap synced.world service values with
    | returned v h w =>
      rw [called] at run
      simp only [Semantics.worldCallOutcome] at run
      split at run
      · simp at run
      · simp only [Semantics.Outcome.trapped.injEq] at run
        rw [← run.2]
        exact Grows.heap (Nat.le_of_eq (hostCall_next hs called).symm) rfl
    | exited c h w =>
      have hh := hostCall_resultHeap hs synced.heap synced.world values (by rw [called]; intro _ _ _ h; cases h)
      rw [called] at run hh
      simp only [resultHeap] at hh
      subst hh
      simp only [Semantics.worldCallOutcome] at run
      split at run
      · simp at run
      · simp only [Semantics.Outcome.trapped.injEq] at run
        rw [← run.2]
        exact Grows.heap (Nat.le_refl _) rfl
    | unavailable s h w =>
      have hh := hostCall_resultHeap hs synced.heap synced.world values (by rw [called]; intro _ _ _ h; cases h)
      rw [called] at run hh
      simp only [resultHeap] at hh
      subst hh
      simp only [Semantics.worldCallOutcome, Semantics.Outcome.trapped.injEq] at run
      rw [← run.2]
      exact Grows.heap (Nat.le_refl _) rfl
    | trapped t h w =>
      have hh := hostCall_resultHeap hs synced.heap synced.world values (by rw [called]; intro _ _ _ h; cases h)
      rw [called] at run hh
      simp only [resultHeap] at hh
      subst hh
      simp only [Semantics.worldCallOutcome, Semantics.Outcome.trapped.injEq] at run
      rw [← run.2]
      exact Grows.heap (Nat.le_refl _) rfl
    | typeMismatch h w =>
      have hh := hostCall_resultHeap hs synced.heap synced.world values (by rw [called]; intro _ _ _ h; cases h)
      rw [called] at run hh
      simp only [resultHeap] at hh
      subst hh
      simp only [Semantics.worldCallOutcome, Semantics.Outcome.trapped.injEq] at run
      rw [← run.2]
      exact Grows.heap (Nat.le_refl _) rfl

theorem call_grows {sp : SrcProgram} {k : Nat} (ih : GrowsBelow sp k) {st : State} {callee : Nat}
    {args : List SrcExpr} {v : Value} {st' : State}
    (run : evalExpr k sp.toCore st (.call callee (args.map SrcExpr.toCore)) = .done v st') :
    Grows st st' := by
  cases k with
  | zero => simp [evalExpr] at run
  | succ k =>
    obtain ⟨values, afterArgs, argsRun, ⟨-, f, completed, c, found, _, bodyRun, result, rfl⟩ |
      ⟨-, service, hs, returns⟩⟩ := call_cases run
    · have := evalExprs_state args argsRun
      subst this
      have entry := bindLocals_same (paramBindings f.params values) { afterArgs with locals := [] }
      exact (((Grows.same (st := afterArgs) rfl rfl).trans (Grows.same entry.1 entry.2)).trans
        (ih k (Nat.lt_succ_self k) bodyRun)).trans (Grows.same (st' := restoreLocals afterArgs completed) rfl rfl)
    · have := evalExprs_state args argsRun
      subst this
      exact host_grows hs returns

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
          exact Grows.heap (allocate_grows allocated) rfl
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
  cases k with
  | zero => simp [evalExpr] at run
  | succ k =>
    simp only [evalExpr] at run
    split at run
    · rename_i p o next argsRun
      have := evalExprs_state [pointer, offset] argsRun
      subst this
      split at run
      · simp at run
      rename_i synced syncedOk
      obtain ⟨same, n0⟩ := syncTo_heap syncedOk
      split at run
      · simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨-, rfl⟩ := run
        exact Grows.heap (Nat.le_of_eq n0.symm) (by rw [same])
      · simp at run
    all_goals simp at run

theorem storeByte_grows {P : Core.Program} {k : Nat} {st : State} {pointer offset value : SrcExpr}
    {v : Value} {st' : State}
    (run : evalExpr k P st (.storeByte pointer.toCore offset.toCore value.toCore) = .done v st') :
    Grows st st' := by
  cases k with
  | zero => simp [evalExpr] at run
  | succ k =>
    simp only [evalExpr] at run
    split at run
    · rename_i p o b next argsRun
      have := evalExprs_state [pointer, offset, value] argsRun
      subst this
      split at run
      · simp at run
      rename_i synced syncedOk
      obtain ⟨same, n0⟩ := syncTo_heap syncedOk
      split at run
      · simp at run
      · rename_i heap stored
        split at run
        · rename_i updated back
          simp only [Semantics.Outcome.done.injEq] at run
          obtain ⟨-, rfl⟩ := run
          obtain ⟨h1, v1⟩ := syncFrom_same back
          refine Grows.heap ?_ ?_
          · simp only [h1, storeByte_next stored, n0, Nat.le_refl]
          · rw [v1]; have := congrArg State.i32ArrayViews same; exact this
        · simp at run
    all_goals simp at run

theorem dealloc_grows {P : Core.Program} {k : Nat} {st : State} {pointer size : SrcExpr} {shift : Nat}
    {v : Value} {st' : State}
    (run : evalExpr k P st (.dealloc pointer.toCore size.toCore (.value (.unsigned .usize (2 ^ shift)))) =
      .done v st') : Grows st st' := by
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
      split at run
      · simp at run
      rename_i synced syncedOk
      obtain ⟨same, n0⟩ := syncTo_heap syncedOk
      split at run
      · rename_i heap freed
        simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨-, rfl⟩ := run
        refine Grows.heap ?_ ?_
        · simp only [deallocate_next freed, n0, Nat.le_refl]
        · have := congrArg State.i32ArrayViews same; exact this
      · simp at run
    all_goals simp at run

theorem structValue_state {P : Core.Program} {k : Nat} {st : State} {ty : SrcType} {es : List SrcExpr}
    {v : Value} {st' : State} (run : evalExpr k P st (ty.literal (es.map SrcExpr.toCore)) = .done v st') :
    st' = st := by
  cases k with
  | zero => cases ty <;> simp [evalExpr] at run
  | succ k =>
    cases ty <;> simp only [SrcType.literal, evalExpr] at run <;> split at run <;>
      first
      | (rename_i vs next argsRun
         simp only [Semantics.Outcome.done.injEq] at run
         rw [← run.2]
         exact evalExprs_state es argsRun)
      | simp at run

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

/-- Arms whose bodies leave the state as it was leave the heap as it was. -/
theorem pureArms_same {P : Core.Program} {value : Value} : ∀ (arms : List (Core.Pattern × Core.Expr)),
    (∀ a ∈ arms, ∀ {k : Nat} {st : State} {v : Value} {st' : State}, evalExpr k P st a.2 = .done v st' → st' = st) →
    ∀ {k : Nat} {st : State} {v : Value} {st' : State},
      Semantics.evalMatchArms k P st value arms = .done v st' →
      st'.heap = st.heap ∧ st'.i32ArrayViews = st.i32ArrayViews
  | [], _, k, st, v, st', run => by cases k <;> simp [Semantics.evalMatchArms] at run
  | (pat, body) :: rest, pure, k, st, v, st', run => by
    cases k with
    | zero => simp [Semantics.evalMatchArms] at run
    | succ k =>
      simp only [Semantics.evalMatchArms] at run
      split at run
      · exact pureArms_same rest (fun a mem => pure a (List.mem_cons_of_mem _ mem)) run
      · rename_i bindings _
        cases armRun : evalExpr k P (st.bindLocals bindings) body with
        | done w completed =>
          simp only [armRun, Semantics.restoreOutcomeLocals, Semantics.Outcome.done.injEq] at run
          obtain ⟨-, rfl⟩ := run
          have := pure (pat, body) (List.mem_cons_self ..) armRun
          subst this
          exact bindLocals_same bindings st
        | trapped => simp [armRun, Semantics.restoreOutcomeLocals] at run
        | exited => simp [armRun, Semantics.restoreOutcomeLocals] at run
        | outOfFuel => simp [armRun, Semantics.restoreOutcomeLocals] at run

theorem matchPure_grows {P : Core.Program} {k : Nat} {st : State} {scrutinee : Nat}
    {arms : List (Core.Pattern × Core.Expr)}
    (pure : ∀ a ∈ arms, ∀ {k : Nat} {st : State} {v : Value} {st' : State}, evalExpr k P st a.2 = .done v st' → st' = st)
    {v : Value} {st' : State} (run : evalExpr k P st (.matchValue (.local scrutinee) arms) = .done v st') :
    Grows st st' := by
  cases k with
  | zero => simp [evalExpr] at run
  | succ k =>
    simp only [evalExpr] at run
    split at run
    · rename_i w next scrutineeRun
      have := eval_local_state scrutineeRun
      subst this
      have := pureArms_same arms pure run
      exact Grows.same this.1 this.2
    all_goals simp at run

theorem value_state {P : Core.Program} (x : Value) {k : Nat} {st : State} {v : Value} {st' : State}
    (run : evalExpr k P st (.value x) = .done v st') : st' = st := by
  cases k <;> simp [evalExpr] at run
  exact run.2.symm

/-- Making a raw slice leaves the state as it was. -/
theorem sliceFrom_grows {P : Core.Program} {k : Nat} {st : State} {element : SrcType}
    {pointer length : SrcExpr} {v : Value} {st' : State}
    (run : evalExpr k P st (element.sliceFrom pointer.toCore length.toCore) = .done v st') :
    Grows st st' := by
  cases k with
  | zero => cases element <;> simp [evalExpr] at run
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
              exact Grows.refl _
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

/-- Resolving `slice[index]` for a write grows as its index does. -/
theorem evalPlace_index_grows {P : Core.Program} {k : Nat} {st : State} {slice : Nat} {index : Core.Expr}
    {r : Semantics.ResolvedPlace} {st' : State}
    (hi : ∀ {st1 v st2}, evalExpr k P st1 index = .done v st2 → Grows st1 st2)
    (run : Semantics.evalPlace (k + 1) P st .address (.index (.local slice) index) = .done r st') :
    Grows st st' := by
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
           have grown := hi indexRun
           repeat' split at run
           all_goals first
             | (simp only [Semantics.Outcome.done.injEq] at run; rw [← run.2]; exact grown)
             | simp at run)
        | simp at run
  all_goals simp at run

/-! ## Places (F5) -/

/-- Every expression a place evaluates grows the state, at fuel up to `k`. -/
inductive PlaceGrows (P : Core.Program) (k : Nat) : Core.Place → Prop
  | local (id : Nat) : PlaceGrows P k (.local id)
  | field {base : Core.Place} (f : Nat) : PlaceGrows P k base → PlaceGrows P k (.field base f)
  | index {base : Core.Place} {e : Core.Expr} : PlaceGrows P k base →
      (∀ {m : Nat} {st : State} {v : Value} {st' : State}, m ≤ k → evalExpr m P st e = .done v st' → Grows st st') →
      PlaceGrows P k (.index base e)
  | deref {r : Core.Expr} :
      (∀ {m : Nat} {st : State} {v : Value} {st' : State}, m ≤ k → evalExpr m P st r = .done v st' → Grows st st') →
      PlaceGrows P k (.deref r)

/-- A place whose expressions grow the state grows it. -/
theorem evalPlace_grows {P : Core.Program} {k : Nat} : ∀ {place : Core.Place}, PlaceGrows P k place →
    ∀ {m : Nat}, m ≤ k + 1 → ∀ {st : State} {acc : Semantics.PlaceAccess} {r : Semantics.ResolvedPlace} {st' : State},
      Semantics.evalPlace m P st acc place = .done r st' → Grows st st'
  | _, .local id, m, _, st, acc, r, st', run => by
    cases m with
    | zero => simp [Semantics.evalPlace] at run
    | succ m =>
      simp only [Semantics.evalPlace] at run
      repeat' split at run
      all_goals first
        | (simp only [Semantics.Outcome.done.injEq] at run; rw [← run.2]; exact Grows.refl _)
        | simp at run
  | _, .field f hb, m, le, st, acc, r, st', run => by
    cases m with
    | zero => simp [Semantics.evalPlace] at run
    | succ m =>
      cases hr : Semantics.evalPlace m P st .address _ with
      | done rb next =>
        have g := evalPlace_grows hb (by omega) hr
        simp only [Semantics.evalPlace, hr] at run
        repeat' split at run
        all_goals first
          | (simp only [Semantics.Outcome.done.injEq] at run; rw [← run.2]; exact g)
          | simp at run
      | trapped _ _ => simp [Semantics.evalPlace, hr] at run
      | exited _ _ => simp [Semantics.evalPlace, hr] at run
      | outOfFuel => simp [Semantics.evalPlace, hr] at run
  | _, .index hb he, m, le, st, acc, r, st', run => by
    cases m with
    | zero => simp [Semantics.evalPlace] at run
    | succ m =>
      cases hr : Semantics.evalPlace m P st .read _ with
      | done rb afterBase =>
        have g1 := evalPlace_grows hb (by omega) hr
        cases hi : evalExpr m P afterBase _ with
        | done iv afterIndex =>
          have g2 := he (by omega) hi
          simp only [Semantics.evalPlace, hr, hi] at run
          repeat' split at run
          all_goals first
            | (simp only [Semantics.Outcome.done.injEq] at run; rw [← run.2]; exact g1.trans g2)
            | simp at run
        | trapped _ _ =>
          simp only [Semantics.evalPlace, hr, hi] at run
          repeat' split at run
          all_goals simp at run
        | exited _ _ =>
          simp only [Semantics.evalPlace, hr, hi] at run
          repeat' split at run
          all_goals simp at run
        | outOfFuel =>
          simp only [Semantics.evalPlace, hr, hi] at run
          repeat' split at run
          all_goals simp at run
      | trapped _ _ => simp [Semantics.evalPlace, hr] at run
      | exited _ _ => simp [Semantics.evalPlace, hr] at run
      | outOfFuel => simp [Semantics.evalPlace, hr] at run
  | _, .deref hr', m, le, st, acc, r, st', run => by
    cases m with
    | zero => simp [Semantics.evalPlace] at run
    | succ m =>
      simp only [Semantics.evalPlace] at run
      split at run
      all_goals first
        | (simp at run; done)
        | (rename_i refRun
           have g := hr' (by omega) refRun
           repeat' split at run
           all_goals first
             | (simp only [Semantics.Outcome.done.injEq] at run; rw [← run.2]; exact g)
             | simp at run)

/-- An assignment, plain or compound, whose place and value may grow the heap. -/
theorem assign_op_grows_eff {P : Core.Program} {k : Nat} {st : State} {op : Core.AssignOp} {place : Core.Place}
    {e : Core.Expr} {u : Value} {st' : State}
    (placeOk : ∀ {acc r st1}, Semantics.evalPlace k P st acc place = .done r st1 → Grows st st1)
    (value : ∀ {st1 rv st2}, evalExpr k P st1 e = .done rv st2 → Grows st1 st2)
    (run : evalExpr (k + 1) P st (.assign op place e) = .done u st') : Grows st st' := by
  simp only [evalExpr] at run
  split at run
  · rename_i resolved afterPlace placeRun
    have g1 := placeOk placeRun
    split at run
    · rename_i rv afterValue valueRun
      have g2 := value valueRun
      split at run
      · simp at run
      rename_i result _
      split at run
      · rename_i assigned written
        split at run
        · rename_i coherent synced
          simp only [Semantics.Outcome.done.injEq] at run
          obtain ⟨-, rfl⟩ := run
          obtain ⟨n3, v3⟩ := synchronized_grows synced
          obtain ⟨n4, v4⟩ := writeNative_grows written
          exact g1.trans (g2.trans (Grows.heap (st := afterValue) (st' := coherent) (Nat.le_of_eq (n3.trans n4).symm) (v3.trans v4)))
        · simp at run
      · simp at run
    all_goals simp at run
  all_goals simp at run

/-! ## Effectful expressions -/

/-- Every effectful expression Core completes with at most `k` fuel grows. -/
def EffGrows (sp : SrcProgram) (k : Nat) : Prop :=
  ∀ m ≤ k, ∀ {st : State} {e : SrcEff} {v : Value} {st' : State},
    evalExpr m sp.toCore st e.toCore = .done v st' → Grows st st'

theorem EffGrows.lower {sp : SrcProgram} {k j : Nat} (ih : EffGrows sp k) (le : j ≤ k) : EffGrows sp j :=
  fun m lt => ih m (Nat.le_trans lt le)

/-- The place an effectful expression names grows the state as its parts do. -/
theorem exprPlace_grows {sp : SrcProgram} {k : Nat} (ih : EffGrows sp k) :
    ∀ place : SrcEff, PlaceGrows sp.toCore k (exprPlace place.toCore)
  | .ePure (.local id) => .local id
  | .ePure (.field id f) => .field f (.local id)
  | .ePure (.int x0) => .deref fun _ run => by rw [(SrcExpr.int x0).eval_state run]; exact Grows.refl _
  | .ePure (.boolean x0) => .deref fun _ run => by rw [(SrcExpr.boolean x0).eval_state run]; exact Grows.refl _
  | .ePure (.unsigned x0 x1) => .deref fun _ run => by rw [(SrcExpr.unsigned x0 x1).eval_state run]; exact Grows.refl _
  | .ePure (.negate x0) => .deref fun _ run => by rw [(SrcExpr.negate x0).eval_state run]; exact Grows.refl _
  | .ePure (.not x0) => .deref fun _ run => by rw [(SrcExpr.not x0).eval_state run]; exact Grows.refl _
  | .ePure (.apply x0 x1 x2) => .deref fun _ run => by rw [(SrcExpr.apply x0 x1 x2).eval_state run]; exact Grows.refl _
  | .ePure (.cast x0 x1) => .deref fun _ run => by rw [(SrcExpr.cast x0 x1).eval_state run]; exact Grows.refl _
  | .ePure .null => .deref fun _ run => by rw [(SrcExpr.null).eval_state run]; exact Grows.refl _
  | .ePure (.char x0) => .deref fun _ run => by rw [(SrcExpr.char x0).eval_state run]; exact Grows.refl _
  | .ePure (.float x0 x1) => .deref fun _ run => by rw [(SrcExpr.float x0 x1).eval_state run]; exact Grows.refl _
  | .eIndex _ index => .index (.local _) fun le run => ih _ le (e := index) run
  | .eField base f => .field f (exprPlace_grows ih base)
  | .eAt base index => .index (exprPlace_grows ih base) fun le run => ih _ le (e := index) run
  | .eDeref _ reference => .deref fun le run => ih _ le (e := reference) run
  | .eCall x0 x1 => .deref fun le run => ih _ le (e := (SrcEff.eCall x0 x1)) run
  | .eApply x0 x1 x2 => .deref fun le run => ih _ le (e := (SrcEff.eApply x0 x1 x2)) run
  | .eNeg x0 => .deref fun le run => ih _ le (e := (SrcEff.eNeg x0)) run
  | .eNot x0 => .deref fun le run => ih _ le (e := (SrcEff.eNot x0)) run
  | .eCast x0 x1 => .deref fun le run => ih _ le (e := (SrcEff.eCast x0 x1)) run
  | .eStruct ty fields => by
    have h : exprPlace (SrcEff.eStruct ty fields).toCore = .deref (SrcEff.eStruct ty fields).toCore := by
      cases ty <;> rfl
    rw [h]
    exact .deref fun le run => ih _ le (e := SrcEff.eStruct ty fields) run
  | .eVariant x0 x1 x2 => .deref fun le run => ih _ le (e := (SrcEff.eVariant x0 x1 x2)) run
  | .eMatch x0 x1 x2 x3 x4 => .deref fun le run => ih _ le (e := (SrcEff.eMatch x0 x1 x2 x3 x4)) run
  | .eDivide x0 x1 x2 => .deref fun le run => ih _ le (e := (SrcEff.eDivide x0 x1 x2)) run
  | .eStride x0 => .deref fun le run => ih _ le (e := (SrcEff.eStride x0)) run
  | .arraySlice x0 x1 => .deref fun le run => ih _ le (e := (SrcEff.arraySlice x0 x1)) run
  | .eIf x0 x1 x2 x3 => .deref fun le run => ih _ le (e := (SrcEff.eIf x0 x1 x2 x3)) run
  | .eLet x0 x1 x2 x3 x4 => .deref fun le run => ih _ le (e := (SrcEff.eLet x0 x1 x2 x3 x4)) run
  | .eLen x0 => .deref fun le run => ih _ le (e := (SrcEff.eLen x0)) run
  | .eStr x0 x1 => .deref fun le run => ih _ le (e := (SrcEff.eStr x0 x1)) run
  | .eBorrow x0 x1 => .deref fun le run => ih _ le (e := (SrcEff.eBorrow x0 x1)) run

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

/-- A let in an expression grows as its body does. -/
theorem letArm_grows {sp : SrcProgram} {w : Value} {id : Nat} {b : SrcEff} {k : Nat} (ih : EffGrows sp k)
    {st : State} {v : Value} {st' : State}
    (run : Semantics.evalMatchArms k sp.toCore st w [(.bind id, b.toCore)] = .done v st') : Grows st st' := by
  cases k with
  | zero => simp [Semantics.evalMatchArms] at run
  | succ k =>
    simp only [Semantics.evalMatchArms, Semantics.matchPattern] at run
    cases armRun : evalExpr k sp.toCore (st.bindLocals [(id, w)]) b.toCore with
    | done w' completed =>
      simp only [armRun, Semantics.restoreOutcomeLocals, Semantics.Outcome.done.injEq] at run
      obtain ⟨-, rfl⟩ := run
      have entry := bindLocals_same [(id, w)] st
      exact ((Grows.same entry.1 entry.2).trans (ih k (Nat.le_succ k) armRun)).trans (Grows.same rfl rfl)
    | trapped => simp [armRun, Semantics.restoreOutcomeLocals] at run
    | exited => simp [armRun, Semantics.restoreOutcomeLocals] at run
    | outOfFuel => simp [armRun, Semantics.restoreOutcomeLocals] at run

/-- A conditional's arms grow as the arm Core runs does. -/
theorem ifArms_grows {sp : SrcProgram} {w : Value} {a b : SrcEff} {k : Nat} (ih : EffGrows sp k)
    {st : State} {v : Value} {st' : State}
    (run : Semantics.evalMatchArms k sp.toCore st w [(.literal (.boolean true), a.toCore), (.wildcard, b.toCore)] =
      .done v st') : Grows st st' := by
  have arm : ∀ {m : Nat} {e : SrcEff}, m ≤ k →
      Semantics.restoreOutcomeLocals st (evalExpr m sp.toCore (st.bindLocals []) e.toCore) = .done v st' →
      Grows st st' := by
    intro m e le r
    cases armRun : evalExpr m sp.toCore (st.bindLocals []) e.toCore with
    | done w' completed =>
      simp only [armRun, Semantics.restoreOutcomeLocals, Semantics.Outcome.done.injEq] at r
      obtain ⟨-, rfl⟩ := r
      exact (ih m le armRun).trans (Grows.same rfl rfl)
    | trapped => simp [armRun, Semantics.restoreOutcomeLocals] at r
    | exited => simp [armRun, Semantics.restoreOutcomeLocals] at r
    | outOfFuel => simp [armRun, Semantics.restoreOutcomeLocals] at r
  cases k with
  | zero => simp [Semantics.evalMatchArms] at run
  | succ k =>
    simp only [Semantics.evalMatchArms] at run
    split at run
    · cases k with
      | zero => simp [Semantics.evalMatchArms] at run
      | succ k =>
        simp only [Semantics.evalMatchArms, Semantics.matchPattern] at run
        exact arm (by omega) run
    · rename_i bindings found
      have nil : bindings = [] := by
        simp only [Semantics.matchPattern] at found
        split at found <;> simp_all
      subst nil
      exact arm (by omega) run

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
    obtain ⟨values, afterArgs, argsRun, ⟨-, f, completed, c, found, _, bodyRun, result, rfl⟩ |
      ⟨-, service, hs, returns⟩⟩ := call_cases run
    · have entry := bindLocals_same (paramBindings f.params values) { afterArgs with locals := [] }
      exact ((effs_grows args ihe argsRun).trans (((Grows.same (st := afterArgs) rfl rfl).trans
        (Grows.same entry.1 entry.2)).trans (ih k (Nat.lt_succ_self k) bodyRun))).trans
        (Grows.same (st' := restoreLocals afterArgs completed) rfl rfl)
    · exact (effs_grows args ihe argsRun).trans (host_grows hs returns)
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
  | eNeg operand | eNot operand | eCast ty operand | eDeref ty operand =>
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
  | arraySlice element array =>
    simp only [SrcEff.toCore, evalExpr, Semantics.expressionPlace?] at run
    split at run
    · rename_i placeRun
      have := evalPlace_readLocal placeRun
      subst this
      simp only [Semantics.Outcome.done.injEq] at run
      rw [← run.2]
      exact Grows.refl _
    all_goals simp at run
  | eStride slice =>
    simp only [SrcEff.toCore, evalExpr] at run
    split at run
    · rename_i w next localRun
      have := eval_local_state localRun
      subst this
      repeat' split at run
      all_goals first
        | (simp only [Semantics.Outcome.done.injEq] at run; rw [← run.2]; exact Grows.refl _)
        | simp at run
    all_goals simp at run
  | eStruct ty fields =>
    simp only [SrcEff.toCore] at run
    cases ty <;> simp only [SrcType.literal, evalExpr] at run <;> split at run <;>
      first
      | (rename_i vs next argsRun
         simp only [Semantics.Outcome.done.injEq] at run
         rw [← run.2]
         exact effs_grows fields ihe argsRun)
      | simp at run
  | eVariant ty variant fields =>
    simp only [SrcEff.toCore, evalExpr] at run
    split at run
    · rename_i vs next argsRun
      simp only [Semantics.Outcome.done.injEq] at run
      rw [← run.2]
      exact effs_grows fields ihe argsRun
    all_goals simp at run
  | eMatch scrutinee ety ty binders values =>
    simp only [SrcEff.toCore, evalExpr] at run
    split at run
    · rename_i w next scrutineeRun
      exact (sub scrutineeRun).trans (effArms_grows binders values ety.typeId 0 ihe run)
    all_goals simp at run
  | eIf c ty a b =>
    simp only [SrcEff.toCore, evalExpr] at run
    split at run
    · rename_i w next condRun
      exact (sub condRun).trans (ifArms_grows ihe run)
    all_goals simp at run
  | eLet id ty a rt b =>
    simp only [SrcEff.toCore, evalExpr] at run
    split at run
    · rename_i w next valueRun
      exact (sub valueRun).trans (letArm_grows ihe run)
    all_goals simp at run
  | eLen slice =>
    simp only [SrcEff.toCore, evalExpr] at run
    split at run
    · rename_i w next localRun
      have := eval_local_state localRun
      subst this
      repeat' split at run
      all_goals first
        | (simp only [Semantics.Outcome.done.injEq] at run; rw [← run.2]; exact Grows.refl _)
        | simp at run
    all_goals simp at run
  | eStr offset chars =>
    simp only [SrcEff.toCore, evalExpr, Semantics.Outcome.done.injEq] at run
    rw [← run.2]
    exact Grows.refl _
  | eBorrow ty place =>
    simp only [SrcEff.toCore, evalExpr] at run
    split at run
    all_goals first
      | (simp at run; done)
      | (rename_i placeRun
         have g := evalPlace_grows (exprPlace_grows ihe place) (Nat.le_succ k) placeRun
         simp only [Semantics.Outcome.done.injEq] at run
         rw [← run.2]
         exact g)
  | eField base field =>
    simp only [SrcEff.toCore, evalExpr] at run
    split at run
    all_goals first
      | (simp at run; done)
      | (rename_i baseRun
         have g := sub baseRun
         repeat' split at run
         all_goals first
           | (simp only [Semantics.Outcome.done.injEq] at run; rw [← run.2]; exact g)
           | simp at run)
  | eAt base index =>
    simp only [SrcEff.toCore, evalExpr] at run
    split at run
    all_goals first
      | (simp at run; done)
      | (rename_i baseRun
         have g := sub baseRun
         split at run
         · rename_i iv afterIndex indexRun
           have g2 := sub indexRun
           repeat' split at run
           all_goals first
             | (simp only [Semantics.Outcome.done.injEq] at run; rw [← run.2]; exact g.trans g2)
             | simp at run
         all_goals simp at run)

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

/-- `Unreachable`'s Core code finishes only when the cell it binds was
already there with a value: then its state is the caller's, the binding
dropped. (In a fresh state the read traps, `uninitializedLocal`.) -/
theorem unreachable_done {P : Core.Program} {fuel : Nat} {st : State} {id : Nat} {ty : SrcType}
    {c : Completion} {st' : State}
    (run : execStmt fuel P st (SrcStmt.unreachable id ty).toCore = .done c st') :
    st' = Semantics.restoreLocals st (st.bindUninitialized id) ∧ (st.cellEntry? st.nextCell).isSome = true ∧
      ∃ v, c = .returned (some v) := by
  rcases fuel with _ | _ | _ | k
  · simp [execStmt] at run
  · simp [SrcStmt.toCore, execStmt, Semantics.restoreOutcomeLocals] at run
  · simp [SrcStmt.toCore, execStmt, evalExpr, Semantics.restoreOutcomeLocals] at run
  simp only [SrcStmt.toCore, execStmt, evalExpr] at run
  have cid : (st.bindUninitialized id).cellId? id = some st.nextCell := by
    simp [State.bindUninitialized, State.bindCell, State.cellId?]
  rw [cid] at run
  simp only at run
  cases hfind : st.cells.find? (fun cell => cell.id == st.nextCell) with
  | none =>
    have hent : (st.bindUninitialized id).cellEntry? st.nextCell = some ⟨st.nextCell, none⟩ := by
      simp [State.cellEntry?, State.bindUninitialized, State.bindCell, List.find?_append, hfind]
    rw [hent] at run
    simp [Semantics.restoreOutcomeLocals] at run
  | some e =>
    have hent : (st.bindUninitialized id).cellEntry? st.nextCell = some e := by
      simp [State.cellEntry?, State.bindUninitialized, State.bindCell, List.find?_append, hfind]
    rw [hent] at run
    rcases e with ⟨eid, _ | v⟩
    · simp [Semantics.restoreOutcomeLocals] at run
    · simp only [Semantics.restoreOutcomeLocals, Semantics.Outcome.done.injEq] at run
      obtain ⟨rfl, rfl⟩ := run
      exact ⟨rfl, by simp [State.cellEntry?, hfind], v, rfl⟩

/-- When `Unreachable`'s Core code traps, its state is the caller's with the
uninitialized binding dropped. -/
theorem unreachable_trapped {P : Core.Program} {fuel : Nat} {st : State} {id : Nat} {ty : SrcType}
    {r : Lanius.Trap} {st' : State}
    (run : execStmt fuel P st (SrcStmt.unreachable id ty).toCore = .trapped r st') :
    st' = Semantics.restoreLocals st (st.bindUninitialized id) := by
  rcases fuel with _ | _ | _ | k
  · simp [execStmt] at run
  · simp [SrcStmt.toCore, execStmt, Semantics.restoreOutcomeLocals] at run
  · simp [SrcStmt.toCore, execStmt, evalExpr, Semantics.restoreOutcomeLocals] at run
  simp only [SrcStmt.toCore, execStmt, evalExpr] at run
  have cid : (st.bindUninitialized id).cellId? id = some st.nextCell := by
    simp [State.bindUninitialized, State.bindCell, State.cellId?]
  rw [cid] at run
  simp only at run
  cases hfind : st.cells.find? (fun cell => cell.id == st.nextCell) with
  | none =>
    have hent : (st.bindUninitialized id).cellEntry? st.nextCell = some ⟨st.nextCell, none⟩ := by
      simp [State.cellEntry?, State.bindUninitialized, State.bindCell, List.find?_append, hfind]
    rw [hent] at run
    simp only [Semantics.restoreOutcomeLocals, Semantics.Outcome.trapped.injEq] at run
    exact run.2.symm
  | some e =>
    have hent : (st.bindUninitialized id).cellEntry? st.nextCell = some e := by
      simp [State.cellEntry?, State.bindUninitialized, State.bindCell, List.find?_append, hfind]
    rw [hent] at run
    rcases e with ⟨eid, _ | v⟩
    · simp only [Semantics.restoreOutcomeLocals, Semantics.Outcome.trapped.injEq] at run
      exact run.2.symm
    · simp [Semantics.restoreOutcomeLocals] at run

/-- A local's read place leaves the state as it was. -/
theorem evalPlace_local_read {P : Core.Program} {k : Nat} {st : State} {id : Nat}
    {r : Semantics.ResolvedPlace} {st' : State}
    (run : Semantics.evalPlace k P st .read (.local id) = .done r st') :
    st' = st ∧ ∃ cell, st.cellId? id = some cell ∧ r.root = cell ∧ r.projections = [] ∧
      ∃ e, st.cellEntry? cell = some e ∧ r.value = e.value := by
  cases k with
  | zero => simp [Semantics.evalPlace] at run
  | succ k =>
    simp only [Semantics.evalPlace] at run
    split at run
    · simp at run
    rename_i cell hcell
    split at run
    · simp at run
    rename_i e he
    split at run
    · simp at run
    simp only [Semantics.Outcome.done.injEq] at run
    obtain ⟨rfl, rfl⟩ := run
    exact ⟨rfl, cell, hcell, rfl, rfl, e, he, rfl⟩

theorem mapBorrowed_next {heap heap' : Memory.Heap} {bytes : List UInt8} {a : Nat}
    (mapped : heap.mapBorrowed bytes 4 = Memory.AllocationResult.allocated a heap') : heap.nextAddress ≤ heap'.nextAddress := by
  simp only [Memory.Heap.mapBorrowed] at mapped
  split at mapped
  · simp at mapped
  simp only [Memory.AllocationResult.allocated.injEq] at mapped
  obtain ⟨-, rfl⟩ := mapped
  exact Nat.le_trans (Nat.le_trans (Nat.le_max_left _ 1) (memAlignUp_ge (max heap.nextAddress 1) 4 (by decide)))
    (Nat.le_add_right _ _)

/-- Core's `mapI32ArrayView` moves the cursor up and adds at most one view. -/
theorem mapView_grows {st : State} {root : Nat} {projections : List Core.ValueProjection}
    {elements : List Value} {v : Value} {st' : State}
    (run : Semantics.mapI32ArrayView st root projections elements = .done v st') : Grows st st' := by
  simp only [Semantics.mapI32ArrayView] at run
  split at run
  · split at run
    · rename_i synced ok
      simp only [Semantics.Outcome.done.injEq] at run
      obtain ⟨-, rfl⟩ := run
      obtain ⟨same, n0⟩ := syncTo_heap ok
      exact Grows.heap (Nat.le_of_eq n0.symm) (by rw [same])
    · simp at run
  · split at run
    · simp at run
    · split at run
      · rename_i address heap mapped
        simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨-, rfl⟩ := run
        exact ⟨mapBorrowed_next mapped, _, rfl⟩
      · simp at run
      · simp at run

/-- `i32_array_data_ptr` of a local grows the state. -/
theorem view_grows {P : Core.Program} {k : Nat} {st : State} {id : Nat} {v : Value} {st' : State}
    (run : evalExpr k P st (.i32ArrayDataPtr (.local id)) = .done v st') : Grows st st' := by
  cases k with
  | zero => simp [evalExpr] at run
  | succ k =>
    simp only [evalExpr, Semantics.expressionPlace?] at run
    split at run
    · rename_i next placeRun
      obtain ⟨rfl, -⟩ := evalPlace_local_read placeRun
      exact mapView_grows run
    all_goals simp at run

/-- `string_data_ptr` of a string literal: Core maps the string's storage
into a fresh borrowed block. -/
theorem strPtr_run {P : Core.Program} {k : Nat} {st : State} {text : String} {v : Value} {st' : State}
    (run : evalExpr k P st (.stringDataPtr (.value (.string text))) = .done v st') :
    ∃ p heap', st.heap.mapBorrowed (Semantics.stringStorage text) 4 = .allocated p heap' ∧ v = .pointer p ∧
      st' = { st with heap := heap' } := by
  cases k with
  | zero => simp [evalExpr] at run
  | succ k =>
    cases k with
    | zero => simp [evalExpr] at run
    | succ k =>
      simp only [evalExpr, Semantics.mapStringDataPtr] at run
      split at run
      · rename_i p heap' map
        simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨rfl, rfl⟩ := run
        exact ⟨p, heap', map, rfl, rfl⟩
      · simp at run
      · simp at run

/-- `string_data_ptr` of a string literal grows the state. -/
theorem strPtr_grows {P : Core.Program} {k : Nat} {st : State} {text : String} {v : Value} {st' : State}
    (run : evalExpr k P st (.stringDataPtr (.value (.string text))) = .done v st') : Grows st st' := by
  obtain ⟨p, heap', map, -, rfl⟩ := strPtr_run run
  exact Grows.heap (mapBorrowed_next map) rfl

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
    | unreachable id ty =>
      obtain ⟨rfl, -⟩ := unreachable_done run
      exact Grows.same rfl rfl
    | letView id length fields pointer body =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i v next valueRun
        have := structValue_state valueRun
        subst this
        refine let_grows (fun {s0 c0 s1} r => ?_) run
        cases f with
        | zero => simp [execStmt] at r
        | succ g =>
          simp only [execStmt] at r
          split at r
          · rename_i w after ptrRun
            exact (view_grows ptrRun).trans
              (let_grows (fun r' => ih g (Nat.lt_succ_of_lt (Nat.lt_succ_self g)) (s := body) r') r)
          all_goals simp at r
      all_goals simp at run
    | letStr pointer chars body =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i w after ptrRun
        exact (strPtr_grows ptrRun).trans (let_grows (fun r => below (s := body) r) run)
      all_goals simp at run
    | matchArm scrutinee enumId variant binds binder ty body rest =>
      simp only [SrcStmt.toCore] at run
      generalize hpats : (if binds then [Core.Pattern.wildcard] else []) = pats at run
      generalize hthen : (if binds then .letLocal binder ty.toCore (.matchValue (.local scrutinee)
        [(.enumVariant enumId variant [.bind binder], .local binder)]) body.toCore else body.toCore) = T at run
      simp only [execStmt] at run
      have testPure : ∀ a ∈ [(Core.Pattern.enumVariant enumId variant pats, Core.Expr.value (.boolean true)),
          (Core.Pattern.wildcard, Core.Expr.value (.boolean false))],
          ∀ {k : Nat} {st : State} {v : Value} {st' : State}, evalExpr k sp.toCore st a.2 = .done v st' → st' = st := by
        intro a mem
        simp only [List.mem_cons, List.not_mem_nil, or_false] at mem
        rcases mem with rfl | rfl
        · exact value_state _
        · exact value_state _
      split at run
      · rename_i next testRun
        refine (matchPure_grows testPure testRun).trans ?_
        rw [← hthen] at run
        split at run
        · cases f with
          | zero => simp [execStmt] at run
          | succ g =>
            simp only [execStmt] at run
            split at run
            · rename_i v n2 initRun
              have bindPure : ∀ a ∈ [(Core.Pattern.enumVariant enumId variant [.bind binder], Core.Expr.local binder)],
                  ∀ {k : Nat} {st : State} {v : Value} {st' : State},
                    evalExpr k sp.toCore st a.2 = .done v st' → st' = st := by
                intro a mem
                simp only [List.mem_cons, List.not_mem_nil, or_false] at mem
                subst mem
                exact fun r => eval_local_state r
              exact (matchPure_grows bindPure initRun).trans
                (let_grows (fun r => ihf g (Nat.lt_succ_self g) (s := body) r) run)
            all_goals simp at run
        · exact below (s := body) run
      · rename_i next testRun
        exact (matchPure_grows testPure testRun).trans (below (s := rest) run)
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
    | setIndexEval slice index value =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i u next assignRun
        simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨-, rfl⟩ := run
        cases f with
        | zero => simp [evalExpr] at assignRun
        | succ k =>
          cases k with
          | zero => simp [evalExpr, Semantics.evalPlace] at assignRun
          | succ k =>
            exact assign_grows_eff (fun r => evalPlace_index_grows
              (fun r => eff_grows (k + 2) ihf k (by omega) r) r)
              (fun r => eff_grows (k + 2) ihf (k + 1) (Nat.le_succ _) r) assignRun
      all_goals simp at run
    | setFieldEval id index value =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i u next assignRun
        simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨-, rfl⟩ := run
        cases f with
        | zero => simp [evalExpr] at assignRun
        | succ k =>
          exact assign_grows_eff (fun r => by have := (evalPlace_field r).1; subst this; exact Grows.refl _)
            (fun r => eff_grows (k + 1) ihf k (Nat.le_succ _) r) assignRun
      all_goals simp at run
    | setPlace place value =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i u next assignRun
        simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨-, rfl⟩ := run
        cases f with
        | zero => simp [evalExpr] at assignRun
        | succ k =>
          exact assign_op_grows_eff
            (fun r => evalPlace_grows (exprPlace_grows (eff_grows (k + 1) ihf) place) (by omega) r)
            (fun r => eff_grows (k + 1) ihf k (Nat.le_succ _) r) assignRun
      all_goals simp at run
    | setPlaceOp op place value =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i u next assignRun
        simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨-, rfl⟩ := run
        cases f with
        | zero => simp [evalExpr] at assignRun
        | succ k =>
          exact assign_op_grows_eff
            (fun r => evalPlace_grows (exprPlace_grows (eff_grows (k + 1) ihf) place) (by omega) r)
            (fun r => eff_grows (k + 1) ihf k (Nat.le_succ _) r) assignRun
      all_goals simp at run
    | returnUnit =>
      simp only [SrcStmt.toCore, execStmt, Semantics.Outcome.done.injEq] at run
      obtain ⟨-, rfl⟩ := run
      exact Grows.refl _
    | assert condition =>
      simp only [SrcStmt.toCore, execStmt] at run
      split at run
      · rename_i u next assertRun
        simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨-, rfl⟩ := run
        cases f with
        | zero => simp [evalExpr] at assertRun
        | succ k =>
          simp only [evalExpr] at assertRun
          split at assertRun
          · rename_i w mid condRun
            have g := eff_grows (k + 1) ihf k (Nat.le_succ _) condRun
            split at assertRun
            all_goals (try simp only [Semantics.Outcome.done.injEq, reduceCtorEq] at assertRun)
            all_goals (try obtain ⟨-, rfl⟩ := assertRun)
            all_goals simp_all
          all_goals simp at assertRun
      all_goals simp at run
    | «break» | «continue» =>
      simp only [SrcStmt.toCore, execStmt, Semantics.Outcome.done.injEq] at run
      obtain ⟨-, rfl⟩ := run
      exact Grows.refl _

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
