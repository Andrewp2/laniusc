import Lanius.Faithful.Sim.Term

/-! # The termination check is sound

`pcall_complete`: under `TermOk`, every call of an annotated function
settles. The proof is a well-founded induction on the measure of the call,
`(rank, size of the designated argument, subrank)`: a checked body run with
calls of fuel `m` is eventually constant in `m` once every call it makes
settles (`stmt_evConst`), and the check sees to it that every call it makes
is smaller than the call being run. -/

namespace Lanius.Faithful.Termination

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

theorem EnvOk.refine {B : Nat} {A : AEnv} {E : Env} (h : EnvOk B A E) {x k : Nat}
    (hx : ∀ v, E.get? x = some v → ∃ n, v = .unsigned .usize n ∧ k ≤ n) : EnvOk B (A.refine x k) E := by
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
  | ge _ => simp only [SizeCls.part, SizeCls.holds] at hw ⊢; omega
  | lit _ => trivial

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
      subst hc
      simp only [SizeCls.holds, UintTy.toCore]
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
    ∃ n, l = .unsigned .usize n ∧ 1 ≤ n := by
  cases l with
  | unsigned t n =>
    cases t <;> simp [evalBinaryValue, scalarEqual, Except.toOption] at h <;> subst h <;>
      simp_all [asBool] <;> omega
  | unit | boolean _ | signed _ _ | f32Bits _ | f64Bits _ | character _ | string _
  | pointer _ | array _ | slice _ _ _ _ _ | rawSlice _ _ _ | «structure» _ _ | enumeration _ _ _
  | reference _ _ _ =>
    simp [evalBinaryValue, scalarEqual, Except.toOption] at h

theorem less_false {l w : Value} {k : Nat}
    (h : (evalBinaryValue target .less l (.unsigned .usize k)).toOption = some w) (hb : asBool w = some false) :
    ∃ n, l = .unsigned .usize n ∧ k ≤ n := by
  cases l with
  | unsigned t n =>
    cases t with
    | usize =>
      simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalUnsignedBinary, Except.toOption,
        Option.some.injEq] at h
      subst h
      simp only [asBool, Option.some.injEq, decide_eq_false_iff_not, Nat.not_lt] at hb
      exact ⟨n, rfl, hb⟩
    | u8 | u16 | u32 | u64 =>
      simp [evalBinaryValue, Semantics.evalShiftBy, Except.toOption] at h
  | signed _ _ =>
    simp [evalBinaryValue, Semantics.evalShiftBy, Except.toOption] at h
  | unit | boolean _ | f32Bits _ | f64Bits _ | character _ | string _
  | pointer _ | array _ | slice _ _ _ _ _ | rawSlice _ _ _ | «structure» _ _ | enumeration _ _ _
  | reference _ _ _ =>
    simp [evalBinaryValue, Except.toOption] at h

theorem localOf_some {e : SrcExpr} {x : Nat} (h : localOf e = some x) : e = .local x := by
  cases e <;> simp_all [localOf]

theorem usizeLit_some {e : SrcExpr} {k : Nat} (h : usizeLit e = some k) :
    ∃ v : BitVec 64, e = .unsigned .usize v ∧ v.toNat = k := by
  cases e with
  | unsigned t v =>
    simp only [usizeLit] at h
    split at h
    · rename_i ht
      simp only [Option.some.injEq] at h
      exact ⟨v, by rw [ht], h⟩
    · simp at h
  | int _ | boolean _ | «local» _ | field _ _ | negate _ | not _ | apply _ _ _ | cast _ _ | null
  | char _ | float _ _ => simp [usizeLit] at h

/-- A guard that failed bounds its local below. -/
theorem guard_ge {E : Env} {c : SrcExpr} {x k : Nat} {w : Value} (hg : guardVar c = some (x, k))
    (hc : pexpr E c = some w) (hb : asBool w = some false) :
    ∀ v, E.get? x = some v → ∃ n, v = .unsigned .usize n ∧ k ≤ n := by
  intro v hv
  cases c with
  | apply op l r =>
    simp only [guardVar] at hg
    cases hr : usizeLit r with
    | none => simp [hr] at hg
    | some k' =>
      obtain ⟨bv, rfl, hbv⟩ := usizeLit_some hr
      simp only [hr] at hg
      cases hl : localOf l with
      | none => simp [hl] at hg
      | some y =>
        have := localOf_some hl
        subst this
        simp only [hl, Option.map_some] at hg
        by_cases he : op = .equal ∧ k' = 0
        · rw [if_pos he] at hg
          obtain ⟨rfl, rfl⟩ := he
          simp only [Option.some.injEq, Prod.mk.injEq] at hg
          obtain ⟨rfl, rfl⟩ := hg
          simp only [pexpr, applyOp, binary, SrcOp.toCore, hv, UintTy.toCore, hbv, Option.bind_some] at hc
          exact equal_zero_false hc hb
        · rw [if_neg he] at hg
          by_cases hlt : op = .less
          · subst hlt
            simp only [↓reduceIte, Option.some.injEq, Prod.mk.injEq] at hg
            obtain ⟨rfl, rfl⟩ := hg
            simp only [pexpr, applyOp, binary, SrcOp.toCore, hv, UintTy.toCore, hbv, Option.bind_some] at hc
            exact less_false hc hb
          · rw [if_neg hlt] at hg
            simp at hg
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
    · rename_i x k hg
      split
      · rename_i never
        simp only [pstmt, Option.bind_eq_some_iff] at hs
        obtain ⟨cv, ⟨w, hw, hb⟩, hs⟩ := hs
        cases cv with
        | true => exact absurd hs (neverNext_sound call a E never)
        | false => exact h.refine (guard_ge hg hw hb)
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

theorem usize_sub {n d : Nat} (h1 : 1 ≤ d) (hd : d ≤ n) : ∃ r, r < n ∧
    evalBinaryValue target .subtract (.unsigned .usize n) (.unsigned .usize d) = .ok (.unsigned .usize r) :=
  ⟨_, by omega, usize_subtract n d⟩

/-- A decrement of a `usize` by at least 1 and at most itself gives a smaller value. -/
theorem dec_lt {sp : SrcProgram} {prims : Prims} {c : Nat} (hd : DecOk sp prims c) {m n d : Nat} {v : Value}
    (h1 : 1 ≤ d) (hdn : d ≤ n) (h : pcall sp prims m c [.unsigned .usize n, .unsigned .usize d] = some v) :
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
    obtain ⟨r, hr, hsub⟩ := usize_sub h1 hdn
    have hgt : decide (d > n) = false := by simp; omega
    simp [pstmt, pexpr, Env.bindAll, Env.get?, hba, applyOp, binary, SrcOp.toCore, usize_greater,
      hsub, Except.toOption, asBool, hgt] at h
    simp only [Option.bind, Done.then, doneValue, Option.some.injEq] at h
    subst h
    exact sizeOf_unsigned_lt hr

/-- What the classes assume of the calls: prims are the identity, and
decrements decrement. -/
structure OracleOk (prims : Prims) (T : TermInfo) (call : Calls) : Prop where
  prim : ∀ c vs v, prims.isPrim c = true → call c vs = some v → single vs = some v
  dec : ∀ c ∈ T.decs, ∀ n d v, 1 ≤ d → d ≤ n → call c [.unsigned .usize n, .unsigned .usize d] = some v →
    sizeOf v < sizeOf (Value.unsigned .usize n)

theorem oracleOk_pcall {sp : SrcProgram} {prims : Prims} {T : TermInfo} (hD : ∀ c ∈ T.decs, DecOk sp prims c)
    (m : Nat) : OracleOk prims T (pcall sp prims m) where
  prim := by
    intro c vs v hp hv
    cases m with
    | zero => simp [pcall] at hv
    | succ m => simpa [pcall, hp] using hv
  dec := fun c hc _ _ _ h1 hdn hv => dec_lt (hD c hc) h1 hdn hv

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
            cases a with
            | ge k =>
              cases b with
              | lit d =>
                simp only [decCls]
                split
                · rename_i hd
                  obtain ⟨hle, n, rfl, hkn⟩ := ha
                  simp only [SizeCls.holds] at hb
                  subst hb
                  have := ho.dec c (List.contains_iff_mem.mp hdec) n d v hd.1 (by omega) h
                  simp only [SizeCls.holds]
                  omega
                · trivial
              | unk | le | lt | ge _ => trivial
            | unk | le | lt | lit _ => trivial
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

theorem foldr_max_le {B : Nat} : ∀ {l : List Nat}, (∀ x ∈ l, x ≤ B) → l.foldr max 0 ≤ B
  | [], _ => Nat.zero_le _
  | x :: l, h => by
    simp only [List.foldr_cons]
    have := foldr_max_le (l := l) fun y hy => h y (List.mem_cons_of_mem _ hy)
    have := h x List.mem_cons_self
    omega

theorem foldr_max_lt {B : Nat} : ∀ {l : List Nat}, l ≠ [] → (∀ x ∈ l, x < B) → l.foldr max 0 < B
  | [], ne, _ => absurd rfl ne
  | x :: l, _, h => by
    simp only [List.foldr_cons]
    have hx := h x List.mem_cons_self
    cases l with
    | nil => simp only [List.foldr_nil]; omega
    | cons y l =>
      have := foldr_max_lt (l := y :: l) (by simp) fun z hz => h z (List.mem_cons_of_mem _ hz)
      omega

theorem le_foldr_max {x : Nat} : ∀ {l : List Nat}, x ∈ l → x ≤ l.foldr max 0
  | [], hx => by simp at hx
  | y :: l, hx => by
    simp only [List.foldr_cons]
    rcases List.mem_cons.mp hx with rfl | hx
    · omega
    · have := le_foldr_max hx
      omega

theorem argAt_le {B : Nat} {cs : List SizeCls} {vs : List Value} (r : ListRel (SizeCls.holds B) cs vs) (p : Nat)
    (h : (cs.getD p .unk).isLe = true) : argAt vs p ≤ B := by
  rcases r.getD p with hu | ⟨v, hv, hk⟩
  · rw [hu] at h; simp [SizeCls.isLe] at h
  · unfold argAt
    rw [hv]
    dsimp only
    revert h hk
    cases cs.getD p .unk with
    | lt => intro _ hk; exact Nat.le_of_lt hk
    | le => intro _ hk; exact hk
    | ge _ => intro _ hk; exact hk.1
    | unk => intro h; simp [SizeCls.isLe] at h
    | lit _ => intro h; simp [SizeCls.isLe] at h

theorem argAt_lt {B : Nat} {cs : List SizeCls} {vs : List Value} (r : ListRel (SizeCls.holds B) cs vs) (p : Nat)
    (h : (cs.getD p .unk).isLt = true) : argAt vs p < B := by
  rcases r.getD p with hu | ⟨v, hv, hk⟩
  · rw [hu] at h; simp [SizeCls.isLt] at h
  · unfold argAt
    rw [hv]
    dsimp only
    revert h hk
    cases cs.getD p .unk with
    | lt => intro _ hk; exact hk
    | le => intro h; simp [SizeCls.isLt] at h
    | ge _ => intro h; simp [SizeCls.isLt] at h
    | unk => intro h; simp [SizeCls.isLt] at h
    | lit _ => intro h; simp [SizeCls.isLt] at h

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
        unfold descends at hd
        simp only [Bool.or_eq_true, Bool.and_eq_true, Bool.not_eq_true', List.isEmpty_eq_false_iff,
          List.all_eq_true, List.mem_map, forall_exists_index, and_imp, forall_apply_eq_imp_iff₂,
          decide_eq_true_eq] at hd
        unfold argSize
        rcases hd with ⟨ne, hlt⟩ | ⟨sub, hle⟩
        · left
          refine foldr_max_lt (by simpa using ne) ?_
          simp only [List.mem_map, forall_exists_index, and_imp, forall_apply_eq_imp_iff₂]
          exact fun p hp => argAt_lt hr p (hlt p hp)
        · have : (a.pos.map (argAt vs)).foldr max 0 ≤ B := by
            refine foldr_max_le ?_
            simp only [List.mem_map, forall_exists_index, and_imp, forall_apply_eq_imp_iff₂]
            exact fun p hp => argAt_le hr p (hle p hp)
          omega

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
          | some xk => exact fun hc2 => ihb (h.refine (guard_ge hg hcv hb)) hc2
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

theorem initCls_holds (pos : List Nat) (vs : List Value) :
    ListRel (SizeCls.holds (argSize pos vs)) (initCls pos vs.length) vs := by
  refine ListRel.of_getElem (by simp [initCls]) fun i h1 h2 => ?_
  simp only [initCls, List.getElem_map, List.getElem_range]
  split
  · rename_i hi
    have : argAt vs i = sizeOf vs[i] := by simp only [argAt, List.getElem?_eq_getElem h2]
    simp only [SizeCls.holds, argSize]
    rw [← this]
    exact le_foldr_max (List.mem_map_of_mem hi)
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

theorem find_mem {c : Nat} {a : TermAnn} : ∀ {t : ATree}, t.find c = some a → (c, a) ∈ t.toList
  | .leaf, h => by simp [ATree.find] at h
  | .node l k b r, h => by
    simp only [ATree.toList]
    simp only [ATree.find] at h
    cases hk : Nat.beq c k with
    | true =>
      rw [hk] at h
      simp only [Option.some.injEq] at h
      subst h
      rw [Nat.eq_of_beq_eq_true hk]
      exact List.mem_append_right _ List.mem_cons_self
    | false =>
      rw [hk] at h
      cases hl : Nat.blt c k with
      | true =>
        rw [hl] at h
        exact List.mem_append_left _ (find_mem h)
      | false =>
        rw [hl] at h
        exact List.mem_append_right _ (List.mem_cons_of_mem _ (find_mem h))

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
          ((hT.fns (c, a) (find_mem ha)).resolve_left (by simpa using hp)) f hf
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

/-! ## Checking a program's annotations one function at a time -/

/-- One annotated function: a prim, or its body passes the check. -/
def FnOk (sp : SrcProgram) (prims : Prims) (T : TermInfo) (p : Nat × TermAnn) : Prop :=
  prims.isPrim p.1 = true ∨ ∀ f, sp.funcs[p.1]? = some f → chkFn prims T p.2 f = true

def AllFns (sp : SrcProgram) (prims : Prims) (T : TermInfo) : List (Nat × TermAnn) → Prop
  | [] => True
  | p :: ps => FnOk sp prims T p ∧ AllFns sp prims T ps

def AllDecs (sp : SrcProgram) (prims : Prims) : List Nat → Prop
  | [] => True
  | c :: cs => DecOk sp prims c ∧ AllDecs sp prims cs

theorem fnOk_of {sp : SrcProgram} {prims : Prims} {T : TermInfo} {c : Nat} {a : TermAnn} {f : SrcFunc}
    (hf : sp.funcs[c]? = some f) (h : chkFn prims T a f = true) : FnOk sp prims T (c, a) :=
  Or.inr fun g hg => by
    rw [hf] at hg
    cases hg
    exact h

theorem decOk_of {sp : SrcProgram} {prims : Prims} {c : Nat} {f : SrcFunc} (a b : Nat) {panic : SrcStmt}
    (np : prims.isPrim c = false) (hf : sp.funcs[c]? = some f) (hids : paramIds f.params = [a, b])
    (hab : a ≠ b)
    (hbody : f.body = .then (.if (.apply .greater (.local b) (.local a)) panic .nop)
      (.return (.apply .minus (.local a) (.local b)))) : DecOk sp prims c :=
  ⟨np, f, a, b, panic, hf, hids, hab, hbody⟩

theorem AllFns.append {sp : SrcProgram} {prims : Prims} {T : TermInfo} :
    ∀ {l₁ l₂ : List (Nat × TermAnn)}, AllFns sp prims T l₁ → AllFns sp prims T l₂ →
      AllFns sp prims T (l₁ ++ l₂)
  | [], _, _, h₂ => h₂
  | _ :: _, _, ⟨hp, h₁⟩, h₂ => ⟨hp, AllFns.append h₁ h₂⟩

theorem AllFns.mem {sp : SrcProgram} {prims : Prims} {T : TermInfo} :
    ∀ {l : List (Nat × TermAnn)}, AllFns sp prims T l → ∀ p ∈ l, FnOk sp prims T p
  | [], _, p, hp => by simp at hp
  | _ :: _, ⟨hq, h⟩, p, hp => by
    rcases List.mem_cons.mp hp with rfl | hp
    · exact hq
    · exact AllFns.mem h p hp

theorem AllDecs.mem {sp : SrcProgram} {prims : Prims} :
    ∀ {l : List Nat}, AllDecs sp prims l → ∀ c ∈ l, DecOk sp prims c
  | [], _, c, hc => by simp at hc
  | _ :: _, ⟨hq, h⟩, c, hc => by
    rcases List.mem_cons.mp hc with rfl | hc
    · exact hq
    · exact AllDecs.mem h c hc

theorem termOk_of {sp : SrcProgram} {prims : Prims} {T : TermInfo} {l : List (Nat × TermAnn)}
    (hd : AllDecs sp prims T.decs) (he : T.anns = l) (hf : AllFns sp prims T l) : TermOk sp prims T :=
  ⟨hd.mem, he ▸ hf.mem⟩

end Lanius.Faithful.Termination
