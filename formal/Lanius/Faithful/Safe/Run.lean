import Lanius.Faithful.Safe.Eff
import Lanius.Faithful.Sim.PrimInv

/-! # Runs that trap only definedly, built along a body

`SafeE P st e`: every Core run of `e` from `st` that traps, at a state whose
heap cursor is at most `2 ^ 64`, traps with a defined trap; `SafeEs` and
`SafeS` for lists and statements. `Known P st e v`: no run of `e` from `st`
traps, and every run that completes returns `v` and leaves `st`. One lemma
per construct builds these along a body, the way the prims and the driver
are written: each part is safe, and the rest is safe from wherever each
completed run of the part left it. -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State Completion evalExpr evalExprs evalMatchArms execStmt restoreLocals)

def SafeE (P : Core.Program) (st : State) (e : Core.Expr) : Prop :=
  ∀ k r s, evalExpr k P st e = .trapped r s → s.heap.nextAddress ≤ 2 ^ 64 → undefinedTrap r = false

def SafeEs (P : Core.Program) (st : State) (es : List Core.Expr) : Prop :=
  ∀ k r s, evalExprs k P st es = .trapped r s → s.heap.nextAddress ≤ 2 ^ 64 → undefinedTrap r = false

def SafeS (P : Core.Program) (st : State) (s : Core.Stmt) : Prop :=
  ∀ k r s', execStmt k P st s = .trapped r s' → s'.heap.nextAddress ≤ 2 ^ 64 → undefinedTrap r = false

structure Known (P : Core.Program) (st : State) (e : Core.Expr) (v : Value) : Prop where
  safe : ∀ {k r s}, evalExpr k P st e = .trapped r s → False
  done : ∀ {k u s}, evalExpr k P st e = .done u s → u = v ∧ s = st

structure Knowns (P : Core.Program) (st : State) (es : List Core.Expr) (vs : List Value) : Prop where
  safe : ∀ {k r s}, evalExprs k P st es = .trapped r s → False
  done : ∀ {k us s}, evalExprs k P st es = .done us s → us = vs ∧ s = st

section
variable {P : Core.Program} {st : State}

/-! ## Known values -/

theorem Known.safeE {e : Core.Expr} {v : Value} (h : Known P st e v) : SafeE P st e :=
  fun _ _ _ run _ => (h.safe run).elim

theorem Knowns.safeEs {es : List Core.Expr} {vs : List Value} (h : Knowns P st es vs) : SafeEs P st es :=
  fun _ _ _ run _ => (h.safe run).elim

theorem known_value (x : Value) : Known P st (.value x) x := ⟨value_trap, value_inv⟩

theorem known_local {id : Nat} {x : Value} (h : st.local? id = some x) : Known P st (.local id) x :=
  ⟨local_trap h, local_eval h⟩

theorem known_unary {op : Core.UnaryOp} {e : Core.Expr} {x v : Value} (ke : Known P st e x)
    (op_ok : Semantics.evalUnaryValue P.target op x = .ok v) : Known P st (.unary op e) v := by
  constructor
  · intro k r s h
    obtain ⟨j, -, h | ⟨w, hw, bad⟩⟩ := unary_trap_inv h
    · exact ke.safe h
    · obtain ⟨rfl, rfl⟩ := ke.done hw
      rw [op_ok] at bad; cases bad
  · intro k u s h
    obtain ⟨j, w, -, hw, ok⟩ := unary_inv h
    obtain ⟨rfl, rfl⟩ := ke.done hw
    rw [op_ok, Except.ok.injEq] at ok
    exact ⟨ok.symm, rfl⟩

theorem known_cast {ty : Core.ScalarTy} {e : Core.Expr} {x v : Value} (ke : Known P st e x)
    (c : Semantics.evalScalarCast P.target ty x = .ok v) : Known P st (.cast ty e) v := by
  constructor
  · intro k r s h
    obtain ⟨j, -, h | ⟨w, hw, bad⟩⟩ := cast_trap_inv h
    · exact ke.safe h
    · obtain ⟨rfl, rfl⟩ := ke.done hw
      rw [c] at bad; cases bad
  · intro k u s h
    obtain ⟨j, w, -, hw, ok⟩ := cast_inv h
    obtain ⟨rfl, rfl⟩ := ke.done hw
    rw [c, Except.ok.injEq] at ok
    exact ⟨ok.symm, rfl⟩

theorem known_binary {op : Core.BinaryOp} {a b : Core.Expr} {l rv v : Value}
    (notAnd : op ≠ .logicalAnd) (notOr : op ≠ .logicalOr) (ka : Known P st a l) (kb : Known P st b rv)
    (op_ok : Semantics.evalBinaryValue P.target op l rv = .ok v) : Known P st (.binary op a b) v := by
  constructor
  · intro k r s h
    obtain ⟨j, -, ha | ⟨l', s1, hl, hb | ⟨rv', hr, bad⟩⟩⟩ := binary_trap_inv notAnd notOr h
    · exact ka.safe ha
    · obtain ⟨rfl, rfl⟩ := ka.done hl
      exact kb.safe hb
    · obtain ⟨rfl, rfl⟩ := ka.done hl
      obtain ⟨rfl, rfl⟩ := kb.done hr
      rw [op_ok] at bad; cases bad
  · intro k u s h
    obtain ⟨j, l', s1, rv', -, hl, hr, ok⟩ := binary_inv notAnd notOr h
    obtain ⟨rfl, rfl⟩ := ka.done hl
    obtain ⟨rfl, rfl⟩ := kb.done hr
    rw [op_ok, Except.ok.injEq] at ok
    exact ⟨ok.symm, rfl⟩

theorem known_or {a b : Core.Expr} {x y : Bool} (ka : Known P st a (.boolean x)) (kb : Known P st b (.boolean y)) :
    Known P st (.binary .logicalOr a b) (.boolean (x || y)) := by
  constructor
  · intro k r s h
    obtain ⟨j, -, ha | ⟨l, hl, notBool, -⟩ | ⟨s1, hl, hb⟩⟩ := logicalOr_trap_inv h
    · exact ka.safe ha
    · obtain ⟨rfl, rfl⟩ := ka.done hl
      exact notBool x rfl
    · obtain ⟨-, rfl⟩ := ka.done hl
      exact kb.safe hb
  · intro k u s h
    obtain ⟨j, s1, x', -, hl, ⟨rfl, rfl, rfl⟩ | ⟨rfl, hr⟩⟩ := logicalOr_inv h
    · obtain ⟨hx, rfl⟩ := ka.done hl
      simp only [Value.boolean.injEq] at hx
      subst hx
      exact ⟨rfl, rfl⟩
    · obtain ⟨hx, rfl⟩ := ka.done hl
      simp only [Value.boolean.injEq] at hx
      subst hx
      obtain ⟨rfl, rfl⟩ := kb.done hr
      exact ⟨rfl, rfl⟩

theorem known_assert {e : Core.Expr} (ke : Known P st e (.boolean true)) :
    Known P st (.intrinsic .assert e) .unit := by
  constructor
  · intro k r s h
    obtain ⟨j, -, h | ⟨v, hv, ⟨rfl, -⟩ | ⟨notBool, -⟩⟩⟩ := assert_trap_inv h
    · exact ke.safe h
    · obtain ⟨bad, -⟩ := ke.done hv; cases bad
    · obtain ⟨rfl, -⟩ := ke.done hv; exact notBool true rfl
  · intro k u s h
    obtain ⟨j, -, hv, rfl⟩ := assert_inv h
    exact ⟨rfl, (ke.done hv).2⟩

theorem stride_trap_inv {e : Core.Expr} {k : Nat} {r : Lanius.Trap} {st' : State}
    (h : evalExpr k P st (.intrinsic .sliceStride e) = .trapped r st') :
    ∃ j, k = j + 1 ∧ (evalExpr j P st e = .trapped r st' ∨
      ∃ w, evalExpr j P st e = .done w st' ∧ Semantics.rawSliceStride? P w = none ∧ r = .typeMismatch) := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    split at h
    · rename_i w next run
      split at h
      all_goals first
        | (split at h
           · simp at h
           · rename_i none
             simp only [Semantics.Outcome.trapped.injEq] at h
             obtain ⟨rfl, rfl⟩ := h
             exact ⟨j, rfl, .inr ⟨w, run, none, rfl⟩⟩)
        | simp_all
    · rename_i reason s1 run
      simp only [Semantics.Outcome.trapped.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨j, rfl, .inl run⟩
    all_goals simp at h

theorem known_stride {e : Core.Expr} {x : Value} {n : Int} (ke : Known P st e x)
    (stride : Semantics.rawSliceStride? P x = some n) :
    Known P st (.intrinsic .sliceStride e) (.signed .isize n) := by
  constructor
  · intro k r s h
    obtain ⟨j, -, h | ⟨w, hw, none, -⟩⟩ := stride_trap_inv h
    · exact ke.safe h
    · obtain ⟨rfl, rfl⟩ := ke.done hw
      rw [stride] at none; cases none
  · intro k u s h
    obtain ⟨j, w, n', -, hw, found, rfl⟩ := stride_inv h
    obtain ⟨rfl, rfl⟩ := ke.done hw
    rw [stride, Option.some.injEq] at found
    exact ⟨by rw [found], rfl⟩

theorem typedSlice_trap_inv {el : Core.Ty} {p n : Core.Expr} {k : Nat} {r : Lanius.Trap} {st' : State}
    (h : evalExpr k P st (.typedSliceFromRawParts el p n) = .trapped r st') :
    ∃ j, k = j + 1 ∧ (evalExpr j P st p = .trapped r st' ∨
      (∃ w, evalExpr j P st p = .done w st' ∧ (∀ a, w ≠ .pointer a) ∧ r = .typeMismatch) ∨
      ∃ a s1, evalExpr j P st p = .done (.pointer a) s1 ∧ (evalExpr j P s1 n = .trapped r st' ∨
        (∃ w, evalExpr j P s1 n = .done w st' ∧ (∀ c, w ≠ .signed .i32 c) ∧ r = .typeMismatch) ∨
        ∃ c s2, evalExpr j P s1 n = .done (.signed .i32 c) s2 ∧
          Semantics.mapRawNominalSlice P s2 el a c = .trapped r st')) := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    split at h
    · rename_i a s1 runP
      split at h
      · rename_i c s2 runN
        exact ⟨j, rfl, .inr (.inr ⟨a, s1, runP, .inr (.inr ⟨c, s2, runN, h⟩)⟩)⟩
      · rename_i w s2 notI runN
        simp only [Semantics.Outcome.trapped.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact ⟨j, rfl, .inr (.inr ⟨a, s1, runP, .inr (.inl ⟨w, runN, fun c e => notI c (by rw [e]), rfl⟩)⟩)⟩
      · rename_i reason s2 runN
        simp only [Semantics.Outcome.trapped.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact ⟨j, rfl, .inr (.inr ⟨a, s1, runP, .inl runN⟩)⟩
      all_goals simp at h
    · rename_i w s1 notP runP
      simp only [Semantics.Outcome.trapped.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨j, rfl, .inr (.inl ⟨w, runP, fun a e => notP a (by rw [e]), rfl⟩)⟩
    · rename_i reason s1 runP
      simp only [Semantics.Outcome.trapped.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨j, rfl, .inl runP⟩
    all_goals simp at h

theorem known_typedSlice {el : Core.Ty} {p n : Core.Expr} {a : Nat} {c : Int} {v : Value}
    (kp : Known P st p (.pointer a)) (kn : Known P st n (.signed .i32 c))
    (m : Semantics.mapRawNominalSlice P st el a c = .done v st) :
    Known P st (.typedSliceFromRawParts el p n) v := by
  constructor
  · intro k r s h
    obtain ⟨j, -, hp' | ⟨w, hw, notP, -⟩ | ⟨a', s1, hp, hn' | ⟨w, hw, notI, -⟩ | ⟨c', s2, hn, bad⟩⟩⟩ :=
      typedSlice_trap_inv h
    · exact kp.safe hp'
    · obtain ⟨rfl, rfl⟩ := kp.done hw; exact notP a rfl
    · obtain ⟨-, rfl⟩ := kp.done hp; exact kn.safe hn'
    · obtain ⟨-, rfl⟩ := kp.done hp
      obtain ⟨rfl, rfl⟩ := kn.done hw; exact notI c rfl
    · obtain ⟨ha, rfl⟩ := kp.done hp
      obtain ⟨hc, rfl⟩ := kn.done hn
      simp only [Value.pointer.injEq, Value.signed.injEq, true_and] at ha hc
      subst ha hc
      rw [m] at bad; cases bad
  · intro k u s h
    obtain ⟨j, a', s1, c', s2, -, hp, hn, m'⟩ := typedSlice_inv h
    obtain ⟨ha, rfl⟩ := kp.done hp
    obtain ⟨hc, rfl⟩ := kn.done hn
    simp only [Value.pointer.injEq, Value.signed.injEq, true_and] at ha hc
    subst ha hc
    rw [m, Semantics.Outcome.done.injEq] at m'
    exact ⟨m'.1.symm, m'.2.symm⟩

theorem known_field {id index sid : Nat} {fields : List Value} {x : Value}
    (known : st.local? id = some (.structure sid fields)) (found : fields[index]? = some x) :
    Known P st (.field (.local id) index) x := by
  constructor
  · intro k r s h
    exact field_local_trap known found h
  · intro k u s h
    obtain ⟨_, sid', fields', -, base, hf⟩ := field_inv h
    obtain ⟨hv, rfl⟩ := local_eval known base
    simp only [Value.structure.injEq] at hv
    obtain ⟨rfl, rfl⟩ := hv
    rw [found, Option.some.injEq] at hf
    exact ⟨hf.symm, rfl⟩

/-- An element of a raw view that reads. -/
theorem known_index_raw {b i : Core.Expr} {el : Core.Ty} {a len pos : Nat} {iv v : Value}
    (kb : Known P st b (.rawSlice el a len)) (ki : Known P st i iv) (ix : Semantics.integerIndex iv = .ok pos)
    (read : Semantics.readRawSliceIndex P st el a len pos = .ok v) : Known P st (.index b i) v := by
  constructor
  · intro k r s h
    cases k with
    | zero => simp [evalExpr] at h
    | succ j =>
      simp only [evalExpr] at h
      cases hb : evalExpr j P st b with
      | done u s1 =>
        obtain ⟨rfl, hs⟩ := kb.done hb
        subst s1
        rw [hb] at h
        simp only at h
        cases hi : evalExpr j P st i with
        | done u2 s2 =>
          obtain ⟨rfl, hs⟩ := ki.done hi
          subst s2
          rw [hi] at h
          simp [ix, read] at h
        | trapped r2 s2 => exact ki.safe hi
        | exited c s2 => rw [hi] at h; simp at h
        | outOfFuel => rw [hi] at h; simp at h
      | trapped r1 s1 => exact kb.safe hb
      | exited c s1 => rw [hb] at h; simp at h
      | outOfFuel => rw [hb] at h; simp at h
  · intro k u s h
    obtain ⟨j, bv, s1, -, hb, rest⟩ := index_inv h
    obtain ⟨rfl, rfl⟩ := kb.done hb
    obtain ⟨iv', pos', hi, ix', read'⟩ := rest _ _ _ rfl
    obtain ⟨rfl, rfl⟩ := ki.done hi
    rw [ix, Except.ok.injEq] at ix'
    subst ix'
    rw [read, Except.ok.injEq] at read'
    exact ⟨read'.symm, rfl⟩

theorem knowns_nil : Knowns P st [] [] := ⟨exprs_nil_trap, exprs_nil_inv⟩

theorem knowns_cons {e : Core.Expr} {es : List Core.Expr} {v : Value} {vs : List Value}
    (ke : Known P st e v) (kes : Knowns P st es vs) : Knowns P st (e :: es) (v :: vs) := by
  constructor
  · intro k r s h
    obtain ⟨j, -, he | ⟨v', s1, hv, hes⟩⟩ := exprs_cons_trap_inv h
    · exact ke.safe he
    · obtain ⟨rfl, rfl⟩ := ke.done hv; exact kes.safe hes
  · intro k us s h
    obtain ⟨j, v', s1, rest, -, hv, hr, rfl⟩ := exprs_cons_inv h
    obtain ⟨rfl, rfl⟩ := ke.done hv
    obtain ⟨rfl, rfl⟩ := kes.done hr
    exact ⟨rfl, rfl⟩

theorem known_struct {id : Nat} {es : List Core.Expr} {vs : List Value} (kes : Knowns P st es vs) :
    Known P st (.structValue id es) (.structure id vs) := by
  constructor
  · intro k r s h
    obtain ⟨j, -, h⟩ := structValue_trap_inv h
    exact kes.safe h
  · intro k u s h
    obtain ⟨j, us, -, hr, rfl⟩ := structValue_inv h
    obtain ⟨rfl, rfl⟩ := kes.done hr
    exact ⟨rfl, rfl⟩

/-! ## Safe expressions -/

theorem safeEs_nil : SafeEs P st [] := fun _ _ _ run _ => (exprs_nil_trap run).elim

theorem safeEs_cons {e : Core.Expr} {es : List Core.Expr} (se : SafeE P st e)
    (rest : ∀ {k v s}, evalExpr k P st e = .done v s → SafeEs P s es) : SafeEs P st (e :: es) := by
  intro k r s h bound
  obtain ⟨j, -, he | ⟨v, s1, hv, hes⟩⟩ := exprs_cons_trap_inv h
  · exact se _ _ _ he bound
  · exact rest hv _ _ _ hes bound

theorem safeE_assert {e : Core.Expr} (se : SafeE P st e)
    (bool : ∀ {k v s}, evalExpr k P st e = .done v s → ∃ x, v = .boolean x) :
    SafeE P st (.intrinsic .assert e) := by
  intro k r s h bound
  obtain ⟨j, -, h | ⟨v, hv, ⟨-, rfl⟩ | ⟨notBool, -⟩⟩⟩ := assert_trap_inv h
  · exact se _ _ _ h bound
  · rfl
  · obtain ⟨x, rfl⟩ := bool hv
    exact (notBool x rfl).elim

def SafeArms (P : Core.Program) (st : State) (sv : Value) (arms : List (Core.Pattern × Core.Expr)) : Prop :=
  ∀ k r s, evalMatchArms k P st sv arms = .trapped r s → s.heap.nextAddress ≤ 2 ^ 64 → undefinedTrap r = false

theorem safeArms_nil {sv : Value} : SafeArms P st sv [] := fun _ _ _ h _ => by
  rw [(arms_nil_trap h).1]; rfl

theorem safeArms_miss {sv : Value} {pat : Core.Pattern} {body : Core.Expr} {arms : List (Core.Pattern × Core.Expr)}
    (miss : Semantics.matchPattern pat sv = none) (rest : SafeArms P st sv arms) :
    SafeArms P st sv ((pat, body) :: arms) := by
  intro k r s h bound
  obtain ⟨j, -, ⟨-, h⟩ | ⟨bs, s2, hit, -, -⟩⟩ := arms_cons_trap_inv h
  · exact rest _ _ _ h bound
  · rw [miss] at hit; cases hit

theorem safeArms_hit {sv : Value} {pat : Core.Pattern} {body : Core.Expr} {arms : List (Core.Pattern × Core.Expr)}
    {bs : List (Nat × Value)} (hit : Semantics.matchPattern pat sv = some bs) (sb : SafeE P (st.bindLocals bs) body) :
    SafeArms P st sv ((pat, body) :: arms) := by
  intro k r s h bound
  obtain ⟨j, -, ⟨miss, -⟩ | ⟨bs', s2, hit', hb, rfl⟩⟩ := arms_cons_trap_inv h
  · rw [hit] at miss; cases miss
  · rw [hit, Option.some.injEq] at hit'
    subst hit'
    exact sb _ _ _ hb bound

theorem safeE_match {s : Core.Expr} {arms : List (Core.Pattern × Core.Expr)} {sv : Value}
    (ks : Known P st s sv) (sa : SafeArms P st sv arms) : SafeE P st (.matchValue s arms) := by
  intro k r s' h bound
  obtain ⟨j, -, hs | ⟨sv', s1, hv, ha⟩⟩ := matchValue_trap_inv h
  · exact (ks.safe hs).elim
  · obtain ⟨rfl, rfl⟩ := ks.done hv
    exact sa _ _ _ ha bound

theorem safeE_cast {ty : Core.ScalarTy} {e : Core.Expr} (se : SafeE P st e)
    (ok : ∀ {k v s}, evalExpr k P st e = .done v s → s.heap.nextAddress ≤ 2 ^ 64 →
      ∃ u, Semantics.evalScalarCast P.target ty v = .ok u) :
    SafeE P st (.cast ty e) := by
  intro k r s h bound
  obtain ⟨j, -, he | ⟨w, hw, bad⟩⟩ := cast_trap_inv h
  · exact se _ _ _ he bound
  · obtain ⟨u, good⟩ := ok hw bound
    rw [good] at bad; cases bad

/-! ## Safe statements -/

theorem safeS_skip : SafeS P st .skip := fun _ _ _ run _ => (skip_trap run).elim

theorem safeS_returnUnit : SafeS P st (.returnValue none) := fun _ _ _ run _ => (returnUnit_trap run).elim

theorem safeS_return {e : Core.Expr} (se : SafeE P st e) : SafeS P st (.returnValue (some e)) := by
  intro k r s h bound
  obtain ⟨j, -, h⟩ := return_trap_inv h
  exact se _ _ _ h bound

theorem safeS_expression {e : Core.Expr} (se : SafeE P st e) : SafeS P st (.expression e) := by
  intro k r s h bound
  obtain ⟨j, -, h⟩ := expression_trap_inv h
  exact se _ _ _ h bound

theorem safeS_seq {a b : Core.Stmt} (sa : SafeS P st a)
    (sb : ∀ {k s}, execStmt k P st a = .done .next s → SafeS P s b) : SafeS P st (.sequence a b) := by
  intro k r s h bound
  obtain ⟨j, -, ha' | ⟨s1, ha, hb⟩⟩ := sequence_trap_inv h
  · exact sa _ _ _ ha' bound
  · exact sb ha _ _ _ hb bound

theorem safeS_let {id : Nat} {ty : Core.Ty} {e : Core.Expr} {body : Core.Stmt} (se : SafeE P st e)
    (sb : ∀ {k v s}, evalExpr k P st e = .done v s → SafeS P (s.bindLocal id v) body) :
    SafeS P st (.letLocal id ty e body) := by
  intro k r s h bound
  obtain ⟨j, -, he | ⟨v, s1, s2, hv, hb, rfl⟩⟩ := letLocal_trap_inv h
  · exact se _ _ _ he bound
  · exact sb hv _ _ _ hb bound

theorem safeS_let_known {id : Nat} {ty : Core.Ty} {e : Core.Expr} {body : Core.Stmt} {v : Value}
    (ke : Known P st e v) (sb : SafeS P (st.bindLocal id v) body) : SafeS P st (.letLocal id ty e body) :=
  safeS_let ke.safeE fun hv => by obtain ⟨rfl, rfl⟩ := ke.done hv; exact sb

theorem safeS_if {cond : Core.Expr} {a b : Core.Stmt} (sc : SafeE P st cond)
    (sb : ∀ {k v s}, evalExpr k P st cond = .done v s → ∃ x, v = .boolean x ∧ SafeS P s (if x then a else b)) :
    SafeS P st (.ifThenElse cond a b) := by
  intro k r s h bound
  obtain ⟨j, -, hc | ⟨v, hv, notBool, -⟩ | ⟨x, s1, hv, hb⟩⟩ := if_trap_inv h
  · exact sc _ _ _ hc bound
  · obtain ⟨x, rfl, -⟩ := sb hv
    exact (notBool x rfl).elim
  · obtain ⟨x', hx, safe⟩ := sb hv
    simp only [Value.boolean.injEq] at hx
    subst hx
    exact safe _ _ _ hb bound

theorem safeS_if_known {cond : Core.Expr} {a b : Core.Stmt} {x : Bool} (kc : Known P st cond (.boolean x))
    (sb : SafeS P st (if x then a else b)) : SafeS P st (.ifThenElse cond a b) :=
  safeS_if kc.safeE fun hv => by obtain ⟨rfl, rfl⟩ := kc.done hv; exact ⟨x, rfl, sb⟩

/-- A completed run of an `if` on a known condition is a run of its branch. -/
theorem if_known_done {cond : Core.Expr} {a b : Core.Stmt} {x : Bool} {k : Nat} {c : Completion} {s : State}
    (kc : Known P st cond (.boolean x)) (h : execStmt k P st (.ifThenElse cond a b) = .done c s) :
    ∃ j, k = j + 1 ∧ execStmt j P st (if x then a else b) = .done c s := by
  obtain ⟨j, s1, x', rfl, hv, hb⟩ := if_inv h
  obtain ⟨hx, rfl⟩ := kc.done hv
  simp only [Value.boolean.injEq] at hx
  subst hx
  exact ⟨j, rfl, hb⟩

/-- A completed run of an expression statement on a known expression leaves
the state as it was. -/
theorem expression_known_done {e : Core.Expr} {v : Value} {k : Nat} {c : Completion} {s : State}
    (ke : Known P st e v) (h : execStmt k P st (.expression e) = .done c s) : c = .next ∧ s = st := by
  obtain ⟨j, u, -, hv, rfl⟩ := expression_inv h
  exact ⟨rfl, (ke.done hv).2⟩

theorem return_not_next {e : Option Core.Expr} {k : Nat} {s : State}
    (h : execStmt k P st (.returnValue e) = .done .next s) : False := by
  cases e with
  | none => exact absurd (returnUnit_inv h).1 (by simp)
  | some e => obtain ⟨_, _, _, _, bad⟩ := return_inv h; cases bad

end

/-! ## Calls -/

/-- A call of a function of `sp`, on arguments of the callee's arity, whose
body is safe from every start the arguments' runs give. -/
theorem safeE_call {sp : SrcProgram} {st : State} {callee : Nat} {args : List Core.Expr} {f : SrcFunc}
    (found : sp.funcs[callee]? = some f) (inside : f.body.breaksOut = false) (sa : SafeEs sp.toCore st args)
    (body : ∀ {k values s}, evalExprs k sp.toCore st args = .done values s → values.length = f.params.length ∧
      SafeS sp.toCore (({ s with locals := [] } : State).bindLocals (paramBindings f.params values)) f.body.toCore) :
    SafeE sp.toCore st (.call callee args) := by
  intro k r s h bound
  obtain ⟨j, -, ha | ⟨values, after, hargs, ⟨-, arity⟩ | ⟨f', completed, found', -, rfl, hb | ⟨c, done, bad⟩⟩⟩⟩ :=
    call_trap_inv (inside_of found) h
  · exact sa _ _ _ ha bound
  · exact (arity f found (body hargs).1).elim
  · rw [found, Option.some.injEq] at found'
    subst found'
    exact (body hargs).2 _ _ _ hb bound
  · rw [found, Option.some.injEq] at found'
    subst found'
    have ends := stmt_ends sp _ inside done
    rcases bad with rfl | ⟨rfl | rfl, -⟩
    · rfl
    · exact ends.elim
    · exact ends.elim

end Lanius.Faithful
