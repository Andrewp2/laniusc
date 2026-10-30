import Lanius.Mini.Reading.Close

/-! # The reading, V8e: integer literals at their expected types

`LitExpr locals want e e'`: the closed expression `e` with each integer
literal at the type its context expects (`intAt`: an unsigned literal, the
null pointer for `0` at ptr, the cast of the i32 literal at isize or at a
signed type that holds it, and `-k` at a narrow signed type whose least
value it is as the cast of the i32 literal `-k`: `negLeast`), and each
wide literal (one of 2^31 or more, read as a marker) at its expected type
too (`wideAt`, `negWideAt`). What a position expects: a let's type, a
local's or field's when stored to, a parameter's, the function's result for
return, a field's or payload's in a literal, a slice element's in an index
store, an arm's result type, Bool for conditions, asserts and `!`; an
operator's operands expect the type of whichever operand has one
(`knownExpr`, `knownEff`), or else, for arithmetic, the operator's expected
type (`operandWant`). The operand of `as`, an index and the heap
operations' operands expect nothing. `ClosedProgram`: the closed functions
with their literals typed, accepted when no wide marker is left untyped. -/

namespace Lanius.Mini.Reading

open Lanius.Mini

/-! ## Expressions -/

inductive LitExpr (locals : List LocalTy) : Option SrcType → SrcExpr → SrcExpr → Prop
  | int {want : Option SrcType} {k : BitVec 32} : LitExpr locals want (.int k) (intAt want k (.int k))
  | boolean {want : Option SrcType} {b : Bool} : LitExpr locals want (.boolean b) (.boolean b)
  | unsigned {want : Option SrcType} {u : UintTy} {k : BitVec 64} :
      LitExpr locals want (.unsigned u k) (.unsigned u k)
  | «local» {want : Option SrcType} {id : Nat} : LitExpr locals want (.local id) (.local id)
  | field {want : Option SrcType} {id j : Nat} : LitExpr locals want (.field id j) (.field id j)
  | negate {want : Option SrcType} {x y : SrcExpr} :
      wideValue x = none → LitExpr locals want x y → LitExpr locals want (.negate x) (negLeast want x (.negate y))
  | negWide {want : Option SrcType} {x : SrcExpr} {n : BitVec 64} :
      wideValue x = some n → LitExpr locals want (.negate x) (negWideAt want n (.negate x))
  | not {want : Option SrcType} {x y : SrcExpr} :
      LitExpr locals (some .bool) x y → LitExpr locals want (.not x) (.not y)
  | apply {want : Option SrcType} {op : SrcOp} {a b a' b' : SrcExpr} :
      LitExpr locals (operandWant op want (knownExpr locals a) (knownExpr locals b)) a a' →
      LitExpr locals (operandWant op want (knownExpr locals a) (knownExpr locals b)) b b' →
      LitExpr locals want (.apply op a b) (.apply op a' b')
  | cast {want : Option SrcType} {t : SrcType} {x y : SrcExpr} :
      wideValue (.cast t x) = none → LitExpr locals none x y → LitExpr locals want (.cast t x) (.cast t y)
  | wide {want : Option SrcType} {t : SrcType} {x : SrcExpr} {n : BitVec 64} :
      wideValue (.cast t x) = some n → LitExpr locals want (.cast t x) (wideAt want n (.cast t x))
  | null {want : Option SrcType} : LitExpr locals want .null .null

/-- Expressions at a list of expected types, in order (none past its end). -/
inductive LitExprs (locals : List LocalTy) : Option (List SrcType) → List SrcExpr → List SrcExpr → Prop
  | nil {wants : Option (List SrcType)} : LitExprs locals wants [] []
  | cons {wants : Option (List SrcType)} {e e' : SrcExpr} {es es' : List SrcExpr} :
      LitExpr locals (firstSrc wants) e e' → LitExprs locals (restSrc wants) es es' →
      LitExprs locals wants (e :: es) (e' :: es')

/-- A match's arms, each value with its binders typed by its variant's
payload and expecting the match's type. -/
inductive LitArms (locals : List LocalTy) : Option (List (List SrcType)) → SrcType → List SrcArm → List SrcArm → Prop
  | nil {ps : Option (List (List SrcType))} {t : SrcType} : LitArms locals ps t [] []
  | cons {ps : Option (List (List SrcType))} {t : SrcType} {a : SrcArm} {v : SrcExpr} {rest rest' : List SrcArm} :
      LitExpr (boundTys a.binders (payloadAt ps 0) locals) (some t) a.value v →
      LitArms locals (restPayloads ps) t rest rest' →
      LitArms locals ps t (a :: rest) (⟨a.binders, v⟩ :: rest')

theorem litExpr_sound (locals : List LocalTy) :
    ∀ (want : Option SrcType) (e : SrcExpr), LitExpr locals want e (litExpr locals want e)
  | want, .int k => by simp only [litExpr]; exact .int
  | want, .boolean b => by simp only [litExpr]; exact .boolean
  | want, .unsigned u k => by simp only [litExpr]; exact .unsigned
  | want, .local id => by simp only [litExpr]; exact .local
  | want, .field id j => by simp only [litExpr]; exact .field
  | want, .negate x => by
    cases hw : wideValue x with
    | none => simp only [litExpr, hw]; exact .negate hw (litExpr_sound locals want x)
    | some n => simp only [litExpr, hw]; exact .negWide hw
  | want, .not x => by simp only [litExpr]; exact .not (litExpr_sound locals _ x)
  | want, .apply op a b => by
    simp only [litExpr]; exact .apply (litExpr_sound locals _ a) (litExpr_sound locals _ b)
  | want, .cast t x => by
    cases hw : wideValue (.cast t x) with
    | none => simp only [litExpr, hw]; exact .cast hw (litExpr_sound locals none x)
    | some n => simp only [litExpr, hw]; exact .wide hw
  | want, .null => by simp only [litExpr]; exact .null

theorem litExprs_sound (locals : List LocalTy) :
    ∀ (wants : Option (List SrcType)) (es : List SrcExpr), LitExprs locals wants es (litExprs locals wants es)
  | wants, [] => by simp only [litExprs]; exact .nil
  | wants, e :: rest => by
    simp only [litExprs]; exact .cons (litExpr_sound locals _ e) (litExprs_sound locals _ rest)

theorem litSrcArms_sound (locals : List LocalTy) (t : SrcType) :
    ∀ (ps : Option (List (List SrcType))) (arms : List SrcArm), LitArms locals ps t arms (litSrcArms locals ps t arms)
  | ps, [] => by simp only [litSrcArms]; exact .nil
  | ps, a :: rest => by
    simp only [litSrcArms]; exact .cons (litExpr_sound _ _ _) (litSrcArms_sound locals t _ rest)

/-! ## Effectful expressions -/

mutual
inductive LitEff (funcs : List SrcFunc) : List LocalTy → Option SrcType → SrcEff → SrcEff → Prop
  | pure {locals : List LocalTy} {want : Option SrcType} {e e' : SrcExpr} :
      LitExpr locals want e e' → LitEff funcs locals want (.ePure e) (.ePure e')
  | call {locals : List LocalTy} {want : Option SrcType} {f : Nat} {args args' : List SrcEff} :
      LitEffs funcs locals (calleeParams funcs f) args args' →
      LitEff funcs locals want (.eCall f args) (.eCall f args')
  | apply {locals : List LocalTy} {want : Option SrcType} {op : SrcOp} {a b a' b' : SrcEff} :
      LitEff funcs locals (operandWant op want (knownEff funcs locals a) (knownEff funcs locals b)) a a' →
      LitEff funcs locals (operandWant op want (knownEff funcs locals a) (knownEff funcs locals b)) b b' →
      LitEff funcs locals want (.eApply op a b) (.eApply op a' b')
  | neg {locals : List LocalTy} {want : Option SrcType} {a a' : SrcEff} :
      LitEff funcs locals want a a' → LitEff funcs locals want (.eNeg a) (.eNeg a')
  | not {locals : List LocalTy} {want : Option SrcType} {a a' : SrcEff} :
      LitEff funcs locals (some .bool) a a' → LitEff funcs locals want (.eNot a) (.eNot a')
  | cast {locals : List LocalTy} {want : Option SrcType} {t : SrcType} {a a' : SrcEff} :
      LitEff funcs locals none a a' → LitEff funcs locals want (.eCast t a) (.eCast t a')
  | index {locals : List LocalTy} {want : Option SrcType} {sl : Nat} {i i' : SrcEff} :
      LitEff funcs locals none i i' → LitEff funcs locals want (.eIndex sl i) (.eIndex sl i')
  | struct {locals : List LocalTy} {want : Option SrcType} {t : SrcType} {fs fs' : List SrcEff} :
      LitEffs funcs locals (srcFields (some t)) fs fs' → LitEff funcs locals want (.eStruct t fs) (.eStruct t fs')
  | variant {locals : List LocalTy} {want : Option SrcType} {t : SrcType} {k : Nat} {ps ps' : List SrcEff} :
      LitEffs funcs locals (payloadAt (srcVariants (some t)) k) ps ps' →
      LitEff funcs locals want (.eVariant t k ps) (.eVariant t k ps')
  | «match» {locals : List LocalTy} {want : Option SrcType} {s s' : SrcEff} {ety t : SrcType} {bs : List (List Nat)} {vs vs' : List SrcEff} :
      LitEff funcs locals (some ety) s s' → LitArmEffs funcs locals (srcVariants (some ety)) t bs vs vs' →
      LitEff funcs locals want (.eMatch s ety t bs vs) (.eMatch s' ety t bs vs')
  | divide {locals : List LocalTy} {want : Option SrcType} {op : SrcDivOp} {a b a' b' : SrcEff} :
      LitEff funcs locals (operandWant .plus want (knownEff funcs locals a) (knownEff funcs locals b)) a a' →
      LitEff funcs locals (operandWant .plus want (knownEff funcs locals a) (knownEff funcs locals b)) b b' →
      LitEff funcs locals want (.eDivide op a b) (.eDivide op a' b')
  | stride {locals : List LocalTy} {want : Option SrcType} {sl : Nat} : LitEff funcs locals want (.eStride sl) (.eStride sl)

inductive LitEffs (funcs : List SrcFunc) : List LocalTy → Option (List SrcType) → List SrcEff → List SrcEff → Prop
  | nil {locals : List LocalTy} {wants : Option (List SrcType)} : LitEffs funcs locals wants [] []
  | cons {locals : List LocalTy} {wants : Option (List SrcType)} {x x' : SrcEff} {xs xs' : List SrcEff} :
      LitEff funcs locals (firstSrc wants) x x' → LitEffs funcs locals (restSrc wants) xs xs' →
      LitEffs funcs locals wants (x :: xs) (x' :: xs')

inductive LitArmEffs (funcs : List SrcFunc) :
    List LocalTy → Option (List (List SrcType)) → SrcType → List (List Nat) → List SrcEff → List SrcEff → Prop
  | nil {locals : List LocalTy} {ps : Option (List (List SrcType))} {t : SrcType} {bs : List (List Nat)} : LitArmEffs funcs locals ps t bs [] []
  | cons {locals : List LocalTy} {ps : Option (List (List SrcType))} {t : SrcType} {bs : List (List Nat)} {v v' : SrcEff}
      {vs vs' : List SrcEff} :
      LitEff funcs (boundTys (firstIds bs) (payloadAt ps 0) locals) (some t) v v' →
      LitArmEffs funcs locals (restPayloads ps) t (restIds bs) vs vs' →
      LitArmEffs funcs locals ps t bs (v :: vs) (v' :: vs')
end

mutual
theorem litEff_sound (funcs : List SrcFunc) :
    ∀ (locals : List LocalTy) (want : Option SrcType) (x : SrcEff), LitEff funcs locals want x (litEff funcs locals want x)
  | locals, want, .ePure e => by simp only [litEff]; exact .pure (litExpr_sound _ _ _)
  | locals, want, .eCall f args => by simp only [litEff]; exact .call (litEffs_sound funcs _ _ args)
  | locals, want, .eApply op a b => by
    simp only [litEff]; exact .apply (litEff_sound funcs _ _ a) (litEff_sound funcs _ _ b)
  | locals, want, .eNeg a => by simp only [litEff]; exact .neg (litEff_sound funcs _ _ a)
  | locals, want, .eNot a => by simp only [litEff]; exact .not (litEff_sound funcs _ _ a)
  | locals, want, .eCast t a => by simp only [litEff]; exact .cast (litEff_sound funcs _ _ a)
  | locals, want, .eIndex sl i => by simp only [litEff]; exact .index (litEff_sound funcs _ _ i)
  | locals, want, .eStruct t fs => by simp only [litEff]; exact .struct (litEffs_sound funcs _ _ fs)
  | locals, want, .eVariant t k ps => by simp only [litEff]; exact .variant (litEffs_sound funcs _ _ ps)
  | locals, want, .eMatch s ety t bs vs => by
    simp only [litEff]; exact .match (litEff_sound funcs _ _ s) (litArmEffs_sound funcs _ _ _ _ vs)
  | locals, want, .eDivide op a b => by
    simp only [litEff]; exact .divide (litEff_sound funcs _ _ a) (litEff_sound funcs _ _ b)
  | locals, want, .eStride sl => by simp only [litEff]; exact .stride

theorem litEffs_sound (funcs : List SrcFunc) :
    ∀ (locals : List LocalTy) (wants : Option (List SrcType)) (xs : List SrcEff),
      LitEffs funcs locals wants xs (litEffs funcs locals wants xs)
  | locals, wants, [] => by simp only [litEffs]; exact .nil
  | locals, wants, x :: rest => by
    simp only [litEffs]; exact .cons (litEff_sound funcs _ _ x) (litEffs_sound funcs _ _ rest)

theorem litArmEffs_sound (funcs : List SrcFunc) :
    ∀ (locals : List LocalTy) (ps : Option (List (List SrcType))) (t : SrcType) (bs : List (List Nat))
      (vs : List SrcEff), LitArmEffs funcs locals ps t bs vs (litArmEffs funcs locals ps t bs vs)
  | locals, ps, t, bs, [] => by simp only [litArmEffs]; exact .nil
  | locals, ps, t, bs, v :: rest => by
    simp only [litArmEffs]; exact .cons (litEff_sound funcs _ _ v) (litArmEffs_sound funcs _ _ _ _ rest)
end

/-! ## Statements -/

inductive LitStmt (funcs : List SrcFunc) (ret : SrcType) : List LocalTy → SrcStmt → SrcStmt → Prop
  | nop {locals : List LocalTy} : LitStmt funcs ret locals .nop .nop
  | «let» {locals : List LocalTy} {id : Nat} {ty : SrcType} {e e' : SrcExpr} {b b' : SrcStmt} :
      LitExpr locals (some ty) e e' → LitStmt funcs ret (withLocal id ty locals) b b' →
      LitStmt funcs ret locals (.let id ty e b) (.let id ty e' b')
  | letStruct {locals : List LocalTy} {id : Nat} {ty : SrcType} {es es' : List SrcExpr} {b b' : SrcStmt} :
      LitExprs locals (srcFields (some ty)) es es' → LitStmt funcs ret (withLocal id ty locals) b b' →
      LitStmt funcs ret locals (.letStruct id ty es b) (.letStruct id ty es' b')
  | letCall {locals : List LocalTy} {id : Nat} {ty : SrcType} {f : Nat} {args args' : List SrcExpr}
      {b b' : SrcStmt} :
      LitExprs locals (calleeParams funcs f) args args' → LitStmt funcs ret (withLocal id ty locals) b b' →
      LitStmt funcs ret locals (.letCall id ty f args b) (.letCall id ty f args' b')
  | letEnum {locals : List LocalTy} {id : Nat} {ty : SrcType} {k : Nat} {es es' : List SrcExpr} {b b' : SrcStmt} :
      LitExprs locals (payloadAt (srcVariants (some ty)) k) es es' →
      LitStmt funcs ret (withLocal id ty locals) b b' →
      LitStmt funcs ret locals (.letEnum id ty k es b) (.letEnum id ty k es' b')
  | letMatch {locals : List LocalTy} {id : Nat} {ty : SrcType} {sc eid : Nat} {arms arms' : List SrcArm}
      {b b' : SrcStmt} :
      LitArms locals (srcVariants (tyLocal locals sc)) ty arms arms' →
      LitStmt funcs ret (withLocal id ty locals) b b' →
      LitStmt funcs ret locals (.letMatch id ty sc eid arms b) (.letMatch id ty sc eid arms' b')
  | set {locals : List LocalTy} {id : Nat} {e e' : SrcExpr} :
      LitExpr locals (tyLocal locals id) e e' → LitStmt funcs ret locals (.set id e) (.set id e')
  | setField {locals : List LocalTy} {id j : Nat} {e e' : SrcExpr} :
      LitExpr locals (tyAt (srcFields (tyLocal locals id)) j) e e' →
      LitStmt funcs ret locals (.setField id j e) (.setField id j e')
  | setCall {locals : List LocalTy} {id f : Nat} {args args' : List SrcExpr} :
      LitExprs locals (calleeParams funcs f) args args' →
      LitStmt funcs ret locals (.setCall id f args) (.setCall id f args')
  | «then» {locals : List LocalTy} {a b a' b' : SrcStmt} :
      LitStmt funcs ret locals a a' → LitStmt funcs ret locals b b' →
      LitStmt funcs ret locals (.then a b) (.then a' b')
  | «if» {locals : List LocalTy} {c c' : SrcExpr} {a b a' b' : SrcStmt} :
      LitExpr locals (some .bool) c c' → LitStmt funcs ret locals a a' → LitStmt funcs ret locals b b' →
      LitStmt funcs ret locals (.if c a b) (.if c' a' b')
  | «while» {locals : List LocalTy} {c c' : SrcExpr} {b b' : SrcStmt} :
      LitExpr locals (some .bool) c c' → LitStmt funcs ret locals b b' →
      LitStmt funcs ret locals (.while c b) (.while c' b')
  | «return» {locals : List LocalTy} {e e' : SrcExpr} :
      LitExpr locals (some ret) e e' → LitStmt funcs ret locals (.return e) (.return e')
  | letAlloc {locals : List LocalTy} {id : Nat} {size size' : SrcExpr} {shift : Nat} {b b' : SrcStmt} :
      LitExpr locals none size size' → LitStmt funcs ret (withLocal id .ptr locals) b b' →
      LitStmt funcs ret locals (.letAlloc id size shift b) (.letAlloc id size' shift b')
  | letLoad {locals : List LocalTy} {id : Nat} {p o p' o' : SrcExpr} {b b' : SrcStmt} :
      LitExpr locals none p p' → LitExpr locals none o o' →
      LitStmt funcs ret (withLocal id (.uint .uint8) locals) b b' →
      LitStmt funcs ret locals (.letLoad id p o b) (.letLoad id p' o' b')
  | setByte {locals : List LocalTy} {p o v p' o' v' : SrcExpr} :
      LitExpr locals none p p' → LitExpr locals none o o' → LitExpr locals none v v' →
      LitStmt funcs ret locals (.setByte p o v) (.setByte p' o' v')
  | free {locals : List LocalTy} {p size p' size' : SrcExpr} {shift : Nat} :
      LitExpr locals none p p' → LitExpr locals none size size' →
      LitStmt funcs ret locals (.free p size shift) (.free p' size' shift)
  | letSlice {locals : List LocalTy} {id : Nat} {el : SrcType} {p n p' n' : SrcExpr} {b b' : SrcStmt} :
      LitExpr locals none p p' → LitExpr locals none n n' →
      LitStmt funcs ret (withLocal id (.slice el) locals) b b' →
      LitStmt funcs ret locals (.letSlice id el p n b) (.letSlice id el p' n' b')
  | letIndex {locals : List LocalTy} {id : Nat} {ty : SrcType} {sl : Nat} {i i' : SrcExpr} {b b' : SrcStmt} :
      LitExpr locals none i i' → LitStmt funcs ret (withLocal id ty locals) b b' →
      LitStmt funcs ret locals (.letIndex id ty sl i b) (.letIndex id ty sl i' b')
  | setIndex {locals : List LocalTy} {sl : Nat} {i v i' v' : SrcExpr} :
      LitExpr locals none i i' → LitExpr locals (srcElement (tyLocal locals sl)) v v' →
      LitStmt funcs ret locals (.setIndex sl i v) (.setIndex sl i' v')
  | letEval {locals : List LocalTy} {id : Nat} {ty : SrcType} {x x' : SrcEff} {b b' : SrcStmt} :
      LitEff funcs locals (some ty) x x' → LitStmt funcs ret (withLocal id ty locals) b b' →
      LitStmt funcs ret locals (.letEval id ty x b) (.letEval id ty x' b')
  | setEval {locals : List LocalTy} {id : Nat} {x x' : SrcEff} :
      LitEff funcs locals (tyLocal locals id) x x' → LitStmt funcs ret locals (.setEval id x) (.setEval id x')
  | ifEval {locals : List LocalTy} {c c' : SrcEff} {a b a' b' : SrcStmt} :
      LitEff funcs locals (some .bool) c c' → LitStmt funcs ret locals a a' → LitStmt funcs ret locals b b' →
      LitStmt funcs ret locals (.ifEval c a b) (.ifEval c' a' b')
  | whileEval {locals : List LocalTy} {c c' : SrcEff} {b b' : SrcStmt} :
      LitEff funcs locals (some .bool) c c' → LitStmt funcs ret locals b b' →
      LitStmt funcs ret locals (.whileEval c b) (.whileEval c' b')
  | returnEval {locals : List LocalTy} {x x' : SrcEff} :
      LitEff funcs locals (some ret) x x' → LitStmt funcs ret locals (.returnEval x) (.returnEval x')
  | discard {locals : List LocalTy} {x x' : SrcEff} :
      LitEff funcs locals none x x' → LitStmt funcs ret locals (.discard x) (.discard x')
  | setIndexEval {locals : List LocalTy} {sl : Nat} {i v i' v' : SrcEff} :
      LitEff funcs locals none i i' → LitEff funcs locals (srcElement (tyLocal locals sl)) v v' →
      LitStmt funcs ret locals (.setIndexEval sl i v) (.setIndexEval sl i' v')
  | setFieldEval {locals : List LocalTy} {id j : Nat} {x x' : SrcEff} :
      LitEff funcs locals (tyAt (srcFields (tyLocal locals id)) j) x x' →
      LitStmt funcs ret locals (.setFieldEval id j x) (.setFieldEval id j x')
  | returnUnit {locals : List LocalTy} : LitStmt funcs ret locals .returnUnit .returnUnit
  | «assert» {locals : List LocalTy} {x x' : SrcEff} :
      LitEff funcs locals (some .bool) x x' → LitStmt funcs ret locals (.assert x) (.assert x')

theorem litStmt_sound (funcs : List SrcFunc) (ret : SrcType) :
    ∀ (locals : List LocalTy) (s : SrcStmt), LitStmt funcs ret locals s (litStmt funcs ret locals s)
  | locals, .nop => by simp only [litStmt]; exact .nop
  | locals, .let id ty e b => by
    simp only [litStmt]; exact .let (litExpr_sound _ _ _) (litStmt_sound funcs ret _ b)
  | locals, .letStruct id ty es b => by
    simp only [litStmt]; exact .letStruct (litExprs_sound _ _ _) (litStmt_sound funcs ret _ b)
  | locals, .letCall id ty f args b => by
    simp only [litStmt]; exact .letCall (litExprs_sound _ _ _) (litStmt_sound funcs ret _ b)
  | locals, .letEnum id ty k es b => by
    simp only [litStmt]; exact .letEnum (litExprs_sound _ _ _) (litStmt_sound funcs ret _ b)
  | locals, .letMatch id ty sc eid arms b => by
    simp only [litStmt]; exact .letMatch (litSrcArms_sound _ _ _ _) (litStmt_sound funcs ret _ b)
  | locals, .set id e => by simp only [litStmt]; exact .set (litExpr_sound _ _ _)
  | locals, .setField id j e => by simp only [litStmt]; exact .setField (litExpr_sound _ _ _)
  | locals, .setCall id f args => by simp only [litStmt]; exact .setCall (litExprs_sound _ _ _)
  | locals, .then a b => by
    simp only [litStmt]; exact .then (litStmt_sound funcs ret _ a) (litStmt_sound funcs ret _ b)
  | locals, .if c a b => by
    simp only [litStmt]
    exact .if (litExpr_sound _ _ _) (litStmt_sound funcs ret _ a) (litStmt_sound funcs ret _ b)
  | locals, .while c b => by
    simp only [litStmt]; exact .while (litExpr_sound _ _ _) (litStmt_sound funcs ret _ b)
  | locals, .return e => by simp only [litStmt]; exact .return (litExpr_sound _ _ _)
  | locals, .letAlloc id size shift b => by
    simp only [litStmt]; exact .letAlloc (litExpr_sound _ _ _) (litStmt_sound funcs ret _ b)
  | locals, .letLoad id p o b => by
    simp only [litStmt]
    exact .letLoad (litExpr_sound _ _ _) (litExpr_sound _ _ _) (litStmt_sound funcs ret _ b)
  | locals, .setByte p o v => by
    simp only [litStmt]; exact .setByte (litExpr_sound _ _ _) (litExpr_sound _ _ _) (litExpr_sound _ _ _)
  | locals, .free p size shift => by
    simp only [litStmt]; exact .free (litExpr_sound _ _ _) (litExpr_sound _ _ _)
  | locals, .letSlice id el p n b => by
    simp only [litStmt]
    exact .letSlice (litExpr_sound _ _ _) (litExpr_sound _ _ _) (litStmt_sound funcs ret _ b)
  | locals, .letIndex id ty sl i b => by
    simp only [litStmt]; exact .letIndex (litExpr_sound _ _ _) (litStmt_sound funcs ret _ b)
  | locals, .setIndex sl i v => by
    simp only [litStmt]; exact .setIndex (litExpr_sound _ _ _) (litExpr_sound _ _ _)
  | locals, .letEval id ty x b => by
    simp only [litStmt]; exact .letEval (litEff_sound _ _ _ _) (litStmt_sound funcs ret _ b)
  | locals, .setEval id x => by simp only [litStmt]; exact .setEval (litEff_sound _ _ _ _)
  | locals, .ifEval c a b => by
    simp only [litStmt]
    exact .ifEval (litEff_sound _ _ _ _) (litStmt_sound funcs ret _ a) (litStmt_sound funcs ret _ b)
  | locals, .whileEval c b => by
    simp only [litStmt]; exact .whileEval (litEff_sound _ _ _ _) (litStmt_sound funcs ret _ b)
  | locals, .returnEval x => by simp only [litStmt]; exact .returnEval (litEff_sound _ _ _ _)
  | locals, .discard x => by simp only [litStmt]; exact .discard (litEff_sound _ _ _ _)
  | locals, .setIndexEval sl i v => by
    simp only [litStmt]; exact .setIndexEval (litEff_sound _ _ _ _) (litEff_sound _ _ _ _)
  | locals, .setFieldEval id j x => by simp only [litStmt]; exact .setFieldEval (litEff_sound _ _ _ _)
  | locals, .returnUnit => by simp only [litStmt]; exact .returnUnit
  | locals, .assert x => by simp only [litStmt]; exact .assert (litEff_sound _ _ _ _)

/-! ## Functions and the closed program -/

/-- A function with its literals typed, its parameters in scope and its
result expected by its returns, with all the functions' signatures. -/
def LitFunc (all : List SrcFunc) (g g' : SrcFunc) : Prop :=
  g'.params = g.params ∧ g'.ret = g.ret ∧ LitStmt all g.ret (paramLocals g.params) g.body g'.body

theorem litFuncs_sound (all : List SrcFunc) :
    ∀ (fs : List SrcFunc), ListRel (LitFunc all) fs (litFuncs all fs)
  | [] => by simp only [litFuncs]; exact .nil
  | g :: rest => by
    simp only [litFuncs]; exact .cons ⟨rfl, rfl, litStmt_sound _ _ _ _⟩ (litFuncs_sound all rest)

/-- The closed program: the functions closed against the tables, their
literals typed, and no wide literal left without a type. -/
def ClosedProgram (decls : Decls) (fns types : List Inst) (funcs : List MFunc) (p : SrcProgram) : Prop :=
  ∃ fs, ListRel (FuncClosed decls fns types) funcs fs ∧ ListRel (LitFunc fs) fs p.funcs ∧
    wideLeftFuncs p.funcs = false

theorem buildClosed_sound {fuel : Nat} {decls : Decls} {fns : List Inst} {types : Option (List Inst)}
    {funcs : List MFunc} {p : SrcProgram} (h : buildClosed fuel decls fns types funcs = some p) :
    ∃ ts, types = some ts ∧ ClosedProgram decls fns ts funcs p := by
  unfold buildClosed at h
  cases types with
  | none => cases h
  | some ts =>
    simp only at h
    cases hc : closeFuncs fuel { decls := decls, fns := fns, types := ts, lowered := loweredAll fuel decls ts ts } funcs with
    | none => rw [hc] at h; cases h
    | some fs =>
      rw [hc] at h
      simp only [untypedRejected] at h
      cases hw : wideLeftFuncs (litFuncs fs fs) with
      | true => rw [hw] at h; cases h
      | false =>
        rw [hw] at h
        simp only [Bool.false_eq_true, if_false, Option.some.injEq] at h
        subst h
        exact ⟨ts, rfl, fs, closeFuncs_sound (loweredAll_ok rfl) _ _ hc, litFuncs_sound fs fs, hw⟩

end Lanius.Mini.Reading
