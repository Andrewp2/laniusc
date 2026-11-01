import Lanius.Faithful.Sim.Term

/-! # The termination check is sound

`pcall_complete`: under `TermOk`, every call of an annotated function
settles. The proof is a well-founded induction on the measure of the call,
`(rank, size of the designated argument, subrank)`: a checked body run with
calls of fuel `m` is eventually constant in `m` once every call it makes
settles (`stmt_evConst`), and the check sees to it that every call it makes
is smaller than the call being run. -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (evalBinaryValue evalUnsignedBinary scalarEqual matchPattern matchPatterns)

/-! ## Eventually constant sequences -/

/-- Constant from some index on. -/
def EvConst {α : Type} (g : Nat → α) : Prop := ∃ N, ∀ m, N ≤ m → g m = g N

theorem EvConst.const {α : Type} (a : α) : EvConst (fun _ => a) := ⟨0, fun _ _ => rfl⟩

theorem EvConst.of_eq {α : Type} {g h : Nat → α} (e : ∀ m, g m = h m) (hh : EvConst h) : EvConst g := by
  obtain ⟨N, hN⟩ := hh
  exact ⟨N, fun m hm => by rw [e, e, hN m hm]⟩

theorem EvConst.map {α β : Type} {x : Nat → α} (f : α → β) (hx : EvConst x) :
    EvConst (fun m => f (x m)) := by
  obtain ⟨N, hN⟩ := hx
  exact ⟨N, fun m hm => by simp only [hN m hm]⟩

theorem EvConst.pair {α β γ : Type} {x : Nat → α} {y : Nat → β} (f : α → β → γ)
    (hx : EvConst x) (hy : EvConst y) : EvConst (fun m => f (x m) (y m)) := by
  obtain ⟨N1, h1⟩ := hx
  obtain ⟨N2, h2⟩ := hy
  refine ⟨max N1 N2, fun m hm => ?_⟩
  simp only [h1 m (by omega), h2 m (by omega), h1 (max N1 N2) (by omega), h2 (max N1 N2) (by omega)]

/-- An eventually constant option, then for its value an eventually constant
continuation. -/
theorem EvConst.bind {α β : Type} {x : Nat → Option α} {k : α → Nat → Option β}
    (hx : EvConst x) (hk : ∀ v, (∃ m, x m = some v) → EvConst (k v)) :
    EvConst (fun m => (x m).bind (fun v => k v m)) := by
  obtain ⟨N1, h1⟩ := hx
  cases e : x N1 with
  | none => exact ⟨N1, fun m hm => by simp only [h1 m hm, e, Option.bind]⟩
  | some v =>
    obtain ⟨N2, h2⟩ := hk v ⟨N1, e⟩
    refine ⟨max N1 N2, fun m hm => ?_⟩
    simp only [h1 m (by omega), h1 (max N1 N2) (by omega), e, Option.bind]
    rw [h2 m (by omega), h2 (max N1 N2) (by omega)]

/-- A statement, then the next one when it went on. -/
theorem EvConst.next {x : Nat → Option Done} {y : Nat → Option Done}
    (hx : EvConst x) (hy : (∃ m, x m = some .next) → EvConst y) :
    EvConst (fun m => (x m).bind (Done.then (y m))) := by
  obtain ⟨N1, h1⟩ := hx
  cases e : x N1 with
  | none => exact ⟨N1, fun m hm => by simp only [h1 m hm, e, Option.bind]⟩
  | some d =>
    cases d with
    | ret r =>
      exact ⟨N1, fun m hm => by simp only [h1 m hm, e, Option.bind, Done.then]⟩
    | next =>
      obtain ⟨N2, h2⟩ := hy ⟨N1, e⟩
      refine ⟨max N1 N2, fun m hm => ?_⟩
      simp only [h1 m (by omega), h1 (max N1 N2) (by omega), e, Option.bind, Done.then]
      rw [h2 m (by omega), h2 (max N1 N2) (by omega)]

/-! ## Sizes of values -/

theorem sizeOf_field {id : Nat} {fields : List Value} {i : Nat} {v : Value}
    (h : fieldOf (.structure id fields) i = some v) : sizeOf v < sizeOf (Value.structure id fields) := by
  simp only [fieldOf] at h
  have mem : v ∈ fields := List.mem_of_getElem? h
  have := List.sizeOf_lt_of_mem mem
  simp only [Value.structure.sizeOf_spec]
  omega

theorem sizeOf_payload {id k : Nat} {payload : List Value} {v : Value} (mem : v ∈ payload) :
    sizeOf v < sizeOf (Value.enumeration id k payload) := by
  have := List.sizeOf_lt_of_mem mem
  simp only [Value.enumeration.sizeOf_spec]
  omega

theorem sizeOf_unsigned_lt {t : Core.UnsignedIntTy} {a b : Nat} (h : a < b) :
    sizeOf (Value.unsigned t a) < sizeOf (Value.unsigned t b) := by
  simp only [Value.unsigned.sizeOf_spec, sizeOf_nat]
  omega

/-! ## Classes of the locals -/

/-- Two lists related elementwise. -/
inductive ListRel {α β : Type} (R : α → β → Prop) : List α → List β → Prop
  | nil : ListRel R [] []
  | cons {a : α} {b : β} {as : List α} {bs : List β} : R a b → ListRel R as bs → ListRel R (a :: as) (b :: bs)

theorem ListRel.imp {α β : Type} {R S : α → β → Prop} (f : ∀ a b, R a b → S a b) :
    ∀ {as : List α} {bs : List β}, ListRel R as bs → ListRel S as bs
  | _, _, .nil => .nil
  | _, _, .cons h rest => .cons (f _ _ h) (rest.imp f)

/-- Every local the classes name holds its class. -/
def EnvOk (B : Nat) (A : AEnv) (E : Env) : Prop :=
  ∀ x c v, A.get? x = some c → E.get? x = some v → c.holds B v

theorem EnvOk.cons {B : Nat} {A : AEnv} {E : Env} (h : EnvOk B A E) {x : Nat} {c : SizeCls} {v : Value}
    (hv : c.holds B v) : EnvOk B ((x, c) :: A) ((x, v) :: E) := by
  intro y c' v' ha he
  simp only [AEnv.get?, Env.get?, List.find?_cons] at ha he
  by_cases hy : x = y
  · subst hy
    simp only [beq_self_eq_true, Option.map_some, Option.some.injEq] at ha he
    subst ha; subst he; exact hv
  · have : (x == y) = false := by simp [hy]
    simp only [this] at ha he
    exact h y c' v' ha he

theorem EnvOk.cons' {B : Nat} {A : AEnv} {E : Env} (h : EnvOk B A E) {a : Nat × SizeCls} {b : Nat × Value}
    (hab : a.1 = b.1 ∧ a.2.holds B b.2) : EnvOk B (a :: A) (b :: E) := by
  obtain ⟨x, c⟩ := a
  obtain ⟨y, v⟩ := b
  obtain ⟨hxy, hc⟩ := hab
  simp only at hxy hc
  subst hxy
  exact h.cons hc

theorem EnvOk.bindAll {B : Nat} {as : List (Nat × SizeCls)} {bs : List (Nat × Value)}
    (r : ListRel (fun a b => a.1 = b.1 ∧ a.2.holds B b.2) as bs) :
    ∀ {A : AEnv} {E : Env}, EnvOk B A E → EnvOk B (A.bindAll as) (E.bindAll bs) := by
  induction r with
  | nil => exact fun h => h
  | cons hab _ ih => exact fun h => ih (h.cons' hab)

theorem EnvOk.refine {B : Nat} {A : AEnv} {E : Env} (h : EnvOk B A E) {x : Nat}
    (hx : ∀ v, E.get? x = some v → ∃ n, v = .unsigned .usize n ∧ n ≠ 0) : EnvOk B (A.refine x) E := by
  unfold AEnv.refine
  split
  · rename_i le
    intro y c v ha he
    simp only [AEnv.get?, List.find?_cons] at ha
    by_cases hy : x = y
    · subst hy
      simp only [beq_self_eq_true, Option.map_some, Option.some.injEq] at ha
      subst ha
      refine ⟨?_, hx v he⟩
      simp only [AEnv.cls] at le
      cases hg : A.get? x with
      | none => simp [hg] at le
      | some c' =>
        simp only [hg, Option.getD_some] at le
        subst le
        exact h x _ v hg he
    · have : (x == y) = false := by simp [hy]
      simp only [this] at ha
      exact h y c v ha he
  · exact h

theorem cls_holds {B : Nat} {A : AEnv} {E : Env} (h : EnvOk B A E) {x : Nat} {v : Value}
    (he : E.get? x = some v) : (A.cls x).holds B v := by
  unfold AEnv.cls
  cases ha : A.get? x with
  | none => trivial
  | some c => exact h x c v ha he

theorem part_holds {B : Nat} {c : SizeCls} {w v : Value} (hw : c.holds B w) (lt : sizeOf v < sizeOf w) :
    c.part.holds B v := by
  cases c with
  | unk => trivial
  | le => simp only [SizeCls.part, SizeCls.holds] at hw ⊢; omega
  | lt => simp only [SizeCls.part, SizeCls.holds] at hw ⊢; omega
  | nz => simp only [SizeCls.part, SizeCls.holds] at hw ⊢; omega
  | one => trivial

theorem fieldOf_lt {w : Value} {i : Nat} {v : Value} (h : fieldOf w i = some v) : sizeOf v < sizeOf w := by
  cases w with
  | «structure» id fields => exact sizeOf_field h
  | unit | boolean _ | signed _ _ | unsigned _ _ | f32Bits _ | f64Bits _ | character _ | string _
  | pointer _ | array _ | slice _ _ _ _ _ | rawSlice _ _ _ | enumeration _ _ _ | reference _ _ _ =>
    simp [fieldOf] at h

theorem exprCls_holds {B : Nat} {A : AEnv} {E : Env} (h : EnvOk B A E) :
    ∀ (e : SrcExpr) {v : Value}, pexpr E e = some v → (exprCls A e).holds B v
  | .local x, v, he => by
    simp only [pexpr] at he
    exact cls_holds h he
  | .field x i, v, he => by
    simp only [pexpr, Option.bind_eq_some_iff] at he
    obtain ⟨w, hw, hf⟩ := he
    exact part_holds (cls_holds h hw) (fieldOf_lt hf)
  | .unsigned t n, v, he => by
    simp only [pexpr, Option.some.injEq] at he
    subst he
    simp only [exprCls]
    split
    · rename_i hc
      obtain ⟨rfl, h1⟩ := hc
      simp only [SizeCls.holds, UintTy.toCore, h1]
    · trivial
  | .int _, _, _ | .boolean _, _, _ | .negate _, _, _ | .not _, _, _ | .apply _ _ _, _, _
  | .cast _ _, _, _ | .null, _, _ | .char _, _, _ | .float _ _, _, _ => trivial

theorem exprsCls_holds {B : Nat} {A : AEnv} {E : Env} (h : EnvOk B A E) :
    ∀ (es : List SrcExpr) {vs : List Value}, pexprs E es = some vs →
      ListRel (fun c v => SizeCls.holds B c v) (es.map (exprCls A)) vs
  | [], vs, he => by
    simp only [pexprs, Option.some.injEq] at he
    subst he; exact .nil
  | e :: es, vs, he => by
    simp only [pexprs, Option.bind_eq_some_iff, Option.map_eq_some_iff] at he
    obtain ⟨v, hv, vs', hvs, rfl⟩ := he
    exact .cons (exprCls_holds h e hv) (exprsCls_holds h es hvs)

/-! ## Matching binds parts -/

theorem matchPatterns_binds :
    ∀ (bs : List Nat) (ps : List Value) {bindings : List (Nat × Value)},
      matchPatterns (bs.map Core.Pattern.bind) ps = some bindings →
      ListRel (fun b q => q.1 = b ∧ q.2 ∈ ps) bs bindings
  | [], [], bindings, h => by
    simp only [List.map_nil, matchPatterns, Option.some.injEq] at h
    subst h; exact .nil
  | [], _ :: _, _, h => by simp [matchPatterns] at h
  | _ :: _, [], _, h => by simp [matchPatterns] at h
  | b :: bs, p :: ps, bindings, h => by
    simp only [List.map_cons, matchPatterns, matchPattern] at h
    split at h
    · rename_i head tail hh ht
      simp only [Option.some.injEq] at hh h
      subst hh; subst h
      refine .cons ⟨rfl, List.mem_cons_self⟩ ?_
      exact (matchPatterns_binds bs ps ht).imp fun _ _ ⟨e, m⟩ => ⟨e, List.mem_cons_of_mem _ m⟩
    · simp at h

theorem match_binds {B : Nat} {c : SizeCls} {v : Value} (hv : c.holds B v) {id k : Nat} {bs : List Nat}
    {bindings : List (Nat × Value)}
    (h : matchPattern (.enumVariant id k (bs.map .bind)) v = some bindings) :
    ListRel (fun a b => a.1 = b.1 ∧ a.2.holds B b.2) (bs.map (·, c.part)) bindings := by
  cases v with
  | enumeration id' k' payload =>
    simp only [matchPattern] at h
    split at h
    · have binds := matchPatterns_binds bs payload h
      clear h
      induction binds with
      | nil => exact .nil
      | cons hd _ ih =>
        refine .cons ⟨hd.1.symm, part_holds hv (sizeOf_payload hd.2)⟩ ih
    · simp at h
  | unit | boolean _ | signed _ _ | unsigned _ _ | f32Bits _ | f64Bits _ | character _ | string _
  | pointer _ | array _ | slice _ _ _ _ _ | rawSlice _ _ _ | «structure» _ _ | reference _ _ _ =>
    simp [matchPattern] at h

/-! ## Guards and statements that do not go on -/

theorem equal_zero_false {l w : Value}
    (h : (evalBinaryValue target .equal l (.unsigned .usize 0)).toOption = some w) (hb : asBool w = some false) :
    ∃ n, l = .unsigned .usize n ∧ n ≠ 0 := by
  cases l with
  | unsigned t n =>
    cases t <;> simp [evalBinaryValue, scalarEqual, Except.toOption] at h <;> subst h <;>
      simp_all [asBool]
  | unit | boolean _ | signed _ _ | f32Bits _ | f64Bits _ | character _ | string _
  | pointer _ | array _ | slice _ _ _ _ _ | rawSlice _ _ _ | «structure» _ _ | enumeration _ _ _
  | reference _ _ _ =>
    simp [evalBinaryValue, scalarEqual, Except.toOption] at h

theorem localOf_some {e : SrcExpr} {x : Nat} (h : localOf e = some x) : e = .local x := by
  cases e <;> simp_all [localOf]

theorem isUsizeLit_zero {e : SrcExpr} (h : isUsizeLit 0 e = true) : e = .unsigned .usize 0 := by
  cases e with
  | unsigned t v =>
    simp only [isUsizeLit, Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq] at h
    obtain ⟨rfl, hv⟩ := h
    have : v = 0 := BitVec.eq_of_toNat_eq (by simpa using hv)
    rw [this]
  | int _ | boolean _ | «local» _ | field _ _ | negate _ | not _ | apply _ _ _ | cast _ _ | null
  | char _ | float _ _ => simp [isUsizeLit] at h

/-- A guard `x == 0` that is false leaves `x` a nonzero `usize`. -/
theorem guard_nz {E : Env} {c : SrcExpr} {x : Nat} {w : Value} (hg : guardVar c = some x)
    (hc : pexpr E c = some w) (hb : asBool w = some false) :
    ∀ v, E.get? x = some v → ∃ n, v = .unsigned .usize n ∧ n ≠ 0 := by
  intro v hv
  cases c with
  | apply op l r =>
    simp only [guardVar] at hg
    split at hg
    · rename_i hop
      simp only [Bool.and_eq_true, decide_eq_true_eq] at hop
      obtain ⟨rfl, hr⟩ := hop
      have hl := localOf_some hg
      subst hl
      have hr' := isUsizeLit_zero hr
      subst hr'
      simp only [pexpr, applyOp, binary, SrcOp.toCore, hv, Option.bind_some] at hc
      exact equal_zero_false (by simpa [UintTy.toCore] using hc) hb
    · simp at hg
  | int _ | boolean _ | unsigned _ _ | «local» _ | field _ _ | negate _ | not _ | cast _ _ | null
  | char _ | float _ _ => simp [guardVar] at hg

theorem neverNext_sound (call : Calls) :
    ∀ (s : SrcStmt) (E : Env), neverNext s = true → pstmt call E s ≠ some .next := by
  intro s
  induction s with
  | nop => intro E h; simp [neverNext] at h
  | «let» id _ value body ih =>
    intro E h e
    simp only [neverNext] at h
    simp only [pstmt, Option.bind_eq_some_iff] at e
    obtain ⟨v, _, e⟩ := e
    exact ih _ h e
  | letStruct id _ _ body ih =>
    intro E h e
    simp only [neverNext] at h
    simp only [pstmt, Option.bind_eq_some_iff] at e
    obtain ⟨v, _, e⟩ := e
    exact ih _ h e
  | letCall id _ _ _ body ih =>
    intro E h e
    simp only [neverNext] at h
    simp only [pstmt, Option.bind_eq_some_iff] at e
    obtain ⟨v, _, e⟩ := e
    exact ih _ h e
  | letEnum id _ _ _ body ih =>
    intro E h e
    simp only [neverNext] at h
    simp only [pstmt, Option.bind_eq_some_iff] at e
    obtain ⟨v, _, e⟩ := e
    exact ih _ h e
  | letEval id _ _ body ih =>
    intro E h e
    simp only [neverNext] at h
    simp only [pstmt, Option.bind_eq_some_iff] at e
    obtain ⟨v, _, e⟩ := e
    exact ih _ h e
  | «then» first second ih1 ih2 =>
    intro E h e
    simp only [neverNext, Bool.or_eq_true] at h
    simp only [pstmt, Option.bind_eq_some_iff] at e
    obtain ⟨d, hd, e⟩ := e
    cases d with
    | next =>
      rcases h with h | h
      · exact ih1 E h hd
      · exact ih2 E h e
    | ret _ => simp [Done.then] at e
  | «if» _ a b iha ihb =>
    intro E h e
    simp only [neverNext, Bool.and_eq_true] at h
    simp only [pstmt, Option.bind_eq_some_iff] at e
    obtain ⟨c, _, e⟩ := e
    cases c
    · exact ihb E h.2 e
    · exact iha E h.1 e
  | ifEval _ a b iha ihb =>
    intro E h e
    simp only [neverNext, Bool.and_eq_true] at h
    simp only [pstmt, Option.bind_eq_some_iff] at e
    obtain ⟨c, _, e⟩ := e
    cases c
    · exact ihb E h.2 e
    · exact iha E h.1 e
  | «return» _ => intro E _ e; simp [pstmt] at e
  | returnEval _ => intro E _ e; simp [pstmt] at e
  | returnUnit => intro E _ e; simp [pstmt] at e
  | discard _ => intro E h; simp [neverNext] at h
  | assert _ => intro E h; simp [neverNext] at h
  | letMatch _ _ _ _ _ _ | set _ _ | setField _ _ _ | setCall _ _ _ | «while» _ _ | letAlloc _ _ _ _
  | letLoad _ _ _ _ | setByte _ _ _ | free _ _ _ | letSlice _ _ _ _ _ | letIndex _ _ _ _ _
  | setIndex _ _ _ | setEval _ _ | whileEval _ _ | setIndexEval _ _ _ | setFieldEval _ _ _ | «break»
  | «continue» | matchArm _ _ _ _ _ _ _ _ | unreachable _ _ => intro E _ e; simp [pstmt] at e

/-- What `after` knows holds once the statement went on. -/
theorem after_ok {B : Nat} {A : AEnv} {E : Env} (h : EnvOk B A E) (call : Calls) :
    ∀ (s : SrcStmt), pstmt call E s = some .next → EnvOk B (A.after s) E := by
  intro s hs
  cases s with
  | «if» c a b =>
    simp only [AEnv.after]
    split
    · rename_i x hg
      split
      · rename_i never
        simp only [pstmt, Option.bind_eq_some_iff] at hs
        obtain ⟨cv, ⟨w, hw, hb⟩, hs⟩ := hs
        cases cv with
        | true => exact absurd hs (neverNext_sound call a E never)
        | false => exact h.refine (guard_nz hg hw hb)
      · exact h
    · exact h
  | nop | «let» _ _ _ _ | letStruct _ _ _ _ | letCall _ _ _ _ _ | letEnum _ _ _ _ _
  | letMatch _ _ _ _ _ _ | set _ _ | setField _ _ _ | setCall _ _ _ | «then» _ _ | «while» _ _
  | «return» _ | letAlloc _ _ _ _ | letLoad _ _ _ _ | setByte _ _ _ | free _ _ _
  | letSlice _ _ _ _ _ | letIndex _ _ _ _ _ | setIndex _ _ _ | letEval _ _ _ _ | setEval _ _
  | ifEval _ _ _ | whileEval _ _ | returnEval _ | discard _ | setIndexEval _ _ _
  | setFieldEval _ _ _ | returnUnit | assert _ | «break» | «continue» | matchArm _ _ _ _ _ _ _ _
  | unreachable _ _ => exact h

/-! ## Calls the classes know -/

theorem paramBindings_ids : ∀ (params : List SrcParam) (vs : List Value),
    paramBindings params vs = (paramIds params).zip vs
  | [], _ => by simp [paramBindings, paramIds]
  | _ :: _, [] => by simp [paramBindings, paramIds]
  | p :: ps, v :: vs => by
    have := paramBindings_ids ps vs
    simp only [paramBindings, paramIds, List.map_cons, List.zip_cons_cons] at this ⊢
    rw [this]

theorem usize_greater (a b : Nat) :
    evalBinaryValue target .greater (.unsigned .usize a) (.unsigned .usize b) = .ok (.boolean (decide (a > b))) := by
  simp [evalBinaryValue, evalUnsignedBinary]

theorem usize_subtract (a b : Nat) :
    evalBinaryValue target .subtract (.unsigned .usize a) (.unsigned .usize b) =
      .ok (.unsigned .usize ((a + 18446744073709551616 - b % 18446744073709551616) % 18446744073709551616)) := by
  have hw : 2 ^ Core.Target.x86_64.pointerWidth.bits = 18446744073709551616 := by decide
  simp [evalBinaryValue, evalUnsignedBinary, Semantics.wrapUnsigned, Semantics.unsignedModulus, target,
    Core.UnsignedIntTy.bits, hw]

theorem usize_sub_one {n : Nat} (hn : n ≠ 0) : ∃ r, r < n ∧
    evalBinaryValue target .subtract (.unsigned .usize n) (.unsigned .usize 1) = .ok (.unsigned .usize r) :=
  ⟨_, by omega, usize_subtract n 1⟩

/-- A decrement of a nonzero `usize` by 1 gives a smaller value. -/
theorem dec_lt {sp : SrcProgram} {prims : Prims} {c : Nat} (hd : DecOk sp prims c) {m n : Nat} {v : Value}
    (hn : n ≠ 0) (h : pcall sp prims m c [.unsigned .usize n, .unsigned .usize 1] = some v) :
    sizeOf v < sizeOf (Value.unsigned .usize n) := by
  obtain ⟨np, f, a, b, panic, hf, hids, hab, hbody⟩ := hd
  cases m with
  | zero => simp [pcall] at h
  | succ m =>
    have hlen : f.params.length = 2 := by
      have := congrArg List.length hids
      simpa [paramIds] using this
    simp only [pcall, np, hf, hlen] at h
    simp only [Bool.false_eq_true, ↓reduceIte, List.length_cons, List.length_nil] at h
    rw [paramEnv, paramBindings_ids, hids, hbody] at h
    have hba : (b == a) = false := by simp [Ne.symm hab]
    obtain ⟨r, hr, hsub⟩ := usize_sub_one hn
    simp [pstmt, pexpr, Env.bindAll, Env.get?, hba, applyOp, binary, SrcOp.toCore, usize_greater,
      hsub, Except.toOption, asBool] at h
    simp only [hn, ↓reduceIte, Option.bind, Done.then, doneValue, Option.some.injEq] at h
    subst h
    exact sizeOf_unsigned_lt hr

/-- What the classes assume of the calls: prims are the identity, and
decrements decrement. -/
structure OracleOk (prims : Prims) (T : TermInfo) (call : Calls) : Prop where
  prim : ∀ c vs v, prims.isPrim c = true → call c vs = some v → single vs = some v
  dec : ∀ c ∈ T.decs, ∀ n v, n ≠ 0 → call c [.unsigned .usize n, .unsigned .usize 1] = some v →
    sizeOf v < sizeOf (Value.unsigned .usize n)

theorem oracleOk_pcall {sp : SrcProgram} {prims : Prims} {T : TermInfo} (hD : ∀ c ∈ T.decs, DecOk sp prims c)
    (m : Nat) : OracleOk prims T (pcall sp prims m) where
  prim := by
    intro c vs v hp hv
    cases m with
    | zero => simp [pcall] at hv
    | succ m => simpa [pcall, hp] using hv
  dec := fun c hc _ _ hn hv => dec_lt (hD c hc) hn hv

theorem callCls_holds {prims : Prims} {T : TermInfo} {call : Calls} {B : Nat} (ho : OracleOk prims T call)
    {c : Nat} {cs : List SizeCls} {vs : List Value} (hr : ListRel (SizeCls.holds B) cs vs) {v : Value}
    (h : call c vs = some v) : (callCls prims T c cs).holds B v := by
  unfold callCls
  split
  · rename_i hp
    have hs := ho.prim c vs v hp h
    cases hr with
    | nil => simp [single] at hs
    | cons hk rest =>
      cases rest with
      | nil =>
        simp only [single, Option.some.injEq] at hs
        subst hs
        exact hk
      | cons _ _ => simp [single] at hs
  · split
    · rename_i hdec
      cases hr with
      | nil => trivial
      | cons ha rest =>
        cases rest with
        | nil => trivial
        | cons hb rest =>
          cases rest with
          | nil =>
            rename_i a va b vb
            simp only
            split
            · rename_i hab
              obtain ⟨rfl, rfl⟩ := hab
              obtain ⟨hle, n, rfl, hn⟩ := ha
              simp only [SizeCls.holds] at hb
              subst hb
              have := ho.dec c (List.contains_iff_mem.mp hdec) n v hn h
              simp only [SizeCls.holds]
              omega
            · trivial
          | cons _ _ => trivial
    · trivial

section
variable {prims : Prims} {T : TermInfo} {call : Calls} {B : Nat}

mutual
theorem effCls_holds (ho : OracleOk prims T call) {A : AEnv} {E : Env} (h : EnvOk B A E) :
    ∀ (e : SrcEff) {v : Value}, peff call E e = some v → (effCls prims T A e).holds B v
  | .ePure x, v, he => by
    simp only [peff] at he
    exact exprCls_holds h x he
  | .eCall c args, v, he => by
    simp only [peff, Option.bind_eq_some_iff] at he
    obtain ⟨vs, hvs, hc⟩ := he
    simp only [effCls]
    exact callCls_holds ho (effsCls_holds ho h args hvs) hc
  | .eApply _ _ _, _, _ | .eNeg _, _, _ | .eNot _, _, _ | .eCast _ _, _, _ | .eIndex _ _, _, _
  | .eStruct _ _, _, _ | .eVariant _ _ _, _, _ | .eMatch _ _ _ _ _, _, _ | .eDivide _ _ _, _, _
  | .eStride _, _, _ => by simp only [effCls]; trivial

theorem effsCls_holds (ho : OracleOk prims T call) {A : AEnv} {E : Env} (h : EnvOk B A E) :
    ∀ (es : List SrcEff) {vs : List Value}, peffs call E es = some vs →
      ListRel (SizeCls.holds B) (effsCls prims T A es) vs
  | [], vs, he => by
    simp only [peffs, Option.some.injEq] at he
    subst he
    exact .nil
  | e :: es, vs, he => by
    simp only [peffs, Option.bind_eq_some_iff, Option.map_eq_some_iff] at he
    obtain ⟨v, hv, vs', hvs, rfl⟩ := he
    exact .cons (effCls_holds ho h e hv) (effsCls_holds ho h es hvs)
end

end

/-! ## Checked bodies settle once their calls do -/

/-- The measure of a call annotated `a` with designated argument of size `s`
is below the one of `me` with size `B`. -/
def Below (me : TermAnn) (B : Nat) (a : TermAnn) (s : Nat) : Prop :=
  a.rank < me.rank ∨ (a.rank = me.rank ∧ (s < B ∨ (s = B ∧ a.sub < me.sub)))

theorem settles_prim {sp : SrcProgram} {prims : Prims} {c : Nat} (hp : prims.isPrim c = true)
    (vs : List Value) : Settles sp prims c vs := by
  refine ⟨1, fun m hm => ?_⟩
  obtain ⟨m, rfl⟩ : ∃ m', m = m' + 1 := ⟨m - 1, by omega⟩
  simp [pcall, hp]

theorem ListRel.getD {B : Nat} {cs : List SizeCls} {vs : List Value} (r : ListRel (SizeCls.holds B) cs vs) :
    ∀ pos, (cs.getD pos .unk = .unk) ∨ ∃ v, vs[pos]? = some v ∧ (cs.getD pos .unk).holds B v := by
  induction r with
  | nil => intro pos; left; simp
  | cons hk _ ih =>
    intro pos
    cases pos with
    | zero => right; exact ⟨_, rfl, by simpa using hk⟩
    | succ p => simpa using ih p

section
variable {sp : SrcProgram} {prims : Prims} {T : TermInfo} {me : TermAnn} {B : Nat}

theorem callSettles
    (IH : ∀ c a vs, T.ann c = some a → Below me B a (argSize a.pos vs) → Settles sp prims c vs)
    {c : Nat} {cs : List SizeCls} {vs : List Value} (hc : callOk prims T me c cs = true)
    (hr : ListRel (SizeCls.holds B) cs vs) : Settles sp prims c vs := by
  unfold callOk at hc
  simp only [Bool.or_eq_true] at hc
  rcases hc with hp | hc
  · exact settles_prim hp vs
  · split at hc
    · simp at hc
    · rename_i a ha
      apply IH c a vs ha
      simp only [Bool.or_eq_true, decide_eq_true_eq, Bool.and_eq_true] at hc
      rcases hc with lt | ⟨eq, hd⟩
      · exact Or.inl lt
      · refine Or.inr ⟨eq, ?_⟩
        rcases hr.getD a.pos with hu | ⟨v, hv, hk⟩
        · rw [hu] at hd; simp [descends] at hd
        · unfold argSize
          rw [hv]
          dsimp only
          revert hd hk
          cases cs.getD a.pos .unk with
          | lt => intro _ hk; exact Or.inl hk
          | le =>
            intro hd hk
            simp only [descends, decide_eq_true_eq] at hd
            simp only [SizeCls.holds] at hk
            omega
          | nz =>
            intro hd hk
            simp only [descends, decide_eq_true_eq] at hd
            simp only [SizeCls.holds] at hk
            omega
          | unk => intro hd; simp [descends] at hd
          | one => intro hd; simp [descends] at hd

mutual
theorem eff_evConst (hD : ∀ c ∈ T.decs, DecOk sp prims c)
    (IH : ∀ c a vs, T.ann c = some a → Below me B a (argSize a.pos vs) → Settles sp prims c vs) :
    ∀ (e : SrcEff) {A : AEnv} {E : Env}, EnvOk B A E → chkEff prims T me A e = true →
      EvConst (fun m => peff (pcall sp prims m) E e)
  | .ePure x, A, E, _, _ => by
    simp only [peff]
    exact EvConst.const _
  | .eCall c args, A, E, h, hc => by
    simp only [chkEff, Bool.and_eq_true] at hc
    simp only [peff]
    refine EvConst.bind (eff_evConst_list hD IH args h hc.1) fun vs ⟨m, hm⟩ => ?_
    exact callSettles IH hc.2 (effsCls_holds (oracleOk_pcall hD m) h args hm)
  | .eApply op l r, A, E, h, hc => by
    simp only [chkEff, Bool.and_eq_true] at hc
    simp only [peff]
    exact EvConst.pair (applyOp op) (eff_evConst hD IH l h hc.1) (eff_evConst hD IH r h hc.2)
  | .eNeg x, A, E, h, hc => by
    simp only [chkEff] at hc
    simp only [peff]
    exact EvConst.map (fun o => o.bind (unary .negate)) (eff_evConst hD IH x h hc)
  | .eNot x, A, E, h, hc => by
    simp only [chkEff] at hc
    simp only [peff]
    exact EvConst.map (fun o => o.bind (unary .logicalNot)) (eff_evConst hD IH x h hc)
  | .eCast ty x, A, E, h, hc => by
    simp only [chkEff] at hc
    simp only [peff]
    exact EvConst.map (fun o => o.bind (cast ty)) (eff_evConst hD IH x h hc)
  | .eIndex _ _, A, E, _, _ => by
    simp only [peff]
    exact EvConst.const _
  | .eStruct ty fields, A, E, h, hc => by
    simp only [chkEff] at hc
    simp only [peff]
    exact EvConst.map (fun o => o.map (Value.structure ty.typeId)) (eff_evConst_list hD IH fields h hc)
  | .eVariant ty k payload, A, E, h, hc => by
    simp only [chkEff] at hc
    simp only [peff]
    exact EvConst.map (fun o => o.map (Value.enumeration ty.typeId k)) (eff_evConst_list hD IH payload h hc)
  | .eMatch scrutinee ety _ binders values, A, E, h, hc => by
    simp only [chkEff, Bool.and_eq_true] at hc
    simp only [peff]
    refine EvConst.bind (eff_evConst hD IH scrutinee h hc.1) fun v ⟨m, hm⟩ => ?_
    exact eff_evConst_arms hD IH (effCls_holds (oracleOk_pcall hD m) h scrutinee hm) ety.typeId values 0 binders
      h hc.2
  | .eDivide op l r, A, E, h, hc => by
    simp only [chkEff, Bool.and_eq_true] at hc
    simp only [peff]
    exact EvConst.pair (binary op.toCore) (eff_evConst hD IH l h hc.1) (eff_evConst hD IH r h hc.2)
  | .eStride _, A, E, _, _ => by
    simp only [peff]
    exact EvConst.const _

theorem eff_evConst_list (hD : ∀ c ∈ T.decs, DecOk sp prims c)
    (IH : ∀ c a vs, T.ann c = some a → Below me B a (argSize a.pos vs) → Settles sp prims c vs) :
    ∀ (es : List SrcEff) {A : AEnv} {E : Env}, EnvOk B A E → chkEffs prims T me A es = true →
      EvConst (fun m => peffs (pcall sp prims m) E es)
  | [], A, E, _, _ => by
    simp only [peffs]
    exact EvConst.const _
  | e :: es, A, E, h, hc => by
    simp only [chkEffs, Bool.and_eq_true] at hc
    simp only [peffs]
    exact EvConst.pair (fun o os => o.bind fun v => os.map (v :: ·)) (eff_evConst hD IH e h hc.1)
      (eff_evConst_list hD IH es h hc.2)

theorem eff_evConst_arms (hD : ∀ c ∈ T.decs, DecOk sp prims c)
    (IH : ∀ c a vs, T.ann c = some a → Below me B a (argSize a.pos vs) → Settles sp prims c vs) {c : SizeCls} {v : Value} (hv : c.holds B v) (id : Nat) :
    ∀ (values : List SrcEff) (k : Nat) (binders : List (List Nat)) {A : AEnv} {E : Env}, EnvOk B A E →
      chkArms prims T me A c.part binders values = true →
      EvConst (fun m => parms (pcall sp prims m) E v id k binders values)
  | _, _, [], A, E, _, _ => by
    simp only [parms]
    exact EvConst.const _
  | [], _, _ :: _, A, E, _, _ => by
    simp only [parms]
    exact EvConst.const _
  | value :: values, k, bs :: rest, A, E, h, hc => by
    simp only [chkArms, Bool.and_eq_true] at hc
    simp only [parms]
    cases hm : matchPattern (.enumVariant id k (bs.map .bind)) v with
    | none => exact eff_evConst_arms hD IH hv id values (k + 1) rest h hc.2
    | some bindings => exact eff_evConst hD IH value (EnvOk.bindAll (match_binds hv hm) h) hc.1
end

end

section
variable {sp : SrcProgram} {prims : Prims} {T : TermInfo} {me : TermAnn} {B : Nat}
  (hD : ∀ c ∈ T.decs, DecOk sp prims c)
  (IH : ∀ c a vs, T.ann c = some a → Below me B a (argSize a.pos vs) → Settles sp prims c vs)
include hD IH

/-- A checked statement, run with calls of fuel `m`, is eventually constant
in `m`. -/
theorem stmt_evConst :
    ∀ (s : SrcStmt) {A : AEnv} {E : Env}, EnvOk B A E → chkStmt prims T me A s = true →
      EvConst (fun m => pstmt (pcall sp prims m) E s) := by
  intro s
  induction s with
  | nop => intro A E _ _; simp only [pstmt]; exact EvConst.const _
  | «let» id _ value body ih =>
    intro A E h hc
    simp only [chkStmt] at hc
    simp only [pstmt]
    cases hv : pexpr E value with
    | none => simp only [Option.bind]; exact EvConst.const _
    | some v => simp only [Option.bind]; exact ih (h.cons (exprCls_holds h value hv)) hc
  | letStruct id ty fields body ih =>
    intro A E h hc
    simp only [chkStmt] at hc
    simp only [pstmt]
    cases hv : pexprs E fields with
    | none => simp only [Option.bind]; exact EvConst.const _
    | some vs => simp only [Option.bind]; exact ih (h.cons (by trivial)) hc
  | letCall id _ callee args body ih =>
    intro A E h hc
    simp only [chkStmt, Bool.and_eq_true] at hc
    simp only [pstmt]
    cases hvs : pexprs E args with
    | none => simp only [Option.bind]; exact EvConst.const _
    | some vs =>
      have hr := exprsCls_holds h args hvs
      refine EvConst.bind (callSettles IH hc.1 hr) fun v ⟨m, hm⟩ => ?_
      exact ih (h.cons (callCls_holds (oracleOk_pcall hD m) hr hm)) hc.2
  | letEnum id ty k payload body ih =>
    intro A E h hc
    simp only [chkStmt] at hc
    simp only [pstmt]
    cases hv : pexprs E payload with
    | none => simp only [Option.bind]; exact EvConst.const _
    | some vs => simp only [Option.bind]; exact ih (h.cons (by trivial)) hc
  | «then» first second ih1 ih2 =>
    intro A E h hc
    simp only [chkStmt, Bool.and_eq_true] at hc
    simp only [pstmt]
    exact EvConst.next (ih1 h hc.1) fun ⟨_, hm⟩ => ih2 (after_ok h _ first hm) hc.2
  | «if» condition a b iha ihb =>
    intro A E h hc
    simp only [chkStmt, Bool.and_eq_true] at hc
    simp only [pstmt]
    cases hcv : pexpr E condition with
    | none => simp only [Option.bind]; exact EvConst.const _
    | some w =>
      cases hb : asBool w with
      | none => simp only [hb, Option.bind]; exact EvConst.const _
      | some bv =>
        simp only [hb, Option.bind]
        cases bv with
        | true => simp only [↓reduceIte]; exact iha h hc.1
        | false =>
          simp only [Bool.false_eq_true, ↓reduceIte]
          have hc2 := hc.2
          revert hc2
          cases hg : guardVar condition with
          | none => exact fun hc2 => ihb h hc2
          | some x => exact fun hc2 => ihb (h.refine (guard_nz hg hcv hb)) hc2
  | letEval id _ value body ih =>
    intro A E h hc
    simp only [chkStmt, Bool.and_eq_true] at hc
    simp only [pstmt]
    refine EvConst.bind (eff_evConst hD IH value h hc.1) fun v ⟨m, hm⟩ => ?_
    exact ih (h.cons (effCls_holds (oracleOk_pcall hD m) h value hm)) hc.2
  | ifEval condition a b iha ihb =>
    intro A E h hc
    simp only [chkStmt, Bool.and_eq_true] at hc
    simp only [pstmt]
    refine EvConst.bind (EvConst.map (fun o => o.bind asBool) (eff_evConst hD IH condition h hc.1.1))
      fun bv _ => ?_
    cases bv with
    | true => simp only [↓reduceIte]; exact iha h hc.1.2
    | false => simp only [Bool.false_eq_true, ↓reduceIte]; exact ihb h hc.2
  | «return» value => intro A E _ _; simp only [pstmt]; exact EvConst.const _
  | returnEval value =>
    intro A E h hc
    simp only [chkStmt] at hc
    simp only [pstmt]
    exact EvConst.map (fun o => o.map fun v => Done.ret (some v)) (eff_evConst hD IH value h hc)
  | discard value =>
    intro A E h hc
    simp only [chkStmt] at hc
    simp only [pstmt]
    exact EvConst.map (fun o => o.map fun _ => Done.next) (eff_evConst hD IH value h hc)
  | assert condition =>
    intro A E h hc
    simp only [chkStmt] at hc
    simp only [pstmt]
    exact EvConst.map (fun o => (o.bind asBool).bind fun b => if b then some Done.next else none)
      (eff_evConst hD IH condition h hc)
  | returnUnit => intro A E _ _; simp only [pstmt]; exact EvConst.const _
  | letMatch _ _ _ _ _ _ | set _ _ | setField _ _ _ | setCall _ _ _ | «while» _ _ | letAlloc _ _ _ _
  | letLoad _ _ _ _ | setByte _ _ _ | free _ _ _ | letSlice _ _ _ _ _ | letIndex _ _ _ _ _
  | setIndex _ _ _ | setEval _ _ | whileEval _ _ | setIndexEval _ _ _ | setFieldEval _ _ _ | «break»
  | «continue» | matchArm _ _ _ _ _ _ _ _ | unreachable _ _ =>
    intro A E _ _; simp only [pstmt]; exact EvConst.const _

end

/-! ## Every annotated call settles -/

theorem ListRel.of_getElem {α β : Type} {R : α → β → Prop} :
    ∀ {as : List α} {bs : List β}, as.length = bs.length →
      (∀ i (h1 : i < as.length) (h2 : i < bs.length), R as[i] bs[i]) → ListRel R as bs
  | [], [], _, _ => .nil
  | [], _ :: _, len, _ => by simp at len
  | _ :: _, [], len, _ => by simp at len
  | a :: as, b :: bs, len, h =>
    .cons (h 0 (by simp) (by simp))
      (ListRel.of_getElem (by simpa using len) fun i h1 h2 => h (i + 1) (Nat.succ_lt_succ h1) (Nat.succ_lt_succ h2))

theorem initCls_holds (pos : Nat) (vs : List Value) :
    ListRel (SizeCls.holds (argSize pos vs)) (initCls pos vs.length) vs := by
  refine ListRel.of_getElem (by simp [initCls]) fun i h1 h2 => ?_
  simp only [initCls, List.getElem_map, List.getElem_range]
  split
  · rename_i hi
    subst hi
    simp only [SizeCls.holds, argSize, List.getElem?_eq_getElem h2]
    exact Nat.le_refl _
  · trivial

theorem zip_rel {B : Nat} {cs : List SizeCls} {vs : List Value} (r : ListRel (SizeCls.holds B) cs vs) :
    ∀ (ids : List Nat), ListRel (fun a b => a.1 = b.1 ∧ a.2.holds B b.2) (ids.zip cs) (ids.zip vs) := by
  induction r with
  | nil => intro ids; simp only [List.zip_nil_right]; exact .nil
  | cons hk _ ih =>
    intro ids
    cases ids with
    | nil => simp only [List.zip_nil_left]; exact .nil
    | cons x ids => exact .cons ⟨rfl, hk⟩ (ih ids)

theorem EnvOk.nil (B : Nat) (E : Env) : EnvOk B [] E := by
  intro x c v ha
  simp [AEnv.get?] at ha

theorem lookup_mem {c : Nat} {a : TermAnn} : ∀ {l : List (Nat × TermAnn)}, l.lookup c = some a → (c, a) ∈ l
  | [], h => by simp [List.lookup] at h
  | (k, b) :: l, h => by
    simp only [List.lookup] at h
    split at h
    · rename_i hk
      simp only [Option.some.injEq] at h
      subst h
      simp only [beq_iff_eq] at hk
      subst hk
      exact List.mem_cons_self
    · exact List.mem_cons_of_mem _ (lookup_mem h)

/-- **Pure calls settle.** Under `TermOk`, a call of an annotated function
on any arguments has a fuel past which `pcall` gives one answer. -/
theorem pcall_complete {sp : SrcProgram} {prims : Prims} {T : TermInfo} (hT : TermOk sp prims T) :
    ∀ c a, T.ann c = some a → ∀ vs, Settles sp prims c vs := by
  suffices H : ∀ r s k c a vs, T.ann c = some a → a.rank = r → argSize a.pos vs = s → a.sub = k →
      Settles sp prims c vs from
    fun c a ha vs => H _ _ _ c a vs ha rfl rfl rfl
  intro r
  induction r using Nat.strongRecOn with
  | _ r IHr =>
  intro s
  induction s using Nat.strongRecOn with
  | _ s IHs =>
  intro k
  induction k using Nat.strongRecOn with
  | _ k IHk =>
  intro c a vs ha hr hs hk
  have IH : ∀ c' a' vs', T.ann c' = some a' → Below a (argSize a.pos vs) a' (argSize a'.pos vs') →
      Settles sp prims c' vs' := by
    intro c' a' vs' ha' hb
    rcases hb with lt | ⟨eq, lt | ⟨eq2, lt⟩⟩
    · exact IHr a'.rank (by omega) _ _ c' a' vs' ha' rfl rfl rfl
    · exact IHs _ (by omega) _ c' a' vs' ha' (by omega) rfl rfl
    · exact IHk _ (by omega) c' a' vs' ha' (by omega) (by omega) rfl
  by_cases hp : prims.isPrim c = true
  · exact settles_prim hp vs
  · have hp' : prims.isPrim c = false := by simpa using hp
    cases hf : sp.funcs[c]? with
    | none =>
      refine ⟨0, fun m _ => ?_⟩
      cases m <;> simp [pcall, hp', hf]
    | some f =>
      by_cases hl : vs.length = f.params.length
      · have hchk : chkFn prims T a f = true :=
          ((hT.fns (c, a) (lookup_mem ha)).resolve_left (by simpa using hp)) f hf
        have henv : EnvOk (argSize a.pos vs)
            (AEnv.bindAll [] ((paramIds f.params).zip (initCls a.pos f.params.length)))
            (paramEnv f.params vs) := by
          rw [paramEnv, paramBindings_ids, ← hl]
          exact EnvOk.bindAll (zip_rel (initCls_holds a.pos vs) _) (EnvOk.nil _ _)
        obtain ⟨N, hN⟩ := stmt_evConst hT.decs IH f.body henv hchk
        refine ⟨N + 1, fun m hm => ?_⟩
        obtain ⟨m, rfl⟩ : ∃ m', m = m' + 1 := ⟨m - 1, by omega⟩
        simp only [pcall, hp', hf, hl, Bool.false_eq_true, ↓reduceIte]
        have e := hN m (by omega)
        simp only at e
        rw [e]
      · refine ⟨0, fun m _ => ?_⟩
        cases m <;> simp [pcall, hp', hf, hl]

end Lanius.Faithful
