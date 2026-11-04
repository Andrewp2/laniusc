import Lanius.Faithful.SelfPre.CompileTypes
import Lanius.Faithful.SelfPre.Tactic
import Lanius.Faithful.SelfPre.LinCert
import Lanius.Mini.Compiler

/-! # Result types of the compile side's evaluator (F14)

`ts` bounds of the values the compiler computes from typed source: each
function's result type is one of its inputs' types or a scalar's (≤ 16 slots).
`val_SrcEff_eval` is the one the pre lemmas need (`eval_args` reads
`ts (SrcEff.eval ..)`); the other `val_` lemmas are the functions it reaches.
`Tactic.valueFacts` finds them by name.

`ts_auto` splits every `match`/`if` and closes each branch with the `val_`
facts of its calls and `omega_atoms`. The evaluator itself is a mutual
structural recursion over `SrcEff`/`List SrcEff`: its cases are stated apart
(`tsm_eval_*`, at a linear bound `M`), so that the recursion check sees only
small terms. -/

namespace Lanius.Faithful.SelfPre
open Lanius.Mini

/-- `ts` of the `some` equations: `ts (F xs) = ts v` for `h : F xs = some v`. -/
theorem ts_of_eq_some {α : Type} [TS α] {o : Option α} {v : α} (h : o = some v) : ts o = ts v := by
  rw [h]; rfl

open Lean Elab Tactic Meta in
elab "ts_close" : tactic => do
  -- the goal's `let`s and `ts`s first, so that the facts below see its calls
  evalTactic (← `(tactic| try simp only [ts_simp, ts_list_SrcType, ts_list_list_SrcType] at ⊢))
  Lanius.Faithful.SelfPre.Tactic.valueFacts
  -- the `some` equations
  withMainContext do
    let mut g ← getMainGoal
    for d in ← getLCtx do
      if d.isImplementationDetail then continue
      let t ← instantiateMVars d.type
      let some (_, _, r) := t.eq? | continue
      unless r.isAppOfArity ``Option.some 2 do continue
      let p ← try some <$> mkAppM ``ts_of_eq_some #[d.toExpr] catch _ => pure none
      let some p := p | continue
      let (_, g') ← (← g.assert `hts (← inferType p) p).intro1P
      g := g'
    replaceMainGoal [g]
  evalTactic (← `(tactic| try simp only [ts_simp, ts_list_SrcType, ts_list_list_SrcType, tySlots, tySlotsList,
    tySlotsVariants, SrcType.size, sizes, maxSize] at *))
  evalTactic (← `(tactic| omega_atoms))

macro "ts_auto" : tactic => `(tactic| (repeat' split) <;> ts_close)

theorem val_armScope (binders : List Nat) (types : List SrcType) (slot : Nat) (scope : List Binding) :
    ts (armScope binders types slot scope) ≤ max (ts types) (max (ts scope) 16) := by
  fun_induction armScope binders types slot scope <;> ts_auto

theorem val_arithSint (operation : BinOp) (left : Typed) (right : Typed) (kind : Option UintTy) :
    ts (arithSint operation left right kind) ≤ max (ts left) (max (ts right) 16) := by
  unfold arithSint; ts_auto

theorem val_arithUint (operation : BinOp) (left : Typed) (right : Typed) (kind : Option UintTy) :
    ts (arithUint operation left right kind) ≤ max (ts left) (max (ts right) 16) := by
  unfold arithUint; ts_auto

theorem val_floatApply (operation : Option FArith) (t : FloatTy) (left : Typed) (right : Typed) :
    ts (floatApply operation t left right) ≤ max (ts left) (max (ts right) 16) := by
  unfold floatApply; ts_auto

theorem val_floatArith (operation : BinOp) (left : Typed) (right : Typed) (kind : Option FloatTy) :
    ts (floatArith operation left right kind) ≤ max (ts left) (max (ts right) 16) := by
  unfold floatArith; ts_auto

theorem val_arith (operation : BinOp) (left : Typed) (right : Typed) :
    ts (arith operation left right) ≤ max (ts left) (max (ts right) 16) := by
  unfold arith; ts_auto

theorem val_lowerShift (operation : BinOp) (left : Typed) (right : Typed) :
    ts (lowerShift operation left right) ≤ max (ts left) (max (ts right) 16) := by
  unfold lowerShift; ts_auto

theorem val_arithShiftRight (left : Typed) (right : Typed) :
    ts (arithShiftRight left right) ≤ max (ts left) (max (ts right) 16) := by
  unfold arithShiftRight; ts_auto

theorem val_conjunction (left : Typed) (right : Typed) :
    ts (conjunction left right) ≤ max (ts left) (max (ts right) 16) := by
  unfold conjunction; ts_auto

theorem val_disjunction (left : Typed) (right : Typed) :
    ts (disjunction left right) ≤ max (ts left) (max (ts right) 16) := by
  unfold disjunction; ts_auto

theorem val_floatOrder (operation : CmpOp) (left : Typed) (right : Typed) (kind : Option FloatTy) :
    ts (floatOrder operation left right kind) ≤ max (ts left) (max (ts right) 16) := by
  unfold floatOrder; ts_auto

theorem val_equality (operation : CmpOp) (left : Typed) (right : Typed) :
    ts (equality operation left right) ≤ max (ts left) (max (ts right) 16) := by
  unfold equality; ts_auto

theorem val_offsetOrArith (operation : BinOp) (left : Typed) (right : Typed) :
    ts (offsetOrArith operation left right) ≤ max (ts left) (max (ts right) 16) := by
  unfold offsetOrArith; ts_auto

theorem val_orderSint (operation : CmpOp) (left : Typed) (right : Typed) (kind : Option UintTy) :
    ts (orderSint operation left right kind) ≤ max (ts left) (max (ts right) 16) := by
  unfold orderSint; ts_auto

theorem val_orderUint (operation : CmpOp) (left : Typed) (right : Typed) (kind : Option UintTy) :
    ts (orderUint operation left right kind) ≤ max (ts left) (max (ts right) 16) := by
  unfold orderUint; ts_auto

theorem val_order (operation : CmpOp) (left : Typed) (right : Typed) :
    ts (order operation left right) ≤ max (ts left) (max (ts right) 16) := by
  unfold order; ts_auto

theorem val_SrcOp_lower (self : SrcOp) (left : Typed) (right : Typed) :
    ts (SrcOp.lower self left right) ≤ max (ts left) (max (ts right) 16) := by
  unfold SrcOp.lower; ts_auto

theorem val_evalOperands (op : SrcOp) (slot : Nat) (l : Evaluated) (r : Evaluated) :
    ts (evalOperands op slot l r) ≤ max (ts l) (max (ts r) 16) := by
  unfold evalOperands; ts_auto

theorem val_evalApply (op : SrcOp) (slot : Nat) (left : Option Evaluated) (right : Option Evaluated) :
    ts (evalApply op slot left right) ≤ max (ts left) (max (ts right) 16) := by
  unfold evalApply; ts_auto

theorem val_consArgs (first : Evaluated) (rest : Option EvaluatedArgs) :
    ts (consArgs first rest) ≤ max (ts first) (max (ts rest) 16) := by
  unfold consArgs; ts_auto

theorem val_paramTypes (params : List SrcParam) :
    ts (paramTypes params) ≤ max (ts params) 16 := by
  fun_induction paramTypes params <;> ts_auto

theorem val_sigsWith (funcs : List SrcFunc) (needs : List Nat) :
    ts (sigsWith funcs needs) ≤ max (ts funcs) 16 := by
  fun_induction sigsWith funcs needs <;> ts_auto

theorem val_evalCallSig (sig : Sig) (callee : Nat) (slot : Nat) (args : EvaluatedArgs) :
    ts (evalCallSig sig callee slot args) ≤ max (ts sig) (max (ts args) 16) := by
  unfold evalCallSig; ts_auto

theorem val_evalHostText (callee : Nat) (slot : Nat) (args : EvaluatedArgs) :
    ts (evalHostText callee slot args) ≤ max (ts args) 16 := by
  unfold evalHostText; ts_auto

theorem val_evalHost (callee : Nat) (slot : Nat) (args : EvaluatedArgs) :
    ts (evalHost callee slot args) ≤ max (ts args) 16 := by
  unfold evalHost; ts_auto

theorem val_evalCall (sig : Option Sig) (callee : Nat) (slot : Nat) (args : Option EvaluatedArgs) :
    ts (evalCall sig callee slot args) ≤ max (ts sig) (max (ts args) 16) := by
  unfold evalCall; ts_auto

theorem val_evalThen (slot : Nat) (operand : Evaluated) (t : Option Typed) :
    ts (evalThen slot operand t) ≤ max (ts operand) (max (ts t) 16) := by
  unfold evalThen; ts_auto

theorem val_floatToFloat (t : FloatTy) (source : FloatTy) (e : Expr) :
    ts (floatToFloat t source e) ≤ 16 := by
  unfold floatToFloat; ts_auto

theorem val_ifNarrow (kind : UintTy) (t : Option Typed) :
    ts (ifNarrow kind t) ≤ max (ts t) 16 := by
  unfold ifNarrow; ts_auto

theorem val_intToFloat (t : FloatTy) (word : Word) (e : Expr) :
    ts (intToFloat t word e) ≤ 16 := by
  unfold intToFloat; ts_auto

theorem val_castToFloat (t : FloatTy) (e : Typed) :
    ts (castToFloat t e) ≤ max (ts e) 16 := by
  unfold castToFloat; ts_auto

theorem val_castToI32 (e : Typed) :
    ts (castToI32 e) ≤ max (ts e) 16 := by
  unfold castToI32; ts_auto

theorem val_castToIsize (e : Typed) :
    ts (castToIsize e) ≤ max (ts e) 16 := by
  unfold castToIsize; ts_auto

theorem val_castToSint (kind : UintTy) (e : Typed) :
    ts (castToSint kind e) ≤ max (ts e) 16 := by
  unfold castToSint; ts_auto

theorem val_castToUint (kind : UintTy) (e : Typed) :
    ts (castToUint kind e) ≤ max (ts e) 16 := by
  unfold castToUint; ts_auto

theorem val_castTo (ty : SrcType) (e : Typed) :
    ts (castTo ty e) ≤ max (ts ty) (max (ts e) 16) := by
  unfold castTo; ts_auto

theorem val_scalarCast (ty : SrcType) (operand : Typed) :
    ts (scalarCast ty operand) ≤ max (ts ty) (max (ts operand) 16) := by
  unfold scalarCast; ts_auto

theorem val_evalCast (ty : SrcType) (slot : Nat) (operand : Option Evaluated) :
    ts (evalCast ty slot operand) ≤ max (ts ty) (max (ts operand) 16) := by
  unfold evalCast; ts_auto

theorem val_evalDivideSint (op : SrcDivOp) (slot : Nat) (l : Evaluated) (r : Evaluated) (k : UintTy) :
    ts (evalDivideSint op slot l r k) ≤ max (ts l) (max (ts r) 16) := by
  unfold evalDivideSint; ts_auto

theorem val_evalDivideUint (op : SrcDivOp) (slot : Nat) (l : Evaluated) (r : Evaluated) (k : UintTy) :
    ts (evalDivideUint op slot l r k) ≤ max (ts l) (max (ts r) 16) := by
  unfold evalDivideUint; ts_auto

theorem val_evalDivide (op : SrcDivOp) (slot : Nat) (l : Evaluated) (r : Evaluated) :
    ts (evalDivide op slot l r) ≤ max (ts l) (max (ts r) 16) := by
  unfold evalDivide; ts_auto

theorem val_evalDivision (op : SrcDivOp) (slot : Nat) (left : Option Evaluated) (right : Option Evaluated) :
    ts (evalDivision op slot left right) ≤ max (ts left) (max (ts right) 16) := by
  unfold evalDivision; ts_auto

theorem val_evalIfOf (slot : Nat) (ty : SrcType) (c : Evaluated) (t : Evaluated) (e : Evaluated) :
    ts (evalIfOf slot ty c t e) ≤ max (ts ty) (max (ts c) (max (ts t) (max (ts e) 16))) := by
  unfold evalIfOf; ts_auto

theorem val_evalIf (slot : Nat) (ty : SrcType) (condition : Option Evaluated) (thenValue : Option Evaluated) (elseValue : Option Evaluated) :
    ts (evalIf slot ty condition thenValue elseValue) ≤ max (ts ty) (max (ts condition) (max (ts thenValue) (max (ts elseValue) 16))) := by
  unfold evalIf; ts_auto

theorem val_evalPick (base : Nat) (element : SrcType) (count : Nat) (slot : Nat) (i : Evaluated) :
    ts (evalPick base element count slot i) ≤ max (ts element) (max (ts i) 16) := by
  unfold evalPick; ts_auto

theorem val_evalArrayElement (base : Nat) (element : SrcType) (count : Nat) (slot : Nat) (index : Option Evaluated) :
    ts (evalArrayElement base element count slot index) ≤ max (ts element) (max (ts index) 16) := by
  unfold evalArrayElement; ts_auto

theorem val_evalArrayIndex (b : Binding) (slot : Nat) (index : Option Evaluated) :
    ts (evalArrayIndex b slot index) ≤ max (ts b) (max (ts index) 16) := by
  unfold evalArrayIndex; ts_auto

theorem val_evalLoad (b : Binding) (slot : Nat) (i : Evaluated) :
    ts (evalLoad b slot i) ≤ max (ts b) (max (ts i) 16) := by
  unfold evalLoad; ts_auto

theorem val_evalLoadByte (b : Binding) (slot : Nat) (i : Evaluated) :
    ts (evalLoadByte b slot i) ≤ max (ts b) (max (ts i) 16) := by
  unfold evalLoadByte; ts_auto

theorem val_evalWordElement (decls : SrcDecls) (b : Binding) (element : SrcType) (slot : Nat) (i : Evaluated) :
    ts (evalWordElement decls b element slot i) ≤ max (ts decls) (max (ts b) (max (ts element) (max (ts i) 16))) := by
  unfold evalWordElement; ts_auto

theorem val_evalElement (decls : SrcDecls) (b : Binding) (element : SrcType) (slot : Nat) (index : Option Evaluated) :
    ts (evalElement decls b element slot index) ≤ max (ts decls) (max (ts b) (max (ts element) (max (ts index) 16))) := by
  unfold evalElement; ts_auto

theorem val_evalIndex (decls : SrcDecls) (scope : List Binding) (slice : Nat) (slot : Nat) (index : Option Evaluated) :
    ts (evalIndex decls scope slice slot index) ≤ max (ts decls) (max (ts scope) (max (ts index) 16)) := by
  unfold evalIndex; ts_auto

theorem val_evalLenOf (b : Binding) (slot : Nat) :
    ts (evalLenOf b slot) ≤ max (ts b) 16 := by
  unfold evalLenOf; ts_auto

theorem val_evalLen (scope : List Binding) (slice : Nat) (slot : Nat) :
    ts (evalLen scope slice slot) ≤ max (ts scope) 16 := by
  unfold evalLen; ts_auto

theorem val_evalLetInOf (slot : Nat) (ty : SrcType) (rt : SrcType) (v : Evaluated) (b : Evaluated) :
    ts (evalLetInOf slot ty rt v b) ≤ max (ts ty) (max (ts rt) (max (ts v) (max (ts b) 16))) := by
  unfold evalLetInOf; ts_auto

theorem val_evalLetIn (slot : Nat) (ty : SrcType) (rt : SrcType) (value : Option Evaluated) (body : Option Evaluated) :
    ts (evalLetIn slot ty rt value body) ≤ max (ts ty) (max (ts rt) (max (ts value) (max (ts body) 16))) := by
  unfold evalLetIn; ts_auto

theorem val_evalMatchOf (slot : Nat) (ety : SrcType) (ty : SrcType) (s : Evaluated) (arms : Stmt) (binders : Nat) (values : Nat) :
    ts (evalMatchOf slot ety ty s arms binders values) ≤ max (ts ety) (max (ts ty) (max (ts s) 16)) := by
  unfold evalMatchOf; ts_auto

theorem val_evalMatch (slot : Nat) (ety : SrcType) (ty : SrcType) (scrutinee : Option Evaluated) (arms : Option Stmt) (binders : Nat) (values : Nat) :
    ts (evalMatch slot ety ty scrutinee arms binders values) ≤ max (ts ety) (max (ts ty) (max (ts scrutinee) 16)) := by
  unfold evalMatch; ts_auto

theorem val_negateFloat (operand : Typed) (kind : Option FloatTy) :
    ts (negateFloat operand kind) ≤ max (ts operand) 16 := by
  unfold negateFloat; ts_auto

theorem val_lowerNegateTyped (operand : Typed) :
    ts (lowerNegateTyped operand) ≤ max (ts operand) 16 := by
  unfold lowerNegateTyped; ts_auto

theorem val_evalNegate (slot : Nat) (operand : Option Evaluated) :
    ts (evalNegate slot operand) ≤ max (ts operand) 16 := by
  unfold evalNegate; ts_auto

theorem val_lowerNotTyped (operand : Typed) :
    ts (lowerNotTyped operand) ≤ max (ts operand) 16 := by
  unfold lowerNotTyped; ts_auto

theorem val_evalNot (slot : Nat) (operand : Option Evaluated) :
    ts (evalNot slot operand) ≤ max (ts operand) 16 := by
  unfold evalNot; ts_auto

theorem val_lowerApply (op : SrcOp) (left : Option Typed) (right : Option Typed) :
    ts (lowerApply op left right) ≤ max (ts left) (max (ts right) 16) := by
  unfold lowerApply; ts_auto

theorem val_lowerCast (ty : SrcType) (operand : Option Typed) :
    ts (lowerCast ty operand) ≤ max (ts ty) (max (ts operand) 16) := by
  unfold lowerCast; ts_auto

theorem val_lowerFieldAt (slot : Nat) (found : Option SrcType) :
    ts (lowerFieldAt slot found) ≤ max (ts found) 16 := by
  unfold lowerFieldAt; ts_auto

theorem val_lowerFieldOf (b : Binding) (field : Nat) :
    ts (lowerFieldOf b field) ≤ max (ts b) 16 := by
  unfold lowerFieldOf; ts_auto

theorem val_lowerField (binding : Option Binding) (field : Nat) :
    ts (lowerField binding field) ≤ max (ts binding) 16 := by
  unfold lowerField; ts_auto

theorem val_lowerFloat (t : FloatTy) (bits : BitVec 64) :
    ts (lowerFloat t bits) ≤ 16 := by
  unfold lowerFloat; ts_auto

theorem val_lowerScalarLocal (b : Binding) :
    ts (lowerScalarLocal b) ≤ max (ts b) 16 := by
  unfold lowerScalarLocal; ts_auto

theorem val_lowerLocal (binding : Option Binding) :
    ts (lowerLocal binding) ≤ max (ts binding) 16 := by
  unfold lowerLocal; ts_auto

theorem val_lowerNegate (operand : Option Typed) :
    ts (lowerNegate operand) ≤ max (ts operand) 16 := by
  unfold lowerNegate; ts_auto

theorem val_lowerNot (operand : Option Typed) :
    ts (lowerNot operand) ≤ max (ts operand) 16 := by
  unfold lowerNot; ts_auto

theorem val_lowerUnsigned (kind : UintTy) (value : BitVec 64) :
    ts (lowerUnsigned kind value) ≤ 16 := by
  unfold lowerUnsigned; ts_auto

theorem val_SrcExpr_lower (self : SrcExpr) (scope : List Binding) :
    ts (SrcExpr.lower self scope) ≤ max (ts self) (max (ts scope) 16) := by
  fun_induction SrcExpr.lower self scope <;> ts_auto

theorem val_evalChecked (slot : Nat) (g : Expr) (t : Typed) :
    ts (evalChecked slot g t) ≤ max (ts t) 16 := by
  unfold evalChecked; ts_auto

theorem val_evalValues (slot : Nat) (ty : SrcType) (values : Option (List Expr)) :
    ts (evalValues slot ty values) ≤ max (ts ty) 16 := by
  unfold evalValues; ts_auto

theorem val_evalCopy (scope : List Binding) (e : SrcExpr) (slot : Nat) (binding : Option Binding) :
    ts (evalCopy scope e slot binding) ≤ max (ts scope) (max (ts e) (max (ts binding) 16)) := by
  unfold evalCopy; ts_auto

theorem val_evalFieldType (scope : List Binding) (e : SrcExpr) (slot : Nat) (found : Option SrcType) :
    ts (evalFieldType scope e slot found) ≤ max (ts scope) (max (ts e) (max (ts found) 16)) := by
  unfold evalFieldType; ts_auto

theorem val_evalFieldOf (scope : List Binding) (e : SrcExpr) (slot : Nat) (b : Binding) (index : Nat) :
    ts (evalFieldOf scope e slot b index) ≤ max (ts scope) (max (ts e) (max (ts b) 16)) := by
  unfold evalFieldOf; ts_auto

theorem val_evalFieldCopy (scope : List Binding) (e : SrcExpr) (slot : Nat) (binding : Option Binding) (index : Nat) :
    ts (evalFieldCopy scope e slot binding index) ≤ max (ts scope) (max (ts e) (max (ts binding) 16)) := by
  unfold evalFieldCopy; ts_auto

theorem val_evalPure (scope : List Binding) (e : SrcExpr) (slot : Nat) :
    ts (evalPure scope e slot) ≤ max (ts scope) (max (ts e) 16) := by
  unfold evalPure; ts_auto

theorem val_evalStr (decls : SrcDecls) (offset : Nat) (chars : List Nat) (slot : Nat) :
    ts (evalStr decls offset chars slot) ≤ max (ts decls) 16 := by
  unfold evalStr; ts_auto

theorem val_wordStride (slot : Nat) (words : Nat) :
    ts (wordStride slot words) ≤ 16 := by
  unfold wordStride; ts_auto

theorem val_evalWordStride (decls : SrcDecls) (element : SrcType) (slot : Nat) :
    ts (evalWordStride decls element slot) ≤ max (ts decls) (max (ts element) 16) := by
  unfold evalWordStride; ts_auto

theorem val_evalStrideOf (decls : SrcDecls) (element : SrcType) (slot : Nat) :
    ts (evalStrideOf decls element slot) ≤ max (ts decls) (max (ts element) 16) := by
  unfold evalStrideOf; ts_auto

theorem val_evalStride (decls : SrcDecls) (scope : List Binding) (slice : Nat) (slot : Nat) :
    ts (evalStride decls scope slice slot) ≤ max (ts decls) (max (ts scope) 16) := by
  unfold evalStride; ts_auto

theorem val_evalStructOf (ty : SrcType) (types : List SrcType) (args : EvaluatedArgs) :
    ts (evalStructOf ty types args) ≤ max (ts ty) (max (ts types) (max (ts args) 16)) := by
  unfold evalStructOf; ts_auto

theorem val_evalStruct (ty : SrcType) (args : Option EvaluatedArgs) :
    ts (evalStruct ty args) ≤ max (ts ty) (max (ts args) 16) := by
  unfold evalStruct; ts_auto

theorem val_evalPayload (ty : SrcType) (types : List SrcType) (variant : Nat) (slot : Nat) (args : EvaluatedArgs) :
    ts (evalPayload ty types variant slot args) ≤ max (ts ty) (max (ts types) (max (ts args) 16)) := by
  unfold evalPayload; ts_auto

theorem val_evalTagged (ty : SrcType) (variants : List (List SrcType)) (variant : Nat) (slot : Nat) (args : EvaluatedArgs) :
    ts (evalTagged ty variants variant slot args) ≤ max (ts ty) (max (ts variants) (max (ts args) 16)) := by
  unfold evalTagged; ts_auto

theorem val_evalVariant (ty : SrcType) (variant : Nat) (slot : Nat) (args : Option EvaluatedArgs) :
    ts (evalVariant ty variant slot args) ≤ max (ts ty) (max (ts args) 16) := by
  unfold evalVariant; ts_auto


/-! The evaluator, at a bound `M` of its inputs' types (linear for `omega`; `val_SrcEff_eval`
below states it as a `max`). Each case apart, its recursive calls' bounds as hypotheses, so
that the mutual theorem's structural recursion checks only small terms. -/

theorem tsm_eval_ePure (e : SrcExpr) (sigs : List Sig) (decls : SrcDecls) (scope : List Binding) (slot : Nat) (M : Nat) (hs : ts sigs ≤ M) (hd : ts decls ≤ M) (hc : ts scope ≤ M) (h16 : 16 ≤ M) (he : ts (SrcEff.ePure e) ≤ M) :
    ts (SrcEff.eval (SrcEff.ePure e) sigs decls scope slot) ≤ M := by
  simp only [ts_simp, ts_list_SrcType, ts_list_list_SrcType, Nat.max_le] at he
  rw [SrcEff.eval]; ts_auto

theorem tsm_eval_eCall (callee : Nat) (args : List SrcEff) (sigs : List Sig) (decls : SrcDecls) (scope : List Binding) (slot : Nat) (M : Nat) (hs : ts sigs ≤ M) (hd : ts decls ≤ M) (hc : ts scope ≤ M) (h16 : 16 ≤ M) (he : ts (SrcEff.eCall callee args) ≤ M) (a0 : ts args ≤ M → ts (evalArgs sigs decls scope args slot) ≤ M) :
    ts (SrcEff.eval (SrcEff.eCall callee args) sigs decls scope slot) ≤ M := by
  simp only [ts_simp, ts_list_SrcType, ts_list_list_SrcType, Nat.max_le] at he
  have := a0 (by omega)
  rw [SrcEff.eval]; ts_auto

theorem tsm_eval_eApply (op : SrcOp) (left right : SrcEff) (sigs : List Sig) (decls : SrcDecls) (scope : List Binding) (slot : Nat) (M : Nat) (hs : ts sigs ≤ M) (hd : ts decls ≤ M) (hc : ts scope ≤ M) (h16 : 16 ≤ M) (he : ts (SrcEff.eApply op left right) ≤ M) (i0 : ts left ≤ M → ts (SrcEff.eval left sigs decls scope slot) ≤ M) (i1 : ts right ≤ M → ts (SrcEff.eval right sigs decls scope (slot + 1)) ≤ M) :
    ts (SrcEff.eval (SrcEff.eApply op left right) sigs decls scope slot) ≤ M := by
  simp only [ts_simp, ts_list_SrcType, ts_list_list_SrcType, Nat.max_le] at he
  have := i0 (by omega)
  have := i1 (by omega)
  rw [SrcEff.eval]; ts_auto

theorem tsm_eval_eNeg (operand : SrcEff) (sigs : List Sig) (decls : SrcDecls) (scope : List Binding) (slot : Nat) (M : Nat) (hs : ts sigs ≤ M) (hd : ts decls ≤ M) (hc : ts scope ≤ M) (h16 : 16 ≤ M) (he : ts (SrcEff.eNeg operand) ≤ M) (i0 : ts operand ≤ M → ts (SrcEff.eval operand sigs decls scope slot) ≤ M) :
    ts (SrcEff.eval (SrcEff.eNeg operand) sigs decls scope slot) ≤ M := by
  simp only [ts_simp, ts_list_SrcType, ts_list_list_SrcType, Nat.max_le] at he
  have := i0 (by omega)
  rw [SrcEff.eval]; ts_auto

theorem tsm_eval_eNot (operand : SrcEff) (sigs : List Sig) (decls : SrcDecls) (scope : List Binding) (slot : Nat) (M : Nat) (hs : ts sigs ≤ M) (hd : ts decls ≤ M) (hc : ts scope ≤ M) (h16 : 16 ≤ M) (he : ts (SrcEff.eNot operand) ≤ M) (i0 : ts operand ≤ M → ts (SrcEff.eval operand sigs decls scope slot) ≤ M) :
    ts (SrcEff.eval (SrcEff.eNot operand) sigs decls scope slot) ≤ M := by
  simp only [ts_simp, ts_list_SrcType, ts_list_list_SrcType, Nat.max_le] at he
  have := i0 (by omega)
  rw [SrcEff.eval]; ts_auto

theorem tsm_eval_eCast (ty : SrcType) (operand : SrcEff) (sigs : List Sig) (decls : SrcDecls) (scope : List Binding) (slot : Nat) (M : Nat) (hs : ts sigs ≤ M) (hd : ts decls ≤ M) (hc : ts scope ≤ M) (h16 : 16 ≤ M) (he : ts (SrcEff.eCast ty operand) ≤ M) (i0 : ts operand ≤ M → ts (SrcEff.eval operand sigs decls scope slot) ≤ M) :
    ts (SrcEff.eval (SrcEff.eCast ty operand) sigs decls scope slot) ≤ M := by
  simp only [ts_simp, ts_list_SrcType, ts_list_list_SrcType, Nat.max_le] at he
  have := i0 (by omega)
  rw [SrcEff.eval]; ts_auto

theorem tsm_eval_eIndex (slice : Nat) (index : SrcEff) (sigs : List Sig) (decls : SrcDecls) (scope : List Binding) (slot : Nat) (M : Nat) (hs : ts sigs ≤ M) (hd : ts decls ≤ M) (hc : ts scope ≤ M) (h16 : 16 ≤ M) (he : ts (SrcEff.eIndex slice index) ≤ M) (i0 : ts index ≤ M → ts (SrcEff.eval index sigs decls scope slot) ≤ M) :
    ts (SrcEff.eval (SrcEff.eIndex slice index) sigs decls scope slot) ≤ M := by
  simp only [ts_simp, ts_list_SrcType, ts_list_list_SrcType, Nat.max_le] at he
  have := i0 (by omega)
  rw [SrcEff.eval]; ts_auto

theorem tsm_eval_eStruct (ty : SrcType) (fields : List SrcEff) (sigs : List Sig) (decls : SrcDecls) (scope : List Binding) (slot : Nat) (M : Nat) (hs : ts sigs ≤ M) (hd : ts decls ≤ M) (hc : ts scope ≤ M) (h16 : 16 ≤ M) (he : ts (SrcEff.eStruct ty fields) ≤ M) (a0 : ts fields ≤ M → ts (evalArgs sigs decls scope fields slot) ≤ M) :
    ts (SrcEff.eval (SrcEff.eStruct ty fields) sigs decls scope slot) ≤ M := by
  simp only [ts_simp, ts_list_SrcType, ts_list_list_SrcType, Nat.max_le] at he
  have := a0 (by omega)
  rw [SrcEff.eval]; ts_auto

theorem tsm_eval_eVariant (ty : SrcType) (variant : Nat) (payload : List SrcEff) (sigs : List Sig) (decls : SrcDecls) (scope : List Binding) (slot : Nat) (M : Nat) (hs : ts sigs ≤ M) (hd : ts decls ≤ M) (hc : ts scope ≤ M) (h16 : 16 ≤ M) (he : ts (SrcEff.eVariant ty variant payload) ≤ M) (a0 : ts payload ≤ M → ts (evalArgs sigs decls scope payload (slot + 1)) ≤ M) :
    ts (SrcEff.eval (SrcEff.eVariant ty variant payload) sigs decls scope slot) ≤ M := by
  simp only [ts_simp, ts_list_SrcType, ts_list_list_SrcType, Nat.max_le] at he
  have := a0 (by omega)
  rw [SrcEff.eval]; ts_auto

theorem tsm_eval_eMatch (scrutinee : SrcEff) (ety ty : SrcType) (binders : List (List Nat)) (values : List SrcEff) (sigs : List Sig) (decls : SrcDecls) (scope : List Binding) (slot : Nat) (M : Nat) (hs : ts sigs ≤ M) (hd : ts decls ≤ M) (hc : ts scope ≤ M) (h16 : 16 ≤ M) (he : ts (SrcEff.eMatch scrutinee ety ty binders values) ≤ M) (i0 : ts scrutinee ≤ M → ts (SrcEff.eval scrutinee sigs decls scope slot) ≤ M) :
    ts (SrcEff.eval (SrcEff.eMatch scrutinee ety ty binders values) sigs decls scope slot) ≤ M := by
  simp only [ts_simp, ts_list_SrcType, ts_list_list_SrcType, Nat.max_le] at he
  have := i0 (by omega)
  rw [SrcEff.eval]; ts_auto

theorem tsm_eval_eDivide (op : SrcDivOp) (left right : SrcEff) (sigs : List Sig) (decls : SrcDecls) (scope : List Binding) (slot : Nat) (M : Nat) (hs : ts sigs ≤ M) (hd : ts decls ≤ M) (hc : ts scope ≤ M) (h16 : 16 ≤ M) (he : ts (SrcEff.eDivide op left right) ≤ M) (i0 : ts left ≤ M → ts (SrcEff.eval left sigs decls scope slot) ≤ M) (i1 : ts right ≤ M → ts (SrcEff.eval right sigs decls scope (slot + 1)) ≤ M) :
    ts (SrcEff.eval (SrcEff.eDivide op left right) sigs decls scope slot) ≤ M := by
  simp only [ts_simp, ts_list_SrcType, ts_list_list_SrcType, Nat.max_le] at he
  have := i0 (by omega)
  have := i1 (by omega)
  rw [SrcEff.eval]; ts_auto

theorem tsm_eval_eStride (slice : Nat) (sigs : List Sig) (decls : SrcDecls) (scope : List Binding) (slot : Nat) (M : Nat) (hs : ts sigs ≤ M) (hd : ts decls ≤ M) (hc : ts scope ≤ M) (h16 : 16 ≤ M) (he : ts (SrcEff.eStride slice) ≤ M) :
    ts (SrcEff.eval (SrcEff.eStride slice) sigs decls scope slot) ≤ M := by
  simp only [ts_simp, ts_list_SrcType, ts_list_list_SrcType, Nat.max_le] at he
  rw [SrcEff.eval]; ts_auto

theorem tsm_eval_arraySlice (element : SrcType) (array : Nat) (sigs : List Sig) (decls : SrcDecls) (scope : List Binding) (slot : Nat) (M : Nat) (hs : ts sigs ≤ M) (hd : ts decls ≤ M) (hc : ts scope ≤ M) (h16 : 16 ≤ M) (he : ts (SrcEff.arraySlice element array) ≤ M) :
    ts (SrcEff.eval (SrcEff.arraySlice element array) sigs decls scope slot) ≤ M := by
  simp only [ts_simp, ts_list_SrcType, ts_list_list_SrcType, Nat.max_le] at he
  rw [SrcEff.eval]; ts_auto

theorem tsm_eval_eIf (condition : SrcEff) (ty : SrcType) (thenValue elseValue : SrcEff) (sigs : List Sig) (decls : SrcDecls) (scope : List Binding) (slot : Nat) (M : Nat) (hs : ts sigs ≤ M) (hd : ts decls ≤ M) (hc : ts scope ≤ M) (h16 : 16 ≤ M) (he : ts (SrcEff.eIf condition ty thenValue elseValue) ≤ M) (i0 : ts condition ≤ M → ts (SrcEff.eval condition sigs decls scope slot) ≤ M) (i1 : ts thenValue ≤ M → ts (SrcEff.eval thenValue sigs decls scope slot) ≤ M) (i2 : ts elseValue ≤ M → ts (SrcEff.eval elseValue sigs decls scope slot) ≤ M) :
    ts (SrcEff.eval (SrcEff.eIf condition ty thenValue elseValue) sigs decls scope slot) ≤ M := by
  simp only [ts_simp, ts_list_SrcType, ts_list_list_SrcType, Nat.max_le] at he
  have := i0 (by omega)
  have := i1 (by omega)
  have := i2 (by omega)
  rw [SrcEff.eval]; ts_auto

theorem tsm_eval_eLet (id : Nat) (ty : SrcType) (value : SrcEff) (rt : SrcType) (body : SrcEff) (sigs : List Sig) (decls : SrcDecls) (scope : List Binding) (slot : Nat) (M : Nat) (hs : ts sigs ≤ M) (hd : ts decls ≤ M) (hc : ts scope ≤ M) (h16 : 16 ≤ M) (he : ts (SrcEff.eLet id ty value rt body) ≤ M) (i0 : ts value ≤ M → ts (SrcEff.eval value sigs decls scope slot) ≤ M) (ib : ∀ s d, ts body ≤ M → ts s ≤ M → ts (SrcEff.eval body sigs decls s d) ≤ M) :
    ts (SrcEff.eval (SrcEff.eLet id ty value rt body) sigs decls scope slot) ≤ M := by
  simp only [ts_simp, ts_list_SrcType, ts_list_list_SrcType, Nat.max_le] at he
  have := i0 (by omega)
  have hsc := val_armScope [id] [ty] slot scope
  rw [SrcEff.eval]
  refine Nat.le_trans (val_evalLetIn _ _ _ _ _) ?_
  dsimp only
  split
  · simp only [ts_none, ts_SrcType] at *; omega_atoms
  · rename_i s h
    rw [h] at hsc
    simp only [ts_some, ts_cons, ts_nil, ts_SrcType] at hsc ⊢
    have := ib s (matchDst slot ty rt) (by omega) (by omega_atoms)
    omega_atoms

theorem tsm_eval_eLen (slice : Nat) (sigs : List Sig) (decls : SrcDecls) (scope : List Binding) (slot : Nat) (M : Nat) (hs : ts sigs ≤ M) (hd : ts decls ≤ M) (hc : ts scope ≤ M) (h16 : 16 ≤ M) (he : ts (SrcEff.eLen slice) ≤ M) :
    ts (SrcEff.eval (SrcEff.eLen slice) sigs decls scope slot) ≤ M := by
  simp only [ts_simp, ts_list_SrcType, ts_list_list_SrcType, Nat.max_le] at he
  rw [SrcEff.eval]; ts_auto

theorem tsm_eval_eStr (offset : Nat) (chars : List Nat) (sigs : List Sig) (decls : SrcDecls) (scope : List Binding) (slot : Nat) (M : Nat) (hs : ts sigs ≤ M) (hd : ts decls ≤ M) (hc : ts scope ≤ M) (h16 : 16 ≤ M) (he : ts (SrcEff.eStr offset chars) ≤ M) :
    ts (SrcEff.eval (SrcEff.eStr offset chars) sigs decls scope slot) ≤ M := by
  simp only [ts_simp, ts_list_SrcType, ts_list_list_SrcType, Nat.max_le] at he
  rw [SrcEff.eval]; ts_auto

theorem tsm_evalArgs_nil (sigs : List Sig) (decls : SrcDecls) (scope : List Binding) (slot : Nat) (M : Nat)
    (h16 : 16 ≤ M) : ts (evalArgs sigs decls scope [] slot) ≤ M := by
  rw [evalArgs]; ts_auto

theorem tsm_evalArgs_cons (sigs : List Sig) (decls : SrcDecls) (scope : List Binding) (arg : SrcEff) (rest : List SrcEff)
    (slot : Nat) (M : Nat) (h16 : 16 ≤ M) (he : ts (arg :: rest) ≤ M)
    (i0 : ts arg ≤ M → ts (SrcEff.eval arg sigs decls scope slot) ≤ M)
    (ir : ∀ d, ts rest ≤ M → ts (evalArgs sigs decls scope rest d) ≤ M) :
    ts (evalArgs sigs decls scope (arg :: rest) slot) ≤ M := by
  simp only [ts_cons, Nat.max_le] at he
  have := i0 (by omega)
  rw [evalArgs]
  split
  · simp only [ts_none]; omega
  · rename_i first h
    have hf : ts first ≤ M := by rw [← ts_of_eq_some h]; assumption
    have := ir (slot + SrcType.size first.ty) (by omega)
    ts_auto

/-- The places' forms (F5) have no meaning yet. -/
theorem tsm_eval_eBorrow (ty : SrcType) (place : SrcEff) (sigs : List Sig) (decls : SrcDecls) (scope : List Binding) (slot : Nat) (M : Nat) :
    ts (SrcEff.eval (SrcEff.eBorrow ty place) sigs decls scope slot) ≤ M := by
  simp only [SrcEff.eval, ts_none]; omega

/-- The places' forms (F5) have no meaning yet. -/
theorem tsm_eval_eDeref (ty : SrcType) (ref : SrcEff) (sigs : List Sig) (decls : SrcDecls) (scope : List Binding) (slot : Nat) (M : Nat) :
    ts (SrcEff.eval (SrcEff.eDeref ty ref) sigs decls scope slot) ≤ M := by
  simp only [SrcEff.eval, ts_none]; omega

/-- The places' forms (F5) have no meaning yet. -/
theorem tsm_eval_eField (base : SrcEff) (field : Nat) (sigs : List Sig) (decls : SrcDecls) (scope : List Binding) (slot : Nat) (M : Nat) :
    ts (SrcEff.eval (SrcEff.eField base field) sigs decls scope slot) ≤ M := by
  simp only [SrcEff.eval, ts_none]; omega

/-- The places' forms (F5) have no meaning yet. -/
theorem tsm_eval_eAt (base index : SrcEff) (sigs : List Sig) (decls : SrcDecls) (scope : List Binding) (slot : Nat) (M : Nat) :
    ts (SrcEff.eval (SrcEff.eAt base index) sigs decls scope slot) ≤ M := by
  simp only [SrcEff.eval, ts_none]; omega

mutual
theorem tsm_SrcEff_eval : ∀ (self : SrcEff) (sigs : List Sig) (decls : SrcDecls) (scope : List Binding) (slot : Nat) (M : Nat),
    ts self ≤ M → ts sigs ≤ M → ts decls ≤ M → ts scope ≤ M → 16 ≤ M → ts (SrcEff.eval self sigs decls scope slot) ≤ M
  | .ePure e, sigs, decls, scope, slot, M, he, hs, hd, hc, h16 =>
    tsm_eval_ePure e sigs decls scope slot M hs hd hc h16 he
  | .eCall callee args, sigs, decls, scope, slot, M, he, hs, hd, hc, h16 =>
    tsm_eval_eCall callee args sigs decls scope slot M hs hd hc h16 he (tsm_evalArgs sigs decls scope args slot M · hs hd hc h16)
  | .eApply op left right, sigs, decls, scope, slot, M, he, hs, hd, hc, h16 =>
    tsm_eval_eApply op left right sigs decls scope slot M hs hd hc h16 he (tsm_SrcEff_eval left sigs decls scope slot M · hs hd hc h16) (tsm_SrcEff_eval right sigs decls scope (slot + 1) M · hs hd hc h16)
  | .eNeg operand, sigs, decls, scope, slot, M, he, hs, hd, hc, h16 =>
    tsm_eval_eNeg operand sigs decls scope slot M hs hd hc h16 he (tsm_SrcEff_eval operand sigs decls scope slot M · hs hd hc h16)
  | .eNot operand, sigs, decls, scope, slot, M, he, hs, hd, hc, h16 =>
    tsm_eval_eNot operand sigs decls scope slot M hs hd hc h16 he (tsm_SrcEff_eval operand sigs decls scope slot M · hs hd hc h16)
  | .eCast ty operand, sigs, decls, scope, slot, M, he, hs, hd, hc, h16 =>
    tsm_eval_eCast ty operand sigs decls scope slot M hs hd hc h16 he (tsm_SrcEff_eval operand sigs decls scope slot M · hs hd hc h16)
  | .eIndex slice index, sigs, decls, scope, slot, M, he, hs, hd, hc, h16 =>
    tsm_eval_eIndex slice index sigs decls scope slot M hs hd hc h16 he (tsm_SrcEff_eval index sigs decls scope slot M · hs hd hc h16)
  | .eStruct ty fields, sigs, decls, scope, slot, M, he, hs, hd, hc, h16 =>
    tsm_eval_eStruct ty fields sigs decls scope slot M hs hd hc h16 he (tsm_evalArgs sigs decls scope fields slot M · hs hd hc h16)
  | .eVariant ty variant payload, sigs, decls, scope, slot, M, he, hs, hd, hc, h16 =>
    tsm_eval_eVariant ty variant payload sigs decls scope slot M hs hd hc h16 he (tsm_evalArgs sigs decls scope payload (slot + 1) M · hs hd hc h16)
  | .eMatch scrutinee ety ty binders values, sigs, decls, scope, slot, M, he, hs, hd, hc, h16 =>
    tsm_eval_eMatch scrutinee ety ty binders values sigs decls scope slot M hs hd hc h16 he (tsm_SrcEff_eval scrutinee sigs decls scope slot M · hs hd hc h16)
  | .eDivide op left right, sigs, decls, scope, slot, M, he, hs, hd, hc, h16 =>
    tsm_eval_eDivide op left right sigs decls scope slot M hs hd hc h16 he (tsm_SrcEff_eval left sigs decls scope slot M · hs hd hc h16) (tsm_SrcEff_eval right sigs decls scope (slot + 1) M · hs hd hc h16)
  | .eStride slice, sigs, decls, scope, slot, M, he, hs, hd, hc, h16 =>
    tsm_eval_eStride slice sigs decls scope slot M hs hd hc h16 he
  | .arraySlice element array, sigs, decls, scope, slot, M, he, hs, hd, hc, h16 =>
    tsm_eval_arraySlice element array sigs decls scope slot M hs hd hc h16 he
  | .eIf condition ty thenValue elseValue, sigs, decls, scope, slot, M, he, hs, hd, hc, h16 =>
    tsm_eval_eIf condition ty thenValue elseValue sigs decls scope slot M hs hd hc h16 he (tsm_SrcEff_eval condition sigs decls scope slot M · hs hd hc h16) (tsm_SrcEff_eval thenValue sigs decls scope slot M · hs hd hc h16) (tsm_SrcEff_eval elseValue sigs decls scope slot M · hs hd hc h16)
  | .eLet id ty value rt body, sigs, decls, scope, slot, M, he, hs, hd, hc, h16 =>
    tsm_eval_eLet id ty value rt body sigs decls scope slot M hs hd hc h16 he (tsm_SrcEff_eval value sigs decls scope slot M · hs hd hc h16) (fun s d hb hsc => tsm_SrcEff_eval body sigs decls s d M hb hs hd hsc h16)
  | .eLen slice, sigs, decls, scope, slot, M, he, hs, hd, hc, h16 =>
    tsm_eval_eLen slice sigs decls scope slot M hs hd hc h16 he
  | .eStr offset chars, sigs, decls, scope, slot, M, he, hs, hd, hc, h16 =>
    tsm_eval_eStr offset chars sigs decls scope slot M hs hd hc h16 he
  | .eBorrow ty place, sigs, decls, scope, slot, M, _, _, _, _, _ =>
    tsm_eval_eBorrow ty place sigs decls scope slot M
  | .eDeref ty ref, sigs, decls, scope, slot, M, _, _, _, _, _ =>
    tsm_eval_eDeref ty ref sigs decls scope slot M
  | .eField base field, sigs, decls, scope, slot, M, _, _, _, _, _ =>
    tsm_eval_eField base field sigs decls scope slot M
  | .eAt base index, sigs, decls, scope, slot, M, _, _, _, _, _ =>
    tsm_eval_eAt base index sigs decls scope slot M
termination_by structural self => self
theorem tsm_evalArgs : ∀ (sigs : List Sig) (decls : SrcDecls) (scope : List Binding) (args : List SrcEff) (slot : Nat) (M : Nat),
    ts args ≤ M → ts sigs ≤ M → ts decls ≤ M → ts scope ≤ M → 16 ≤ M → ts (evalArgs sigs decls scope args slot) ≤ M
  | sigs, decls, scope, [], slot, M, he, hs, hd, hc, h16 => tsm_evalArgs_nil sigs decls scope slot M h16
  | sigs, decls, scope, arg :: rest, slot, M, he, hs, hd, hc, h16 =>
    tsm_evalArgs_cons sigs decls scope arg rest slot M h16 he (tsm_SrcEff_eval arg sigs decls scope slot M · hs hd hc h16)
      (fun d hr => tsm_evalArgs sigs decls scope rest d M hr hs hd hc h16)
termination_by structural sigs decls scope args => args
end

/-- An evaluation's type: its expression's, the signatures', the declarations', the scope's, or a scalar's. -/
theorem val_SrcEff_eval (self : SrcEff) (sigs : List Sig) (decls : SrcDecls) (scope : List Binding) (slot : Nat) :
    ts (SrcEff.eval self sigs decls scope slot) ≤ max (ts self) (max (ts sigs) (max (ts decls) (max (ts scope) 16))) :=
  tsm_SrcEff_eval self sigs decls scope slot _ (by omega) (by omega) (by omega) (by omega) (by omega)

theorem vals_SrcEff_eval (self : SrcEff) (sigs : List Sig) (decls : SrcDecls) (scope : List Binding) (slot : Nat)
    (v : Evaluated) (h : SrcEff.eval self sigs decls scope slot = some v) :
    ts v ≤ max (ts self) (max (ts sigs) (max (ts decls) (max (ts scope) 16))) := by
  have := val_SrcEff_eval self sigs decls scope slot
  rw [h] at this; exact this

theorem val_evalArgs (sigs : List Sig) (decls : SrcDecls) (scope : List Binding) (args : List SrcEff) (slot : Nat) :
    ts (evalArgs sigs decls scope args slot) ≤ max (ts sigs) (max (ts decls) (max (ts scope) (max (ts args) 16))) :=
  tsm_evalArgs sigs decls scope args slot _ (by omega) (by omega) (by omega) (by omega) (by omega)


end Lanius.Faithful.SelfPre
