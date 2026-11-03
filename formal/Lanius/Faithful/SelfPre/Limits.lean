import Lanius.Faithful.SelfPre.TS
import Lanius.Mini.Frontend
import Lanius.Mini.Compiler

/-! # The front end's implementation limits (F14)

`untypedRejected` rejects a program unless `limFuncs` accepts it: every type
in it has at most `weightLimit` slots and every function's lets need at most
`depthLimit` (`2 ^ 40`) slots along a scope (SEMANTIC_DECISIONS "The front
end's implementation limits"). `limSlots t` is at least `t`'s slot count and
at most the limit, and so is every type inside `t`; `limStmt s` is at least
`s`'s depth. So what the front end returns has `ts` at most `weightLimit` and
each function's `SrcStmt.depth` at most `2 ^ 40` (`frontEndWords_limits`). -/

open Lanius.Mini
open Lanius.Faithful.SelfPre

namespace Lanius.Faithful.SelfPre.Limits

theorem weightSum_some {x y z : Nat} (h : weightSum x y = some z) : z = x + y ∧ z ≤ weightLimit := by
  unfold weightSum at h
  split at h
  · cases h
  · rename_i hc
    cases h
    simp only [Bool.or_eq_true, decide_eq_true_eq, not_or, Nat.not_lt] at hc
    omega

theorem weightAddTo_some {x z : Nat} {b : Option Nat} (h : weightAddTo x b = some z) :
    ∃ y, b = some y ∧ z = x + y ∧ z ≤ weightLimit := by
  cases b with
  | none => simp [weightAddTo] at h
  | some y => exact ⟨y, rfl, weightSum_some h⟩

theorem weightAdd_some {z : Nat} {a b : Option Nat} (h : weightAdd a b = some z) :
    ∃ x y, a = some x ∧ b = some y ∧ z = x + y ∧ z ≤ weightLimit := by
  cases a with
  | none => simp [weightAdd] at h
  | some x =>
    obtain ⟨y, rfl, e, le⟩ := weightAddTo_some h
    exact ⟨x, y, rfl, rfl, e, le⟩

theorem weightArray_some {n z : Nat} {o : Option Nat} (h : weightArray n o = some z) :
    ∃ x, o = some x ∧ 1 ≤ z ∧ n * x ≤ z ∧ z ≤ weightLimit := by
  cases o with
  | none => simp [weightArray] at h
  | some x =>
    refine ⟨x, rfl, ?_⟩
    simp only [weightArray, weightTimes] at h
    split at h
    · cases h
    · obtain ⟨e, le⟩ := weightSum_some h
      have : n * x ≤ max n 1 * x := Nat.mul_le_mul_right x (Nat.le_max_left n 1)
      omega

theorem depthSum_some {x y z : Nat} (h : depthSum x y = some z) : z = x + y ∧ z ≤ 2 ^ 40 := by
  unfold depthSum at h
  by_cases h1 : depthLimit < x
  · simp [h1] at h
  · by_cases h2 : depthLimit - x < y
    · simp [h2] at h
    · simp only [h1, h2, decide_false, Bool.or_false, Bool.false_eq_true, if_false, Option.some.injEq] at h
      subst h
      simp only [depthLimit] at h1 h2
      omega

/-! ## Types -/

mutual
theorem limSlots_ok : ∀ (t : SrcType) {w : Nat}, limSlots t = some w →
    1 ≤ w ∧ SrcType.size t ≤ w ∧ w ≤ weightLimit ∧ tySlots t ≤ weightLimit
  | .i32, _, h => by simp only [limSlots, Option.some.injEq] at h; subst h; simp [SrcType.size, tySlots, weightLimit]
  | .bool, _, h => by simp only [limSlots, Option.some.injEq] at h; subst h; simp [SrcType.size, tySlots, weightLimit]
  | .uint _, _, h => by simp only [limSlots, Option.some.injEq] at h; subst h; simp [SrcType.size, tySlots, weightLimit]
  | .ptr, _, h => by simp only [limSlots, Option.some.injEq] at h; subst h; simp [SrcType.size, tySlots, weightLimit]
  | .unit, _, h => by simp only [limSlots, Option.some.injEq] at h; subst h; simp [SrcType.size, tySlots, weightLimit]
  | .isize, _, h => by simp only [limSlots, Option.some.injEq] at h; subst h; simp [SrcType.size, tySlots, weightLimit]
  | .char, _, h => by simp only [limSlots, Option.some.injEq] at h; subst h; simp [SrcType.size, tySlots, weightLimit]
  | .float _, _, h => by simp only [limSlots, Option.some.injEq] at h; subst h; simp [SrcType.size, tySlots, weightLimit]
  | .sint _, _, h => by simp only [limSlots, Option.some.injEq] at h; subst h; simp [SrcType.size, tySlots, weightLimit]
  | .str, _, h => by simp only [limSlots, Option.some.injEq] at h; subst h; simp [SrcType.size, tySlots, weightLimit]
  | .view n, _, h => by
    simp only [limSlots] at h
    obtain ⟨rfl, le⟩ := weightSum_some h
    simp only [SrcType.size, tySlots]
    omega
  | .struct id fields, w, h => by
    have ih := @limSlotsList_ok fields
    simp only [limSlots] at h
    obtain ⟨y, hy, rfl, le⟩ := weightAddTo_some h
    obtain ⟨a, b, c⟩ := ih hy
    simp only [SrcType.size, tySlots]
    omega
  | .enum id variants, w, h => by
    have ih := @limSlotsVariants_ok variants
    simp only [limSlots] at h
    obtain ⟨y, hy, rfl, le⟩ := weightAddTo_some h
    obtain ⟨a, b, c⟩ := ih hy
    simp only [SrcType.size, tySlots]
    omega
  | .slice e, w, h => by
    have ih := @limSlots_ok e
    simp only [limSlots] at h
    obtain ⟨y, hy, rfl, le⟩ := weightAddTo_some h
    obtain ⟨a, b, c, d⟩ := ih hy
    simp only [SrcType.size, tySlots]
    omega
  | .ref e, w, h => by
    have ih := @limSlots_ok e
    simp only [limSlots] at h
    obtain ⟨y, hy, rfl, le⟩ := weightAddTo_some h
    obtain ⟨a, b, c, d⟩ := ih hy
    simp only [SrcType.size, tySlots]
    omega
  | .array e n, w, h => by
    have ih := @limSlots_ok e
    simp only [limSlots] at h
    obtain ⟨y, hy, one, mul, le⟩ := weightArray_some h
    obtain ⟨a, b, c, d⟩ := ih hy
    have : n * SrcType.size e ≤ n * y := Nat.mul_le_mul_left n b
    simp only [SrcType.size, tySlots]
    omega
termination_by structural t => t

theorem limSlotsList_ok : ∀ (ts : List SrcType) {w : Nat}, limSlotsList ts = some w →
    sizes ts ≤ w ∧ w ≤ weightLimit ∧ tySlotsList ts ≤ weightLimit
  | [], _, h => by
    simp only [limSlotsList, Option.some.injEq] at h
    subst h
    simp [sizes, tySlotsList, weightLimit]
  | t :: rest, w, h => by
    have ih1 := @limSlots_ok t
    have ih2 := @limSlotsList_ok rest
    simp only [limSlotsList] at h
    obtain ⟨x, y, hx, hy, rfl, le⟩ := weightAdd_some h
    obtain ⟨a, b, c, d⟩ := ih1 hx
    obtain ⟨e, f, g⟩ := ih2 hy
    simp only [sizes, tySlotsList]
    omega
termination_by structural ts => ts

theorem limSlotsVariants_ok : ∀ (vs : List (List SrcType)) {w : Nat}, limSlotsVariants vs = some w →
    maxSize vs ≤ w ∧ w ≤ weightLimit ∧ tySlotsVariants vs ≤ weightLimit
  | [], _, h => by
    simp only [limSlotsVariants, Option.some.injEq] at h
    subst h
    simp [maxSize, tySlotsVariants, weightLimit]
  | v :: rest, w, h => by
    have ih1 := @limSlotsList_ok v
    have ih2 := @limSlotsVariants_ok rest
    simp only [limSlotsVariants] at h
    obtain ⟨x, y, hx, hy, rfl, le⟩ := weightAdd_some h
    obtain ⟨a, b, c⟩ := ih1 hx
    obtain ⟨e, f, g⟩ := ih2 hy
    simp only [maxSize, tySlotsVariants]
    omega
termination_by structural vs => vs
end

theorem limTy_ok {t : SrcType} (h : limTy t = true) : ts t ≤ weightLimit := by
  simp only [limTy, Bool.not_eq_true'] at h
  cases hs : limSlots t with
  | none => rw [hs] at h; simp [isNoneWeight] at h
  | some w => exact (limSlots_ok t hs).2.2.2

/-! ## Expressions -/

theorem limExpr_ok : ∀ (e : SrcExpr), limExpr e = true → ts e ≤ weightLimit
  | .int _, _ => by simp
  | .boolean _, _ => by simp
  | .unsigned _ _, _ => by simp
  | .local _, _ => by simp
  | .field _ _, _ => by simp
  | .null, _ => by simp
  | .char _, _ => by simp
  | .float _ _, _ => by simp
  | .negate x, h => by
    have := limExpr_ok x (by simpa [limExpr] using h)
    simpa using this
  | .not x, h => by
    have := limExpr_ok x (by simpa [limExpr] using h)
    simpa using this
  | .apply _ a b, h => by
    simp only [limExpr, Bool.and_eq_true] at h
    have := limExpr_ok a h.1
    have := limExpr_ok b h.2
    simp only [ts_SrcExpr_apply]
    omega
  | .cast t x, h => by
    simp only [limExpr, Bool.and_eq_true] at h
    have := limTy_ok h.1
    have := limExpr_ok x h.2
    simp only [ts_SrcExpr_cast]
    omega

theorem limExprs_ok : ∀ (es : List SrcExpr), limExprs es = true → ts es ≤ weightLimit
  | [], _ => by simp
  | e :: rest, h => by
    simp only [limExprs, Bool.and_eq_true] at h
    have := limExpr_ok e h.1
    have := limExprs_ok rest h.2
    simp only [ts_cons]
    omega

theorem limArms_ok : ∀ (arms : List SrcArm), limArms arms = true → ts arms ≤ weightLimit
  | [], _ => by simp
  | ⟨bs, v⟩ :: rest, h => by
    simp only [limArms, Bool.and_eq_true] at h
    have := limExpr_ok v h.1
    have := limArms_ok rest h.2
    simp only [ts_cons, ts_SrcArm_mk]
    omega

mutual
theorem limEff_ok : ∀ (x : SrcEff), limEff x = true → ts x ≤ weightLimit
  | .ePure e, h => by
    have := limExpr_ok e (by simpa [limEff] using h)
    simpa using this
  | .eCall _ args, h => by
    have ih := limEffs_ok args
    have := ih (by simpa [limEff] using h)
    simpa using this
  | .eApply _ a b, h => by
    have iha := limEff_ok a
    have ihb := limEff_ok b
    simp only [limEff, Bool.and_eq_true] at h
    have := iha h.1
    have := ihb h.2
    simp only [ts_SrcEff_eApply]
    omega
  | .eNeg a, h => by
    have ih := limEff_ok a
    have := ih (by simpa [limEff] using h)
    simpa using this
  | .eNot a, h => by
    have ih := limEff_ok a
    have := ih (by simpa [limEff] using h)
    simpa using this
  | .eCast t a, h => by
    have ih := limEff_ok a
    simp only [limEff, Bool.and_eq_true] at h
    have := limTy_ok h.1
    have := ih h.2
    simp only [ts_SrcEff_eCast]
    omega
  | .eIndex _ i, h => by
    have ih := limEff_ok i
    have := ih (by simpa [limEff] using h)
    simpa using this
  | .eStruct t fs, h => by
    have ih := limEffs_ok fs
    simp only [limEff, Bool.and_eq_true] at h
    have := limTy_ok h.1
    have := ih h.2
    simp only [ts_SrcEff_eStruct]
    omega
  | .eVariant t _ ps, h => by
    have ih := limEffs_ok ps
    simp only [limEff, Bool.and_eq_true] at h
    have := limTy_ok h.1
    have := ih h.2
    simp only [ts_SrcEff_eVariant]
    omega
  | .eMatch sc ety t _ vs, h => by
    have ih1 := limEff_ok sc
    have ih2 := limEffs_ok vs
    simp only [limEff, Bool.and_eq_true] at h
    have := ih1 h.1.1.1
    have := limTy_ok h.1.1.2
    have := limTy_ok h.1.2
    have := ih2 h.2
    simp only [ts_SrcEff_eMatch]
    omega
  | .eDivide _ a b, h => by
    have iha := limEff_ok a
    have ihb := limEff_ok b
    simp only [limEff, Bool.and_eq_true] at h
    have := iha h.1
    have := ihb h.2
    simp only [ts_SrcEff_eDivide]
    omega
  | .eStride _, _ => by simp
  | .arraySlice t _, h => by
    have := limTy_ok (by simpa [limEff] using h)
    simpa using this
  | .eIf c t a b, h => by
    have ih1 := limEff_ok c
    have ih2 := limEff_ok a
    have ih3 := limEff_ok b
    simp only [limEff, Bool.and_eq_true] at h
    have := ih1 h.1.1.1
    have := limTy_ok h.1.1.2
    have := ih2 h.1.2
    have := ih3 h.2
    simp only [ts_SrcEff_eIf]
    omega
  | .eLet _ t v rt b, h => by
    have ih1 := limEff_ok v
    have ih2 := limEff_ok b
    simp only [limEff, Bool.and_eq_true] at h
    have := limTy_ok h.1.1.1
    have := ih1 h.1.1.2
    have := limTy_ok h.1.2
    have := ih2 h.2
    simp only [ts_SrcEff_eLet]
    omega
  | .eLen _, _ => by simp
  | .eStr _ _, _ => by simp
termination_by structural x => x

theorem limEffs_ok : ∀ (xs : List SrcEff), limEffs xs = true → ts xs ≤ weightLimit
  | [], _ => by simp
  | x :: rest, h => by
    have ih1 := limEff_ok x
    have ih2 := limEffs_ok rest
    simp only [limEffs, Bool.and_eq_true] at h
    have := ih1 h.1
    have := ih2 h.2
    simp only [ts_cons]
    omega
termination_by structural xs => xs
end

/-! ## Statements -/

theorem limBind_some {k d : Option Nat} {ok : Bool} {z : Nat} (h : limBind k ok d = some z) :
    ok = true ∧ ∃ x y, k = some x ∧ d = some y ∧ z = y + x ∧ z ≤ 2 ^ 40 := by
  unfold limBind at h
  cases ok with
  | false => simp at h
  | true =>
    refine ⟨rfl, ?_⟩
    cases k with
    | none => simp at h
    | some x =>
      cases d with
      | none => simp at h
      | some y =>
        simp only [Bool.not_true, Bool.false_eq_true, if_false] at h
        obtain ⟨e, le⟩ := depthSum_some h
        exact ⟨x, y, rfl, rfl, e, le⟩

theorem limLeaf_some {ok : Bool} {z : Nat} (h : limLeaf ok = some z) : ok = true ∧ z = 0 := by
  unfold limLeaf at h
  cases ok with
  | false => simp at h
  | true => simp only [if_true, Option.some.injEq] at h; exact ⟨rfl, h.symm⟩

theorem limGuard_some {ok : Bool} {d : Option Nat} {z : Nat} (h : limGuard ok d = some z) :
    ok = true ∧ d = some z := by
  unfold limGuard at h
  cases ok with
  | false => simp at h
  | true => simp only [if_true] at h; exact ⟨rfl, h⟩

theorem limMax_some {a b : Option Nat} {z : Nat} (h : limMax a b = some z) :
    ∃ x y, a = some x ∧ b = some y ∧ z = max x y := by
  cases a with
  | none => simp [limMax] at h
  | some x =>
    cases b with
    | none => simp [limMax] at h
    | some y =>
      simp only [limMax, Option.some.injEq] at h
      exact ⟨x, y, rfl, rfl, h.symm⟩

theorem limConst_some {t : Option Nat} {n z : Nat} (h : limConst t n = some z) : (∃ x, t = some x) ∧ z = n := by
  cases t with
  | none => simp [limConst] at h
  | some x => simp only [limConst, Option.some.injEq] at h; exact ⟨⟨x, rfl⟩, h.symm⟩

/-- A binding of type `ty` in front of a body. -/
theorem bind_ty {ty : SrcType} {ok : Bool} {d : Option Nat} {z : Nat} (h : limBind (limSlots ty) ok d = some z) :
    ok = true ∧ ∃ y, d = some y ∧ y + SrcType.size ty ≤ z ∧ z ≤ 2 ^ 40 ∧ ts ty ≤ weightLimit := by
  obtain ⟨ok, x, y, hx, hy, rfl, le⟩ := limBind_some h
  obtain ⟨-, a, -, c⟩ := limSlots_ok ty hx
  exact ⟨ok, y, hy, by omega, le, c⟩

theorem limStmt_ok : ∀ (s : SrcStmt) {d : Nat}, limStmt s = some d →
    SrcStmt.depth s ≤ d ∧ d ≤ 2 ^ 40 ∧ ts s ≤ weightLimit
  | .nop, _, h => by simp only [limStmt, Option.some.injEq] at h; subst h; simp [SrcStmt.depth]
  | .returnUnit, _, h => by simp only [limStmt, Option.some.injEq] at h; subst h; simp [SrcStmt.depth]
  | .break, _, h => by simp only [limStmt, Option.some.injEq] at h; subst h; simp [SrcStmt.depth]
  | .continue, _, h => by simp only [limStmt, Option.some.injEq] at h; subst h; simp [SrcStmt.depth]
  | .let _ ty e body, d, h => by
    have ih := @limStmt_ok body
    simp only [limStmt] at h
    obtain ⟨ok, y, hy, a, b, c⟩ := bind_ty h
    obtain ⟨e1, e2, e3⟩ := ih hy
    have := limExpr_ok e ok
    simp only [SrcStmt.depth, ts_SrcStmt_let]
    omega
  | .letStruct _ ty es body, d, h => by
    have ih := @limStmt_ok body
    simp only [limStmt] at h
    obtain ⟨ok, y, hy, a, b, c⟩ := bind_ty h
    obtain ⟨e1, e2, e3⟩ := ih hy
    have := limExprs_ok es ok
    simp only [SrcStmt.depth, ts_SrcStmt_letStruct]
    omega
  | .letCall _ ty _ es body, d, h => by
    have ih := @limStmt_ok body
    simp only [limStmt] at h
    obtain ⟨ok, y, hy, a, b, c⟩ := bind_ty h
    obtain ⟨e1, e2, e3⟩ := ih hy
    have := limExprs_ok es ok
    simp only [SrcStmt.depth, ts_SrcStmt_letCall]
    omega
  | .letEnum _ ty _ es body, d, h => by
    have ih := @limStmt_ok body
    simp only [limStmt] at h
    obtain ⟨ok, y, hy, a, b, c⟩ := bind_ty h
    obtain ⟨e1, e2, e3⟩ := ih hy
    have := limExprs_ok es ok
    simp only [SrcStmt.depth, ts_SrcStmt_letEnum]
    omega
  | .letMatch _ ty _ _ arms body, d, h => by
    have ih := @limStmt_ok body
    simp only [limStmt] at h
    obtain ⟨ok, y, hy, a, b, c⟩ := bind_ty h
    obtain ⟨e1, e2, e3⟩ := ih hy
    have := limArms_ok arms ok
    simp only [SrcStmt.depth, ts_SrcStmt_letMatch]
    omega
  | .letIndex _ ty _ i body, d, h => by
    have ih := @limStmt_ok body
    simp only [limStmt] at h
    obtain ⟨ok, y, hy, a, b, c⟩ := bind_ty h
    obtain ⟨e1, e2, e3⟩ := ih hy
    have := limExpr_ok i ok
    simp only [SrcStmt.depth, ts_SrcStmt_letIndex]
    omega
  | .letEval _ ty x body, d, h => by
    have ih := @limStmt_ok body
    simp only [limStmt] at h
    obtain ⟨ok, y, hy, a, b, c⟩ := bind_ty h
    obtain ⟨e1, e2, e3⟩ := ih hy
    have := limEff_ok x ok
    simp only [SrcStmt.depth, ts_SrcStmt_letEval]
    omega
  | .letAlloc _ size _ body, d, h => by
    have ih := @limStmt_ok body
    simp only [limStmt] at h
    obtain ⟨ok, x, y, hx, hy, rfl, le⟩ := limBind_some h
    simp only [limOne, Option.some.injEq] at hx
    subst hx
    obtain ⟨e1, e2, e3⟩ := ih hy
    have := limExpr_ok size ok
    simp only [SrcStmt.depth, ts_SrcStmt_letAlloc]
    omega
  | .letLoad _ p o body, d, h => by
    have ih := @limStmt_ok body
    simp only [limStmt] at h
    obtain ⟨ok, x, y, hx, hy, rfl, le⟩ := limBind_some h
    simp only [limOne, Option.some.injEq] at hx
    subst hx
    obtain ⟨e1, e2, e3⟩ := ih hy
    simp only [Bool.and_eq_true] at ok
    have := limExpr_ok p ok.1
    have := limExpr_ok o ok.2
    simp only [SrcStmt.depth, ts_SrcStmt_letLoad]
    omega
  | .letStr _ _ body, d, h => by
    have ih := @limStmt_ok body
    simp only [limStmt] at h
    obtain ⟨-, x, y, hx, hy, rfl, le⟩ := limBind_some h
    simp only [limOne, Option.some.injEq] at hx
    subst hx
    obtain ⟨e1, e2, e3⟩ := ih hy
    simp only [SrcStmt.depth, ts_SrcStmt_letStr]
    omega
  | .letSlice _ el p n body, d, h => by
    have ih := @limStmt_ok body
    simp only [limStmt] at h
    obtain ⟨ok, x, y, hx, hy, rfl, le⟩ := limBind_some h
    obtain ⟨⟨w, hw⟩, rfl⟩ := limConst_some hx
    obtain ⟨e1, e2, e3⟩ := ih hy
    have : ts el ≤ weightLimit := (limSlots_ok el hw).2.2.2
    simp only [Bool.and_eq_true] at ok
    have := limExpr_ok p ok.1
    have := limExpr_ok n ok.2
    simp only [SrcStmt.depth, ts_SrcStmt_letSlice]
    omega
  | .letView _ n es _ body, d, h => by
    have ih := @limStmt_ok body
    simp only [limStmt] at h
    obtain ⟨ok, x, y, hx, hy, rfl, le⟩ := limBind_some h
    obtain ⟨rfl, -⟩ := depthSum_some hx
    obtain ⟨e1, e2, e3⟩ := ih hy
    have := limExprs_ok es ok
    simp only [SrcStmt.depth, ts_SrcStmt_letView]
    omega
  | .unreachable _ ty, d, h => by
    simp only [limStmt] at h
    obtain ⟨⟨w, hw⟩, rfl⟩ := limConst_some h
    have : ts ty ≤ weightLimit := (limSlots_ok ty hw).2.2.2
    simp only [SrcStmt.depth, ts_SrcStmt_unreachable]
    omega
  | .set _ e, d, h => by
    simp only [limStmt] at h
    obtain ⟨ok, rfl⟩ := limLeaf_some h
    have := limExpr_ok e ok
    simp only [SrcStmt.depth, ts_SrcStmt_set]
    omega
  | .setField _ _ e, d, h => by
    simp only [limStmt] at h
    obtain ⟨ok, rfl⟩ := limLeaf_some h
    have := limExpr_ok e ok
    simp only [SrcStmt.depth, ts_SrcStmt_setField]
    omega
  | .setCall _ _ es, d, h => by
    simp only [limStmt] at h
    obtain ⟨ok, rfl⟩ := limLeaf_some h
    have := limExprs_ok es ok
    simp only [SrcStmt.depth, ts_SrcStmt_setCall]
    omega
  | .return e, d, h => by
    simp only [limStmt] at h
    obtain ⟨ok, rfl⟩ := limLeaf_some h
    have := limExpr_ok e ok
    simp only [SrcStmt.depth, ts_SrcStmt_return]
    omega
  | .setByte p o v, d, h => by
    simp only [limStmt] at h
    obtain ⟨ok, rfl⟩ := limLeaf_some h
    simp only [Bool.and_eq_true] at ok
    have := limExpr_ok p ok.1.1
    have := limExpr_ok o ok.1.2
    have := limExpr_ok v ok.2
    simp only [SrcStmt.depth, ts_SrcStmt_setByte]
    omega
  | .free p size _, d, h => by
    simp only [limStmt] at h
    obtain ⟨ok, rfl⟩ := limLeaf_some h
    simp only [Bool.and_eq_true] at ok
    have := limExpr_ok p ok.1
    have := limExpr_ok size ok.2
    simp only [SrcStmt.depth, ts_SrcStmt_free]
    omega
  | .setIndex _ i v, d, h => by
    simp only [limStmt] at h
    obtain ⟨ok, rfl⟩ := limLeaf_some h
    simp only [Bool.and_eq_true] at ok
    have := limExpr_ok i ok.1
    have := limExpr_ok v ok.2
    simp only [SrcStmt.depth, ts_SrcStmt_setIndex]
    omega
  | .setEval _ x, d, h => by
    simp only [limStmt] at h
    obtain ⟨ok, rfl⟩ := limLeaf_some h
    have := limEff_ok x ok
    simp only [SrcStmt.depth, ts_SrcStmt_setEval]
    omega
  | .returnEval x, d, h => by
    simp only [limStmt] at h
    obtain ⟨ok, rfl⟩ := limLeaf_some h
    have := limEff_ok x ok
    simp only [SrcStmt.depth, ts_SrcStmt_returnEval]
    omega
  | .discard x, d, h => by
    simp only [limStmt] at h
    obtain ⟨ok, rfl⟩ := limLeaf_some h
    have := limEff_ok x ok
    simp only [SrcStmt.depth, ts_SrcStmt_discard]
    omega
  | .assert x, d, h => by
    simp only [limStmt] at h
    obtain ⟨ok, rfl⟩ := limLeaf_some h
    have := limEff_ok x ok
    simp only [SrcStmt.depth, ts_SrcStmt_assert]
    omega
  | .setIndexEval _ i v, d, h => by
    simp only [limStmt] at h
    obtain ⟨ok, rfl⟩ := limLeaf_some h
    simp only [Bool.and_eq_true] at ok
    have := limEff_ok i ok.1
    have := limEff_ok v ok.2
    simp only [SrcStmt.depth, ts_SrcStmt_setIndexEval]
    omega
  | .setFieldEval _ _ x, d, h => by
    simp only [limStmt] at h
    obtain ⟨ok, rfl⟩ := limLeaf_some h
    have := limEff_ok x ok
    simp only [SrcStmt.depth, ts_SrcStmt_setFieldEval]
    omega
  | .then a b, d, h => by
    have iha := @limStmt_ok a
    have ihb := @limStmt_ok b
    simp only [limStmt] at h
    obtain ⟨x, y, hx, hy, rfl⟩ := limMax_some h
    obtain ⟨a1, a2, a3⟩ := iha hx
    obtain ⟨b1, b2, b3⟩ := ihb hy
    simp only [SrcStmt.depth, ts_SrcStmt_then]
    omega
  | .if c a b, d, h => by
    have iha := @limStmt_ok a
    have ihb := @limStmt_ok b
    simp only [limStmt] at h
    obtain ⟨ok, hm⟩ := limGuard_some h
    obtain ⟨x, y, hx, hy, rfl⟩ := limMax_some hm
    obtain ⟨a1, a2, a3⟩ := iha hx
    obtain ⟨b1, b2, b3⟩ := ihb hy
    have := limExpr_ok c ok
    simp only [SrcStmt.depth, ts_SrcStmt_if]
    omega
  | .ifEval c a b, d, h => by
    have iha := @limStmt_ok a
    have ihb := @limStmt_ok b
    simp only [limStmt] at h
    obtain ⟨ok, hm⟩ := limGuard_some h
    obtain ⟨x, y, hx, hy, rfl⟩ := limMax_some hm
    obtain ⟨a1, a2, a3⟩ := iha hx
    obtain ⟨b1, b2, b3⟩ := ihb hy
    have := limEff_ok c ok
    simp only [SrcStmt.depth, ts_SrcStmt_ifEval]
    omega
  | .while c body, d, h => by
    have ih := @limStmt_ok body
    simp only [limStmt] at h
    obtain ⟨ok, hb⟩ := limGuard_some h
    obtain ⟨b1, b2, b3⟩ := ih hb
    have := limExpr_ok c ok
    simp only [SrcStmt.depth, ts_SrcStmt_while]
    omega
  | .whileEval c body, d, h => by
    have ih := @limStmt_ok body
    simp only [limStmt] at h
    obtain ⟨ok, hb⟩ := limGuard_some h
    obtain ⟨b1, b2, b3⟩ := ih hb
    have := limEff_ok c ok
    simp only [SrcStmt.depth, ts_SrcStmt_whileEval]
    omega
  | .matchArm _ _ _ _ _ ty body rest, d, h => by
    have ih1 := @limStmt_ok body
    have ih2 := @limStmt_ok rest
    simp only [limStmt] at h
    obtain ⟨x, y, hx, hy, rfl⟩ := limMax_some h
    obtain ⟨-, z, hz, a, b, c⟩ := bind_ty hx
    obtain ⟨a1, a2, a3⟩ := ih1 hz
    obtain ⟨b1, b2, b3⟩ := ih2 hy
    simp only [SrcStmt.depth, ts_SrcStmt_matchArm]
    omega

theorem limParams_ok : ∀ (ps : List SrcParam), limParams ps = true → ts ps ≤ weightLimit
  | [], _ => by simp
  | ⟨_, ty⟩ :: rest, h => by
    simp only [limParams, Bool.and_eq_true] at h
    have := limTy_ok h.1
    have := limParams_ok rest h.2
    simp only [ts_cons, ts_SrcParam_mk]
    omega

theorem limParamSlots_ok : ∀ (ps : List SrcParam) {d : Nat}, limParamSlots ps = some d →
    paramsSize ps ≤ d ∧ d ≤ 2 ^ 40
  | [], _, h => by
    simp only [limParamSlots, Option.some.injEq] at h
    subst h
    simp [paramsSize]
  | ⟨_, ty⟩ :: rest, d, h => by
    have ih := @limParamSlots_ok rest
    simp only [limParamSlots] at h
    obtain ⟨-, y, hy, a, b, -⟩ := bind_ty h
    obtain ⟨e1, e2⟩ := ih hy
    simp only [paramsSize]
    omega

theorem limFuncs_ok : ∀ (fs : List SrcFunc), limFuncs fs = true →
    ts fs ≤ weightLimit ∧ ∀ f ∈ fs, SrcStmt.depth f.body ≤ 2 ^ 40 ∧ paramsSize f.params ≤ 2 ^ 40
  | [], _ => by simp
  | ⟨ps, ret, body⟩ :: rest, h => by
    simp only [limFuncs, Bool.and_eq_true, Bool.not_eq_true'] at h
    obtain ⟨⟨⟨⟨hp, hps⟩, hr⟩, hb⟩, hrest⟩ := h
    cases hs : limStmt body with
    | none => rw [hs] at hb; simp [isNoneWeight] at hb
    | some d =>
      cases hq : limParamSlots ps with
      | none => rw [hq] at hps; simp [isNoneWeight] at hps
      | some q =>
        obtain ⟨d1, d2, d3⟩ := limStmt_ok body hs
        obtain ⟨q1, q2⟩ := limParamSlots_ok ps hq
        obtain ⟨r1, r2⟩ := limFuncs_ok rest hrest
        have := limParams_ok ps hp
        have := limTy_ok hr
        refine ⟨?_, fun f mem => ?_⟩
        · simp only [ts_cons, ts_SrcFunc_mk]
          omega
        · rcases List.mem_cons.mp mem with rfl | mem
          · exact ⟨Nat.le_trans d1 d2, Nat.le_trans q1 q2⟩
          · exact r2 f mem

/-! ## The front end -/

theorem untypedRejected_some {fs : List SrcFunc} {p : SrcProgram} (h : untypedRejected fs = some p) :
    limFuncs p.funcs = true ∧ ts p = ts p.funcs := by
  unfold untypedRejected at h
  split at h
  · cases h
  · rename_i hc
    simp only [Bool.or_eq_true, Bool.not_eq_true', not_or, Bool.not_eq_false] at hc
    cases h
    exact ⟨by simpa [placedProgram] using hc.2, by simp [placedProgram]⟩

theorem buildFiles_limits {fuel : Nat} {roots : List CTree} {p : SrcProgram} (h : buildFiles fuel roots = some p) :
    limFuncs p.funcs = true ∧ ts p = ts p.funcs := by
  unfold buildFiles at h
  split at h
  · cases h
  · split at h
    · cases h
    · unfold buildCollected at h
      split at h
      · cases h
      · unfold buildChecked at h
        split at h
        · unfold buildMono at h
          split at h
          · cases h
          · unfold buildClosed at h
            split at h
            · cases h
            · split at h
              · cases h
              · exact untypedRejected_some h
        · cases h

/-- What the front end returns is within the limits: its types' slots, each
function's lets' slots along a scope and each function's parameters' slots. -/
theorem frontEndWords_limits {g : List Rule} {W : List (BitVec 32)} {p : SrcProgram}
    (h : frontEndWords g W = some p) :
    ts p ≤ weightLimit ∧ ∀ f ∈ p.funcs, SrcStmt.depth f.body ≤ 2 ^ 40 ∧ paramsSize f.params ≤ 2 ^ 40 := by
  unfold frontEndWords at h
  split at h
  · cases h
  · unfold frontEndRead at h
    split at h
    · unfold frontEndFiles at h
      split at h
      · cases h
      · obtain ⟨ok, e⟩ := buildFiles_limits h
        obtain ⟨a, b⟩ := limFuncs_ok _ ok
        exact ⟨by rw [e]; exact a, b⟩
    · cases h

end Lanius.Faithful.SelfPre.Limits
