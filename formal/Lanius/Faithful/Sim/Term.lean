import Lanius.Faithful.Pure

/-! # Pure runs that settle: a termination check

`pcall` with too little fuel gives `none`, the same as an error, so a pure run
says nothing until we know that more fuel would not change it. `TermOk` is a
syntactic check that a pure call settles: for every callee and arguments
there is a fuel past which `pcall` gives one answer (`pcall_complete`,
`Sim/TermSound.lean`).

The check is the size-change argument of a recursive descent, with an
annotation per function (`TermAnn`, generated and untrusted): a rank, the
position of a designated argument, and a subrank. A call `c(vs)` is measured
by `(rank c, sizeOf vs[pos c], sub c)`, lexicographically, and every call a
checked body makes must be smaller than the call being run:

* to a function of a lower rank (a callee in an earlier strongly connected
  component of the call graph), with any arguments;
* in the same rank, with the callee's designated argument strictly smaller
  than the caller's (`lt`), or no larger (`le`) and a lower subrank.

What is smaller is a class of each local's value against the size `B` of the
caller's designated argument (`SizeCls`), which the check follows through the
body (`AEnv`), from `le` for the designated parameter. A field of a value no
larger than `B`, and the payload of an enum matched on one, are smaller
(structural descent through `match` and fields). `boxed` and `unbox` are the
identity, so they keep their argument's class (descent through a `Box`).
After `if x == 0 { .. } ` that does not go on, or in its `else`, `x` is a
nonzero `usize` (`nz`), and a call of a decrement function (`DecOk`, the
prelude's `minus`, checked once) on such an `x` and `1` gives a smaller value
(counted-down fuel and counters).

Prims, the designated position and the subrank are only read by the check;
the soundness proof never trusts them. -/

namespace Lanius.Faithful.Termination

open Lanius.Mini
open Lanius.Core (Value)

/-- What the check knows of a value, against the size `B` of the designated
argument of the call being run: nothing, no larger, smaller, no larger and a
nonzero `usize`, or the `usize` 1. -/
inductive SizeCls where
  | unk
  | le
  | lt
  | nz
  | one
  deriving DecidableEq, Repr

def SizeCls.holds (B : Nat) : SizeCls → Value → Prop
  | .unk, _ => True
  | .le, v => sizeOf v ≤ B
  | .lt, v => sizeOf v < B
  | .nz, v => sizeOf v ≤ B ∧ ∃ n, v = .unsigned .usize n ∧ n ≠ 0
  | .one, v => v = .unsigned .usize 1

/-- The class of a field or payload value of a value of this class. -/
def SizeCls.part : SizeCls → SizeCls
  | .le | .lt | .nz => .lt
  | .unk | .one => .unk

/-- Classes of locals, the newest binding first, as `Env`. -/
abbrev AEnv := List (Nat × SizeCls)

def AEnv.get? (A : AEnv) (id : Nat) : Option SizeCls :=
  (A.find? (fun binding => binding.1 == id)).map Prod.snd

def AEnv.bindAll (A : AEnv) (bindings : List (Nat × SizeCls)) : AEnv :=
  bindings.foldl (fun result binding => binding :: result) A

def AEnv.cls (A : AEnv) (id : Nat) : SizeCls := (A.get? id).getD .unk

/-- After a guard `x == 0` failed: `x`, if no larger, is a nonzero `usize`. -/
def AEnv.refine (A : AEnv) (x : Nat) : AEnv :=
  if A.cls x = .le then (x, .nz) :: A else A

/-- A function's place in the order: its rank, the position of its
designated argument, and its subrank. -/
structure TermAnn where
  rank : Nat
  pos : Nat
  sub : Nat
  deriving DecidableEq, Repr

/-- The annotations of the checked functions, and the decrement functions. -/
structure TermInfo where
  anns : List (Nat × TermAnn)
  decs : List Nat
  deriving Repr

def TermInfo.ann (T : TermInfo) (c : Nat) : Option TermAnn := T.anns.lookup c

/-- The size of a call's designated argument. -/
noncomputable def argSize (pos : Nat) (vs : List Value) : Nat :=
  match vs[pos]? with
  | some v => sizeOf v
  | none => 0

/-- The `usize` literal `k`. -/
def isUsizeLit (k : Nat) : SrcExpr → Bool
  | .unsigned t v => decide (t = .usize) && v.toNat == k
  | .int _ | .boolean _ | .local _ | .field _ _ | .negate _ | .not _ | .apply _ _ _ | .cast _ _
  | .null | .char _ | .float _ _ => false

def localOf : SrcExpr → Option Nat
  | .local x => some x
  | .int _ | .boolean _ | .unsigned _ _ | .field _ _ | .negate _ | .not _ | .apply _ _ _
  | .cast _ _ | .null | .char _ | .float _ _ => none

/-- `x == 0` on a `usize` local `x`. -/
def guardVar : SrcExpr → Option Nat
  | .apply op l r => if op = .equal && isUsizeLit 0 r then localOf l else none
  | .int _ | .boolean _ | .unsigned _ _ | .local _ | .field _ _ | .negate _ | .not _ | .cast _ _
  | .null | .char _ | .float _ _ => none

def exprCls (A : AEnv) : SrcExpr → SizeCls
  | .local x => A.cls x
  | .field x _ => (A.cls x).part
  | .unsigned t v => if t = .usize ∧ v.toNat = 1 then .one else .unk
  | .int _ | .boolean _ | .negate _ | .not _ | .apply _ _ _ | .cast _ _ | .null | .char _
  | .float _ _ => .unk

/-- A statement that never ends by going on to the next one. -/
def neverNext : SrcStmt → Bool
  | .nop => false
  | .let _ _ _ body => neverNext body
  | .letStruct _ _ _ body => neverNext body
  | .letCall _ _ _ _ body => neverNext body
  | .letEnum _ _ _ _ body => neverNext body
  | .letMatch _ _ _ _ _ _ => true
  | .set _ _ => true
  | .setField _ _ _ => true
  | .setCall _ _ _ => true
  | .then first second => neverNext first || neverNext second
  | .if _ a b => neverNext a && neverNext b
  | .while _ _ => true
  | .return _ => true
  | .letAlloc _ _ _ _ => true
  | .letLoad _ _ _ _ => true
  | .setByte _ _ _ => true
  | .free _ _ _ => true
  | .letSlice _ _ _ _ _ => true
  | .letIndex _ _ _ _ _ => true
  | .setIndex _ _ _ => true
  | .letEval _ _ _ body => neverNext body
  | .setEval _ _ => true
  | .ifEval _ a b => neverNext a && neverNext b
  | .whileEval _ _ => true
  | .returnEval _ => true
  | .discard _ => false
  | .setIndexEval _ _ _ => true
  | .setFieldEval _ _ _ => true
  | .returnUnit => true
  | .assert _ => false
  | .break => true
  | .continue => true
  | .matchArm _ _ _ _ _ _ _ _ => true
  | .unreachable _ _ => true

/-- What is known after a statement that went on to the next one: after
`if x == 0 { a } else { b }` with an `a` that does not go on, `x` is nonzero. -/
def AEnv.after (A : AEnv) : SrcStmt → AEnv
  | .if c a _ =>
    match guardVar c with
    | some x => if neverNext a then A.refine x else A
    | none => A
  | .nop | .let _ _ _ _ | .letStruct _ _ _ _ | .letCall _ _ _ _ _ | .letEnum _ _ _ _ _
  | .letMatch _ _ _ _ _ _ | .set _ _ | .setField _ _ _ | .setCall _ _ _ | .then _ _ | .while _ _
  | .return _ | .letAlloc _ _ _ _ | .letLoad _ _ _ _ | .setByte _ _ _ | .free _ _ _
  | .letSlice _ _ _ _ _ | .letIndex _ _ _ _ _ | .setIndex _ _ _ | .letEval _ _ _ _ | .setEval _ _
  | .ifEval _ _ _ | .whileEval _ _ | .returnEval _ | .discard _ | .setIndexEval _ _ _
  | .setFieldEval _ _ _ | .returnUnit | .assert _ | .break | .continue | .matchArm _ _ _ _ _ _ _ _
  | .unreachable _ _ => A

/-- A same-rank call descends: its designated argument is smaller, or no
larger with a lower subrank. -/
def descends : SizeCls → Bool → Bool
  | .lt, _ => true
  | .le, lower => lower
  | .nz, lower => lower
  | .unk, _ => false
  | .one, _ => false

section
variable (prims : Prims) (T : TermInfo) (me : TermAnn)

/-- The class of a call's value: a prim's is its argument's, a decrement's
of a nonzero `x` and `1` is smaller. -/
def callCls (c : Nat) (cs : List SizeCls) : SizeCls :=
  if prims.isPrim c then
    match cs with
    | [k] => k
    | [] => .unk
    | _ :: _ :: _ => .unk
  else if T.decs.contains c then
    match cs with
    | [a, b] => if a = .nz ∧ b = .one then .lt else .unk
    | [] => .unk
    | [_] => .unk
    | _ :: _ :: _ :: _ => .unk
  else .unk

/-- A call the body of a call annotated `me` may make, on arguments of
classes `cs`. -/
def callOk (c : Nat) (cs : List SizeCls) : Bool :=
  prims.isPrim c ||
    match T.ann c with
    | none => false
    | some a => decide (a.rank < me.rank) ||
        (decide (a.rank = me.rank) && descends (cs.getD a.pos .unk) (decide (a.sub < me.sub)))

mutual
def effCls (A : AEnv) : SrcEff → SizeCls
  | .ePure e => exprCls A e
  | .eCall c args => callCls prims T c (effsCls A args)
  | .eApply _ _ _ => .unk
  | .eNeg _ => .unk
  | .eNot _ => .unk
  | .eCast _ _ => .unk
  | .eIndex _ _ => .unk
  | .eStruct _ _ => .unk
  | .eVariant _ _ _ => .unk
  | .eMatch _ _ _ _ _ => .unk
  | .eDivide _ _ _ => .unk
  | .eStride _ => .unk

def effsCls (A : AEnv) : List SrcEff → List SizeCls
  | [] => []
  | e :: es => effCls A e :: effsCls A es
end

mutual
def chkEff (A : AEnv) : SrcEff → Bool
  | .ePure _ => true
  | .eCall c args => chkEffs A args && callOk prims T me c (effsCls prims T A args)
  | .eApply _ left right => chkEff A left && chkEff A right
  | .eNeg operand => chkEff A operand
  | .eNot operand => chkEff A operand
  | .eCast _ operand => chkEff A operand
  | .eIndex _ _ => true
  | .eStruct _ fields => chkEffs A fields
  | .eVariant _ _ payload => chkEffs A payload
  | .eMatch scrutinee _ _ binders values =>
      chkEff A scrutinee && chkArms A (effCls prims T A scrutinee).part binders values
  | .eDivide _ left right => chkEff A left && chkEff A right
  | .eStride _ => true

def chkEffs (A : AEnv) : List SrcEff → Bool
  | [] => true
  | e :: es => chkEff A e && chkEffs A es

def chkArms (A : AEnv) (k : SizeCls) : List (List Nat) → List SrcEff → Bool
  | [], _ => true
  | _ :: _, [] => true
  | binders :: rest, value :: values =>
      chkEff (A.bindAll (binders.map (·, k))) value && chkArms A k rest values
end

def chkStmt (A : AEnv) : SrcStmt → Bool
  | .nop => true
  | .let id _ value body => chkStmt ((id, exprCls A value) :: A) body
  | .letStruct id _ _ body => chkStmt ((id, .unk) :: A) body
  | .letCall id _ callee args body =>
      callOk prims T me callee (args.map (exprCls A)) &&
        chkStmt ((id, callCls prims T callee (args.map (exprCls A))) :: A) body
  | .letEnum id _ _ _ body => chkStmt ((id, .unk) :: A) body
  | .letMatch _ _ _ _ _ _ => true
  | .set _ _ => true
  | .setField _ _ _ => true
  | .setCall _ _ _ => true
  | .then first second => chkStmt A first && chkStmt (A.after first) second
  | .if condition thenBranch elseBranch =>
      chkStmt A thenBranch &&
        chkStmt (match guardVar condition with
          | some x => A.refine x
          | none => A) elseBranch
  | .while _ _ => true
  | .return _ => true
  | .letAlloc _ _ _ _ => true
  | .letLoad _ _ _ _ => true
  | .setByte _ _ _ => true
  | .free _ _ _ => true
  | .letSlice _ _ _ _ _ => true
  | .letIndex _ _ _ _ _ => true
  | .setIndex _ _ _ => true
  | .letEval id _ value body =>
      chkEff prims T me A value && chkStmt ((id, effCls prims T A value) :: A) body
  | .setEval _ _ => true
  | .ifEval condition thenBranch elseBranch =>
      chkEff prims T me A condition && chkStmt A thenBranch && chkStmt A elseBranch
  | .whileEval _ _ => true
  | .returnEval value => chkEff prims T me A value
  | .discard value => chkEff prims T me A value
  | .setIndexEval _ _ _ => true
  | .setFieldEval _ _ _ => true
  | .returnUnit => true
  | .assert condition => chkEff prims T me A condition
  | .break => true
  | .continue => true
  | .matchArm _ _ _ _ _ _ _ _ => true
  | .unreachable _ _ => true

/-- The classes of a call's parameters: its designated one no larger. -/
def initCls (pos n : Nat) : List SizeCls :=
  (List.range n).map fun i => if i = pos then .le else .unk

def paramIds (params : List SrcParam) : List Nat := params.map (·.id)

/-- A function body checked for the annotation `me`. -/
def chkFn (f : SrcFunc) : Bool :=
  chkStmt prims T me (AEnv.bindAll [] ((paramIds f.params).zip (initCls me.pos f.params.length))) f.body

end

/-- A decrement function: `minus(a, b)`, which panics when `b > a` and
otherwise returns `a - b`. -/
def DecOk (sp : SrcProgram) (prims : Prims) (c : Nat) : Prop :=
  prims.isPrim c = false ∧ ∃ f a b panic, sp.funcs[c]? = some f ∧ paramIds f.params = [a, b] ∧ a ≠ b ∧
    f.body = .then (.if (.apply .greater (.local b) (.local a)) panic .nop)
      (.return (.apply .minus (.local a) (.local b)))

/-- Every annotated function's body passes the check, and the decrement
functions are decrements. -/
structure TermOk (sp : SrcProgram) (prims : Prims) (T : TermInfo) : Prop where
  decs : ∀ c ∈ T.decs, DecOk sp prims c
  fns : ∀ p ∈ T.anns, prims.isPrim p.1 = true ∨ ∀ f, sp.funcs[p.1]? = some f → chkFn prims T p.2 f = true

/-- A pure call settles: past some fuel, more fuel gives the same answer. -/
def Settles (sp : SrcProgram) (prims : Prims) (c : Nat) (vs : List Value) : Prop :=
  ∃ N, ∀ m, N ≤ m → pcall sp prims m c vs = pcall sp prims N c vs

end Lanius.Faithful.Termination
