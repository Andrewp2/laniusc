import Lanius.Faithful.Sim.Term
import Lanius.Faithful.Sim.Mono
import Lanius.Faithful.Agree

/-! # The termination check is sound

Every pure call settles (`pcall_settles`), as more fuel keeps a value. What
the check knows of the locals holds of their values (`EnvOk`): through the
statements of a body (`after_ok`, `neverNext_sound`), at calls whose values
the classes know (`OracleOk`), and for the measure of a call, `(rank, size
of the designated argument, subrank)`, below which every call a checked
body makes is (`Below`). `pcall_live` (`Live.lean`) is the well-founded
induction on that measure. -/

namespace Lanius.Faithful.Termination

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (evalBinaryValue evalUnsignedBinary scalarEqual matchPattern matchPatterns)

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
  | nil _ _ => trivial

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

/-! ## Facts from matches -/

/-- The facts hold of `B`. -/
def WitOk (B : Nat) (W : Wit) : Prop :=
  ∀ p ∈ W, ∀ j ≤ p.2, sizeOf (Value.enumeration p.1 j []) < B

theorem WitOk.nil (B : Nat) : WitOk B [] := by
  intro p hp
  simp at hp

/-- **A payload-free variant is minimal**: smaller than a later or the same
variant of its enum with a payload. -/
theorem sizeOf_nil_lt {id j k : Nat} {p : Value} {ps : List Value} (h : j ≤ k) :
    sizeOf (Value.enumeration id j []) < sizeOf (Value.enumeration id k (p :: ps)) := by
  have hps : 0 < sizeOf ps := by
    cases ps with
    | nil => simp only [List.nil.sizeOf_spec]; omega
    | cons _ _ => simp only [List.cons.sizeOf_spec]; omega
  simp only [Value.enumeration.sizeOf_spec, List.cons.sizeOf_spec, List.nil.sizeOf_spec, sizeOf_nat]
  omega

theorem match_payload {id k b : Nat} {bs : List Nat} {v : Value} {bindings : List (Nat × Value)}
    (h : matchPattern (.enumVariant id k ((b :: bs).map .bind)) v = some bindings) :
    ∃ p ps, v = .enumeration id k (p :: ps) := by
  cases v with
  | enumeration id' k' payload =>
    simp only [matchPattern] at h
    split at h
    · rename_i hc
      simp only [Bool.and_eq_true, beq_iff_eq] at hc
      obtain ⟨rfl, rfl⟩ := hc
      cases payload with
      | nil => simp [matchPatterns] at h
      | cons p ps => exact ⟨p, ps, rfl⟩
    · simp at h
  | unit | boolean _ | signed _ _ | unsigned _ _ | f32Bits _ | f64Bits _ | character _ | string _
  | pointer _ | array _ | slice _ _ _ _ _ | rawSlice _ _ _ | «structure» _ _ | reference _ _ _ =>
    simp [matchPattern] at h

theorem le_of_isLe {B : Nat} {c : SizeCls} {v : Value} (hv : c.holds B v) (hle : c.isLe = true) :
    sizeOf v ≤ B := by
  cases c with
  | lt => exact Nat.le_of_lt hv
  | le => exact hv
  | ge _ => exact hv.1
  | unk => simp [SizeCls.isLe] at hle
  | lit _ => simp [SizeCls.isLe] at hle
  | nil _ _ => simp [SizeCls.isLe] at hle

/-- An arm with a payload, on a value no larger than `B`, adds its fact. -/
theorem WitOk.arm {B : Nat} {W : Wit} (hW : WitOk B W) {c : SizeCls} {v : Value} (hv : c.holds B v)
    {id k : Nat} {bs : List Nat} {bindings : List (Nat × Value)}
    (h : matchPattern (.enumVariant id k (bs.map .bind)) v = some bindings) :
    WitOk B (if c.isLe && !bs.isEmpty then (id, k) :: W else W) := by
  cases hc : (c.isLe && !bs.isEmpty) with
  | false => exact hW
  | true =>
    simp only [ite_true]
    simp only [Bool.and_eq_true, Bool.not_eq_true', List.isEmpty_eq_false_iff] at hc
    obtain ⟨hle, hne⟩ := hc
    cases bs with
    | nil => exact absurd rfl hne
    | cons b bs =>
      obtain ⟨p, ps, rfl⟩ := match_payload h
      have hB := le_of_isLe hv hle
      intro q hq j hj
      rcases List.mem_cons.mp hq with rfl | hq
      · have := sizeOf_nil_lt (p := p) (ps := ps) (id := id) hj
        exact Nat.lt_of_lt_of_le this hB
      · exact hW q hq j hj

theorem res_holds {B : Nat} {W : Wit} (hW : WitOk B W) :
    ∀ {c : SizeCls} {v : Value}, c.holds B v → (c.res W).holds B v
  | .nil id j, v, h => by
    simp only [SizeCls.res]
    split
    · rename_i hw
      simp only [List.any_eq_true, Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq] at hw
      obtain ⟨⟨id', k⟩, hp, hid, hj⟩ := hw
      simp only [SizeCls.holds] at h ⊢
      subst h
      dsimp only at hid hj
      subst hid
      exact hW _ hp j hj
    · trivial
  | .unk, _, h | .le, _, h | .lt, _, h | .ge _, _, h | .lit _, _, h => h

theorem ListRel.res {B : Nat} {W : Wit} (hW : WitOk B W) {cs : List SizeCls} {vs : List Value}
    (r : ListRel (SizeCls.holds B) cs vs) : ListRel (SizeCls.holds B) (cs.map (SizeCls.res W)) vs := by
  induction r with
  | nil => exact .nil
  | cons h _ ih => exact .cons (res_holds hW h) ih

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

theorem Out.pop_next {o : Out} {e : Env} (h : o.pop = .next e) : ∃ eb, o = .next eb := by
  cases o with
  | next eb => exact ⟨eb, rfl⟩
  | brk _ => simp [Out.pop] at h
  | cont _ => simp [Out.pop] at h
  | ret _ => simp [Out.pop] at h

theorem neverNext_sound (call : Calls) (fuel : Nat) :
    ∀ (s : SrcStmt) (E e : Env), neverNext s = true → mstmt call fuel E s ≠ some (.next e) := by
  intro s
  induction s with
  | nop => intro E e h; simp [neverNext] at h
  | «let» id _ value body ih =>
    intro E e h he
    simp only [neverNext] at h
    simp only [mstmt, Option.bind_eq_some_iff, Option.map_eq_some_iff] at he
    obtain ⟨v, _, ob, hb, hp⟩ := he
    obtain ⟨eb, rfl⟩ := Out.pop_next hp
    exact ih _ eb h hb
  | letStruct id _ _ body ih =>
    intro E e h he
    simp only [neverNext] at h
    simp only [mstmt, Option.bind_eq_some_iff, Option.map_eq_some_iff] at he
    obtain ⟨v, _, ob, hb, hp⟩ := he
    obtain ⟨eb, rfl⟩ := Out.pop_next hp
    exact ih _ eb h hb
  | letCall id _ _ _ body ih =>
    intro E e h he
    simp only [neverNext] at h
    simp only [mstmt, Option.bind_eq_some_iff, Option.map_eq_some_iff] at he
    obtain ⟨v, _, ob, hb, hp⟩ := he
    obtain ⟨eb, rfl⟩ := Out.pop_next hp
    exact ih _ eb h hb
  | letEnum id _ _ _ body ih =>
    intro E e h he
    simp only [neverNext] at h
    simp only [mstmt, Option.bind_eq_some_iff, Option.map_eq_some_iff] at he
    obtain ⟨v, _, ob, hb, hp⟩ := he
    obtain ⟨eb, rfl⟩ := Out.pop_next hp
    exact ih _ eb h hb
  | letEval id _ _ body ih =>
    intro E e h he
    simp only [neverNext] at h
    simp only [mstmt, Option.bind_eq_some_iff, Option.map_eq_some_iff] at he
    obtain ⟨v, _, ob, hb, hp⟩ := he
    obtain ⟨eb, rfl⟩ := Out.pop_next hp
    exact ih _ eb h hb
  | «then» first second ih1 ih2 =>
    intro E e h he
    simp only [neverNext, Bool.or_eq_true] at h
    simp only [mstmt, Option.bind_eq_some_iff] at he
    obtain ⟨o1, h1, he⟩ := he
    cases o1 with
    | next e1 =>
      rcases h with h | h
      · exact ih1 E e1 h h1
      · exact ih2 e1 e h he
    | brk _ => simp [Out.then] at he
    | cont _ => simp [Out.then] at he
    | ret _ => simp [Out.then] at he
  | «if» _ a b iha ihb =>
    intro E e h he
    simp only [neverNext, Bool.and_eq_true] at h
    simp only [mstmt, Option.bind_eq_some_iff] at he
    obtain ⟨c, _, he⟩ := he
    cases c
    · exact ihb E e h.2 he
    · exact iha E e h.1 he
  | ifEval _ a b iha ihb =>
    intro E e h he
    simp only [neverNext, Bool.and_eq_true] at h
    simp only [mstmt, Option.bind_eq_some_iff] at he
    obtain ⟨c, _, he⟩ := he
    cases c
    · exact ihb E e h.2 he
    · exact iha E e h.1 he
  | «return» _ => intro E e _ he; simp [mstmt] at he
  | returnEval _ => intro E e _ he; simp [mstmt] at he
  | returnUnit => intro E e _ he; simp [mstmt] at he
  | discard _ => intro E e h; simp [neverNext] at h
  | assert _ => intro E e h; simp [neverNext] at h
  | set _ _ => intro E e h; simp [neverNext] at h
  | setEval _ _ => intro E e h; simp [neverNext] at h
  | «while» _ _ => intro E e h; simp [neverNext] at h
  | whileEval _ _ => intro E e h; simp [neverNext] at h
  | «break» => intro E e _ he; simp [mstmt] at he
  | «continue» => intro E e _ he; simp [mstmt] at he
  | letMatch _ _ _ _ _ _ | setField _ _ _ | setCall _ _ _ | letAlloc _ _ _ _ | letView _ _ _ _ _
  | letLoad _ _ _ _ | setByte _ _ _ | free _ _ _ | letSlice _ _ _ _ _ | letIndex _ _ _ _ _
  | setIndex _ _ _ | setIndexEval _ _ _ | setFieldEval _ _ _
  | matchArm _ _ _ _ _ _ _ _ | unreachable _ _ => intro E e _ he; simp [mstmt] at he

theorem AEnv.get?_forget (ws : List Nat) (x : Nat) : ∀ (A : AEnv),
    (A.forget ws).get? x = (A.get? x).map (fun c => if ws.contains x then .unk else c)
  | [] => rfl
  | (y, c) :: A => by
    have ih := AEnv.get?_forget ws x A
    have e1 : AEnv.forget ((y, c) :: A) ws = (if ws.contains y then (y, .unk) else (y, c)) :: AEnv.forget A ws := rfl
    have g : ∀ (z : Nat) (k : SizeCls) (A' : AEnv),
        AEnv.get? ((z, k) :: A') x = if z = x then some k else A'.get? x := by
      intro z k A'
      by_cases hz : z = x
      · subst hz
        simp [AEnv.get?]
      · have : (z == x) = false := by simpa using hz
        simp [AEnv.get?, this, hz]
    rw [e1]
    by_cases hw : ws.contains y = true
    · rw [if_pos hw, g, g]
      by_cases hy : y = x
      · subst hy
        rw [if_pos rfl, if_pos rfl]
        simp only [Option.map_some]
        rw [if_pos hw]
      · rw [if_neg hy, if_neg hy]
        exact ih
    · rw [if_neg hw, g, g]
      by_cases hy : y = x
      · subst hy
        rw [if_pos rfl, if_pos rfl]
        simp only [Option.map_some]
        rw [if_neg hw]
      · rw [if_neg hy, if_neg hy]
        exact ih

/-- Classes of locals a statement did not assign still hold after it. -/
theorem EnvOk.forget {B : Nat} {A : AEnv} {E E' : Env} {ws : List Nat} (h : EnvOk B A E)
    (hk : ∀ x, x ∉ ws → E'.get? x = E.get? x) : EnvOk B (A.forget ws) E' := by
  intro x c v ha he
  rw [AEnv.get?_forget] at ha
  by_cases hw : ws.contains x = true
  · simp only [hw, if_true, Option.map_eq_some_iff] at ha
    obtain ⟨_, _, rfl⟩ := ha
    trivial
  · simp only [hw, Bool.false_eq_true, if_false, Option.map_id'] at ha
    have hx : x ∉ ws := fun m => hw (List.contains_iff_mem.mpr m)
    rw [hk x hx] at he
    exact h x c v ha he

/-- What `after` knows holds once the statement went on, in the
environment it started in. -/
theorem after_ok' {B : Nat} {A : AEnv} {E : Env} (h : EnvOk B A E) (call : Calls) (fuel : Nat) :
    ∀ (s : SrcStmt) {E' : Env}, mstmt call fuel E s = some (.next E') → EnvOk B (A.after s) E := by
  intro s E' hs
  cases s with
  | «if» c a b =>
    simp only [AEnv.after]
    split
    · rename_i x k hg
      split
      · rename_i never
        simp only [mstmt, Option.bind_eq_some_iff] at hs
        obtain ⟨cv, ⟨w, hw, hb⟩, hs⟩ := hs
        cases cv with
        | true => exact absurd hs (neverNext_sound call fuel a E E' never)
        | false => exact h.refine (guard_ge hg hw hb)
      · exact h
    · exact h
  | nop | «let» _ _ _ _ | letStruct _ _ _ _ | letCall _ _ _ _ _ | letEnum _ _ _ _ _
  | letMatch _ _ _ _ _ _ | set _ _ | setField _ _ _ | setCall _ _ _ | «then» _ _ | «while» _ _
  | «return» _ | letAlloc _ _ _ _ | letView _ _ _ _ _ | letLoad _ _ _ _ | setByte _ _ _ | free _ _ _
  | letSlice _ _ _ _ _ | letIndex _ _ _ _ _ | setIndex _ _ _ | letEval _ _ _ _ | setEval _ _
  | ifEval _ _ _ | whileEval _ _ | returnEval _ | discard _ | setIndexEval _ _ _
  | setFieldEval _ _ _ | returnUnit | assert _ | «break» | «continue» | matchArm _ _ _ _ _ _ _ _
  | unreachable _ _ => exact h

/-- What the check knows after a statement that went on: what `after`
knows, but of the locals it may have assigned. -/
theorem after_ok {B : Nat} {A : AEnv} {E : Env} (h : EnvOk B A E) (call : Calls) (fuel : Nat)
    (s : SrcStmt) {E' : Env} (hs : mstmt call fuel E s = some (.next E')) :
    EnvOk B ((A.after s).forget s.writes) E' :=
  EnvOk.forget (after_ok' h call fuel s hs) fun x hx => mstmt_unwritten call fuel s hs E' rfl x hx

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
    have ga : Env.get? [(b, Value.unsigned .usize d), (a, Value.unsigned .usize n)] a =
        some (Value.unsigned .usize n) := by simp [Env.get?, hba]
    have gb : Env.get? [(b, Value.unsigned .usize d), (a, Value.unsigned .usize n)] b =
        some (Value.unsigned .usize d) := by simp [Env.get?]
    simp [mstmt, pexpr, Env.bindAll, ga, gb, applyOp, binary, SrcOp.toCore, usize_greater,
      hsub, Except.toOption, asBool, hgt, Out.then, outValue] at h
    subst h
    exact sizeOf_unsigned_lt hr

/-- What the classes assume of the calls: prims are the identity, and
decrements decrement. -/
structure OracleOk (prims : Prims) (T : TermInfo) (call : Calls) : Prop where
  prim : ∀ c vs v, prims.isPrim c = true → call c vs = some v → single vs = some v
  dec : ∀ c ∈ T.decs, ∀ n d v, 1 ≤ d → d ≤ n → call c [.unsigned .usize n, .unsigned .usize d] = some v →
    sizeOf v < sizeOf (Value.unsigned .usize n)
  const : ∀ c id j, T.consts.lookup c = some (id, j) → ∀ vs v, call c vs = some v →
    v = .enumeration id j []

theorem lookup_mem3 {c : Nat} {x : Nat × Nat} :
    ∀ {l : List (Nat × Nat × Nat)}, l.lookup c = some x → (c, x) ∈ l
  | [], h => by simp [List.lookup] at h
  | (k, y) :: l, h => by
    simp only [List.lookup] at h
    split at h
    · rename_i hk
      simp only [Option.some.injEq] at h
      subst h
      simp only [beq_iff_eq] at hk
      subst hk
      exact List.mem_cons_self
    · exact List.mem_cons_of_mem _ (lookup_mem3 h)

theorem const_val {sp : SrcProgram} {prims : Prims} {c id j : Nat} (hc : ConstOk sp prims c id j)
    {m : Nat} {vs : List Value} {v : Value} (h : pcall sp prims m c vs = some v) :
    v = .enumeration id j [] := by
  obtain ⟨np, f, ty, hf, hid, hbody⟩ := hc
  cases m with
  | zero => simp [pcall] at h
  | succ m =>
    simp only [pcall, np, hf, Bool.false_eq_true, ↓reduceIte] at h
    split at h
    · rw [hbody] at h
      simp [mstmt, peff, peffs, Option.bind, outValue] at h
      rw [← h, hid]
    · simp at h

theorem oracleOk_pcall {sp : SrcProgram} {prims : Prims} {T : TermInfo} (hD : ∀ c ∈ T.decs, DecOk sp prims c)
    (hC : ∀ p ∈ T.consts, ConstOk sp prims p.1 p.2.1 p.2.2)
    (m : Nat) : OracleOk prims T (pcall sp prims m) where
  prim := by
    intro c vs v hp hv
    cases m with
    | zero => simp [pcall] at hv
    | succ m => simpa [pcall, hp] using hv
  dec := fun c hc _ _ _ h1 hdn hv => dec_lt (hD c hc) h1 hdn hv
  const := fun c id j hl _ _ hv => const_val (hC _ (lookup_mem3 hl)) hv

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
              | unk | le | lt | ge _ | nil _ _ => trivial
            | unk | le | lt | lit _ | nil _ _ => trivial
          | cons _ _ => trivial
    · split
      · rename_i id j hl
        exact ho.const c id j hl vs v h
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
  | .eStride _, _, _ | .arraySlice _ _, _, _ | .eIf _ _ _ _, _, _ | .eLet _ _ _ _ _, _, _
  | .eLen _, _, _ => by
    simp only [effCls]; trivial

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

/-! ## Measures of calls -/

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
    | nil _ _ => intro h; simp [SizeCls.isLe] at h

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
    | nil _ _ => intro h; simp [SizeCls.isLt] at h

end

/-! ## Every call settles -/

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

/-- **Pure calls settle.** A call has a fuel past which `pcall` gives one
answer: more fuel keeps a value (`pcall_mono`). -/
theorem pcall_settles (sp : SrcProgram) (prims : Prims) (c : Nat) (vs : List Value) : Settles sp prims c vs := by
  by_cases h : ∃ n w, pcall sp prims n c vs = some w
  · obtain ⟨n, w, hw⟩ := h
    exact ⟨n, fun m hm => by rw [hw]; exact pcall_mono sp prims n hw hm⟩
  · have hn : ∀ m, pcall sp prims m c vs = none := fun m => by
      cases e : pcall sp prims m c vs with
      | none => rfl
      | some w => exact absurd ⟨m, w, e⟩ h
    exact ⟨0, fun m _ => by rw [hn m, hn 0]⟩

/-- Under `TermOk`, a call of an annotated function settles; `pcall_settles`
needs no annotation. -/
theorem pcall_complete {sp : SrcProgram} {prims : Prims} {T : TermInfo} (_hT : TermOk sp prims T) :
    ∀ c a, T.ann c = some a → ∀ vs, Settles sp prims c vs :=
  fun c _ _ vs => pcall_settles sp prims c vs

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

def AllConsts (sp : SrcProgram) (prims : Prims) : List (Nat × Nat × Nat) → Prop
  | [] => True
  | p :: ps => ConstOk sp prims p.1 p.2.1 p.2.2 ∧ AllConsts sp prims ps

theorem AllConsts.mem {sp : SrcProgram} {prims : Prims} :
    ∀ {l : List (Nat × Nat × Nat)}, AllConsts sp prims l → ∀ p ∈ l, ConstOk sp prims p.1 p.2.1 p.2.2
  | [], _, p, hp => by simp at hp
  | _ :: _, ⟨hq, h⟩, p, hp => by
    rcases List.mem_cons.mp hp with rfl | hp
    · exact hq
    · exact AllConsts.mem h p hp

theorem constOk_of {sp : SrcProgram} {prims : Prims} {c id : Nat} {f : SrcFunc} {ty : SrcType} (j : Nat)
    (np : prims.isPrim c = false) (hf : sp.funcs[c]? = some f)
    (hbody : f.body = .returnEval (.eVariant ty j [])) (hid : ty.typeId = id) : ConstOk sp prims c id j :=
  ⟨np, f, ty, hf, hid, hbody⟩

theorem termOk_of {sp : SrcProgram} {prims : Prims} {T : TermInfo} {l : List (Nat × TermAnn)}
    (hd : AllDecs sp prims T.decs) (hk : AllConsts sp prims T.consts) (he : T.anns = l)
    (hf : AllFns sp prims T l) : TermOk sp prims T :=
  ⟨hd.mem, hk.mem, he ▸ hf.mem⟩

end Lanius.Faithful.Termination
