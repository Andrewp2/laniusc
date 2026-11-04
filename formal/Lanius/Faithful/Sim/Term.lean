module

public import Lanius.Faithful.Pure

@[expose] public section

/-! # Pure runs that settle: a termination check

`pcall` with too little fuel gives `none`, the same as an error, so a pure run
says nothing until we know that more fuel would not change it. More fuel
keeps a value (`pcall_mono`), so every pure call settles: for every callee
and arguments there is a fuel past which `pcall` gives one answer
(`pcall_settles`, `Sim/TermSound.lean`). Whether that answer is a value
takes a measure that every call descends: `TermOk` is a syntactic check of
one, which `pcall_live` (`Sim/Live.lean`) uses.

The check is the size-change argument of a recursive descent, with an
annotation per function (`TermAnn`, generated and untrusted): a rank, the
positions of its designated arguments, and a subrank. A call `c(vs)` is
measured by `(rank c, size, sub c)`, lexicographically, where `size` is the
largest `sizeOf` of its designated arguments (`argSize`), and every call a
checked body makes must be smaller than the call being run:

* to a function of a lower rank (a callee in an earlier strongly connected
  component of the call graph), with any arguments;
* in the same rank, with each of the callee's designated arguments strictly
  smaller than the caller's size (`lt`), or no larger (`le`) and a lower
  subrank.

What is smaller is a class of each local's value against the size `B` of the
caller's designated arguments (`SizeCls`), which the check follows through the
body (`AEnv`), from `le` for the designated parameters. A field of a value no
larger than `B`, and the payload of an enum matched on one, are smaller
(structural descent through `match` and fields). `boxed` and `unbox` are the
identity, so they keep their argument's class (descent through a `Box`). A
local a statement may assign (`SrcStmt.writes`) is known as nothing after it
(`AEnv.forget`).
After `if x == 0 { .. }` or `if x < k { .. }` that does not go on, or in its
`else`, `x` is a `usize` of at least 1 or `k` (`ge`), and a call of a
decrement function (`DecOk`, the prelude's `minus`, checked once) on such an
`x` and a literal from 1 to that bound gives a smaller value (counted-down
fuel and counters). A match arm with a payload, on a value no larger than
`B`, shows that the payload-free variants of that enum up to the arm's are
smaller than `B` (`Wit`), so a constant such as `empty()` (`ConstOk`) passed
in place of a list the caller matched non-empty is smaller too (`fl_add`
walking two lists).

The annotations are only read by the check; the soundness proof never
trusts them. -/

namespace Lanius.Faithful.Termination

open Lanius.Mini
open Lanius.Core (Value)

/-- What the check knows of a value, against the size `B` of the designated
arguments of the call being run: nothing, no larger, smaller, no larger and a
`usize` of at least `k`, or the `usize` `k`. -/
inductive SizeCls where
  | unk
  | le
  | lt
  | ge (k : Nat)
  | lit (k : Nat)
  | nil (id j : Nat)
  deriving DecidableEq, Repr

def SizeCls.holds (B : Nat) : SizeCls → Value → Prop
  | .unk, _ => True
  | .le, v => sizeOf v ≤ B
  | .lt, v => sizeOf v < B
  | .ge k, v => sizeOf v ≤ B ∧ ∃ n, v = .unsigned .usize n ∧ k ≤ n
  | .lit k, v => v = .unsigned .usize k
  | .nil id j, v => v = .enumeration id j []

/-- The class of a field or payload value of a value of this class. -/
def SizeCls.part : SizeCls → SizeCls
  | .le | .lt | .ge _ => .lt
  | .unk | .lit _ | .nil _ _ => .unk

/-- Facts the check has learnt of `B`: `(id, k)` says every variant of enum
`id` from 0 to `k` without a payload is smaller than `B`, from a value no
larger than `B` that matched variant `k` with a payload. -/
abbrev Wit := List (Nat × Nat)

/-- A class read with the facts: a payload-free variant they bound is
smaller. -/
def SizeCls.res (W : Wit) : SizeCls → SizeCls
  | .nil id j => if W.any (fun p => p.1 == id && decide (j ≤ p.2)) then .lt else .unk
  | .unk => .unk
  | .le => .le
  | .lt => .lt
  | .ge k => .ge k
  | .lit k => .lit k

/-- Classes of locals, the newest binding first, as `Env`. -/
abbrev AEnv := List (Nat × SizeCls)

def AEnv.get? (A : AEnv) (id : Nat) : Option SizeCls :=
  (A.find? (fun binding => binding.1 == id)).map Prod.snd

def AEnv.bindAll (A : AEnv) (bindings : List (Nat × SizeCls)) : AEnv :=
  bindings.foldl (fun result binding => binding :: result) A

def AEnv.cls (A : AEnv) (id : Nat) : SizeCls := (A.get? id).getD .unk

/-- After a guard failed that bounds `x` below by `k`: `x`, if no larger, is a
`usize` of at least `k`. -/
def AEnv.refine (A : AEnv) (x k : Nat) : AEnv :=
  if A.cls x = .le then (x, .ge k) :: A else A

/-- A function's place in the order: its rank, the positions of its
designated arguments, and its subrank. -/
structure TermAnn where
  rank : Nat
  pos : List Nat
  sub : Nat
  deriving DecidableEq, Repr

/-- A search tree of annotations keyed by function index, so the kernel finds
an annotation in a logarithmic number of literal comparisons. -/
inductive ATree where
  | leaf
  | node (l : ATree) (k : Nat) (a : TermAnn) (r : ATree)
  deriving Repr

def ATree.find (c : Nat) : ATree → Option TermAnn
  | .leaf => none
  | .node l k a r =>
    match Nat.beq c k with
    | true => some a
    | false =>
      match Nat.blt c k with
      | true => find c l
      | false => find c r

def ATree.toList : ATree → List (Nat × TermAnn)
  | .leaf => []
  | .node l k a r => l.toList ++ (k, a) :: r.toList

/-- The annotations of the checked functions, and the decrement functions.
The tree need not be ordered: the soundness proof uses only that `find`
returns an entry of the tree. -/
structure TermInfo where
  tab : ATree
  decs : List Nat
  /-- Functions `c` returning the payload-free variant `j` of enum `id`, as
  `(c, id, j)`: the prelude's `empty`. -/
  consts : List (Nat × Nat × Nat) := []
  deriving Repr

def TermInfo.anns (T : TermInfo) : List (Nat × TermAnn) := T.tab.toList

def TermInfo.ann (T : TermInfo) (c : Nat) : Option TermAnn := T.tab.find c

/-- The size of an argument. -/
noncomputable def argAt (vs : List Value) (p : Nat) : Nat :=
  match vs[p]? with
  | some v => sizeOf v
  | none => 0

/-- The size of a call: the largest of its designated arguments. -/
noncomputable def argSize (pos : List Nat) (vs : List Value) : Nat :=
  (pos.map (argAt vs)).foldr max 0

/-- A `usize` literal. -/
def usizeLit : SrcExpr → Option Nat
  | .unsigned t v => if t = .usize then some v.toNat else none
  | .int _ | .boolean _ | .local _ | .field _ _ | .negate _ | .not _ | .apply _ _ _ | .cast _ _
  | .null | .char _ | .float _ _ => none

def localOf : SrcExpr → Option Nat
  | .local x => some x
  | .int _ | .boolean _ | .unsigned _ _ | .field _ _ | .negate _ | .not _ | .apply _ _ _
  | .cast _ _ | .null | .char _ | .float _ _ => none

/-- A local `x` and a `k`: `x == 0` (`k = 1`) or `x < k`, whose failure
bounds `x` below by `k`. -/
def guardVar : SrcExpr → Option (Nat × Nat)
  | .apply op l r =>
    match usizeLit r with
    | some k =>
      if op = .equal ∧ k = 0 then (localOf l).map (·, 1)
      else if op = .less then (localOf l).map (·, k)
      else none
    | none => none
  | .int _ | .boolean _ | .unsigned _ _ | .local _ | .field _ _ | .negate _ | .not _ | .cast _ _
  | .null | .char _ | .float _ _ => none

def exprCls (A : AEnv) : SrcExpr → SizeCls
  | .local x => A.cls x
  | .field x _ => (A.cls x).part
  | .unsigned t v => if t = .usize then .lit v.toNat else .unk
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
  | .set _ _ => false
  | .setField _ _ _ => true
  | .setCall _ _ _ => true
  | .then first second => neverNext first || neverNext second
  | .if _ a b => neverNext a && neverNext b
  | .while _ _ => false
  | .return _ => true
  | .letAlloc _ _ _ _ => true
  | .letView _ _ _ _ _ => true
  | .letStr _ _ _ => true
  | .letLoad _ _ _ _ => true
  | .setByte _ _ _ => true
  | .free _ _ _ => true
  | .letSlice _ _ _ _ _ => true
  | .letIndex _ _ _ _ _ => true
  | .setIndex _ _ _ => true
  | .letEval _ _ _ body => neverNext body
  | .setEval _ _ => false
  | .ifEval _ a b => neverNext a && neverNext b
  | .whileEval _ _ => false
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
  | .setPlace _ _ => false
  | .setPlaceOp _ _ _ => false

/-- What is known after a statement that went on to the next one: after
`if x < k { a } else { b }` with an `a` that does not go on, `x ≥ k`. -/
def AEnv.after (A : AEnv) : SrcStmt → AEnv
  | .if c a _ =>
    match guardVar c with
    | some (x, k) => if neverNext a then A.refine x k else A
    | none => A
  | .nop | .let _ _ _ _ | .letStruct _ _ _ _ | .letCall _ _ _ _ _ | .letEnum _ _ _ _ _
  | .letMatch _ _ _ _ _ _ | .set _ _ | .setField _ _ _ | .setCall _ _ _ | .then _ _ | .while _ _
  | .return _ | .letAlloc _ _ _ _ | .letView _ _ _ _ _ | .letStr _ _ _ | .letLoad _ _ _ _ | .setByte _ _ _ | .free _ _ _
  | .letSlice _ _ _ _ _ | .letIndex _ _ _ _ _ | .setIndex _ _ _ | .letEval _ _ _ _ | .setEval _ _
  | .ifEval _ _ _ | .whileEval _ _ | .returnEval _ | .discard _ | .setIndexEval _ _ _
  | .setFieldEval _ _ _ | .returnUnit | .assert _ | .break | .continue | .matchArm _ _ _ _ _ _ _ _
  | .unreachable _ _ | .setPlace _ _ | .setPlaceOp _ _ _ => A

/-- Nothing known of the locals in `ws`, which a statement may have assigned. -/
def AEnv.forget (A : AEnv) (ws : List Nat) : AEnv :=
  A.map fun binding => if ws.contains binding.1 then (binding.1, .unk) else binding

def SizeCls.isLt : SizeCls → Bool
  | .lt => true
  | .unk | .le | .ge _ | .lit _ | .nil _ _ => false

def SizeCls.isLe : SizeCls → Bool
  | .lt | .le | .ge _ => true
  | .unk | .lit _ | .nil _ _ => false

/-- A same-rank call descends: its designated arguments are smaller, or no
larger with a lower subrank. -/
def descends (ks : List SizeCls) (lower : Bool) : Bool :=
  (!ks.isEmpty && ks.all SizeCls.isLt) || (lower && ks.all SizeCls.isLe)

/-- A decrement's value: smaller, for a `usize` of at least `k` and a literal
from 1 to `k`. -/
def decCls : SizeCls → SizeCls → SizeCls
  | .ge k, .lit d => if 1 ≤ d ∧ d ≤ k then .lt else .unk
  | .ge _, .unk | .ge _, .le | .ge _, .lt | .ge _, .ge _ | .ge _, .nil _ _ => .unk
  | .unk, _ | .le, _ | .lt, _ | .lit _, _ | .nil _ _, _ => .unk

section
variable (prims : Prims) (T : TermInfo) (me : TermAnn)

/-- The class of a call's value: a prim's is its argument's, a decrement's
by a literal within the bound of its first argument is smaller, and a
constant's is its variant. -/
def callCls (c : Nat) (cs : List SizeCls) : SizeCls :=
  if prims.isPrim c then
    match cs with
    | [k] => k
    | [] => .unk
    | _ :: _ :: _ => .unk
  else if T.decs.contains c then
    match cs with
    | [a, b] => decCls a b
    | [] => .unk
    | [_] => .unk
    | _ :: _ :: _ :: _ => .unk
  else
    match T.consts.lookup c with
    | some (id, j) => .nil id j
    | none => .unk

/-- A call the body of a call annotated `me` may make, on arguments of
classes `cs`, with the facts `W`. -/
def callOk (W : Wit) (c : Nat) (cs : List SizeCls) : Bool :=
  prims.isPrim c ||
    match T.ann c with
    | none => false
    | some a => decide (a.rank < me.rank) ||
        (decide (a.rank = me.rank) &&
          descends (a.pos.map fun p => (cs.map (SizeCls.res W)).getD p .unk) (decide (a.sub < me.sub)))

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
  | .arraySlice _ _ => .unk
  | .eIf _ _ _ _ => .unk
  | .eLet _ _ _ _ _ => .unk
  | .eLen _ | .eStr _ _ | .eBorrow _ _ | .eDeref _ _ | .eField _ _ | .eAt _ _ => .unk

def effsCls (A : AEnv) : List SrcEff → List SizeCls
  | [] => []
  | e :: es => effCls A e :: effsCls A es
end

mutual
def chkEff (A : AEnv) (W : Wit) : SrcEff → Bool
  | .ePure _ => true
  | .eCall c args => chkEffs A W args && callOk prims T me W c (effsCls prims T A args)
  | .eApply _ left right => chkEff A W left && chkEff A W right
  | .eNeg operand => chkEff A W operand
  | .eNot operand => chkEff A W operand
  | .eCast _ operand => chkEff A W operand
  | .eIndex _ _ => true
  | .eStruct _ fields => chkEffs A W fields
  | .eVariant _ _ payload => chkEffs A W payload
  | .eMatch scrutinee ety _ binders values =>
      chkEff A W scrutinee && chkArms A W (effCls prims T A scrutinee) ety.typeId 0 binders values
  | .eDivide _ left right => chkEff A W left && chkEff A W right
  | .eStride _ => true
  | .arraySlice _ _ => true
  | .eIf condition _ thenValue elseValue =>
      chkEff A W condition && chkEff A W thenValue && chkEff A W elseValue
  | .eLet id _ value _ body => chkEff A W value && chkEff ((id, effCls prims T A value) :: A) W body
  | .eLen _ | .eStr _ _ => true
  | .eBorrow _ _ | .eDeref _ _ | .eField _ _ | .eAt _ _ => false

def chkEffs (A : AEnv) (W : Wit) : List SrcEff → Bool
  | [] => true
  | e :: es => chkEff A W e && chkEffs A W es

/-- The arms of a match on a value of class `k` of enum `id`, from variant
`i`. An arm with a payload on a value no larger than `B` adds the fact. -/
def chkArms (A : AEnv) (W : Wit) (k : SizeCls) (id : Nat) : Nat → List (List Nat) → List SrcEff → Bool
  | _, [], _ => true
  | _, _ :: _, [] => true
  | i, binders :: rest, value :: values =>
      chkEff (A.bindAll (binders.map (·, k.part)))
          (if k.isLe && !binders.isEmpty then (id, i) :: W else W) value &&
        chkArms A W k id (i + 1) rest values
end

def chkStmt (A : AEnv) (W : Wit) : SrcStmt → Bool
  | .nop => true
  | .let id _ value body => chkStmt ((id, exprCls A value) :: A) W body
  | .letStruct id _ _ body => chkStmt ((id, .unk) :: A) W body
  | .letCall id _ callee args body =>
      callOk prims T me W callee (args.map (exprCls A)) &&
        chkStmt ((id, callCls prims T callee (args.map (exprCls A))) :: A) W body
  | .letEnum id _ _ _ body => chkStmt ((id, .unk) :: A) W body
  | .letMatch _ _ _ _ _ _ => true
  | .set _ _ => true
  | .setField _ _ _ => true
  | .setCall _ _ _ => true
  | .then first second => chkStmt A W first && chkStmt ((A.after first).forget first.writes) W second
  | .if condition thenBranch elseBranch =>
      chkStmt A W thenBranch &&
        chkStmt (match guardVar condition with
          | some (x, k) => A.refine x k
          | none => A) W elseBranch
  | .while _ _ => true
  | .return _ => true
  | .letAlloc _ _ _ _ => true
  | .letView _ _ _ _ _ => true
  | .letStr _ _ _ => true
  | .letLoad _ _ _ _ => true
  | .setByte _ _ _ => true
  | .free _ _ _ => true
  | .letSlice _ _ _ _ _ => true
  | .letIndex _ _ _ _ _ => true
  | .setIndex _ _ _ => true
  | .letEval id _ value body =>
      chkEff prims T me A W value && chkStmt ((id, effCls prims T A value) :: A) W body
  | .setEval _ value => chkEff prims T me A W value
  | .ifEval condition thenBranch elseBranch =>
      chkEff prims T me A W condition && chkStmt A W thenBranch && chkStmt A W elseBranch
  | .whileEval _ _ => true
  | .returnEval value => chkEff prims T me A W value
  | .discard value => chkEff prims T me A W value
  | .setIndexEval _ _ _ => true
  | .setFieldEval _ _ _ => true
  | .returnUnit => true
  | .assert condition => chkEff prims T me A W condition
  | .break => true
  | .continue => true
  | .matchArm _ _ _ _ _ _ _ _ => true
  | .unreachable _ _ => true
  | .setPlace _ _ => false
  | .setPlaceOp _ _ _ => false

/-- The classes of a call's parameters: its designated ones no larger. -/
def initCls (pos : List Nat) (n : Nat) : List SizeCls :=
  (List.range n).map fun i => if i ∈ pos then .le else .unk

def paramIds (params : List SrcParam) : List Nat := params.map (·.id)

/-- A function body checked for the annotation `me`. -/
def chkFn (f : SrcFunc) : Bool :=
  chkStmt prims T me (AEnv.bindAll [] ((paramIds f.params).zip (initCls me.pos f.params.length))) [] f.body

end

/-- A decrement function: `minus(a, b)`, which runs `panic` when `b > a`
(the prelude's `minus` returns 0 there) and otherwise returns `a - b`. -/
def DecOk (sp : SrcProgram) (prims : Prims) (c : Nat) : Prop :=
  prims.isPrim c = false ∧ ∃ f a b panic, sp.funcs[c]? = some f ∧ paramIds f.params = [a, b] ∧ a ≠ b ∧
    f.body = .then (.if (.apply .greater (.local b) (.local a)) panic .nop)
      (.return (.apply .minus (.local a) (.local b)))

/-- A constant: a function that returns the payload-free variant `j` of enum
`id`. -/
def ConstOk (sp : SrcProgram) (prims : Prims) (c id j : Nat) : Prop :=
  prims.isPrim c = false ∧ ∃ f ty, sp.funcs[c]? = some f ∧ ty.typeId = id ∧
    f.body = .returnEval (.eVariant ty j [])

/-- Every annotated function's body passes the check, the decrement
functions are decrements, and the constants constants. -/
structure TermOk (sp : SrcProgram) (prims : Prims) (T : TermInfo) : Prop where
  decs : ∀ c ∈ T.decs, DecOk sp prims c
  consts : ∀ p ∈ T.consts, ConstOk sp prims p.1 p.2.1 p.2.2
  fns : ∀ p ∈ T.anns, prims.isPrim p.1 = true ∨ ∀ f, sp.funcs[p.1]? = some f → chkFn prims T p.2 f = true

/-- A pure call settles: past some fuel, more fuel gives the same answer. -/
def Settles (sp : SrcProgram) (prims : Prims) (c : Nat) (vs : List Value) : Prop :=
  ∃ N, ∀ m, N ≤ m → pcall sp prims m c vs = pcall sp prims N c vs

end Lanius.Faithful.Termination
