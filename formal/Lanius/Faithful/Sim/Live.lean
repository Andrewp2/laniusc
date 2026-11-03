import Lanius.Faithful.Sim.TermSound
import Lanius.Faithful.Safe.Value

/-! # Checked pure calls have values

`pcall_complete` (`TermSound.lean`) shows that every annotated pure call
settles; the answer it settles to can be `none`. Here a call settles to a
value of its return type when its arguments have their parameters' types
(`PTy`), the program passes `PureProg`'s typing, and every function it can
reach passes `LiveFn`: no division but by a constant that cannot fail, shifts
only by constants below the width, no `assert`, no `return;` in a function
with a value, a body that never just ends in one with a value, and no call
of the functions in `bad`. -/

namespace Lanius.Faithful.Termination

open Lanius.Mini
open Lanius.Faithful
open Lanius.Core (Value)
open Lanius.Semantics (evalBinaryValue evalSignedBinary evalUnsignedBinary evalUnaryValue evalScalarCast
  scalarEqual matchPattern matchPatterns)

/-! ## Pure values of a source type -/

mutual
/-- The pure value `v` has source type `t`: a scalar in its type's range, a
struct or an enum of values of its parts' types, or, for a box, a value of
the type it holds (`boxed` and `unbox` are the identity). -/
inductive PTy (boxes : Boxes) : SrcType → Value → Prop where
  | scalar {t : SrcType} {v : Value} : STy t v → PTy boxes t v
  | struct {id : Nat} {fs : List SrcType} {vs : List Value} :
      boxes id = none → PTys boxes fs vs → PTy boxes (.struct id fs) (.structure id vs)
  | enum {id : Nat} {variants : List (List SrcType)} {k : Nat} {fs : List SrcType} {vs : List Value} :
      variants[k]? = some fs → PTys boxes fs vs → PTy boxes (.enum id variants) (.enumeration id k vs)
  | box {id : Nat} {t : SrcType} {v : Value} :
      boxes id = some t → PTy boxes t v → PTy boxes (.struct id [.ptr]) v

inductive PTys (boxes : Boxes) : List SrcType → List Value → Prop where
  | nil : PTys boxes [] []
  | cons {t : SrcType} {ts : List SrcType} {v : Value} {vs : List Value} :
      PTy boxes t v → PTys boxes ts vs → PTys boxes (t :: ts) (v :: vs)
end

/-- Every local the type environment has is bound, to a value of its type. -/
def EnvTy (boxes : Boxes) (tenv : TEnv) (env : Env) : Prop :=
  ∀ x t, tenv.get? x = some t → ∃ v, env.get? x = some v ∧ PTy boxes t v

/-! ## The check -/

/-- A shift amount that cannot fail: a constant below the width of the
unsigned type it is cast to. -/
def shiftAmtOk : SrcExpr → Bool
  | .cast (.uint k) (.int n) => decide (0 ≤ n.toInt) && decide (n.toInt < k.width)
  | .int _ | .boolean _ | .unsigned _ _ | .local _ | .field _ _ | .negate _ | .not _ | .apply _ _ _
  | .cast _ _ | .null | .char _ | .float _ _ => false

def isShiftOp : SrcOp → Bool
  | .shiftLeft | .shiftRight => true
  | .plus | .minus | .times | .bitAnd | .bitOr | .bitXor | .less | .lessEq | .greater | .greaterEq
  | .equal | .notEqual | .logicalAnd | .logicalOr => false

/-- A pure expression whose operators cannot fail on operands of their types. -/
def liveExpr : SrcExpr → Bool
  | .apply op l r => liveExpr l && liveExpr r && (!isShiftOp op || shiftAmtOk r)
  | .negate e => liveExpr e
  | .not e => liveExpr e
  | .cast _ e => liveExpr e
  | .int _ | .boolean _ | .unsigned _ _ | .local _ | .field _ _ | .null | .char _ | .float _ _ => true

def liveExprs : List SrcExpr → Bool
  | [] => true
  | e :: es => liveExpr e && liveExprs es

/-- A divisor that cannot fail: a constant other than 0 and -1. -/
def divisorOk : SrcEff → Bool
  | .ePure (.int n) => n != 0 && n != BitVec.allOnes 32
  | .ePure (.unsigned _ n) => n != 0
  | .ePure _ | .eCall _ _ | .eApply _ _ _ | .eNeg _ | .eNot _ | .eCast _ _ | .eIndex _ _ | .eStruct _ _
  | .eVariant _ _ _ | .eMatch _ _ _ _ _ | .eDivide _ _ _ | .eStride _
  | .arraySlice _ _ | .eIf _ _ _ _ | .eLet _ _ _ _ _ | .eLen _ | .eStr _ _ => false

/-- A match with an arm for every variant of its enum type. -/
def armsFull : SrcType → List (List Nat) → Bool
  | .enum _ variants, binders => variants.length == binders.length
  | .i32, _ | .bool, _ | .uint _, _ | .struct _ _, _ | .ptr, _ | .slice _, _ | .unit, _ | .isize, _
  | .char, _ | .float _, _ | .sint _, _ | .array _ _, _ | .view _, _ | .str, _ => false

section
variable (bad : List Nat)

mutual
def liveEff : SrcEff → Bool
  | .ePure e => liveExpr e
  | .eCall c args => !bad.contains c && liveEffs args
  | .eApply op l r => !isShiftOp op && liveEff l && liveEff r
  | .eNeg e => liveEff e
  | .eNot e => liveEff e
  | .eCast _ e => liveEff e
  | .eIndex _ _ => false
  | .eStruct _ fs => liveEffs fs
  | .eVariant _ _ fs => liveEffs fs
  | .eMatch s ety _ binders vs => liveEff s && liveEffs vs && armsFull ety binders
  | .eDivide _ l r => liveEff l && divisorOk r
  | .eStride _ => false
  | .arraySlice _ _ => false
  | .eIf c _ a b => liveEff c && liveEff a && liveEff b
  | .eLet _ _ value _ body => liveEff value && liveEff body
  | .eLen _ | .eStr _ _ => false

def liveEffs : List SrcEff → Bool
  | [] => true
  | e :: es => liveEff e && liveEffs es
end

/-- A statement that cannot fail but at a call, in a function returning `ret`. -/
def liveStmt (ret : SrcType) : SrcStmt → Bool
  | .nop => true
  | .let _ _ value body => liveExpr value && liveStmt ret body
  | .letStruct _ _ fields body => liveExprs fields && liveStmt ret body
  | .letCall _ _ c args body => !bad.contains c && liveExprs args && liveStmt ret body
  | .letEnum _ _ _ payload body => liveExprs payload && liveStmt ret body
  | .then first second => liveStmt ret first && liveStmt ret second
  | .if c a b => liveExpr c && liveStmt ret a && liveStmt ret b
  | .return value => liveExpr value
  | .letEval _ _ value body => liveEff bad value && liveStmt ret body
  | .ifEval c a b => liveEff bad c && liveStmt ret a && liveStmt ret b
  | .returnEval value => liveEff bad value
  | .discard value => liveEff bad value
  | .returnUnit => decide (ret.toCore = .unit)
  | .set _ value => liveExpr value
  | .setEval _ value => liveEff bad value
  | .letMatch _ _ _ _ _ _ | .setField _ _ _ | .setCall _ _ _ | .while _ _ | .letAlloc _ _ _ _ | .letView _ _ _ _ _ | .letStr _ _ _
  | .letLoad _ _ _ _ | .setByte _ _ _ | .free _ _ _ | .letSlice _ _ _ _ _ | .letIndex _ _ _ _ _
  | .setIndex _ _ _ | .whileEval _ _ | .setIndexEval _ _ _ | .setFieldEval _ _ _
  | .assert _ | .break | .continue | .matchArm _ _ _ _ _ _ _ _ | .unreachable _ _ => false

/-- A function whose body cannot fail but at a call, and that returns a value
on every path when it has one. -/
def LiveFn (f : SrcFunc) : Bool :=
  liveStmt bad f.ret f.body && (decide (f.ret.toCore = .unit) || neverNext f.body)

end

/-! ## Pure expressions of checked types have values -/

theorem PTy.sty {boxes : Boxes} {t : SrcType} {v : Value} (h : PTy boxes t v) (s : scalarTy t = true) :
    STy t v := by
  cases h with
  | scalar h => exact h
  | struct => simp [scalarTy] at s
  | enum => simp [scalarTy] at s
  | box => simp [scalarTy] at s

theorem numTy_scalarTy {t : SrcType} (h : numTy t = true) : scalarTy t = true := by
  cases t <;> simp_all [numTy, scalarTy]

theorem signed_error_op {tgt : Core.Target} {op : Core.BinaryOp} {ty : Core.SignedIntTy} {a b : Int}
    {reason : Lanius.Trap} (h : evalSignedBinary tgt op ty a b = .error reason) :
    op = .divide ∨ op = .remainder ∨ op = .shiftLeft ∨ op = .shiftRight ∨
      op = .logicalAnd ∨ op = .logicalOr ∨ op = .equal ∨ op = .notEqual := by
  cases op <;> simp only [evalSignedBinary] at h <;> simp_all

theorem unsigned_error_op {tgt : Core.Target} {op : Core.BinaryOp} {ty : Core.UnsignedIntTy} {a b : Nat}
    {reason : Lanius.Trap} (h : evalUnsignedBinary tgt op ty a b = .error reason) :
    op = .divide ∨ op = .remainder ∨ op = .shiftLeft ∨ op = .shiftRight ∨
      op = .logicalAnd ∨ op = .logicalOr ∨ op = .equal ∨ op = .notEqual := by
  cases op <;> simp only [evalUnsignedBinary] at h <;> simp_all

/-- Operands of the types `opTy` accepts, and a shift's amount below its
width: Core's operator (but `&&` and `||`) gives a value. -/
theorem binary_live {op : SrcOp} {tl tr t : SrcType} {lv rv : Value}
    (ht : opTy op tl tr = some t) (notAnd : op ≠ .logicalAnd) (notOr : op ≠ .logicalOr)
    (hl : STy tl lv) (hr : STy tr rv)
    (shift : isShiftOp op = true → ∃ k n, tl = .uint k ∧ rv = .unsigned k.toCore n ∧ n < k.width) :
    ∃ v, evalBinaryValue .x86_64 op.toCore lv rv = .ok v := by
  obtain ⟨rfl, cmp⟩ := opTy_same ht notAnd notOr
  cases h : evalBinaryValue .x86_64 op.toCore lv rv with
  | ok v => exact ⟨v, rfl⟩
  | error reason =>
    exfalso
    by_cases eq : op = .equal ∨ op = .notEqual
    · cases tr with
      | i32 =>
        obtain ⟨a, rfl, -⟩ := hl; obtain ⟨b, rfl, -⟩ := hr
        rcases eq with rfl | rfl <;> simp [SrcOp.toCore, evalBinaryValue, Semantics.scalarEqual] at h
      | isize =>
        obtain ⟨a, rfl, -⟩ := hl; obtain ⟨b, rfl, -⟩ := hr
        rcases eq with rfl | rfl <;> simp [SrcOp.toCore, evalBinaryValue, Semantics.scalarEqual] at h
      | uint k =>
        obtain ⟨a, rfl, -⟩ := hl; obtain ⟨b, rfl, -⟩ := hr
        rcases eq with rfl | rfl <;> simp [SrcOp.toCore, evalBinaryValue, Semantics.scalarEqual] at h
      | bool =>
        obtain ⟨a, rfl⟩ := hl; obtain ⟨b, rfl⟩ := hr
        rcases eq with rfl | rfl <;> simp [SrcOp.toCore, evalBinaryValue, Semantics.scalarEqual] at h
      | unit =>
        have hl' : lv = .unit := hl
        have hr' : rv = .unit := hr
        subst hl' hr'
        rcases eq with rfl | rfl <;> simp [SrcOp.toCore, evalBinaryValue, Semantics.scalarEqual] at h
      | struct => exact hl.elim
      | enum => exact hl.elim
      | ptr => exact hl.elim
      | slice => exact hl.elim
      | char => exact hl.elim
      | float => exact hl.elim
      | sint => exact hl.elim
      | array => exact hl.elim
      | view | str => exact hl.elim
    · have num : numTy tr = true := by rcases cmp with e | e | e <;> simp_all
      have notEq : op ≠ .equal := fun e => eq (.inl e)
      have notNe : op ≠ .notEqual := fun e => eq (.inr e)
      cases tr with
      | i32 =>
        obtain ⟨a, rfl, -⟩ := hl; obtain ⟨b, rfl, -⟩ := hr
        have e : evalSignedBinary .x86_64 op.toCore .i32 a b = .error reason := by
          cases op <;> simp_all [SrcOp.toCore, evalBinaryValue]
        rcases signed_error_op e with e | e | e | e | e | e | e | e <;>
          cases op <;> simp_all [SrcOp.toCore, isShiftOp]
      | isize =>
        obtain ⟨a, rfl, -⟩ := hl; obtain ⟨b, rfl, -⟩ := hr
        have e : evalSignedBinary .x86_64 op.toCore .isize a b = .error reason := by
          cases op <;> simp_all [SrcOp.toCore, evalBinaryValue]
        rcases signed_error_op e with e | e | e | e | e | e | e | e <;>
          cases op <;> simp_all [SrcOp.toCore, isShiftOp]
      | uint k =>
        obtain ⟨a, rfl, -⟩ := hl; obtain ⟨b, rfl, -⟩ := hr
        have e : evalUnsignedBinary .x86_64 op.toCore k.toCore a b = .error reason := by
          cases op <;> simp_all [SrcOp.toCore, evalBinaryValue]
        rcases unsigned_error_op e with e | e | e | e | e | e | e | e <;>
          cases op <;> simp_all [SrcOp.toCore, isShiftOp]
        all_goals
          have nb : ¬ b ≥ k.toCore.bits .x86_64 := by rw [uint_bits]; omega
          simp [evalUnsignedBinary, nb] at e
      | bool => simp [numTy] at num
      | unit => simp [numTy] at num
      | struct => simp [numTy] at num
      | enum => simp [numTy] at num
      | ptr => simp [numTy] at num
      | slice => simp [numTy] at num
      | char => exact hl.elim
      | float => exact hl.elim
      | sint => exact hl.elim
      | array => exact hl.elim
      | view | str => exact hl.elim

theorem PTys.get {boxes : Boxes} : ∀ {ts : List SrcType} {vs : List Value}, PTys boxes ts vs →
    ∀ {i : Nat} {t : SrcType}, ts[i]? = some t → ∃ v, vs[i]? = some v ∧ PTy boxes t v
  | _, _, .nil, _, _, h => by simp at h
  | _, _, .cons hv hs, 0, _, h => by
    simp only [List.getElem?_cons_zero, Option.some.injEq] at h
    subst h
    exact ⟨_, rfl, hv⟩
  | _, _, .cons _ hs, i + 1, _, h => by
    simp only [List.getElem?_cons_succ] at h ⊢
    exact hs.get h

theorem PTy.field {boxes : Boxes} {t ft : SrcType} {index : Nat} {v : Value} (r : PTy boxes t v)
    (ht : fieldTy boxes t index = some ft) : ∃ x, fieldOf v index = some x ∧ PTy boxes ft x := by
  cases r with
  | scalar s =>
    rcases sty_cases s with ⟨_, rfl⟩ | ⟨_, _, rfl⟩ | ⟨_, _, rfl⟩ | rfl <;> cases t <;> simp_all [fieldTy, STy]
  | struct none rs =>
    simp only [fieldTy, none, Option.isNone_none, if_true] at ht
    obtain ⟨x, hx, rx⟩ := rs.get ht
    exact ⟨x, hx, rx⟩
  | enum => simp [fieldTy] at ht
  | box some => simp [fieldTy, some] at ht

theorem shiftAmt_value {tenv : TEnv} {env : Env} {boxes : Boxes} {e : SrcExpr} {t : SrcType} {v : Value}
    (ok : shiftAmtOk e = true) (ht : exprTy boxes tenv e = some t) (hv : pexpr env e = some v) :
    ∃ k n, t = .uint k ∧ v = .unsigned k.toCore n ∧ n < k.width := by
  cases e with
  | cast ty x =>
    cases ty with
    | uint k =>
      cases x with
      | int n =>
        simp only [shiftAmtOk, Bool.and_eq_true, decide_eq_true_eq] at ok
        simp only [exprTy, Option.bind_some, castTy, numTy, Bool.and_self, if_true, Option.some.injEq] at ht
        simp only [pexpr, Option.bind_some, cast, SrcType.toScalar, evalScalarCast, Lanius.Faithful.target,
          Except.toOption, Option.some.injEq] at hv
        subst ht hv
        refine ⟨k, _, rfl, rfl, ?_⟩
        have m : (k.width : Int) ≤ Int.ofNat (Semantics.unsignedModulus .x86_64 k.toCore) := by
          cases k <;> decide
        simp only [Semantics.wrapUnsignedInt]
        rw [Int.emod_eq_of_lt ok.1 (by omega)]
        omega
      | _ => simp [shiftAmtOk] at ok
    | _ => simp [shiftAmtOk] at ok
  | _ => simp [shiftAmtOk] at ok

theorem opTy_bool {op : SrcOp} {tl tr t : SrcType} (isB : op = .logicalAnd ∨ op = .logicalOr)
    (h : opTy op tl tr = some t) : t = .bool ∧ tl = .bool ∧ tr = .bool := by
  rcases isB with rfl | rfl <;> simp only [opTy] at h <;> split at h <;>
    (try simp at h) <;>
    (rename_i hb
     simp only [Bool.and_eq_true] at h hb
     exact ⟨h.symm, SrcType.isBool_eq hb.1, SrcType.isBool_eq hb.2⟩)

theorem applyOp_other {op : SrcOp} (notAnd : op ≠ .logicalAnd) (notOr : op ≠ .logicalOr) (l r : Option Value) :
    applyOp op l r = binary op.toCore l r := by
  cases op <;> simp_all [applyOp]

theorem bool_value {boxes : Boxes} {v : Value} (h : PTy boxes .bool v) : ∃ b, v = .boolean b :=
  h.sty rfl

/-- A checked pure expression whose shifts are by constants below the width
has a value of its type. -/
theorem expr_live {boxes : Boxes} {tenv : TEnv} {env : Env} (hE : EnvTy boxes tenv env) (e : SrcExpr) :
    ∀ {t : SrcType}, exprTy boxes tenv e = some t → liveExpr e = true →
      ∃ v, pexpr env e = some v ∧ PTy boxes t v := by
  induction e with
  | int value =>
    intro t ht _
    simp only [exprTy, Option.some.injEq] at ht
    subst ht
    exact ⟨_, rfl, .scalar ⟨_, rfl, BitVec.le_toInt value, BitVec.toInt_lt⟩⟩
  | boolean value =>
    intro t ht _
    simp only [exprTy, Option.some.injEq] at ht
    subst ht
    exact ⟨_, rfl, .scalar ⟨_, rfl⟩⟩
  | unsigned kind value =>
    intro t ht _
    simp only [exprTy] at ht
    split at ht
    · rename_i lt
      simp only [Option.some.injEq] at ht
      subst ht
      exact ⟨_, rfl, .scalar ⟨_, rfl, lt⟩⟩
    · simp at ht
  | «local» id =>
    intro t ht _
    exact hE id t ht
  | field id index =>
    intro t ht _
    simp only [exprTy, Option.bind_eq_some_iff] at ht
    obtain ⟨tl, htl, hft⟩ := ht
    obtain ⟨v, hv, rv⟩ := hE id tl htl
    obtain ⟨x, hx, rx⟩ := rv.field hft
    exact ⟨x, by simp only [pexpr, hv, Option.bind_some, hx], rx⟩
  | negate operand ih =>
    intro t ht live
    simp only [exprTy, Option.bind_eq_some_iff] at ht
    obtain ⟨to, hto, hn⟩ := ht
    obtain ⟨rfl, num⟩ := numOf_some hn
    obtain ⟨q, hq, rq⟩ := ih hto (by simpa only [liveExpr] using live)
    have sq := rq.sty (numTy_scalarTy num)
    cases hw : evalUnaryValue .x86_64 .negate q with
    | error reason => exact (neg_ok num sq hw).elim
    | ok w =>
      refine ⟨w, ?_, .scalar (neg_sty sq hw)⟩
      simp only [pexpr, hq, Option.bind_some, unary, Lanius.Faithful.target, hw]
      rfl
  | «not» operand ih =>
    intro t ht live
    simp only [exprTy, Option.bind_eq_some_iff] at ht
    obtain ⟨to, hto, hb⟩ := ht
    obtain ⟨rfl, rfl⟩ := boolOf_some hb
    obtain ⟨q, hq, rq⟩ := ih hto (by simpa only [liveExpr] using live)
    have sq := rq.sty rfl
    cases hw : evalUnaryValue .x86_64 .logicalNot q with
    | error reason => exact (not_ok sq hw).elim
    | ok w =>
      refine ⟨w, ?_, .scalar (not_sty hw)⟩
      simp only [pexpr, hq, Option.bind_some, unary, Lanius.Faithful.target, hw]
      rfl
  | apply op left right ihl ihr =>
    intro t ht live
    simp only [liveExpr, Bool.and_eq_true] at live
    obtain ⟨⟨livel, liver⟩, liveShift⟩ := live
    simp only [exprTy, Option.bind_eq_some_iff] at ht
    obtain ⟨tl, htl, tr, htr, ht⟩ := ht
    obtain ⟨ql, hql, rl⟩ := ihl htl livel
    obtain ⟨qr, hqr, rr⟩ := ihr htr liver
    by_cases isB : op = .logicalAnd ∨ op = .logicalOr
    · obtain ⟨rfl, rfl, rfl⟩ := opTy_bool isB ht
      obtain ⟨bl, rfl⟩ := bool_value rl
      obtain ⟨br, rfl⟩ := bool_value rr
      rcases isB with rfl | rfl <;> cases bl <;>
        exact ⟨_, by simp [pexpr, applyOp, hql, hqr, asBool]; rfl, .scalar ⟨_, rfl⟩⟩
    have notAnd : op ≠ .logicalAnd := fun e => isB (.inl e)
    have notOr : op ≠ .logicalOr := fun e => isB (.inr e)
    obtain ⟨rfl, cmp⟩ := opTy_same ht notAnd notOr
    have scal : scalarTy tr = true := by
      rcases cmp with rfl | rfl | num
      · simp only [opTy, Bool.and_eq_true] at ht; split at ht <;> simp_all
      · simp only [opTy, Bool.and_eq_true] at ht; split at ht <;> simp_all
      · exact numTy_scalarTy num
    have sl := rl.sty scal
    have sr := rr.sty scal
    have shift : isShiftOp op = true → ∃ k n, tr = .uint k ∧ qr = .unsigned k.toCore n ∧ n < k.width := by
      intro hs
      simp only [hs, Bool.not_true, Bool.false_or] at liveShift
      exact shiftAmt_value liveShift htr hqr
    obtain ⟨w, hw⟩ := binary_live ht notAnd notOr sl sr shift
    refine ⟨w, ?_, .scalar (binary_sty sl ht notAnd notOr hw)⟩
    simp only [pexpr, applyOp_other notAnd notOr, binary, hql, hqr, Option.bind_some, Lanius.Faithful.target, hw]
    rfl
  | cast ty operand ih =>
    intro t ht live
    simp only [exprTy, Option.bind_eq_some_iff] at ht
    obtain ⟨to, hto, hc⟩ := ht
    obtain ⟨rfl, num, numTo⟩ := castTy_some hc
    obtain ⟨q, hq, rq⟩ := ih hto (by simpa only [liveExpr] using live)
    have sq := rq.sty (numTy_scalarTy num)
    cases hw : evalScalarCast .x86_64 t.toScalar q with
    | error reason => exact (cast_ok num numTo sq hw).elim
    | ok w =>
      refine ⟨w, ?_, .scalar (cast_sty sq numTo hw)⟩
      simp only [pexpr, hq, Option.bind_some, cast, Lanius.Faithful.target, hw]
      rfl
  | null => intro t ht _; simp [exprTy] at ht
  | char code => intro t ht _; simp [exprTy] at ht
  | float ft x => intro t ht _; simp [exprTy] at ht

theorem exprs_live {boxes : Boxes} {tenv : TEnv} {env : Env} (hE : EnvTy boxes tenv env) :
    ∀ (es : List SrcExpr) {ts : List SrcType}, exprTys boxes tenv es = some ts → liveExprs es = true →
      ∃ vs, pexprs env es = some vs ∧ PTys boxes ts vs
  | [], ts, ht, _ => by
    simp only [exprTys, Option.some.injEq] at ht
    subst ht
    exact ⟨[], rfl, .nil⟩
  | e :: es, ts, ht, live => by
    simp only [liveExprs, Bool.and_eq_true] at live
    simp only [exprTys, Option.bind_eq_some_iff, Option.map_eq_some_iff] at ht
    obtain ⟨t, het, ts', hts, rfl⟩ := ht
    obtain ⟨v, hv, rv⟩ := expr_live hE e het live.1
    obtain ⟨vs, hvs, rvs⟩ := exprs_live hE es hts live.2
    exact ⟨v :: vs, by simp [pexprs, hv, hvs], .cons rv rvs⟩

/-! ## Typed environments -/

theorem EnvTy.cons {boxes : Boxes} {tenv : TEnv} {env : Env} (h : EnvTy boxes tenv env) {x : Nat}
    {t : SrcType} {v : Value} (hv : PTy boxes t v) : EnvTy boxes ((x, t) :: tenv) ((x, v) :: env) := by
  intro y t' ht
  rw [TEnv.get?_cons] at ht
  rw [Env.get?_cons']
  by_cases hy : x = y
  · simp only [hy, if_true, Option.some.injEq] at ht ⊢
    subst ht
    exact ⟨v, rfl, hv⟩
  · simp only [hy, if_false] at ht ⊢
    exact h y t' ht

theorem EnvTy.cons' {boxes : Boxes} {tenv : TEnv} {env : Env} (h : EnvTy boxes tenv env)
    {a : Nat × SrcType} {b : Nat × Value} (hab : a.1 = b.1 ∧ PTy boxes a.2 b.2) :
    EnvTy boxes (a :: tenv) (b :: env) := by
  obtain ⟨x, t⟩ := a
  obtain ⟨y, v⟩ := b
  obtain ⟨hxy, hv⟩ := hab
  simp only at hxy hv
  subst hxy
  exact h.cons hv

theorem EnvTy.bindAll {boxes : Boxes} {as : List (Nat × SrcType)} {bs : List (Nat × Value)}
    (r : ListRel (fun a b => a.1 = b.1 ∧ PTy boxes a.2 b.2) as bs) :
    ∀ {tenv : TEnv} {env : Env}, EnvTy boxes tenv env → EnvTy boxes (tenv.bindAll as) (env.bindAll bs) := by
  induction r with
  | nil => exact fun h => h
  | cons hab _ ih => exact fun h => ih (h.cons' hab)

theorem EnvTy.nil (boxes : Boxes) (env : Env) : EnvTy boxes [] env := by
  intro x t ht
  simp [TEnv.get?] at ht

theorem PTys.zip_rel {boxes : Boxes} : ∀ {ts : List SrcType} {vs : List Value}, PTys boxes ts vs →
    ∀ (ids : List Nat), ListRel (fun a b => a.1 = b.1 ∧ PTy boxes a.2 b.2) (ids.zip ts) (ids.zip vs)
  | _, _, .nil, ids => by simp only [List.zip_nil_right]; exact .nil
  | _, _, .cons hv hs, ids => by
    cases ids with
    | nil => simp only [List.zip_nil_left]; exact .nil
    | cons x ids => exact .cons ⟨rfl, hv⟩ (hs.zip_rel ids)

theorem PTys.length {boxes : Boxes} : ∀ {ts : List SrcType} {vs : List Value}, PTys boxes ts vs →
    ts.length = vs.length
  | _, _, .nil => rfl
  | _, _, .cons _ hs => by simp [hs.length]

theorem paramEnv_ty {boxes : Boxes} {params : List SrcParam} {vs : List Value}
    (h : PTys boxes (params.map (·.ty)) vs) : EnvTy boxes (paramTEnv params) (paramEnv params vs) := by
  have e : params.map (fun p => (p.id, p.ty)) = (paramIds params).zip (params.map (·.ty)) := by
    clear h
    induction params with
    | nil => rfl
    | cons p ps ih => simp only [List.map_cons, paramIds, List.zip_cons_cons] at ih ⊢; rw [ih]
  rw [paramTEnv, paramEnv, paramBindings_ids, e]
  exact EnvTy.bindAll (h.zip_rel _) (EnvTy.nil _ _)

/-! ## Division by a constant that cannot fail -/

theorem divide_live {op : SrcDivOp} {tl : SrcType} {lv rv : Value} {r : SrcExpr}
    (ok : divisorOk (.ePure r) = true) (hl : STy tl lv) {boxes : Boxes} {tenv : TEnv} {env : Env}
    (htr : exprTy boxes tenv r = some tl) (hr : pexpr env r = some rv) :
    ∃ v, evalBinaryValue .x86_64 op.toCore lv rv = .ok v := by
  cases r with
  | int n =>
    simp only [divisorOk, Bool.and_eq_true, bne_iff_ne, ne_eq] at ok
    simp only [exprTy, Option.some.injEq] at htr
    simp only [pexpr, Option.some.injEq] at hr
    subst htr hr
    obtain ⟨a, rfl, -⟩ := hl
    have h0 : n.toInt ≠ 0 := fun e => ok.1 (BitVec.toInt_inj.mp (by rw [e]; rfl))
    have h1 : n.toInt ≠ -1 := fun e => ok.2 (BitVec.toInt_inj.mp (by rw [e]; rfl))
    cases op <;> simp [SrcDivOp.toCore, evalBinaryValue, evalSignedBinary, h0, h1]
  | unsigned k n =>
    simp only [divisorOk, bne_iff_ne, ne_eq] at ok
    simp only [exprTy] at htr
    split at htr
    · simp only [Option.some.injEq] at htr
      simp only [pexpr, Option.some.injEq] at hr
      subst htr hr
      obtain ⟨a, rfl, -⟩ := hl
      have h0 : n.toNat ≠ 0 := fun e => ok (BitVec.eq_of_toNat_eq (by rw [e]; rfl))
      cases op <;> simp [SrcDivOp.toCore, evalBinaryValue, evalUnsignedBinary, h0]
    · simp at htr
  | boolean _ | «local» _ | field _ _ | negate _ | «not» _ | apply _ _ _ | cast _ _ | null | char _
  | float _ _ => simp [divisorOk] at ok

/-! ## Prims -/

theorem unbox_pty {boxes : Boxes} {id : Nat} {t : SrcType} {v : Value} (hb : boxes id = some t)
    (h : PTy boxes (.struct id [.ptr]) v) : PTy boxes t v := by
  cases h with
  | scalar s => exact s.elim
  | struct none _ => simp [hb] at none
  | box hb' hv => rw [hb] at hb'; cases hb'; exact hv

/-- The prims are the identity from their parameter's type to their return
type: what `pcall_live` needs of `PrimsOk`. -/
def PrimsTy (sp : SrcProgram) (prims : Prims) : Prop :=
  ∀ c f, prims.isPrim c = true → sp.funcs[c]? = some f → ∀ vs,
    PTys (boxElem sp prims) (f.params.map (·.ty)) vs → ∃ v, single vs = some v ∧ PTy (boxElem sp prims) f.ret v

theorem primsTy_of {sp : SrcProgram} {prims : Prims} (hP : PrimsOk sp prims) : PrimsTy sp prims := by
  intro c f hp hf vs hvs
  simp only [Prims.isPrim, Bool.or_eq_true, List.contains_iff_mem] at hp
  rcases hp with hb | hu
  · obtain ⟨t, id, _, _, _, hc, -, -, -, -, hbox, -⟩ := hP.1 c hb
    rw [hc, Option.some.injEq] at hf
    subst hf
    cases hvs with
    | cons hv hs =>
      cases hs
      exact ⟨_, rfl, .box hbox hv⟩
  · obtain ⟨t, id, _, hc, -, -, hbox⟩ := hP.2 c hu
    rw [hc, Option.some.injEq] at hf
    subst hf
    cases hvs with
    | cons hv hs =>
      cases hs
      exact ⟨_, rfl, unbox_pty hbox hv⟩

/-! ## Eventually some -/

/-- From some fuel on, `g` gives one value, and it has property `P`. -/
def EvSome {α : Type} (g : Nat → Option α) (P : α → Prop) : Prop :=
  ∃ N a, P a ∧ ∀ m, N ≤ m → g m = some a

theorem EvSome.const {α : Type} {P : α → Prop} {g : Nat → Option α} {a : α} (hg : ∀ m, g m = some a)
    (ha : P a) : EvSome g P :=
  ⟨0, a, ha, fun m _ => hg m⟩

theorem EvSome.of_eq {α : Type} {P : α → Prop} {g h : Nat → Option α} (e : ∀ m, g m = h m)
    (hh : EvSome h P) : EvSome g P := by
  obtain ⟨N, a, pa, hN⟩ := hh
  exact ⟨N, a, pa, fun m hm => (e m).trans (hN m hm)⟩

theorem EvSome.bind {α β : Type} {P : α → Prop} {Q : β → Prop} {x : Nat → Option α}
    {k : α → Nat → Option β} (hx : EvSome x P) (hk : ∀ a, P a → (∃ M, x M = some a) → EvSome (k a) Q) :
    EvSome (fun m => (x m).bind fun a => k a m) Q := by
  obtain ⟨N, a, pa, hN⟩ := hx
  obtain ⟨M, b, qb, hM⟩ := hk a pa ⟨N, hN N (Nat.le_refl _)⟩
  refine ⟨max N M, b, qb, fun m hm => ?_⟩
  simp only [hN m (by omega), Option.bind_some]
  exact hM m (by omega)

theorem EvSome.map {α β : Type} {P : α → Prop} {Q : β → Prop} {x : Nat → Option α} {f : α → β}
    (hx : EvSome x P) (hf : ∀ a, P a → Q (f a)) : EvSome (fun m => (x m).map f) Q := by
  obtain ⟨N, a, pa, hN⟩ := hx
  exact ⟨N, f a, hf a pa, fun m hm => by simp only [hN m hm, Option.map_some]⟩

theorem EvSome.pair {α β γ : Type} {P : α → Prop} {Q : β → Prop} {R : γ → Prop} {x : Nat → Option α}
    {y : Nat → Option β} (f : Option α → Option β → Option γ) (hx : EvSome x P) (hy : EvSome y Q)
    (hf : ∀ a b, P a → Q b → ∃ c, f (some a) (some b) = some c ∧ R c) :
    EvSome (fun m => f (x m) (y m)) R := by
  obtain ⟨N, a, pa, hN⟩ := hx
  obtain ⟨M, b, qb, hM⟩ := hy
  obtain ⟨c, hc, rc⟩ := hf a b pa qb
  exact ⟨max N M, c, rc, fun m hm => by show f (x m) (y m) = some c; rw [hN m (by omega), hM m (by omega), hc]⟩

theorem EvSome.lift {α β : Type} {P : α → Prop} {Q : β → Prop} {x : Nat → Option α}
    (f : Option α → Option β) (hx : EvSome x P) (hf : ∀ a, P a → ∃ b, f (some a) = some b ∧ Q b) :
    EvSome (fun m => f (x m)) Q := by
  obtain ⟨N, a, pa, hN⟩ := hx
  obtain ⟨b, hb, qb⟩ := hf a pa
  exact ⟨N, b, qb, fun m hm => by show f (x m) = some b; rw [hN m hm, hb]⟩

/-! ## Calls -/

section
variable {sp : SrcProgram} {prims : Prims} {T : TermInfo} {me : TermAnn} {B : Nat}

theorem callBelow {W : Wit} (hW : WitOk B W) {c : Nat} {cs : List SizeCls} {vs : List Value}
    (hc : callOk prims T me W c cs = true) (hr0 : ListRel (SizeCls.holds B) cs vs) :
    prims.isPrim c = true ∨ ∃ a, T.ann c = some a ∧ Below me B a (argSize a.pos vs) := by
  have hr := hr0.res hW
  unfold callOk at hc
  simp only [Bool.or_eq_true] at hc
  rcases hc with hp | hc
  · exact .inl hp
  · split at hc
    · simp at hc
    · rename_i a ha
      refine .inr ⟨a, ha, ?_⟩
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

/-- A call of `c` on arguments of its parameters' types settles to a value of
its return type. -/
def GoodCall (sp : SrcProgram) (prims : Prims) (c : Nat) (vs : List Value) : Prop :=
  ∀ f, sp.funcs[c]? = some f → PTys (boxElem sp prims) (f.params.map (·.ty)) vs →
    EvSome (fun m => pcall sp prims m c vs) (PTy (boxElem sp prims) f.ret)

variable {outside bad : List Nat}

/-- What the bodies' calls assume: calls of smaller measure, of functions
neither prims, `outside` nor `bad`, are good. -/
def CallsGood (sp : SrcProgram) (prims : Prims) (T : TermInfo) (me : TermAnn) (B : Nat)
    (outside bad : List Nat) : Prop :=
  ∀ c a vs, T.ann c = some a → Below me B a (argSize a.pos vs) → prims.isPrim c = false →
    outside.contains c = false → bad.contains c = false → GoodCall sp prims c vs

theorem call_live (hP : PrimsTy sp prims) (IH : CallsGood sp prims T me B outside bad)
    {W : Wit} (hW : WitOk B W) {c : Nat} {cs : List SizeCls} {vs : List Value}
    (hc : callOk prims T me W c cs = true) (hr0 : ListRel (SizeCls.holds B) cs vs)
    {ts : List SrcType} {t : SrcType} (hct : callTy sp outside c ts = some t)
    (hts : PTys (boxElem sp prims) ts vs) (hbad : bad.contains c = false) :
    EvSome (fun m => pcall sp prims m c vs) (PTy (boxElem sp prims) t) := by
  simp only [callTy] at hct
  split at hct
  · simp at hct
  · rename_i hout
    split at hct
    · rename_i f hf
      split at hct
      · rename_i same
        simp only [Option.some.injEq] at hct
        subst hct
        rw [typesSame_eq _ same] at hts
        cases hp : prims.isPrim c with
        | true =>
          obtain ⟨v, hv, rv⟩ := hP c f hp hf vs hts
          refine ⟨1, v, rv, fun m hm => ?_⟩
          obtain ⟨m, rfl⟩ : ∃ m', m = m' + 1 := ⟨m - 1, by omega⟩
          simp [pcall, hp, hv]
        | false =>
          rcases callBelow hW hc hr0 with hp' | ⟨a, ha, hb⟩
          · simp [hp] at hp'
          · exact IH c a vs ha hb hp (by simpa using hout) hbad f hf hts
      · simp at hct
    · simp at hct
end

/-! ## Operators on typed values -/

theorem apply_live {boxes : Boxes} {op : SrcOp} {tl tr t : SrcType} {a b : Value}
    (ht : opTy op tl tr = some t) (notShift : isShiftOp op = false) (pa : PTy boxes tl a) (pb : PTy boxes tr b) :
    ∃ c, applyOp op (some a) (some b) = some c ∧ PTy boxes t c := by
  by_cases isB : op = .logicalAnd ∨ op = .logicalOr
  · obtain ⟨rfl, rfl, rfl⟩ := opTy_bool isB ht
    obtain ⟨bl, rfl⟩ := bool_value pa
    obtain ⟨br, rfl⟩ := bool_value pb
    rcases isB with rfl | rfl <;> cases bl <;>
      exact ⟨_, by simp [applyOp, asBool]; rfl, .scalar ⟨_, rfl⟩⟩
  have notAnd : op ≠ .logicalAnd := fun e => isB (.inl e)
  have notOr : op ≠ .logicalOr := fun e => isB (.inr e)
  obtain ⟨rfl, cmp⟩ := opTy_same ht notAnd notOr
  have scal : scalarTy tr = true := by
    rcases cmp with rfl | rfl | num
    · simp only [opTy, Bool.and_eq_true] at ht; split at ht <;> simp_all
    · simp only [opTy, Bool.and_eq_true] at ht; split at ht <;> simp_all
    · exact numTy_scalarTy num
  have sl := pa.sty scal
  have sr := pb.sty scal
  obtain ⟨w, hw⟩ := binary_live ht notAnd notOr sl sr (by simp [notShift])
  refine ⟨w, ?_, .scalar (binary_sty sl ht notAnd notOr hw)⟩
  simp only [applyOp_other notAnd notOr, binary, Option.bind_some, Lanius.Faithful.target, hw]
  rfl

theorem neg_live {boxes : Boxes} {to t : SrcType} {a : Value} (hn : numOf to = some t) (pa : PTy boxes to a) :
    ∃ c, (some a).bind (unary .negate) = some c ∧ PTy boxes t c := by
  obtain ⟨rfl, num⟩ := numOf_some hn
  have sa := pa.sty (numTy_scalarTy num)
  cases hw : evalUnaryValue .x86_64 .negate a with
  | error reason => exact (neg_ok num sa hw).elim
  | ok w =>
    refine ⟨w, ?_, .scalar (neg_sty sa hw)⟩
    simp only [Option.bind_some, unary, Lanius.Faithful.target, hw]
    rfl

theorem not_live {boxes : Boxes} {to t : SrcType} {a : Value} (hb : boolOf to = some t) (pa : PTy boxes to a) :
    ∃ c, (some a).bind (unary .logicalNot) = some c ∧ PTy boxes t c := by
  obtain ⟨rfl, rfl⟩ := boolOf_some hb
  have sa := pa.sty rfl
  cases hw : evalUnaryValue .x86_64 .logicalNot a with
  | error reason => exact (not_ok sa hw).elim
  | ok w =>
    refine ⟨w, ?_, .scalar (not_sty hw)⟩
    simp only [Option.bind_some, unary, Lanius.Faithful.target, hw]
    rfl

theorem cast_live {boxes : Boxes} {ty to t : SrcType} {a : Value} (hc : castTy ty to = some t)
    (pa : PTy boxes to a) : ∃ c, (some a).bind (cast ty) = some c ∧ PTy boxes t c := by
  obtain ⟨rfl, num, numTo⟩ := castTy_some hc
  have sa := pa.sty (numTy_scalarTy num)
  cases hw : evalScalarCast .x86_64 t.toScalar a with
  | error reason => exact (cast_ok num numTo sa hw).elim
  | ok w =>
    refine ⟨w, ?_, .scalar (cast_sty sa numTo hw)⟩
    simp only [Option.bind_some, cast, Lanius.Faithful.target, hw]
    rfl

theorem structTy_some {boxes : Boxes} {ty t : SrcType} {ts : List SrcType} (h : structTy boxes ty ts = some t) :
    ∃ id fs, ty = .struct id fs ∧ t = ty ∧ boxes id = none ∧ ts = fs := by
  cases ty with
  | struct id fs =>
    simp only [structTy, Bool.and_eq_true, Option.isNone_iff_eq_none] at h
    split at h
    · rename_i ok
      simp only [Option.some.injEq] at h
      exact ⟨id, fs, rfl, h.symm, ok.1, typesSame_eq _ ok.2⟩
    · simp at h
  | i32 | bool | uint _ | enum _ _ | ptr | slice _ | unit | isize | char | float _ | sint _ | array _ _ | view | str =>
    simp [structTy] at h

theorem variantTy_some {ty t : SrcType} {k : Nat} {ts : List SrcType} (h : variantTy ty k ts = some t) :
    ∃ id variants fs, ty = .enum id variants ∧ t = ty ∧ variants[k]? = some fs ∧ ts = fs := by
  cases ty with
  | enum id variants =>
    simp only [variantTy] at h
    split at h
    · rename_i fs hfs
      split at h
      · rename_i same
        simp only [Option.some.injEq] at h
        exact ⟨id, variants, fs, rfl, h.symm, hfs, typesSame_eq _ same⟩
      · simp at h
    · simp at h
  | i32 | bool | uint _ | struct _ _ | ptr | slice _ | unit | isize | char | float _ | sint _ | array _ _ | view | str =>
    simp [variantTy] at h

theorem PTy.enum_inv {boxes : Boxes} {id : Nat} {variants : List (List SrcType)} {v : Value}
    (h : PTy boxes (.enum id variants) v) :
    ∃ k fs payload, v = .enumeration id k payload ∧ variants[k]? = some fs ∧ PTys boxes fs payload := by
  cases h with
  | scalar s => exact s.elim
  | enum hk hs => exact ⟨_, _, _, rfl, hk, hs⟩

theorem matchPatterns_zip : ∀ (bs : List Nat) (ps : List Value), bs.length = ps.length →
    matchPatterns (bs.map Core.Pattern.bind) ps = some (bs.zip ps)
  | [], [], _ => rfl
  | [], _ :: _, h => by simp at h
  | _ :: _, [], h => by simp at h
  | b :: bs, p :: ps, h => by
    simp only [List.map_cons, matchPatterns, matchPattern, matchPatterns_zip bs ps (by simpa using h),
      List.zip_cons_cons]
    rfl

theorem matchPattern_variant (id j k : Nat) (pats : List Core.Pattern) (payload : List Value) :
    matchPattern (.enumVariant id j pats) (.enumeration id k payload) =
      if j = k then matchPatterns pats payload else none := by
  simp only [matchPattern, beq_self_eq_true, Bool.true_and, beq_iff_eq]

/-! ## Checked effects settle to values of their types -/

section
variable {sp : SrcProgram} {prims : Prims} {T : TermInfo} {me : TermAnn} {B : Nat} {outside bad : List Nat}

mutual
theorem eff_live (hO : ∀ m, OracleOk prims T (pcall sp prims m)) (hP : PrimsTy sp prims)
    (IH : CallsGood sp prims T me B outside bad) :
    ∀ (e : SrcEff) {A : AEnv} {W : Wit} {E : Env} {tenv : TEnv} {t : SrcType}, EnvOk B A E → WitOk B W →
      chkEff prims T me A W e = true → EnvTy (boxElem sp prims) tenv E →
      effTy sp outside (boxElem sp prims) tenv e = some t → liveEff bad e = true →
      EvSome (fun m => peff (pcall sp prims m) E e) (PTy (boxElem sp prims) t)
  | .ePure x, A, W, E, tenv, t, _, _, _, hE, ht, hl => by
    simp only [effTy] at ht
    simp only [liveEff] at hl
    obtain ⟨v, hv, rv⟩ := expr_live hE x ht hl
    exact EvSome.const (fun m => by simp only [peff, hv]) rv
  | .eCall c args, A, W, E, tenv, t, h, hW, hc, hE, ht, hl => by
    simp only [chkEff, Bool.and_eq_true] at hc
    simp only [liveEff, Bool.and_eq_true, Bool.not_eq_true'] at hl
    simp only [effTy, Option.bind_eq_some_iff] at ht
    obtain ⟨ts, hts, hct⟩ := ht
    simp only [peff]
    exact EvSome.bind (effs_live hO hP IH args h hW hc.1 hE hts hl.2) fun vs hvs ⟨M, hM⟩ =>
      call_live hP IH hW hc.2 (effsCls_holds (hO M) h args hM) hct hvs hl.1
  | .eApply op l r, A, W, E, tenv, t, h, hW, hc, hE, ht, hl => by
    simp only [chkEff, Bool.and_eq_true] at hc
    simp only [liveEff, Bool.and_eq_true, Bool.not_eq_true'] at hl
    simp only [effTy, Option.bind_eq_some_iff] at ht
    obtain ⟨tl, htl, tr, htr, ht⟩ := ht
    simp only [peff]
    exact EvSome.pair (applyOp op) (eff_live hO hP IH l h hW hc.1 hE htl hl.1.2)
      (eff_live hO hP IH r h hW hc.2 hE htr hl.2) fun a b pa pb => apply_live ht hl.1.1 pa pb
  | .eNeg x, A, W, E, tenv, t, h, hW, hc, hE, ht, hl => by
    simp only [chkEff] at hc
    simp only [liveEff] at hl
    simp only [effTy, Option.bind_eq_some_iff] at ht
    obtain ⟨to, hto, hn⟩ := ht
    simp only [peff]
    exact EvSome.lift (fun o => o.bind (unary .negate)) (eff_live hO hP IH x h hW hc hE hto hl)
      fun a pa => neg_live hn pa
  | .eNot x, A, W, E, tenv, t, h, hW, hc, hE, ht, hl => by
    simp only [chkEff] at hc
    simp only [liveEff] at hl
    simp only [effTy, Option.bind_eq_some_iff] at ht
    obtain ⟨to, hto, hn⟩ := ht
    simp only [peff]
    exact EvSome.lift (fun o => o.bind (unary .logicalNot)) (eff_live hO hP IH x h hW hc hE hto hl)
      fun a pa => not_live hn pa
  | .eCast ty x, A, W, E, tenv, t, h, hW, hc, hE, ht, hl => by
    simp only [chkEff] at hc
    simp only [liveEff] at hl
    simp only [effTy, Option.bind_eq_some_iff] at ht
    obtain ⟨to, hto, hn⟩ := ht
    simp only [peff]
    exact EvSome.lift (fun o => o.bind (cast ty)) (eff_live hO hP IH x h hW hc hE hto hl)
      fun a pa => cast_live hn pa
  | .eIndex _ _, A, W, E, tenv, t, _, _, _, _, ht, _ => by simp [effTy] at ht
  | .eStruct ty fields, A, W, E, tenv, t, h, hW, hc, hE, ht, hl => by
    simp only [chkEff] at hc
    simp only [liveEff] at hl
    simp only [effTy, Option.bind_eq_some_iff] at ht
    obtain ⟨ts, hts, hst⟩ := ht
    obtain ⟨id, fs, rfl, rfl, hb, rfl⟩ := structTy_some hst
    simp only [peff]
    exact EvSome.map (effs_live hO hP IH fields h hW hc hE hts hl) fun vs hvs => .struct hb hvs
  | .eVariant ty k payload, A, W, E, tenv, t, h, hW, hc, hE, ht, hl => by
    simp only [chkEff] at hc
    simp only [liveEff] at hl
    simp only [effTy, Option.bind_eq_some_iff] at ht
    obtain ⟨ts, hts, hvt⟩ := ht
    obtain ⟨id, variants, fs, rfl, rfl, hk, rfl⟩ := variantTy_some hvt
    simp only [peff]
    exact EvSome.map (effs_live hO hP IH payload h hW hc hE hts hl) fun vs hvs => .enum hk hvs
  | .eMatch scrutinee ety rty binders values, A, W, E, tenv, t, h, hW, hc, hE, ht, hl => by
    simp only [chkEff, Bool.and_eq_true] at hc
    simp only [liveEff, Bool.and_eq_true] at hl
    simp only [effTy, Option.bind_eq_some_iff] at ht
    obtain ⟨st, hst, ht⟩ := ht
    cases ety
    case enum eid variants =>
      dsimp only at ht
      split at ht
      · rename_i ok
        simp only [Option.some.injEq] at ht
        subst ht
        simp only [Bool.and_eq_true] at ok
        have e := SrcType.same_eq ok.1
        subst e
        simp only [armsFull, beq_iff_eq] at hl
        simp only [peff]
        refine EvSome.bind (eff_live hO hP IH scrutinee h hW hc.1 hE hst hl.1.1) fun v hv ⟨M, hM⟩ => ?_
        obtain ⟨k, fs, payload, rfl, hk, hpt⟩ := hv.enum_inv
        exact arms_live hO hP IH (effCls_holds (hO M) h scrutinee hM) rfl hpt values 0 binders variants
          h hW hc.2 hE ok.2 hl.1.2 hl.2 (Nat.zero_le _) (by simpa using hk)
      · simp at ht
    all_goals simp at ht
  | .eDivide op l r, A, W, E, tenv, t, h, hW, hc, hE, ht, hl => by
    simp only [chkEff, Bool.and_eq_true] at hc
    simp only [liveEff, Bool.and_eq_true] at hl
    simp only [effTy, Option.bind_eq_some_iff] at ht
    obtain ⟨tl, htl, tr, htr, ht⟩ := ht
    obtain ⟨rfl, num, rfl⟩ := divTy_some ht
    cases r
    case ePure x =>
      simp only [effTy] at htr
      have lx : liveExpr x = true := by cases x <;> simp_all [divisorOk, liveExpr]
      obtain ⟨b, hb, -⟩ := expr_live hE x htr lx
      simp only [peff, hb]
      refine EvSome.lift (fun o => binary op.toCore o (some b)) (eff_live hO hP IH l h hW hc.1 hE htl hl.1)
        fun a pa => ?_
      have sa := pa.sty (numTy_scalarTy num)
      obtain ⟨w, hw⟩ := divide_live (op := op) hl.2 sa htr hb
      exact ⟨w, by simp only [binary, Option.bind_some, Lanius.Faithful.target, hw]; rfl,
        .scalar (divide_sty sa hw)⟩
    all_goals simp [divisorOk] at hl
  | .eStride _, A, W, E, tenv, t, _, _, _, _, ht, _ => by simp [effTy] at ht
  | .arraySlice _ _, A, W, E, tenv, t, _, _, _, _, ht, _ => by simp [effTy] at ht
  | .eIf c ty a b, A, W, E, tenv, t, h, hW, hc, hE, ht, hl => by
    simp only [chkEff, Bool.and_eq_true] at hc
    simp only [liveEff, Bool.and_eq_true] at hl
    simp only [effTy] at ht
    split at ht
    · rename_i hcb
      have hct := isBoolTy_some hcb
      simp only [Option.bind_eq_some_iff] at ht
      obtain ⟨ta, hta, tb, htb, hab⟩ := ht
      split at hab
      · rename_i same
        simp only [Option.some.injEq] at hab
        subst hab
        have e := SrcType.same_eq same
        subst e
        simp only [peff]
        refine EvSome.bind (k := fun w m => (asBool w).bind fun bv =>
            if bv then peff (pcall sp prims m) E a else peff (pcall sp prims m) E b)
          (eff_live hO hP IH c h hW hc.1.1 hE hct hl.1.1) fun w hw _ => ?_
        obtain ⟨bv, rfl⟩ := bool_value hw
        cases bv with
        | true => exact EvSome.of_eq (fun m => rfl) (eff_live hO hP IH a h hW hc.1.2 hE hta hl.1.2)
        | false => exact EvSome.of_eq (fun m => rfl) (eff_live hO hP IH b h hW hc.2 hE htb hl.2)
      · simp at hab
    · simp at ht
  | .eLet id ty value rt body, A, W, E, tenv, t, h, hW, hc, hE, ht, hl => by
    simp only [chkEff, Bool.and_eq_true] at hc
    simp only [liveEff, Bool.and_eq_true] at hl
    simp only [effTy, Option.bind_eq_some_iff] at ht
    obtain ⟨tv, htv, hb⟩ := ht
    simp only [peff]
    exact EvSome.bind (eff_live hO hP IH value h hW hc.1 hE htv hl.1) fun v hv ⟨M, hM⟩ =>
      eff_live hO hP IH body (h.cons (effCls_holds (hO M) h value hM)) hW hc.2 (hE.cons hv) hb hl.2
  | .eLen _, A, W, E, tenv, t, _, _, _, _, ht, _ | .eStr _ _, A, W, E, tenv, t, _, _, _, _, ht, _ => by simp [effTy] at ht

theorem effs_live (hO : ∀ m, OracleOk prims T (pcall sp prims m)) (hP : PrimsTy sp prims)
    (IH : CallsGood sp prims T me B outside bad) :
    ∀ (es : List SrcEff) {A : AEnv} {W : Wit} {E : Env} {tenv : TEnv} {ts : List SrcType}, EnvOk B A E →
      WitOk B W → chkEffs prims T me A W es = true → EnvTy (boxElem sp prims) tenv E →
      effTys sp outside (boxElem sp prims) tenv es = some ts → liveEffs bad es = true →
      EvSome (fun m => peffs (pcall sp prims m) E es) (PTys (boxElem sp prims) ts)
  | [], A, W, E, tenv, ts, _, _, _, _, ht, _ => by
    simp only [effTys, Option.some.injEq] at ht
    subst ht
    exact EvSome.const (a := []) (fun m => by simp only [peffs]) .nil
  | e :: es, A, W, E, tenv, ts, h, hW, hc, hE, ht, hl => by
    simp only [chkEffs, Bool.and_eq_true] at hc
    simp only [liveEffs, Bool.and_eq_true] at hl
    simp only [effTys, Option.bind_eq_some_iff, Option.map_eq_some_iff] at ht
    obtain ⟨t, het, ts', hts, rfl⟩ := ht
    simp only [peffs]
    exact EvSome.pair (fun o os => o.bind fun v => os.map (v :: ·))
      (eff_live hO hP IH e h hW hc.1 hE het hl.1) (effs_live hO hP IH es h hW hc.2 hE hts hl.2)
      fun a b pa pb => ⟨a :: b, by simp, .cons pa pb⟩

theorem arms_live (hO : ∀ m, OracleOk prims T (pcall sp prims m)) (hP : PrimsTy sp prims)
    (IH : CallsGood sp prims T me B outside bad) {c : SizeCls} {v : Value} (hv : c.holds B v)
    {id k : Nat} {payload : List Value} {fs : List SrcType} (hval : v = .enumeration id k payload)
    (hpt : PTys (boxElem sp prims) fs payload) {rty : SrcType} :
    ∀ (values : List SrcEff) (j : Nat) (binders : List (List Nat)) (variants : List (List SrcType))
      {A : AEnv} {W : Wit} {E : Env} {tenv : TEnv},
      EnvOk B A E → WitOk B W → chkArms prims T me A W c id j binders values = true →
      EnvTy (boxElem sp prims) tenv E →
      armsOk sp outside (boxElem sp prims) tenv rty variants binders values = true →
      liveEffs bad values = true → variants.length = binders.length → j ≤ k → variants[k - j]? = some fs →
      EvSome (fun m => parms (pcall sp prims m) E v id j binders values) (PTy (boxElem sp prims) rty)
  | [], j, [], variants, A, W, E, tenv, _, _, _, _, _, _, len, _, hk => by
    simp only [List.length_nil, List.length_eq_zero_iff] at len
    subst len
    simp at hk
  | [], j, _ :: _, variants, A, W, E, tenv, _, _, _, _, ha, _, _, _, _ => by simp [armsOk] at ha
  | _ :: _, j, [], variants, A, W, E, tenv, _, _, _, _, ha, _, _, _, _ => by simp [armsOk] at ha
  | _ :: _, j, _ :: _, [], A, W, E, tenv, _, _, _, _, ha, _, _, _, _ => by simp [armsOk] at ha
  | value :: values, j, bs :: rest, fs' :: variants, A, W, E, tenv, h, hW, hc, hE, ha, hl, len, hj, hk => by
    rw [chkArms] at hc
    replace hc := Bool.and_eq_true_iff.mp hc
    rw [armsOk] at ha
    have ha1 := Bool.and_eq_true_iff.mp ha
    have ha2 := Bool.and_eq_true_iff.mp ha1.1
    have hlen := beq_iff_eq.mp ha2.1
    have harm := ha2.2
    have hrest := ha1.2
    simp only [liveEffs, Bool.and_eq_true] at hl
    simp only [List.length_cons, Nat.add_right_cancel_iff] at len
    subst hval
    by_cases hjk : j = k
    · subst hjk
      simp only [Nat.sub_self, List.getElem?_cons_zero, Option.some.injEq] at hk
      subst hk
      have hm : matchPattern (.enumVariant id j (bs.map .bind)) (.enumeration id j payload) =
          some (bs.zip payload) := by
        rw [matchPattern_variant, if_pos rfl]
        exact matchPatterns_zip _ _ (by rw [hlen, hpt.length])
      simp only [parms, hm]
      cases hty : effTy sp outside (boxElem sp prims) (tenv.bindAll (bs.zip fs')) value with
      | none => rw [hty] at harm; simp at harm
      | some t =>
        rw [hty] at harm
        have e := SrcType.same_eq harm
        subst e
        exact eff_live hO hP IH value (EnvOk.bindAll (match_binds hv hm) h) (hW.arm hv hm) hc.1
          (EnvTy.bindAll (hpt.zip_rel bs) hE) hty hl.1
    · have hm : matchPattern (.enumVariant id j (bs.map .bind)) (.enumeration id k payload) = none := by
        rw [matchPattern_variant, if_neg hjk]
      simp only [parms, hm]
      have e : k - j = (k - (j + 1)) + 1 := by omega
      rw [e] at hk
      exact arms_live hO hP IH hv rfl hpt values (j + 1) rest variants h hW hc.2 hE hrest hl.2 len
        (by omega) (by simpa using hk)
end

end

/-! ## Checked statements settle -/

/-- How a statement of a function returning `ret` ended: on, with the locals
of `tenv` of their types, or a return of a value of type `ret` (`return;`
only when it is `()`). -/
def OutOk (boxes : Boxes) (ret : SrcType) (tenv : TEnv) : Out → Prop
  | .next env => EnvTy boxes tenv env
  | .brk _ => False
  | .cont _ => False
  | .ret (some v) => PTy boxes ret v
  | .ret none => ret.toCore = .unit

/-- An assignment of a value of the local's type keeps the types. -/
theorem EnvTy.set {boxes : Boxes} {tenv : TEnv} {env env' : Env} (hE : EnvTy boxes tenv env) {id : Nat}
    {t : SrcType} {v : Value} (hg : tenv.get? id = some t) (rv : PTy boxes t v) (hs : env.set id v = some env') :
    EnvTy boxes tenv env' := by
  intro x t' ht
  by_cases hx : x = id
  · subst hx
    rw [hg, Option.some.injEq] at ht
    subst ht
    exact ⟨v, Env.set_get_self hs, rv⟩
  · rw [Env.set_get_ne hs hx]
    exact hE x t' ht

/-- After a `let`'s body, the types below its binding. -/
theorem EnvTy.pop {boxes : Boxes} {tenv : TEnv} {env eb : Env} {id : Nat} {t : SrcType} {v : Value}
    (hE : EnvTy boxes tenv env) (hb : EnvTy boxes ((id, t) :: tenv) eb) (ha : Agree [] ((id, v) :: env) eb) :
    EnvTy boxes tenv eb.tail := by
  intro x t' ht
  obtain ⟨-, hid, w, hw⟩ := ha.pop
  by_cases hx : x = id
  · subst hx
    rw [hid]
    exact hE x t' ht
  · have h := hb x t' (by rw [TEnv.get?_cons, if_neg (Ne.symm hx)]; exact ht)
    rw [hw, Env.get?_cons'', if_neg (Ne.symm hx)] at h
    exact h

theorem OutOk.pop {boxes : Boxes} {ret : SrcType} {tenv : TEnv} {env : Env} {id : Nat} {t : SrcType}
    {v : Value} {o : Out} (hE : EnvTy boxes tenv env) (ho : OutOk boxes ret ((id, t) :: tenv) o)
    (ha : ∀ e, o.env? = some e → Agree [] ((id, v) :: env) e) : OutOk boxes ret tenv o.pop := by
  cases o with
  | next eb => exact EnvTy.pop hE ho (ha eb rfl)
  | brk _ => exact ho.elim
  | cont _ => exact ho.elim
  | ret r => cases r <;> exact ho

/-- A `let`'s ending from its body's. -/
theorem EvSome.pop {P Q : Out → Prop} {g : Nat → Option Out} (h : EvSome g P)
    (hq : ∀ o, P o → (∃ M, g M = some o) → Q o.pop) : EvSome (fun m => (g m).map Out.pop) Q := by
  obtain ⟨N, a, pa, hN⟩ := h
  exact ⟨N, a.pop, hq a pa ⟨N, hN N (Nat.le_refl _)⟩, fun m hm => by simp only [hN m hm, Option.map_some]⟩

theorem unit_pty {boxes : Boxes} {ret : SrcType} (h : ret.toCore = .unit) : PTy boxes ret .unit := by
  cases ret with
  | unit => exact .scalar rfl
  | i32 | bool | uint _ | struct _ _ | enum _ _ | ptr | slice _ | array _ _ | isize | char | float _
  | sint _ | view _ | str => simp [SrcType.toCore] at h

section
variable {sp : SrcProgram} {prims : Prims} {T : TermInfo} {me : TermAnn} {B : Nat} {outside bad : List Nat}
  (hO : ∀ m, OracleOk prims T (pcall sp prims m)) (hP : PrimsTy sp prims)
  (IH : CallsGood sp prims T me B outside bad)
include hO hP IH

theorem stmt_live {ret : SrcType} :
    ∀ (s : SrcStmt) {A : AEnv} {W : Wit} {E : Env} {tenv : TEnv}, EnvOk B A E → WitOk B W →
      chkStmt prims T me A W s = true → EnvTy (boxElem sp prims) tenv E →
      stmtOk sp outside (boxElem sp prims) ret tenv s = true → liveStmt bad ret s = true →
      EvSome (fun m => mstmt (pcall sp prims m) m E s) (OutOk (boxElem sp prims) ret tenv) := by
  intro s
  induction s with
  | nop => intro A W E tenv _ _ _ hE _ _; exact EvSome.const (a := .next E) (fun m => rfl) hE
  | «let» id _ value body ih =>
    intro A W E tenv h hW hc hE hs hl
    simp only [chkStmt] at hc
    simp only [liveStmt, Bool.and_eq_true] at hl
    cases ht : exprTy (boxElem sp prims) tenv value with
    | none => simp [stmtOk, ht] at hs
    | some t =>
      simp only [stmtOk, ht] at hs
      obtain ⟨v, hv, rv⟩ := expr_live hE value ht hl.1
      simp only [mstmt, hv, Option.bind_some]
      exact EvSome.pop (ih (h.cons (exprCls_holds h value hv)) hW hc (hE.cons rv) hs hl.2)
        fun o ho ⟨M, hM⟩ => OutOk.pop hE ho (mstmt_agree _ _ body hM)
  | letStruct id ty fields body ih =>
    intro A W E tenv h hW hc hE hs hl
    simp only [chkStmt] at hc
    simp only [liveStmt, Bool.and_eq_true] at hl
    cases ht : (exprTys (boxElem sp prims) tenv fields).bind (structTy (boxElem sp prims) ty) with
    | none => simp [stmtOk, ht] at hs
    | some t =>
      simp only [stmtOk, ht] at hs
      simp only [Option.bind_eq_some_iff] at ht
      obtain ⟨ts, hts, hst⟩ := ht
      obtain ⟨sid, fs, rfl, rfl, hb, rfl⟩ := structTy_some hst
      obtain ⟨vs, hvs, rvs⟩ := exprs_live hE fields hts hl.1
      simp only [mstmt, hvs, Option.bind_some]
      exact EvSome.pop (ih (h.cons (by trivial)) hW hc (hE.cons (.struct hb rvs)) hs hl.2)
        fun o ho ⟨M, hM⟩ => OutOk.pop hE ho (mstmt_agree _ _ body hM)
  | letCall id _ callee args body ih =>
    intro A W E tenv h hW hc hE hs hl
    simp only [chkStmt, Bool.and_eq_true] at hc
    simp only [liveStmt, Bool.and_eq_true, Bool.not_eq_true'] at hl
    cases ht : (exprTys (boxElem sp prims) tenv args).bind (callTy sp outside callee) with
    | none => simp [stmtOk, ht] at hs
    | some t =>
      simp only [stmtOk, ht] at hs
      simp only [Option.bind_eq_some_iff] at ht
      obtain ⟨ts, hts, hct⟩ := ht
      obtain ⟨vs, hvs, rvs⟩ := exprs_live hE args hts hl.1.2
      have hr := exprsCls_holds h args hvs
      simp only [mstmt, hvs, Option.bind_some]
      exact EvSome.bind (call_live hP IH hW hc.1 hr hct rvs hl.1.1) fun v hv ⟨M, hM⟩ =>
        EvSome.pop (ih (h.cons (callCls_holds (hO M) hr hM)) hW hc.2 (hE.cons hv) hs hl.2)
          fun o ho ⟨M', hM'⟩ => OutOk.pop hE ho (mstmt_agree _ _ body hM')
  | letEnum id ty k payload body ih =>
    intro A W E tenv h hW hc hE hs hl
    simp only [chkStmt] at hc
    simp only [liveStmt, Bool.and_eq_true] at hl
    cases ht : (exprTys (boxElem sp prims) tenv payload).bind (variantTy ty k) with
    | none => simp [stmtOk, ht] at hs
    | some t =>
      simp only [stmtOk, ht] at hs
      simp only [Option.bind_eq_some_iff] at ht
      obtain ⟨ts, hts, hvt⟩ := ht
      obtain ⟨eid, variants, fs, rfl, rfl, hk, rfl⟩ := variantTy_some hvt
      obtain ⟨vs, hvs, rvs⟩ := exprs_live hE payload hts hl.1
      simp only [mstmt, hvs, Option.bind_some]
      exact EvSome.pop (ih (h.cons (by trivial)) hW hc (hE.cons (.enum hk rvs)) hs hl.2)
        fun o ho ⟨M, hM⟩ => OutOk.pop hE ho (mstmt_agree _ _ body hM)
  | «then» first second ih1 ih2 =>
    intro A W E tenv h hW hc hE hs hl
    simp only [chkStmt, Bool.and_eq_true] at hc
    simp only [stmtOk, Bool.and_eq_true] at hs
    simp only [liveStmt, Bool.and_eq_true] at hl
    simp only [mstmt]
    refine EvSome.bind (k := fun o m => Out.then (fun e => mstmt (pcall sp prims m) m e second) o)
      (ih1 h hW hc.1 hE hs.1 hl.1) fun o ho ⟨M, hM⟩ => ?_
    cases o with
    | next e1 => exact EvSome.of_eq (fun m => rfl) (ih2 (after_ok h _ M first hM) hW hc.2 ho hs.2 hl.2)
    | brk _ => exact ho.elim
    | cont _ => exact ho.elim
    | ret r => exact EvSome.const (fun m => rfl) ho
  | «if» condition a b iha ihb =>
    intro A W E tenv h hW hc hE hs hl
    simp only [chkStmt, Bool.and_eq_true] at hc
    simp only [stmtOk, Bool.and_eq_true] at hs
    simp only [liveStmt, Bool.and_eq_true] at hl
    have hct := isBoolTy_some hs.1.1
    obtain ⟨w, hw, rw⟩ := expr_live hE condition hct hl.1.1
    obtain ⟨bv, rfl⟩ := bool_value rw
    cases bv with
    | true =>
      simp only [mstmt, hw, Option.bind_some, asBool, ↓reduceIte]
      exact iha h hW hc.1 hE hs.1.2 hl.1.2
    | false =>
      simp only [mstmt, hw, Option.bind_some, asBool, Bool.false_eq_true, ↓reduceIte]
      have hc2 := hc.2
      revert hc2
      cases hg : guardVar condition with
      | none => exact fun hc2 => ihb h hW hc2 hE hs.2 hl.2
      | some xk => exact fun hc2 => ihb (h.refine (guard_ge hg hw rfl)) hW hc2 hE hs.2 hl.2
  | «return» value =>
    intro A W E tenv _ _ _ hE hs hl
    cases ht : exprTy (boxElem sp prims) tenv value with
    | none => simp [stmtOk, ht] at hs
    | some t =>
      simp only [stmtOk, ht] at hs
      have e := SrcType.same_eq hs
      subst e
      simp only [liveStmt] at hl
      obtain ⟨v, hv, rv⟩ := expr_live hE value ht hl
      exact EvSome.const (a := .ret (some v)) (fun m => by simp only [mstmt, hv, Option.map_some]) rv
  | letEval id _ value body ih =>
    intro A W E tenv h hW hc hE hs hl
    simp only [chkStmt, Bool.and_eq_true] at hc
    simp only [liveStmt, Bool.and_eq_true] at hl
    cases ht : effTy sp outside (boxElem sp prims) tenv value with
    | none => simp [stmtOk, ht] at hs
    | some t =>
      simp only [stmtOk, ht] at hs
      simp only [mstmt]
      exact EvSome.bind (eff_live hO hP IH value h hW hc.1 hE ht hl.1) fun v hv ⟨M, hM⟩ =>
        EvSome.pop (ih (h.cons (effCls_holds (hO M) h value hM)) hW hc.2 (hE.cons hv) hs hl.2)
          fun o ho ⟨M', hM'⟩ => OutOk.pop hE ho (mstmt_agree _ _ body hM')
  | ifEval condition a b iha ihb =>
    intro A W E tenv h hW hc hE hs hl
    simp only [chkStmt, Bool.and_eq_true] at hc
    simp only [stmtOk, Bool.and_eq_true] at hs
    simp only [liveStmt, Bool.and_eq_true] at hl
    have hct := isBoolTy_some hs.1.1
    simp only [mstmt]
    refine EvSome.bind (P := fun _ => True) (x := fun m => (peff (pcall sp prims m) E condition).bind asBool)
      (k := fun bv m => if bv then mstmt (pcall sp prims m) m E a else mstmt (pcall sp prims m) m E b) ?_
      fun bv _ _ => ?_
    · refine EvSome.bind (k := fun w _ => asBool w) (eff_live hO hP IH condition h hW hc.1.1 hE hct hl.1.1)
        fun w hw _ => ?_
      obtain ⟨bv, rfl⟩ := bool_value hw
      exact EvSome.const (a := bv) (fun m => rfl) trivial
    · cases bv with
      | true => exact EvSome.of_eq (fun m => rfl) (iha h hW hc.1.2 hE hs.1.2 hl.1.2)
      | false => exact EvSome.of_eq (fun m => rfl) (ihb h hW hc.2 hE hs.2 hl.2)
  | returnEval value =>
    intro A W E tenv h hW hc hE hs hl
    cases ht : effTy sp outside (boxElem sp prims) tenv value with
    | none => simp [stmtOk, ht] at hs
    | some t =>
      simp only [stmtOk, ht] at hs
      have e := SrcType.same_eq hs
      subst e
      simp only [chkStmt] at hc
      simp only [liveStmt] at hl
      simp only [mstmt]
      exact EvSome.map (eff_live hO hP IH value h hW hc hE ht hl) fun v hv => hv
  | discard value =>
    intro A W E tenv h hW hc hE hs hl
    simp only [stmtOk, Option.isSome_iff_exists] at hs
    obtain ⟨t, ht⟩ := hs
    simp only [chkStmt] at hc
    simp only [liveStmt] at hl
    simp only [mstmt]
    exact EvSome.map (eff_live hO hP IH value h hW hc hE ht hl) fun _ _ => hE
  | assert condition => intro A W E tenv _ _ _ _ _ hl; simp [liveStmt] at hl
  | returnUnit =>
    intro A W E tenv _ _ _ _ _ hl
    simp only [liveStmt, decide_eq_true_eq] at hl
    exact EvSome.const (a := .ret none) (fun m => rfl) hl
  | set id value =>
    intro A W E tenv _ _ _ hE hs hl
    simp only [liveStmt] at hl
    cases hg : tenv.get? id with
    | none => simp [stmtOk, setOk, hg] at hs
    | some t =>
      cases ht : exprTy (boxElem sp prims) tenv value with
      | none => simp [stmtOk, setOk, hg, ht] at hs
      | some t' =>
        simp only [stmtOk, setOk, hg, ht] at hs
        have e := SrcType.same_eq hs
        subst e
        obtain ⟨v, hv, rv⟩ := expr_live hE value ht hl
        obtain ⟨w, hw, -⟩ := hE id _ hg
        obtain ⟨E', hE'⟩ := Env.set_isSome (env := E) (id := id) v (by simp [hw])
        exact EvSome.const (a := .next E') (fun m => by simp only [mstmt, hv, Option.bind_some, hE', Option.map_some])
          (hE.set hg rv hE')
  | setEval id value =>
    intro A W E tenv h hW hc hE hs hl
    simp only [liveStmt] at hl
    simp only [chkStmt] at hc
    cases hg : tenv.get? id with
    | none => simp [stmtOk, setOk, hg] at hs
    | some t =>
      cases ht : effTy sp outside (boxElem sp prims) tenv value with
      | none => simp [stmtOk, setOk, hg, ht] at hs
      | some t' =>
        simp only [stmtOk, setOk, hg, ht] at hs
        have e := SrcType.same_eq hs
        subst e
        obtain ⟨w, hw, -⟩ := hE id _ hg
        simp only [mstmt]
        refine EvSome.bind (eff_live hO hP IH value h hW hc hE ht hl) fun v rv _ => ?_
        obtain ⟨E', hE'⟩ := Env.set_isSome (env := E) (id := id) v (by simp [hw])
        exact EvSome.const (a := .next E') (fun m => by simp only [hE', Option.map_some]) (hE.set hg rv hE')
  | «while» _ _ | whileEval _ _ | «break» | «continue» =>
    intro A W E tenv _ _ _ _ _ hl; simp [liveStmt] at hl
  | letMatch _ _ _ _ _ _ | setField _ _ _ | setCall _ _ _ | letAlloc _ _ _ _ | letView _ _ _ _ _ | letStr _ _ _
  | letLoad _ _ _ _ | setByte _ _ _ | free _ _ _ | letSlice _ _ _ _ _ | letIndex _ _ _ _ _
  | setIndex _ _ _ | setIndexEval _ _ _ | setFieldEval _ _ _
  | matchArm _ _ _ _ _ _ _ _ | unreachable _ _ =>
    intro A W E tenv _ _ _ _ hs _; simp [stmtOk] at hs

end

/-! ## Checked live calls settle to values -/

/-- **Live pure calls have values.** Under `TermOk`, `PrimsTy` and
`PureProg`, when every function but the prims, those `outside` and those in
`bad` passes `LiveFn`, a call of an annotated function of none of these, on
arguments of its parameters' types, settles to a value of its return type. -/
theorem pcall_live {sp : SrcProgram} {prims : Prims} {T : TermInfo} {outside bad : List Nat}
    (hT : TermOk sp prims T) (hP : PrimsTy sp prims) (hPure : PureProg sp prims outside)
    (hL : ∀ c f, sp.funcs[c]? = some f → prims.isPrim c = false → outside.contains c = false →
      bad.contains c = false → LiveFn bad f = true) :
    ∀ c a, T.ann c = some a → prims.isPrim c = false → outside.contains c = false →
      bad.contains c = false → ∀ vs, GoodCall sp prims c vs := by
  suffices H : ∀ r s k c a vs, T.ann c = some a → a.rank = r → argSize a.pos vs = s → a.sub = k →
      prims.isPrim c = false → outside.contains c = false → bad.contains c = false →
      GoodCall sp prims c vs from
    fun c a ha hp hout hbad vs => H _ _ _ c a vs ha rfl rfl rfl hp hout hbad
  intro r
  induction r using Nat.strongRecOn with
  | _ r IHr =>
  intro s
  induction s using Nat.strongRecOn with
  | _ s IHs =>
  intro k
  induction k using Nat.strongRecOn with
  | _ k IHk =>
  intro c a vs ha hr hs hk hp hout hbad
  have IH : CallsGood sp prims T a (argSize a.pos vs) outside bad := by
    intro c' a' vs' ha' hb hp' hout' hbad'
    rcases hb with lt | ⟨eq, lt | ⟨eq2, lt⟩⟩
    · exact IHr a'.rank (by omega) _ _ c' a' vs' ha' rfl rfl rfl hp' hout' hbad'
    · exact IHs _ (by omega) _ c' a' vs' ha' (by omega) rfl rfl hp' hout' hbad'
    · exact IHk _ (by omega) c' a' vs' ha' (by omega) (by omega) rfl hp' hout' hbad'
  intro f hf hvs
  have hl : vs.length = f.params.length := by rw [← hvs.length, List.length_map]
  have hchk : chkFn prims T a f = true :=
    ((hT.fns (c, a) (find_mem ha)).resolve_left (by simp [hp])) f hf
  have henv : EnvOk (argSize a.pos vs)
      (AEnv.bindAll [] ((paramIds f.params).zip (initCls a.pos f.params.length)))
      (paramEnv f.params vs) := by
    rw [paramEnv, paramBindings_ids, ← hl]
    exact EnvOk.bindAll (zip_rel (initCls_holds a.pos vs) _) (EnvOk.nil _ _)
  have hpure : PureFunc sp prims outside f = true := hPure c f hf hp hout
  have hlive := hL c f hf hp hout hbad
  simp only [LiveFn, Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq] at hlive
  obtain ⟨N, d, hd, hN⟩ := stmt_live (oracleOk_pcall hT.decs hT.consts) hP IH f.body henv (WitOk.nil _)
    hchk (paramEnv_ty hvs) (PureFunc.stmt hpure) hlive.1
  have hdv : ∃ v, outValue f.ret d = some v ∧ PTy (boxElem sp prims) f.ret v := by
    cases d with
    | next e =>
      rcases hlive.2 with hu | hn
      · exact ⟨.unit, by simp [outValue, hu], unit_pty hu⟩
      · exact absurd (hN N (Nat.le_refl _)) (neverNext_sound _ _ f.body _ e hn)
    | brk _ => exact hd.elim
    | cont _ => exact hd.elim
    | ret o =>
      cases o with
      | some v => exact ⟨v, rfl, hd⟩
      | none => exact ⟨.unit, by simp [outValue, show f.ret.toCore = .unit from hd], unit_pty hd⟩
  obtain ⟨v, hv, rv⟩ := hdv
  refine ⟨N + 1, v, rv, fun m hm => ?_⟩
  obtain ⟨m, rfl⟩ : ∃ m', m = m' + 1 := ⟨m - 1, by omega⟩
  simp only [pcall, hp, hf, hl, Bool.false_eq_true, ↓reduceIte, hN m (by omega), Option.bind_some, hv]

end Lanius.Faithful.Termination

namespace Lanius.Faithful.Termination

open Lanius.Mini
open Lanius.Faithful

/-! ## Checking `LiveFn` one function at a time -/

/-- What `pcall_live` asks of function `i`, `f`, as one test. -/
abbrev LiveOk (prims : Prims) (outside bad : List Nat) (i : Nat) (f : SrcFunc) : Prop :=
  (prims.isPrim i || outside.contains i || bad.contains i || LiveFn bad f) = true

/-- `LiveOk` of the functions `fs` numbered from `n`, but those in `skip`. -/
def LivesOk (prims : Prims) (outside bad skip : List Nat) (n : Nat) (fs : List SrcFunc) : Prop :=
  ∀ j f, fs[j]? = some f → skip.contains (n + j) = true ∨ LiveOk prims outside bad (n + j) f

section
variable {prims : Prims} {outside bad skip : List Nat}

theorem livesOk_nil {n : Nat} : LivesOk prims outside bad skip n [] :=
  fun _ _ h => nomatch h

theorem livesOk_cons {n : Nat} {f : SrcFunc} {fs : List SrcFunc}
    (head : skip.contains n = true ∨ LiveOk prims outside bad n f)
    (tail : LivesOk prims outside bad skip (n + 1) fs) : LivesOk prims outside bad skip n (f :: fs)
  | 0, g, h => by
    rw [List.getElem?_cons_zero, Option.some.injEq] at h
    subst h
    exact head
  | j + 1, g, h => by
    rw [List.getElem?_cons_succ] at h
    have := tail j g h
    rwa [Nat.add_assoc, Nat.add_comm 1 j] at this

theorem livesOk_append {n : Nat} {xs ys : List SrcFunc} (left : LivesOk prims outside bad skip n xs)
    (right : LivesOk prims outside bad skip (n + xs.length) ys) : LivesOk prims outside bad skip n (xs ++ ys) := by
  intro j f h
  by_cases lt : j < xs.length
  · rw [List.getElem?_append_left lt] at h
    exact left j f h
  · have le : xs.length ≤ j := Nat.le_of_not_lt lt
    rw [List.getElem?_append_right le] at h
    have := right (j - xs.length) f h
    rwa [Nat.add_assoc, Nat.add_sub_cancel' le] at this

theorem LiveOk.liveFn {i : Nat} {f : SrcFunc} (h : LiveOk prims outside bad i f) (hp : prims.isPrim i = false)
    (hout : outside.contains i = false) (hbad : bad.contains i = false) : LiveFn bad f = true := by
  simp only [LiveOk, hp, hout, hbad, Bool.false_or] at h
  exact h

end

end Lanius.Faithful.Termination
