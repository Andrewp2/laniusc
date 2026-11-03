module

public import Lanius.Mini.Reading.Det.Lower
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.SrcType_same
import all Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.UintTy_isWide
import all Lanius.Mini.Compiler.P.UintTy_mask
import all Lanius.Mini.Compiler.P.arithShiftRight
import all Lanius.Mini.Compiler.P.equality
import all Lanius.Mini.Compiler.P.floatApply
import all Lanius.Mini.Compiler.P.indexOf
import all Lanius.Mini.Compiler.P.render
import all Lanius.Mini.Compiler.Types
import all Lanius.Mini.Frontend.P.collect
import all Lanius.Mini.Frontend.P.distinct
import all Lanius.Mini.Frontend.P.findConst
import all Lanius.Mini.Frontend.P.hasKids
import all Lanius.Mini.Frontend.P.isEmptyUsize
import all Lanius.Mini.Frontend.P.itemOf
import all Lanius.Mini.Frontend.P.methodDecl
import all Lanius.Mini.Frontend.P.moduleOr
import all Lanius.Mini.Frontend.P.noToken
import all Lanius.Mini.Frontend.P.noTrees
import all Lanius.Mini.Frontend.P.rootInsts
import all Lanius.Mini.Frontend.P.scalarOf
import all Lanius.Mini.Frontend.P.shrFirst
import all Lanius.Mini.Frontend.P.textSelf
import all Lanius.Mini.Frontend.P.typeDeclAt
import all Lanius.Mini.Frontend.P.typePathSpellings
import all Lanius.Mini.Frontend.P.variantIn
import all Lanius.Mini.Frontend.P.variantOfDecl
import all Lanius.Mini.Frontend.Types

@[expose] public section
/-! # The reading is deterministic, F1: pure expressions

Literals, locals, fields, casts, constants and the pure expressions
(`ExprR`). -/

namespace Lanius.Mini.Reading

open Lanius.Mini Lanius.Mini.Prod

/-- Close a goal whose hypotheses give one node two different productions,
the operator levels among them. -/
macro "expr_clash" : tactic => `(tactic| (exfalso; prods_clash [levelProds]))

theorem localOf_unique {scope : List Local} {c : CTree} {a b : Local} (h₁ : LocalOf scope c a)
    (h₂ : LocalOf scope c b) : a = b := by
  cases h₁ with
  | name e _ p n => cases h₂ with
    | name _ _ p' n' =>
      obtain ⟨_, _, _, rfl⟩ := p
      obtain ⟨_, _, _, rfl⟩ := p'
      obtain ⟨_, f⟩ := n
      obtain ⟨_, f'⟩ := n'
      exact (firstWith_unique f f').2
    | «self» e' _ => prod_clash
  | self e n => cases h₂ with
    | name e' _ _ _ => prod_clash
    | «self» _ n' =>
      obtain ⟨_, f⟩ := n
      obtain ⟨_, f'⟩ := n'
      exact (firstWith_unique f f').2

theorem fieldIndex_unique {decls : Decls} {t : Ty} {name : Name} {i j : Nat} (h₁ : FieldIndex decls t name i)
    (h₂ : FieldIndex decls t name j) : i = j := by
  obtain ⟨d, args, td, rfl, e, f⟩ := h₁
  obtain ⟨d', args', td', e', e'', f'⟩ := h₂
  cases e'
  rw [e] at e''
  cases e''
  exact (firstWith_unique f f').1

theorem member_unique {env : FrontEnv} {scope : List Local} {primary tail : CTree} {a b : SrcExpr}
    (h₁ : Member env scope primary tail a) (h₂ : Member env scope primary tail b) : a = b := by
  obtain ⟨_, _, l, j, lo, fi, rfl⟩ := h₁
  obtain ⟨_, _, l', j', lo', fi', rfl⟩ := h₂
  have el := localOf_unique lo lo'
  subst el
  rw [fieldIndex_unique fi fi']

theorem scalarTy_unique {t : Ty} {a b : SrcType} (h₁ : ScalarTy t a) (h₂ : ScalarTy t b) : a = b := by
  cases h₁ <;> cases h₂ <;> rfl

theorem namedScalar_unique {env : FrontEnv} {n : Name} {a b : SrcType} (h₁ : NamedScalar env n a)
    (h₂ : NamedScalar env n b) : a = b := by
  cases h₁ with
  | param p s => cases h₂ with
    | param p' s' =>
      rw [paramTy_unique p p'] at s
      exact scalarTy_unique s s'
    | prim no _ _ => exact (paramTy_noParam p no).elim
    | alias no _ _ _ => exact (paramTy_noParam p no).elim
  | prim no l s => cases h₂ with
    | param p' _ => exact (paramTy_noParam p' no).elim
    | prim _ l' s' =>
      rw [l] at l'
      cases l'
      exact scalarTy_unique s s'
    | alias _ l' _ _ => rw [l] at l'; cases l'
  | alias no l al s => cases h₂ with
    | param p' _ => exact (paramTy_noParam p' no).elim
    | prim _ l' _ => rw [l] at l'; cases l'
    | alias _ _ al' s' =>
      rw [aliasTy_unique al al'] at s
      exact scalarTy_unique s s'

theorem castType_unique {env : FrontEnv} {t : CTree} {a b : SrcType} (h₁ : CastType env t a)
    (h₂ : CastType env t b) : a = b :=
  namedScalar_unique h₁.2.2.2.2 h₂.2.2.2.2

theorem casts_unique {env : FrontEnv} : ∀ {acc : SrcExpr} {tail : CTree} {a b : SrcExpr},
    Casts env acc tail a → Casts env acc tail b → a = b
  | _, _, _, _, .done _, .done _ => rfl
  | _, _, _, _, .done e, .step e' .. => absurd e e'
  | _, _, _, _, .step e' .., .done e => absurd e e'
  | _, _, _, _, .step _ c r, .step _ c' r' => by
    have e := castType_unique c c'
    subst e
    exact casts_unique r r'

theorem intLiteral_unique {text : List Nat} {a b : SrcExpr} (h₁ : IntLiteral text a) (h₂ : IntLiteral text b) :
    a = b := by
  cases h₁ with
  | small v lt => cases h₂ with
    | small v' => obtain rfl := Option.some.inj (v.symm.trans v'); rfl
    | wide v' ge _ => obtain rfl := Option.some.inj (v.symm.trans v'); omega
  | wide v ge _ => cases h₂ with
    | small v' lt => obtain rfl := Option.some.inj (v.symm.trans v'); omega
    | wide v' => obtain rfl := Option.some.inj (v.symm.trans v'); rfl

/-- Reads back `utf8Encode`. -/
def utf8Decode (l : List Nat) : Nat :=
  let x := fun i => l.getD i 0 - 128
  if l.length = 1 then l.getD 0 0
  else if l.length = 2 then (l.getD 0 0 - 192) * 64 + x 1
  else if l.length = 3 then ((l.getD 0 0 - 224) * 64 + x 1) * 64 + x 2
  else (((l.getD 0 0 - 240) * 64 + x 1) * 64 + x 2) * 64 + x 3

theorem utf8Decode_encode {c : Nat} (h : c < 1114112) : utf8Decode (utf8Encode c) = c := by
  by_cases h1 : c < 128
  · rw [utf8Encode, if_pos h1]; simp [utf8Decode]
  by_cases h2 : c < 2048
  · rw [utf8Encode, if_neg h1, if_pos h2]; simp only [utf8Decode, List.length, List.getD_cons_zero, List.getD_cons_succ, Nat.zero_add, Nat.reduceAdd, Nat.reduceEqDiff, if_true, if_false]; omega
  by_cases h3 : c < 65536
  · rw [utf8Encode, if_neg h1, if_neg h2, if_pos h3]; simp only [utf8Decode, List.length, List.getD_cons_zero, List.getD_cons_succ, Nat.zero_add, Nat.reduceAdd, Nat.reduceEqDiff, if_true, if_false]; omega
  · rw [utf8Encode, if_neg h1, if_neg h2, if_neg h3]; simp only [utf8Decode, List.length, List.getD_cons_zero, List.getD_cons_succ, Nat.zero_add, Nat.reduceAdd, Nat.reduceEqDiff, if_true, if_false]; omega

theorem utf8Encode_not_escape {c e : Nat} (h : utf8Encode c ++ [39] = [92, e, 39]) : False := by
  by_cases h1 : c < 128
  · rw [utf8Encode, if_pos h1] at h; simp at h
  by_cases h2 : c < 2048
  · rw [utf8Encode, if_neg h1, if_pos h2] at h; simp only [List.cons_append, List.cons.injEq] at h; omega
  by_cases h3 : c < 65536
  · rw [utf8Encode, if_neg h1, if_neg h2, if_pos h3] at h; simp at h
  · rw [utf8Encode, if_neg h1, if_neg h2, if_neg h3] at h; simp at h

theorem escape_unique {e a b : Nat} (h₁ : Escape e a) (h₂ : Escape e b) : a = b := by
  cases h₁ <;> cases h₂ <;> rfl

theorem charLiteral_cases {text : List Nat} {n : Nat} (h : CharLiteral text n) :
    (text = 39 :: utf8Encode n ++ [39] ∧ n < 1114112) ∨ ∃ e, text = [39, 92, e, 39] ∧ Escape e n := by
  cases h with
  | plain s _ _ _ => exact .inl ⟨rfl, s.1⟩
  | escape e => exact .inr ⟨_, rfl, e⟩

theorem charLiteral_unique {text : List Nat} {a b : Nat} (h₁ : CharLiteral text a) (h₂ : CharLiteral text b) :
    a = b := by
  rcases charLiteral_cases h₁ with ⟨ta, sa⟩ | ⟨e, ta, ea⟩ <;>
    rcases charLiteral_cases h₂ with ⟨tb, sb⟩ | ⟨e', tb, eb⟩ <;> rw [ta] at tb
  · simp only [List.cons.injEq, List.append_cancel_right_eq, true_and] at tb
    rw [← utf8Decode_encode sa, ← utf8Decode_encode sb, tb]
  · simp only [List.cons_append, List.cons.injEq, true_and] at tb
    exact (utf8Encode_not_escape tb).elim
  · simp only [List.cons_append, List.cons.injEq, true_and] at tb
    exact (utf8Encode_not_escape tb.symm).elim
  · simp only [List.cons.injEq, true_and, and_true] at tb
    subst tb
    exact escape_unique ea eb

theorem typedLiteral_unique {t : Ty} {v a b : SrcExpr} (h₁ : TypedLiteral t v a) (h₂ : TypedLiteral t v b) :
    a = b := by
  cases h₁ <;> cases h₂ <;> rfl

theorem wideOf_unique {t : Ty} {negative : Bool} {n : Nat} {a b : SrcExpr} (h₁ : WideOf t negative n a)
    (h₂ : WideOf t negative n b) : a = b := by
  cases h₁ <;> cases h₂ <;> rfl

theorem wideConst_unique {t : Ty} {toks : List Token} {a b : SrcExpr} (h₁ : WideConst t toks a)
    (h₂ : WideConst t toks b) : a = b := by
  cases h₁ with
  | pos v _ w => cases h₂ with
    | pos v' _ w' => obtain rfl := Option.some.inj (v.symm.trans v'); exact wideOf_unique w w'
  | neg _ v _ w => cases h₂ with
    | «neg» _ v' _ w' => obtain rfl := Option.some.inj (v.symm.trans v'); exact wideOf_unique w w'

/-! Two different constructors of `ExprR` at one node: their productions clash. -/

theorem clash_wrap_assign {c : CTree} (a0 : nodeProd c = pExpr ∨ nodeProd c = pBase) (b0 : nodeProd c = pAssign) : False := by
  simp only [pAssign, pBase, pExpr] at *; omega
theorem clash_wrap_level {c : CTree} (a0 : nodeProd c = pExpr ∨ nodeProd c = pBase) (b0 : nodeProd c ∈ levelProds) : False := by
  simp only [levelProds, List.mem_cons, List.not_mem_nil, or_false, pOrexpr, pAndexpr, pBitOr, pBitXor, pBitAnd, pEquality, pCompare, pShift, pAdd, pMul, pBase, pExpr] at *; omega
theorem clash_wrap_cast {c : CTree} (a0 : nodeProd c = pExpr ∨ nodeProd c = pBase) (b0 : nodeProd c = pCast) : False := by
  simp only [pBase, pCast, pExpr] at *; omega
theorem clash_wrap_neg {c : CTree} (a0 : nodeProd c = pExpr ∨ nodeProd c = pBase) (b0 : nodeProd c = pNeg) : False := by
  simp only [pBase, pExpr, pNeg] at *; omega
theorem clash_wrap_not {c : CTree} (a0 : nodeProd c = pExpr ∨ nodeProd c = pBase) (b0 : nodeProd c = pNot) : False := by
  simp only [pBase, pExpr, pNot] at *; omega
theorem clash_wrap_postfix {c : CTree} (a0 : nodeProd c = pExpr ∨ nodeProd c = pBase) (b0 : nodeProd c = pPostfix) : False := by
  simp only [pBase, pExpr, pPostfix] at *; omega
theorem clash_wrap_member {c : CTree} (a0 : nodeProd c = pExpr ∨ nodeProd c = pBase) (b0 : nodeProd c = pPostfix) : False := by
  simp only [pBase, pExpr, pPostfix] at *; omega
theorem clash_wrap_group {c : CTree} (a0 : nodeProd c = pExpr ∨ nodeProd c = pBase) (b0 : nodeProd c = pGroup) : False := by
  simp only [pBase, pExpr, pGroup] at *; omega
theorem clash_wrap_local {c : CTree} (a0 : nodeProd c = pExpr ∨ nodeProd c = pBase) (b0 : nodeProd c = pIdent) : False := by
  simp only [pBase, pExpr, pIdent] at *; omega
theorem clash_wrap_const {c : CTree} (a0 : nodeProd c = pExpr ∨ nodeProd c = pBase) (b0 : nodeProd c = pIdent) : False := by
  simp only [pBase, pExpr, pIdent] at *; omega
theorem clash_wrap_self {c : CTree} (a0 : nodeProd c = pExpr ∨ nodeProd c = pBase) (b0 : nodeProd c = pSelfValue) : False := by
  simp only [pBase, pExpr, pSelfValue] at *; omega
theorem clash_wrap_int {c : CTree} (a0 : nodeProd c = pExpr ∨ nodeProd c = pBase) (b0 : nodeProd c = pInt) : False := by
  simp only [pBase, pExpr, pInt] at *; omega
theorem clash_wrap_char {c : CTree} (a0 : nodeProd c = pExpr ∨ nodeProd c = pBase) (b0 : nodeProd c = pChar) : False := by
  simp only [pBase, pChar, pExpr] at *; omega
theorem clash_wrap_float {c : CTree} (a0 : nodeProd c = pExpr ∨ nodeProd c = pBase) (b0 : nodeProd c = pFloat) : False := by
  simp only [pBase, pExpr, pFloat] at *; omega
theorem clash_wrap_true {c : CTree} (a0 : nodeProd c = pExpr ∨ nodeProd c = pBase) (b0 : nodeProd c = pTrue) : False := by
  simp only [pBase, pExpr, pTrue] at *; omega
theorem clash_wrap_false {c : CTree} (a0 : nodeProd c = pExpr ∨ nodeProd c = pBase) (b0 : nodeProd c = pFalse) : False := by
  simp only [pBase, pExpr, pFalse] at *; omega
theorem clash_assign_level {c : CTree} (a0 : nodeProd c = pAssign) (b0 : nodeProd c ∈ levelProds) : False := by
  simp only [levelProds, List.mem_cons, List.not_mem_nil, or_false, pOrexpr, pAndexpr, pBitOr, pBitXor, pBitAnd, pEquality, pCompare, pShift, pAdd, pMul, pAssign] at *; omega
theorem clash_assign_cast {c : CTree} (a0 : nodeProd c = pAssign) (b0 : nodeProd c = pCast) : False := by
  simp only [pAssign, pCast] at *; omega
theorem clash_assign_neg {c : CTree} (a0 : nodeProd c = pAssign) (b0 : nodeProd c = pNeg) : False := by
  simp only [pAssign, pNeg] at *; omega
theorem clash_assign_not {c : CTree} (a0 : nodeProd c = pAssign) (b0 : nodeProd c = pNot) : False := by
  simp only [pAssign, pNot] at *; omega
theorem clash_assign_postfix {c : CTree} (a0 : nodeProd c = pAssign) (b0 : nodeProd c = pPostfix) : False := by
  simp only [pAssign, pPostfix] at *; omega
theorem clash_assign_member {c : CTree} (a0 : nodeProd c = pAssign) (b0 : nodeProd c = pPostfix) : False := by
  simp only [pAssign, pPostfix] at *; omega
theorem clash_assign_group {c : CTree} (a0 : nodeProd c = pAssign) (b0 : nodeProd c = pGroup) : False := by
  simp only [pAssign, pGroup] at *; omega
theorem clash_assign_local {c : CTree} (a0 : nodeProd c = pAssign) (b0 : nodeProd c = pIdent) : False := by
  simp only [pAssign, pIdent] at *; omega
theorem clash_assign_const {c : CTree} (a0 : nodeProd c = pAssign) (b0 : nodeProd c = pIdent) : False := by
  simp only [pAssign, pIdent] at *; omega
theorem clash_assign_self {c : CTree} (a0 : nodeProd c = pAssign) (b0 : nodeProd c = pSelfValue) : False := by
  simp only [pAssign, pSelfValue] at *; omega
theorem clash_assign_int {c : CTree} (a0 : nodeProd c = pAssign) (b0 : nodeProd c = pInt) : False := by
  simp only [pAssign, pInt] at *; omega
theorem clash_assign_char {c : CTree} (a0 : nodeProd c = pAssign) (b0 : nodeProd c = pChar) : False := by
  simp only [pAssign, pChar] at *; omega
theorem clash_assign_float {c : CTree} (a0 : nodeProd c = pAssign) (b0 : nodeProd c = pFloat) : False := by
  simp only [pAssign, pFloat] at *; omega
theorem clash_assign_true {c : CTree} (a0 : nodeProd c = pAssign) (b0 : nodeProd c = pTrue) : False := by
  simp only [pAssign, pTrue] at *; omega
theorem clash_assign_false {c : CTree} (a0 : nodeProd c = pAssign) (b0 : nodeProd c = pFalse) : False := by
  simp only [pAssign, pFalse] at *; omega
theorem clash_level_cast {c : CTree} (a0 : nodeProd c ∈ levelProds) (b0 : nodeProd c = pCast) : False := by
  simp only [levelProds, List.mem_cons, List.not_mem_nil, or_false, pOrexpr, pAndexpr, pBitOr, pBitXor, pBitAnd, pEquality, pCompare, pShift, pAdd, pMul, pCast] at *; omega
theorem clash_level_neg {c : CTree} (a0 : nodeProd c ∈ levelProds) (b0 : nodeProd c = pNeg) : False := by
  simp only [levelProds, List.mem_cons, List.not_mem_nil, or_false, pOrexpr, pAndexpr, pBitOr, pBitXor, pBitAnd, pEquality, pCompare, pShift, pAdd, pMul, pNeg] at *; omega
theorem clash_level_not {c : CTree} (a0 : nodeProd c ∈ levelProds) (b0 : nodeProd c = pNot) : False := by
  simp only [levelProds, List.mem_cons, List.not_mem_nil, or_false, pOrexpr, pAndexpr, pBitOr, pBitXor, pBitAnd, pEquality, pCompare, pShift, pAdd, pMul, pNot] at *; omega
theorem clash_level_postfix {c : CTree} (a0 : nodeProd c ∈ levelProds) (b0 : nodeProd c = pPostfix) : False := by
  simp only [levelProds, List.mem_cons, List.not_mem_nil, or_false, pOrexpr, pAndexpr, pBitOr, pBitXor, pBitAnd, pEquality, pCompare, pShift, pAdd, pMul, pPostfix] at *; omega
theorem clash_level_member {c : CTree} (a0 : nodeProd c ∈ levelProds) (b0 : nodeProd c = pPostfix) : False := by
  simp only [levelProds, List.mem_cons, List.not_mem_nil, or_false, pOrexpr, pAndexpr, pBitOr, pBitXor, pBitAnd, pEquality, pCompare, pShift, pAdd, pMul, pPostfix] at *; omega
theorem clash_level_group {c : CTree} (a0 : nodeProd c ∈ levelProds) (b0 : nodeProd c = pGroup) : False := by
  simp only [levelProds, List.mem_cons, List.not_mem_nil, or_false, pOrexpr, pAndexpr, pBitOr, pBitXor, pBitAnd, pEquality, pCompare, pShift, pAdd, pMul, pGroup] at *; omega
theorem clash_level_local {c : CTree} (a0 : nodeProd c ∈ levelProds) (b0 : nodeProd c = pIdent) : False := by
  simp only [levelProds, List.mem_cons, List.not_mem_nil, or_false, pOrexpr, pAndexpr, pBitOr, pBitXor, pBitAnd, pEquality, pCompare, pShift, pAdd, pMul, pIdent] at *; omega
theorem clash_level_const {c : CTree} (a0 : nodeProd c ∈ levelProds) (b0 : nodeProd c = pIdent) : False := by
  simp only [levelProds, List.mem_cons, List.not_mem_nil, or_false, pOrexpr, pAndexpr, pBitOr, pBitXor, pBitAnd, pEquality, pCompare, pShift, pAdd, pMul, pIdent] at *; omega
theorem clash_level_self {c : CTree} (a0 : nodeProd c ∈ levelProds) (b0 : nodeProd c = pSelfValue) : False := by
  simp only [levelProds, List.mem_cons, List.not_mem_nil, or_false, pOrexpr, pAndexpr, pBitOr, pBitXor, pBitAnd, pEquality, pCompare, pShift, pAdd, pMul, pSelfValue] at *; omega
theorem clash_level_int {c : CTree} (a0 : nodeProd c ∈ levelProds) (b0 : nodeProd c = pInt) : False := by
  simp only [levelProds, List.mem_cons, List.not_mem_nil, or_false, pOrexpr, pAndexpr, pBitOr, pBitXor, pBitAnd, pEquality, pCompare, pShift, pAdd, pMul, pInt] at *; omega
theorem clash_level_char {c : CTree} (a0 : nodeProd c ∈ levelProds) (b0 : nodeProd c = pChar) : False := by
  simp only [levelProds, List.mem_cons, List.not_mem_nil, or_false, pOrexpr, pAndexpr, pBitOr, pBitXor, pBitAnd, pEquality, pCompare, pShift, pAdd, pMul, pChar] at *; omega
theorem clash_level_float {c : CTree} (a0 : nodeProd c ∈ levelProds) (b0 : nodeProd c = pFloat) : False := by
  simp only [levelProds, List.mem_cons, List.not_mem_nil, or_false, pOrexpr, pAndexpr, pBitOr, pBitXor, pBitAnd, pEquality, pCompare, pShift, pAdd, pMul, pFloat] at *; omega
theorem clash_level_true {c : CTree} (a0 : nodeProd c ∈ levelProds) (b0 : nodeProd c = pTrue) : False := by
  simp only [levelProds, List.mem_cons, List.not_mem_nil, or_false, pOrexpr, pAndexpr, pBitOr, pBitXor, pBitAnd, pEquality, pCompare, pShift, pAdd, pMul, pTrue] at *; omega
theorem clash_level_false {c : CTree} (a0 : nodeProd c ∈ levelProds) (b0 : nodeProd c = pFalse) : False := by
  simp only [levelProds, List.mem_cons, List.not_mem_nil, or_false, pOrexpr, pAndexpr, pBitOr, pBitXor, pBitAnd, pEquality, pCompare, pShift, pAdd, pMul, pFalse] at *; omega
theorem clash_cast_neg {c : CTree} (a0 : nodeProd c = pCast) (b0 : nodeProd c = pNeg) : False := by
  simp only [pCast, pNeg] at *; omega
theorem clash_cast_not {c : CTree} (a0 : nodeProd c = pCast) (b0 : nodeProd c = pNot) : False := by
  simp only [pCast, pNot] at *; omega
theorem clash_cast_postfix {c : CTree} (a0 : nodeProd c = pCast) (b0 : nodeProd c = pPostfix) : False := by
  simp only [pCast, pPostfix] at *; omega
theorem clash_cast_member {c : CTree} (a0 : nodeProd c = pCast) (b0 : nodeProd c = pPostfix) : False := by
  simp only [pCast, pPostfix] at *; omega
theorem clash_cast_group {c : CTree} (a0 : nodeProd c = pCast) (b0 : nodeProd c = pGroup) : False := by
  simp only [pCast, pGroup] at *; omega
theorem clash_cast_local {c : CTree} (a0 : nodeProd c = pCast) (b0 : nodeProd c = pIdent) : False := by
  simp only [pCast, pIdent] at *; omega
theorem clash_cast_const {c : CTree} (a0 : nodeProd c = pCast) (b0 : nodeProd c = pIdent) : False := by
  simp only [pCast, pIdent] at *; omega
theorem clash_cast_self {c : CTree} (a0 : nodeProd c = pCast) (b0 : nodeProd c = pSelfValue) : False := by
  simp only [pCast, pSelfValue] at *; omega
theorem clash_cast_int {c : CTree} (a0 : nodeProd c = pCast) (b0 : nodeProd c = pInt) : False := by
  simp only [pCast, pInt] at *; omega
theorem clash_cast_char {c : CTree} (a0 : nodeProd c = pCast) (b0 : nodeProd c = pChar) : False := by
  simp only [pCast, pChar] at *; omega
theorem clash_cast_float {c : CTree} (a0 : nodeProd c = pCast) (b0 : nodeProd c = pFloat) : False := by
  simp only [pCast, pFloat] at *; omega
theorem clash_cast_true {c : CTree} (a0 : nodeProd c = pCast) (b0 : nodeProd c = pTrue) : False := by
  simp only [pCast, pTrue] at *; omega
theorem clash_cast_false {c : CTree} (a0 : nodeProd c = pCast) (b0 : nodeProd c = pFalse) : False := by
  simp only [pCast, pFalse] at *; omega
theorem clash_neg_not {c : CTree} (a0 : nodeProd c = pNeg) (b0 : nodeProd c = pNot) : False := by
  simp only [pNeg, pNot] at *; omega
theorem clash_neg_postfix {c : CTree} (a0 : nodeProd c = pNeg) (b0 : nodeProd c = pPostfix) : False := by
  simp only [pNeg, pPostfix] at *; omega
theorem clash_neg_member {c : CTree} (a0 : nodeProd c = pNeg) (b0 : nodeProd c = pPostfix) : False := by
  simp only [pNeg, pPostfix] at *; omega
theorem clash_neg_group {c : CTree} (a0 : nodeProd c = pNeg) (b0 : nodeProd c = pGroup) : False := by
  simp only [pGroup, pNeg] at *; omega
theorem clash_neg_local {c : CTree} (a0 : nodeProd c = pNeg) (b0 : nodeProd c = pIdent) : False := by
  simp only [pIdent, pNeg] at *; omega
theorem clash_neg_const {c : CTree} (a0 : nodeProd c = pNeg) (b0 : nodeProd c = pIdent) : False := by
  simp only [pIdent, pNeg] at *; omega
theorem clash_neg_self {c : CTree} (a0 : nodeProd c = pNeg) (b0 : nodeProd c = pSelfValue) : False := by
  simp only [pNeg, pSelfValue] at *; omega
theorem clash_neg_int {c : CTree} (a0 : nodeProd c = pNeg) (b0 : nodeProd c = pInt) : False := by
  simp only [pInt, pNeg] at *; omega
theorem clash_neg_char {c : CTree} (a0 : nodeProd c = pNeg) (b0 : nodeProd c = pChar) : False := by
  simp only [pChar, pNeg] at *; omega
theorem clash_neg_float {c : CTree} (a0 : nodeProd c = pNeg) (b0 : nodeProd c = pFloat) : False := by
  simp only [pFloat, pNeg] at *; omega
theorem clash_neg_true {c : CTree} (a0 : nodeProd c = pNeg) (b0 : nodeProd c = pTrue) : False := by
  simp only [pNeg, pTrue] at *; omega
theorem clash_neg_false {c : CTree} (a0 : nodeProd c = pNeg) (b0 : nodeProd c = pFalse) : False := by
  simp only [pFalse, pNeg] at *; omega
theorem clash_not_postfix {c : CTree} (a0 : nodeProd c = pNot) (b0 : nodeProd c = pPostfix) : False := by
  simp only [pNot, pPostfix] at *; omega
theorem clash_not_member {c : CTree} (a0 : nodeProd c = pNot) (b0 : nodeProd c = pPostfix) : False := by
  simp only [pNot, pPostfix] at *; omega
theorem clash_not_group {c : CTree} (a0 : nodeProd c = pNot) (b0 : nodeProd c = pGroup) : False := by
  simp only [pGroup, pNot] at *; omega
theorem clash_not_local {c : CTree} (a0 : nodeProd c = pNot) (b0 : nodeProd c = pIdent) : False := by
  simp only [pIdent, pNot] at *; omega
theorem clash_not_const {c : CTree} (a0 : nodeProd c = pNot) (b0 : nodeProd c = pIdent) : False := by
  simp only [pIdent, pNot] at *; omega
theorem clash_not_self {c : CTree} (a0 : nodeProd c = pNot) (b0 : nodeProd c = pSelfValue) : False := by
  simp only [pNot, pSelfValue] at *; omega
theorem clash_not_int {c : CTree} (a0 : nodeProd c = pNot) (b0 : nodeProd c = pInt) : False := by
  simp only [pInt, pNot] at *; omega
theorem clash_not_char {c : CTree} (a0 : nodeProd c = pNot) (b0 : nodeProd c = pChar) : False := by
  simp only [pChar, pNot] at *; omega
theorem clash_not_float {c : CTree} (a0 : nodeProd c = pNot) (b0 : nodeProd c = pFloat) : False := by
  simp only [pFloat, pNot] at *; omega
theorem clash_not_true {c : CTree} (a0 : nodeProd c = pNot) (b0 : nodeProd c = pTrue) : False := by
  simp only [pNot, pTrue] at *; omega
theorem clash_not_false {c : CTree} (a0 : nodeProd c = pNot) (b0 : nodeProd c = pFalse) : False := by
  simp only [pFalse, pNot] at *; omega
theorem clash_postfix_member {c : CTree} (a0 : nodeProd c = pPostfix) (a1 : nodeProd (kid c 1) = pPostfixEnd) (b0 : nodeProd c = pPostfix) (b1 : nodeProd (kid c 1) = pPostfixMember) : False := by
  simp only [pPostfix, pPostfixEnd, pPostfixMember] at *; omega
theorem clash_postfix_group {c : CTree} (a0 : nodeProd c = pPostfix) (b0 : nodeProd c = pGroup) : False := by
  simp only [pGroup, pPostfix] at *; omega
theorem clash_postfix_local {c : CTree} (a0 : nodeProd c = pPostfix) (b0 : nodeProd c = pIdent) : False := by
  simp only [pIdent, pPostfix] at *; omega
theorem clash_postfix_const {c : CTree} (a0 : nodeProd c = pPostfix) (b0 : nodeProd c = pIdent) : False := by
  simp only [pIdent, pPostfix] at *; omega
theorem clash_postfix_self {c : CTree} (a0 : nodeProd c = pPostfix) (b0 : nodeProd c = pSelfValue) : False := by
  simp only [pPostfix, pSelfValue] at *; omega
theorem clash_postfix_int {c : CTree} (a0 : nodeProd c = pPostfix) (b0 : nodeProd c = pInt) : False := by
  simp only [pInt, pPostfix] at *; omega
theorem clash_postfix_char {c : CTree} (a0 : nodeProd c = pPostfix) (b0 : nodeProd c = pChar) : False := by
  simp only [pChar, pPostfix] at *; omega
theorem clash_postfix_float {c : CTree} (a0 : nodeProd c = pPostfix) (b0 : nodeProd c = pFloat) : False := by
  simp only [pFloat, pPostfix] at *; omega
theorem clash_postfix_true {c : CTree} (a0 : nodeProd c = pPostfix) (b0 : nodeProd c = pTrue) : False := by
  simp only [pPostfix, pTrue] at *; omega
theorem clash_postfix_false {c : CTree} (a0 : nodeProd c = pPostfix) (b0 : nodeProd c = pFalse) : False := by
  simp only [pFalse, pPostfix] at *; omega
theorem clash_member_group {c : CTree} (a0 : nodeProd c = pPostfix) (b0 : nodeProd c = pGroup) : False := by
  simp only [pGroup, pPostfix] at *; omega
theorem clash_member_local {c : CTree} (a0 : nodeProd c = pPostfix) (b0 : nodeProd c = pIdent) : False := by
  simp only [pIdent, pPostfix] at *; omega
theorem clash_member_const {c : CTree} (a0 : nodeProd c = pPostfix) (b0 : nodeProd c = pIdent) : False := by
  simp only [pIdent, pPostfix] at *; omega
theorem clash_member_self {c : CTree} (a0 : nodeProd c = pPostfix) (b0 : nodeProd c = pSelfValue) : False := by
  simp only [pPostfix, pSelfValue] at *; omega
theorem clash_member_int {c : CTree} (a0 : nodeProd c = pPostfix) (b0 : nodeProd c = pInt) : False := by
  simp only [pInt, pPostfix] at *; omega
theorem clash_member_char {c : CTree} (a0 : nodeProd c = pPostfix) (b0 : nodeProd c = pChar) : False := by
  simp only [pChar, pPostfix] at *; omega
theorem clash_member_float {c : CTree} (a0 : nodeProd c = pPostfix) (b0 : nodeProd c = pFloat) : False := by
  simp only [pFloat, pPostfix] at *; omega
theorem clash_member_true {c : CTree} (a0 : nodeProd c = pPostfix) (b0 : nodeProd c = pTrue) : False := by
  simp only [pPostfix, pTrue] at *; omega
theorem clash_member_false {c : CTree} (a0 : nodeProd c = pPostfix) (b0 : nodeProd c = pFalse) : False := by
  simp only [pFalse, pPostfix] at *; omega
theorem clash_group_local {c : CTree} (a0 : nodeProd c = pGroup) (b0 : nodeProd c = pIdent) : False := by
  simp only [pGroup, pIdent] at *; omega
theorem clash_group_const {c : CTree} (a0 : nodeProd c = pGroup) (b0 : nodeProd c = pIdent) : False := by
  simp only [pGroup, pIdent] at *; omega
theorem clash_group_self {c : CTree} (a0 : nodeProd c = pGroup) (b0 : nodeProd c = pSelfValue) : False := by
  simp only [pGroup, pSelfValue] at *; omega
theorem clash_group_int {c : CTree} (a0 : nodeProd c = pGroup) (b0 : nodeProd c = pInt) : False := by
  simp only [pGroup, pInt] at *; omega
theorem clash_group_char {c : CTree} (a0 : nodeProd c = pGroup) (b0 : nodeProd c = pChar) : False := by
  simp only [pChar, pGroup] at *; omega
theorem clash_group_float {c : CTree} (a0 : nodeProd c = pGroup) (b0 : nodeProd c = pFloat) : False := by
  simp only [pFloat, pGroup] at *; omega
theorem clash_group_true {c : CTree} (a0 : nodeProd c = pGroup) (b0 : nodeProd c = pTrue) : False := by
  simp only [pGroup, pTrue] at *; omega
theorem clash_group_false {c : CTree} (a0 : nodeProd c = pGroup) (b0 : nodeProd c = pFalse) : False := by
  simp only [pFalse, pGroup] at *; omega
theorem clash_local_self {c : CTree} (a0 : nodeProd c = pIdent) (b0 : nodeProd c = pSelfValue) : False := by
  simp only [pIdent, pSelfValue] at *; omega
theorem clash_local_int {c : CTree} (a0 : nodeProd c = pIdent) (b0 : nodeProd c = pInt) : False := by
  simp only [pIdent, pInt] at *; omega
theorem clash_local_char {c : CTree} (a0 : nodeProd c = pIdent) (b0 : nodeProd c = pChar) : False := by
  simp only [pChar, pIdent] at *; omega
theorem clash_local_float {c : CTree} (a0 : nodeProd c = pIdent) (b0 : nodeProd c = pFloat) : False := by
  simp only [pFloat, pIdent] at *; omega
theorem clash_local_true {c : CTree} (a0 : nodeProd c = pIdent) (b0 : nodeProd c = pTrue) : False := by
  simp only [pIdent, pTrue] at *; omega
theorem clash_local_false {c : CTree} (a0 : nodeProd c = pIdent) (b0 : nodeProd c = pFalse) : False := by
  simp only [pFalse, pIdent] at *; omega
theorem clash_const_self {c : CTree} (a0 : nodeProd c = pIdent) (b0 : nodeProd c = pSelfValue) : False := by
  simp only [pIdent, pSelfValue] at *; omega
theorem clash_const_int {c : CTree} (a0 : nodeProd c = pIdent) (b0 : nodeProd c = pInt) : False := by
  simp only [pIdent, pInt] at *; omega
theorem clash_const_char {c : CTree} (a0 : nodeProd c = pIdent) (b0 : nodeProd c = pChar) : False := by
  simp only [pChar, pIdent] at *; omega
theorem clash_const_float {c : CTree} (a0 : nodeProd c = pIdent) (b0 : nodeProd c = pFloat) : False := by
  simp only [pFloat, pIdent] at *; omega
theorem clash_const_true {c : CTree} (a0 : nodeProd c = pIdent) (b0 : nodeProd c = pTrue) : False := by
  simp only [pIdent, pTrue] at *; omega
theorem clash_const_false {c : CTree} (a0 : nodeProd c = pIdent) (b0 : nodeProd c = pFalse) : False := by
  simp only [pFalse, pIdent] at *; omega
theorem clash_self_int {c : CTree} (a0 : nodeProd c = pSelfValue) (b0 : nodeProd c = pInt) : False := by
  simp only [pInt, pSelfValue] at *; omega
theorem clash_self_char {c : CTree} (a0 : nodeProd c = pSelfValue) (b0 : nodeProd c = pChar) : False := by
  simp only [pChar, pSelfValue] at *; omega
theorem clash_self_float {c : CTree} (a0 : nodeProd c = pSelfValue) (b0 : nodeProd c = pFloat) : False := by
  simp only [pFloat, pSelfValue] at *; omega
theorem clash_self_true {c : CTree} (a0 : nodeProd c = pSelfValue) (b0 : nodeProd c = pTrue) : False := by
  simp only [pSelfValue, pTrue] at *; omega
theorem clash_self_false {c : CTree} (a0 : nodeProd c = pSelfValue) (b0 : nodeProd c = pFalse) : False := by
  simp only [pFalse, pSelfValue] at *; omega
theorem clash_int_char {c : CTree} (a0 : nodeProd c = pInt) (b0 : nodeProd c = pChar) : False := by
  simp only [pChar, pInt] at *; omega
theorem clash_int_float {c : CTree} (a0 : nodeProd c = pInt) (b0 : nodeProd c = pFloat) : False := by
  simp only [pFloat, pInt] at *; omega
theorem clash_int_true {c : CTree} (a0 : nodeProd c = pInt) (b0 : nodeProd c = pTrue) : False := by
  simp only [pInt, pTrue] at *; omega
theorem clash_int_false {c : CTree} (a0 : nodeProd c = pInt) (b0 : nodeProd c = pFalse) : False := by
  simp only [pFalse, pInt] at *; omega
theorem clash_char_float {c : CTree} (a0 : nodeProd c = pChar) (b0 : nodeProd c = pFloat) : False := by
  simp only [pChar, pFloat] at *; omega
theorem clash_char_true {c : CTree} (a0 : nodeProd c = pChar) (b0 : nodeProd c = pTrue) : False := by
  simp only [pChar, pTrue] at *; omega
theorem clash_char_false {c : CTree} (a0 : nodeProd c = pChar) (b0 : nodeProd c = pFalse) : False := by
  simp only [pChar, pFalse] at *; omega
theorem clash_float_true {c : CTree} (a0 : nodeProd c = pFloat) (b0 : nodeProd c = pTrue) : False := by
  simp only [pFloat, pTrue] at *; omega
theorem clash_float_false {c : CTree} (a0 : nodeProd c = pFloat) (b0 : nodeProd c = pFalse) : False := by
  simp only [pFalse, pFloat] at *; omega
theorem clash_true_false {c : CTree} (a0 : nodeProd c = pTrue) (b0 : nodeProd c = pFalse) : False := by
  simp only [pFalse, pTrue] at *; omega

mutual
theorem exprR_unique : ∀ {env : FrontEnv} {scope : List Local} {c : CTree} {a b : SrcExpr},
    ExprR env scope c a → ExprR env scope c b → a = b
  | _, _, _, _, _, .wrap p0 r, h₂ => by
    cases h₂ with
    | «wrap» _ r' =>
      exact exprR_unique r r'
    | «assign» q0 q1 _ => exact (clash_wrap_assign p0 q0).elim
    | «level» q0 _ _ => exact (clash_wrap_level p0 q0).elim
    | «cast» q0 _ _ => exact (clash_wrap_cast p0 q0).elim
    | «neg» q0 _ => exact (clash_wrap_neg p0 q0).elim
    | «not» q0 _ => exact (clash_wrap_not p0 q0).elim
    | «postfix» q0 q1 _ => exact (clash_wrap_postfix p0 q0).elim
    | «member» q0 q1 _ => exact (clash_wrap_member p0 q0).elim
    | «group» q0 _ => exact (clash_wrap_group p0 q0).elim
    | «local» q0 q1 _ => exact (clash_wrap_local p0 q0).elim
    | «const» q0 q1 _ _ _ _ _ => exact (clash_wrap_const p0 q0).elim
    | «self» q0 _ => exact (clash_wrap_self p0 q0).elim
    | «int» q0 _ => exact (clash_wrap_int p0 q0).elim
    | «char» q0 _ => exact (clash_wrap_char p0 q0).elim
    | «float» q0 _ => exact (clash_wrap_float p0 q0).elim
    | «true» q0 => exact (clash_wrap_true p0 q0).elim
    | «false» q0 => exact (clash_wrap_false p0 q0).elim
  | _, _, _, _, _, .assign p0 p1 r, h₂ => by
    cases h₂ with
    | «wrap» q0 _ => exact (clash_wrap_assign q0 p0).elim
    | «assign» _ _ r' =>
      exact exprR_unique r r'
    | «level» q0 _ _ => exact (clash_assign_level p0 q0).elim
    | «cast» q0 _ _ => exact (clash_assign_cast p0 q0).elim
    | «neg» q0 _ => exact (clash_assign_neg p0 q0).elim
    | «not» q0 _ => exact (clash_assign_not p0 q0).elim
    | «postfix» q0 q1 _ => exact (clash_assign_postfix p0 q0).elim
    | «member» q0 q1 _ => exact (clash_assign_member p0 q0).elim
    | «group» q0 _ => exact (clash_assign_group p0 q0).elim
    | «local» q0 q1 _ => exact (clash_assign_local p0 q0).elim
    | «const» q0 q1 _ _ _ _ _ => exact (clash_assign_const p0 q0).elim
    | «self» q0 _ => exact (clash_assign_self p0 q0).elim
    | «int» q0 _ => exact (clash_assign_int p0 q0).elim
    | «char» q0 _ => exact (clash_assign_char p0 q0).elim
    | «float» q0 _ => exact (clash_assign_float p0 q0).elim
    | «true» q0 => exact (clash_assign_true p0 q0).elim
    | «false» q0 => exact (clash_assign_false p0 q0).elim
  | _, _, _, _, _, .level p0 r f, h₂ => by
    cases h₂ with
    | «wrap» q0 _ => exact (clash_wrap_level q0 p0).elim
    | «assign» q0 q1 _ => exact (clash_assign_level q0 p0).elim
    | «level» _ r' f' =>
      have e := exprR_unique r r'
      subst e
      exact fold_unique f f'
    | «cast» q0 _ _ => exact (clash_level_cast p0 q0).elim
    | «neg» q0 _ => exact (clash_level_neg p0 q0).elim
    | «not» q0 _ => exact (clash_level_not p0 q0).elim
    | «postfix» q0 q1 _ => exact (clash_level_postfix p0 q0).elim
    | «member» q0 q1 _ => exact (clash_level_member p0 q0).elim
    | «group» q0 _ => exact (clash_level_group p0 q0).elim
    | «local» q0 q1 _ => exact (clash_level_local p0 q0).elim
    | «const» q0 q1 _ _ _ _ _ => exact (clash_level_const p0 q0).elim
    | «self» q0 _ => exact (clash_level_self p0 q0).elim
    | «int» q0 _ => exact (clash_level_int p0 q0).elim
    | «char» q0 _ => exact (clash_level_char p0 q0).elim
    | «float» q0 _ => exact (clash_level_float p0 q0).elim
    | «true» q0 => exact (clash_level_true p0 q0).elim
    | «false» q0 => exact (clash_level_false p0 q0).elim
  | _, _, _, _, _, .cast p0 r k, h₂ => by
    cases h₂ with
    | «wrap» q0 _ => exact (clash_wrap_cast q0 p0).elim
    | «assign» q0 q1 _ => exact (clash_assign_cast q0 p0).elim
    | «level» q0 _ _ => exact (clash_level_cast q0 p0).elim
    | «cast» _ r' k' =>
      have e := exprR_unique r r'
      subst e
      exact casts_unique k k'
    | «neg» q0 _ => exact (clash_cast_neg p0 q0).elim
    | «not» q0 _ => exact (clash_cast_not p0 q0).elim
    | «postfix» q0 q1 _ => exact (clash_cast_postfix p0 q0).elim
    | «member» q0 q1 _ => exact (clash_cast_member p0 q0).elim
    | «group» q0 _ => exact (clash_cast_group p0 q0).elim
    | «local» q0 q1 _ => exact (clash_cast_local p0 q0).elim
    | «const» q0 q1 _ _ _ _ _ => exact (clash_cast_const p0 q0).elim
    | «self» q0 _ => exact (clash_cast_self p0 q0).elim
    | «int» q0 _ => exact (clash_cast_int p0 q0).elim
    | «char» q0 _ => exact (clash_cast_char p0 q0).elim
    | «float» q0 _ => exact (clash_cast_float p0 q0).elim
    | «true» q0 => exact (clash_cast_true p0 q0).elim
    | «false» q0 => exact (clash_cast_false p0 q0).elim
  | _, _, _, _, _, .neg p0 r, h₂ => by
    cases h₂ with
    | «wrap» q0 _ => exact (clash_wrap_neg q0 p0).elim
    | «assign» q0 q1 _ => exact (clash_assign_neg q0 p0).elim
    | «level» q0 _ _ => exact (clash_level_neg q0 p0).elim
    | «cast» q0 _ _ => exact (clash_cast_neg q0 p0).elim
    | «neg» _ r' =>
      rw [exprR_unique r r']
    | «not» q0 _ => exact (clash_neg_not p0 q0).elim
    | «postfix» q0 q1 _ => exact (clash_neg_postfix p0 q0).elim
    | «member» q0 q1 _ => exact (clash_neg_member p0 q0).elim
    | «group» q0 _ => exact (clash_neg_group p0 q0).elim
    | «local» q0 q1 _ => exact (clash_neg_local p0 q0).elim
    | «const» q0 q1 _ _ _ _ _ => exact (clash_neg_const p0 q0).elim
    | «self» q0 _ => exact (clash_neg_self p0 q0).elim
    | «int» q0 _ => exact (clash_neg_int p0 q0).elim
    | «char» q0 _ => exact (clash_neg_char p0 q0).elim
    | «float» q0 _ => exact (clash_neg_float p0 q0).elim
    | «true» q0 => exact (clash_neg_true p0 q0).elim
    | «false» q0 => exact (clash_neg_false p0 q0).elim
  | _, _, _, _, _, .not p0 r, h₂ => by
    cases h₂ with
    | «wrap» q0 _ => exact (clash_wrap_not q0 p0).elim
    | «assign» q0 q1 _ => exact (clash_assign_not q0 p0).elim
    | «level» q0 _ _ => exact (clash_level_not q0 p0).elim
    | «cast» q0 _ _ => exact (clash_cast_not q0 p0).elim
    | «neg» q0 _ => exact (clash_neg_not q0 p0).elim
    | «not» _ r' =>
      rw [exprR_unique r r']
    | «postfix» q0 q1 _ => exact (clash_not_postfix p0 q0).elim
    | «member» q0 q1 _ => exact (clash_not_member p0 q0).elim
    | «group» q0 _ => exact (clash_not_group p0 q0).elim
    | «local» q0 q1 _ => exact (clash_not_local p0 q0).elim
    | «const» q0 q1 _ _ _ _ _ => exact (clash_not_const p0 q0).elim
    | «self» q0 _ => exact (clash_not_self p0 q0).elim
    | «int» q0 _ => exact (clash_not_int p0 q0).elim
    | «char» q0 _ => exact (clash_not_char p0 q0).elim
    | «float» q0 _ => exact (clash_not_float p0 q0).elim
    | «true» q0 => exact (clash_not_true p0 q0).elim
    | «false» q0 => exact (clash_not_false p0 q0).elim
  | _, _, _, _, _, .postfix p0 p1 r, h₂ => by
    cases h₂ with
    | «wrap» q0 _ => exact (clash_wrap_postfix q0 p0).elim
    | «assign» q0 q1 _ => exact (clash_assign_postfix q0 p0).elim
    | «level» q0 _ _ => exact (clash_level_postfix q0 p0).elim
    | «cast» q0 _ _ => exact (clash_cast_postfix q0 p0).elim
    | «neg» q0 _ => exact (clash_neg_postfix q0 p0).elim
    | «not» q0 _ => exact (clash_not_postfix q0 p0).elim
    | «postfix» _ _ r' =>
      exact exprR_unique r r'
    | «member» q0 q1 _ => exact (clash_postfix_member p0 p1 q0 q1).elim
    | «group» q0 _ => exact (clash_postfix_group p0 q0).elim
    | «local» q0 q1 _ => exact (clash_postfix_local p0 q0).elim
    | «const» q0 q1 _ _ _ _ _ => exact (clash_postfix_const p0 q0).elim
    | «self» q0 _ => exact (clash_postfix_self p0 q0).elim
    | «int» q0 _ => exact (clash_postfix_int p0 q0).elim
    | «char» q0 _ => exact (clash_postfix_char p0 q0).elim
    | «float» q0 _ => exact (clash_postfix_float p0 q0).elim
    | «true» q0 => exact (clash_postfix_true p0 q0).elim
    | «false» q0 => exact (clash_postfix_false p0 q0).elim
  | _, _, _, _, _, .member p0 p1 m, h₂ => by
    cases h₂ with
    | «wrap» q0 _ => exact (clash_wrap_member q0 p0).elim
    | «assign» q0 q1 _ => exact (clash_assign_member q0 p0).elim
    | «level» q0 _ _ => exact (clash_level_member q0 p0).elim
    | «cast» q0 _ _ => exact (clash_cast_member q0 p0).elim
    | «neg» q0 _ => exact (clash_neg_member q0 p0).elim
    | «not» q0 _ => exact (clash_not_member q0 p0).elim
    | «postfix» q0 q1 _ => exact (clash_postfix_member q0 q1 p0 p1).elim
    | «member» _ _ m' =>
      exact member_unique m m'
    | «group» q0 _ => exact (clash_member_group p0 q0).elim
    | «local» q0 q1 _ => exact (clash_member_local p0 q0).elim
    | «const» q0 q1 _ _ _ _ _ => exact (clash_member_const p0 q0).elim
    | «self» q0 _ => exact (clash_member_self p0 q0).elim
    | «int» q0 _ => exact (clash_member_int p0 q0).elim
    | «char» q0 _ => exact (clash_member_char p0 q0).elim
    | «float» q0 _ => exact (clash_member_float p0 q0).elim
    | «true» q0 => exact (clash_member_true p0 q0).elim
    | «false» q0 => exact (clash_member_false p0 q0).elim
  | _, _, _, _, _, .group p0 r, h₂ => by
    cases h₂ with
    | «wrap» q0 _ => exact (clash_wrap_group q0 p0).elim
    | «assign» q0 q1 _ => exact (clash_assign_group q0 p0).elim
    | «level» q0 _ _ => exact (clash_level_group q0 p0).elim
    | «cast» q0 _ _ => exact (clash_cast_group q0 p0).elim
    | «neg» q0 _ => exact (clash_neg_group q0 p0).elim
    | «not» q0 _ => exact (clash_not_group q0 p0).elim
    | «postfix» q0 q1 _ => exact (clash_postfix_group q0 p0).elim
    | «member» q0 q1 _ => exact (clash_member_group q0 p0).elim
    | «group» _ r' =>
      exact exprR_unique r r'
    | «local» q0 q1 _ => exact (clash_group_local p0 q0).elim
    | «const» q0 q1 _ _ _ _ _ => exact (clash_group_const p0 q0).elim
    | «self» q0 _ => exact (clash_group_self p0 q0).elim
    | «int» q0 _ => exact (clash_group_int p0 q0).elim
    | «char» q0 _ => exact (clash_group_char p0 q0).elim
    | «float» q0 _ => exact (clash_group_float p0 q0).elim
    | «true» q0 => exact (clash_group_true p0 q0).elim
    | «false» q0 => exact (clash_group_false p0 q0).elim
  | _, _, _, _, _, .local p0 p1 l, h₂ => by
    cases h₂ with
    | «wrap» q0 _ => exact (clash_wrap_local q0 p0).elim
    | «assign» q0 q1 _ => exact (clash_assign_local q0 p0).elim
    | «level» q0 _ _ => exact (clash_level_local q0 p0).elim
    | «cast» q0 _ _ => exact (clash_cast_local q0 p0).elim
    | «neg» q0 _ => exact (clash_neg_local q0 p0).elim
    | «not» q0 _ => exact (clash_not_local q0 p0).elim
    | «postfix» q0 q1 _ => exact (clash_postfix_local q0 p0).elim
    | «member» q0 q1 _ => exact (clash_member_local q0 p0).elim
    | «group» q0 _ => exact (clash_group_local q0 p0).elim
    | «local» _ _ l' =>
      rw [localOf_unique l l']
    | «const» q0 q1 nl _ _ _ _ => exact (nl _ l).elim
    | «self» q0 _ => exact (clash_local_self p0 q0).elim
    | «int» q0 _ => exact (clash_local_int p0 q0).elim
    | «char» q0 _ => exact (clash_local_char p0 q0).elim
    | «float» q0 _ => exact (clash_local_float p0 q0).elim
    | «true» q0 => exact (clash_local_true p0 q0).elim
    | «false» q0 => exact (clash_local_false p0 q0).elim
  | _, _, _, _, _, .const p0 p1 nl s r k v, h₂ => by
    cases h₂ with
    | «wrap» q0 _ => exact (clash_wrap_const q0 p0).elim
    | «assign» q0 q1 _ => exact (clash_assign_const q0 p0).elim
    | «level» q0 _ _ => exact (clash_level_const q0 p0).elim
    | «cast» q0 _ _ => exact (clash_cast_const q0 p0).elim
    | «neg» q0 _ => exact (clash_neg_const q0 p0).elim
    | «not» q0 _ => exact (clash_not_const q0 p0).elim
    | «postfix» q0 q1 _ => exact (clash_postfix_const q0 p0).elim
    | «member» q0 q1 _ => exact (clash_member_const q0 p0).elim
    | «group» q0 _ => exact (clash_group_const q0 p0).elim
    | «local» q0 q1 l' => exact (nl _ l').elim
    | «const» _ _ _ s' r' k' v' =>
      rw [pathSpellings_unique s s'] at r
      obtain ⟨rfl, rfl⟩ := resolves_unique r r'
      have e := constNamed_unique k k'
      subst e
      exact constValue_unique v v'
    | «self» q0 _ => exact (clash_const_self p0 q0).elim
    | «int» q0 _ => exact (clash_const_int p0 q0).elim
    | «char» q0 _ => exact (clash_const_char p0 q0).elim
    | «float» q0 _ => exact (clash_const_float p0 q0).elim
    | «true» q0 => exact (clash_const_true p0 q0).elim
    | «false» q0 => exact (clash_const_false p0 q0).elim
  | _, _, _, _, _, .self p0 l, h₂ => by
    cases h₂ with
    | «wrap» q0 _ => exact (clash_wrap_self q0 p0).elim
    | «assign» q0 q1 _ => exact (clash_assign_self q0 p0).elim
    | «level» q0 _ _ => exact (clash_level_self q0 p0).elim
    | «cast» q0 _ _ => exact (clash_cast_self q0 p0).elim
    | «neg» q0 _ => exact (clash_neg_self q0 p0).elim
    | «not» q0 _ => exact (clash_not_self q0 p0).elim
    | «postfix» q0 q1 _ => exact (clash_postfix_self q0 p0).elim
    | «member» q0 q1 _ => exact (clash_member_self q0 p0).elim
    | «group» q0 _ => exact (clash_group_self q0 p0).elim
    | «local» q0 q1 _ => exact (clash_local_self q0 p0).elim
    | «const» q0 q1 _ _ _ _ _ => exact (clash_const_self q0 p0).elim
    | «self» _ l' =>
      rw [localOf_unique l l']
    | «int» q0 _ => exact (clash_self_int p0 q0).elim
    | «char» q0 _ => exact (clash_self_char p0 q0).elim
    | «float» q0 _ => exact (clash_self_float p0 q0).elim
    | «true» q0 => exact (clash_self_true p0 q0).elim
    | «false» q0 => exact (clash_self_false p0 q0).elim
  | _, _, _, _, _, .int p0 i, h₂ => by
    cases h₂ with
    | «wrap» q0 _ => exact (clash_wrap_int q0 p0).elim
    | «assign» q0 q1 _ => exact (clash_assign_int q0 p0).elim
    | «level» q0 _ _ => exact (clash_level_int q0 p0).elim
    | «cast» q0 _ _ => exact (clash_cast_int q0 p0).elim
    | «neg» q0 _ => exact (clash_neg_int q0 p0).elim
    | «not» q0 _ => exact (clash_not_int q0 p0).elim
    | «postfix» q0 q1 _ => exact (clash_postfix_int q0 p0).elim
    | «member» q0 q1 _ => exact (clash_member_int q0 p0).elim
    | «group» q0 _ => exact (clash_group_int q0 p0).elim
    | «local» q0 q1 _ => exact (clash_local_int q0 p0).elim
    | «const» q0 q1 _ _ _ _ _ => exact (clash_const_int q0 p0).elim
    | «self» q0 _ => exact (clash_self_int q0 p0).elim
    | «int» _ i' =>
      exact intLiteral_unique i i'
    | «char» q0 _ => exact (clash_int_char p0 q0).elim
    | «float» q0 _ => exact (clash_int_float p0 q0).elim
    | «true» q0 => exact (clash_int_true p0 q0).elim
    | «false» q0 => exact (clash_int_false p0 q0).elim
  | _, _, _, _, _, .char p0 l, h₂ => by
    cases h₂ with
    | «wrap» q0 _ => exact (clash_wrap_char q0 p0).elim
    | «assign» q0 q1 _ => exact (clash_assign_char q0 p0).elim
    | «level» q0 _ _ => exact (clash_level_char q0 p0).elim
    | «cast» q0 _ _ => exact (clash_cast_char q0 p0).elim
    | «neg» q0 _ => exact (clash_neg_char q0 p0).elim
    | «not» q0 _ => exact (clash_not_char q0 p0).elim
    | «postfix» q0 q1 _ => exact (clash_postfix_char q0 p0).elim
    | «member» q0 q1 _ => exact (clash_member_char q0 p0).elim
    | «group» q0 _ => exact (clash_group_char q0 p0).elim
    | «local» q0 q1 _ => exact (clash_local_char q0 p0).elim
    | «const» q0 q1 _ _ _ _ _ => exact (clash_const_char q0 p0).elim
    | «self» q0 _ => exact (clash_self_char q0 p0).elim
    | «int» q0 _ => exact (clash_int_char q0 p0).elim
    | «char» _ l' =>
      rw [charLiteral_unique l l']
    | «float» q0 _ => exact (clash_char_float p0 q0).elim
    | «true» q0 => exact (clash_char_true p0 q0).elim
    | «false» q0 => exact (clash_char_false p0 q0).elim
  | _, _, _, _, _, .float p0 l, h₂ => by
    cases h₂ with
    | «wrap» q0 _ => exact (clash_wrap_float q0 p0).elim
    | «assign» q0 q1 _ => exact (clash_assign_float q0 p0).elim
    | «level» q0 _ _ => exact (clash_level_float q0 p0).elim
    | «cast» q0 _ _ => exact (clash_cast_float q0 p0).elim
    | «neg» q0 _ => exact (clash_neg_float q0 p0).elim
    | «not» q0 _ => exact (clash_not_float q0 p0).elim
    | «postfix» q0 q1 _ => exact (clash_postfix_float q0 p0).elim
    | «member» q0 q1 _ => exact (clash_member_float q0 p0).elim
    | «group» q0 _ => exact (clash_group_float q0 p0).elim
    | «local» q0 q1 _ => exact (clash_local_float q0 p0).elim
    | «const» q0 q1 _ _ _ _ _ => exact (clash_const_float q0 p0).elim
    | «self» q0 _ => exact (clash_self_float q0 p0).elim
    | «int» q0 _ => exact (clash_int_float q0 p0).elim
    | «char» q0 _ => exact (clash_char_float q0 p0).elim
    | «float» _ l' =>
      rw [l] at l'
      cases l'
      rfl
    | «true» q0 => exact (clash_float_true p0 q0).elim
    | «false» q0 => exact (clash_float_false p0 q0).elim
  | _, _, _, _, _, .true p0, h₂ => by
    cases h₂ with
    | «wrap» q0 _ => exact (clash_wrap_true q0 p0).elim
    | «assign» q0 q1 _ => exact (clash_assign_true q0 p0).elim
    | «level» q0 _ _ => exact (clash_level_true q0 p0).elim
    | «cast» q0 _ _ => exact (clash_cast_true q0 p0).elim
    | «neg» q0 _ => exact (clash_neg_true q0 p0).elim
    | «not» q0 _ => exact (clash_not_true q0 p0).elim
    | «postfix» q0 q1 _ => exact (clash_postfix_true q0 p0).elim
    | «member» q0 q1 _ => exact (clash_member_true q0 p0).elim
    | «group» q0 _ => exact (clash_group_true q0 p0).elim
    | «local» q0 q1 _ => exact (clash_local_true q0 p0).elim
    | «const» q0 q1 _ _ _ _ _ => exact (clash_const_true q0 p0).elim
    | «self» q0 _ => exact (clash_self_true q0 p0).elim
    | «int» q0 _ => exact (clash_int_true q0 p0).elim
    | «char» q0 _ => exact (clash_char_true q0 p0).elim
    | «float» q0 _ => exact (clash_float_true q0 p0).elim
    | «true» _ =>
      rfl
    | «false» q0 => exact (clash_true_false p0 q0).elim
  | _, _, _, _, _, .false p0, h₂ => by
    cases h₂ with
    | «wrap» q0 _ => exact (clash_wrap_false q0 p0).elim
    | «assign» q0 q1 _ => exact (clash_assign_false q0 p0).elim
    | «level» q0 _ _ => exact (clash_level_false q0 p0).elim
    | «cast» q0 _ _ => exact (clash_cast_false q0 p0).elim
    | «neg» q0 _ => exact (clash_neg_false q0 p0).elim
    | «not» q0 _ => exact (clash_not_false q0 p0).elim
    | «postfix» q0 q1 _ => exact (clash_postfix_false q0 p0).elim
    | «member» q0 q1 _ => exact (clash_member_false q0 p0).elim
    | «group» q0 _ => exact (clash_group_false q0 p0).elim
    | «local» q0 q1 _ => exact (clash_local_false q0 p0).elim
    | «const» q0 q1 _ _ _ _ _ => exact (clash_const_false q0 p0).elim
    | «self» q0 _ => exact (clash_self_false q0 p0).elim
    | «int» q0 _ => exact (clash_int_false q0 p0).elim
    | «char» q0 _ => exact (clash_char_false q0 p0).elim
    | «float» q0 _ => exact (clash_float_false q0 p0).elim
    | «true» q0 => exact (clash_true_false q0 p0).elim
    | «false» _ =>
      rfl

theorem fold_unique : ∀ {env : FrontEnv} {scope : List Local} {acc : SrcExpr} {tail : CTree} {a b : SrcExpr},
    Fold env scope acc tail a → Fold env scope acc tail b → a = b
  | _, _, _, _, _, _, .done _, .done _ => rfl
  | _, _, _, _, _, _, .done e, .step e' .. => absurd e e'
  | _, _, _, _, _, _, .step e' .., .done e => absurd e e'
  | _, _, _, _, _, _, .step _ o r f, .step _ o' r' f' => by
    rw [o] at o'
    cases o'
    have e := exprR_unique r r'
    subst e
    exact fold_unique f f'

theorem constValue_unique : ∀ {decls : Decls} {k : ConstDecl} {a b : SrcExpr},
    ConstValue decls k a → ConstValue decls k b → a = b
  | _, _, _, _, .literal t r _ l, .literal t' r' _ l' => by
    rw [tyR_unique t t', exprR_unique r r'] at l
    exact typedLiteral_unique l l'
  | _, _, _, _, .literal _ r n _, .wide _ r' w _ => by
    rw [exprR_unique r r', w] at n
    cases n
  | _, _, _, _, .wide _ r w _, .literal _ r' n _ => by
    rw [exprR_unique r r', n] at w
    cases w
  | _, _, _, _, .wide t _ _ w, .wide t' _ _ w' => by
    rw [tyR_unique t t'] at w
    exact wideConst_unique w w'
end

end Lanius.Mini.Reading
