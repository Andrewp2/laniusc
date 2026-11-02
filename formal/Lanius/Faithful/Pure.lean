module

public import Lanius.Semantics
public import Lanius.Mini.Compiler.Types
public import Lanius.Mini.SourceCore

@[expose] public section

/-! # The pure meaning of a front-pass program

The verified compiler is written in pure Lanius: values are never mutated,
and the only memory it touches is the prelude's `Box<T>`, whose `boxed`
writes a value into a fresh block and whose `unbox` reads it back. This file
gives such a program a meaning without a heap: `boxed` and `unbox` are the
identity, locals are an environment, and everything else is what Core does,
with Core's own scalar functions.

Fuel counts calls and loop steps: `peff` and `mstmt` go by the syntax of a
body, with the meaning of its calls a parameter, and `pcall` gives a call
with fuel `n + 1` its body's meaning with calls of fuel `n` and loops of at
most `n` steps. An assignment replaces the value of its local's newest
binding, and a loop is recursion on its fuel (`ploop`). A body with no loop
and no assignment has the simpler meaning `pstmt`, which leaves the
environment it got, so a function's certificate unfolds its body without
fuel case splits (`pcall_succ`), and a Core run with fuel `n` has a pure run
within the same fuel (`Faithful/Simulation.lean`). The constructs pure code
does not use (raw memory, fields written in place) have no pure meaning
(`none`).

Each extracted Lean function is then proved to be what the pure semantics
computes for its Lanius function (`Faithful/Cert.lean`), on values that
encode the Lean arguments: one certificate per function, by induction on
the fuel. -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (evalUnaryValue evalBinaryValue evalScalarCast matchPattern)

/-- Local values, the newest binding first, as Core's `locals` find them. -/
abbrev Env := List (Nat × Value)

def Env.get? (env : Env) (id : Nat) : Option Value :=
  (env.find? (fun binding => binding.1 == id)).map Prod.snd

/-- Bindings added one after another, as Core's `bindLocals`. -/
def Env.bindAll (env : Env) (bindings : List (Nat × Value)) : Env :=
  bindings.foldl (fun result binding => binding :: result) env

def target : Core.Target := .x86_64

/-- The functions whose calls the pure semantics answers itself: instances
of the prelude's `boxed` and `unbox`, each the identity on its one argument. -/
structure Prims where
  boxed : List Nat
  unbox : List Nat

def Prims.isPrim (prims : Prims) (callee : Nat) : Bool :=
  prims.boxed.contains callee || prims.unbox.contains callee

def single : List Value → Option Value
  | [] => none
  | [value] => some value
  | _ :: _ :: _ => none

def fieldOf : Value → Nat → Option Value
  | .structure _ fields, index => fields[index]?
  | .unit, _ | .boolean _, _ | .signed _ _, _ | .unsigned _ _, _ | .f32Bits _, _ | .f64Bits _, _
  | .character _, _ | .string _, _ | .pointer _, _ | .array _, _ | .slice _ _ _ _ _, _
  | .rawSlice _ _ _, _ | .enumeration _ _ _, _ | .reference _ _ _, _ => none

/-- The boolean a condition gives, as Core's `if` and `&&` read it. -/
def asBool : Value → Option Bool
  | .boolean b => some b
  | .unit | .signed _ _ | .unsigned _ _ | .f32Bits _ | .f64Bits _ | .character _ | .string _
  | .pointer _ | .array _ | .slice _ _ _ _ _ | .rawSlice _ _ _ | .structure _ _
  | .enumeration _ _ _ | .reference _ _ _ => none

def unary (op : Core.UnaryOp) (value : Value) : Option Value :=
  (evalUnaryValue target op value).toOption

def cast (ty : SrcType) (value : Value) : Option Value :=
  (evalScalarCast target ty.toScalar value).toOption

def binary (op : Core.BinaryOp) (left right : Option Value) : Option Value :=
  left.bind fun l => right.bind fun r => (evalBinaryValue target op l r).toOption

/-- Core's `&&` and `||` look at the right side only when the left one does
not decide; the others evaluate both sides, left first. -/
def applyOp (op : SrcOp) (left right : Option Value) : Option Value :=
  match op with
  | .logicalAnd => left.bind asBool |>.bind fun b => if b then right else some (.boolean false)
  | .logicalOr => left.bind asBool |>.bind fun b => if b then some (.boolean true) else right
  | .plus | .minus | .times | .bitAnd | .bitOr | .bitXor | .shiftLeft | .shiftRight | .less
  | .lessEq | .greater | .greaterEq | .equal | .notEqual => binary op.toCore left right

/-- A pure expression: Core's evaluation of its `toCore`, without fuel. -/
def pexpr (env : Env) : SrcExpr → Option Value
  | .int value => some (.signed .i32 value.toInt)
  | .boolean value => some (.boolean value)
  | .unsigned kind value => some (.unsigned kind.toCore value.toNat)
  | .local id => env.get? id
  | .field id index => (env.get? id).bind (fieldOf · index)
  | .negate operand => (pexpr env operand).bind (unary .negate)
  | .not operand => (pexpr env operand).bind (unary .logicalNot)
  | .apply op left right => applyOp op (pexpr env left) (pexpr env right)
  | .cast ty operand => (pexpr env operand).bind (cast ty)
  | .null => some (.pointer 0)
  | .char code => some (.character (UInt32.ofNat code.toNat))
  | .float t x => some (t.value x)

def pexprs (env : Env) : List SrcExpr → Option (List Value)
  | [] => some []
  | e :: es => (pexpr env e).bind fun v => (pexprs env es).map (v :: ·)

/-- How a statement ends: on to the next one, or a `return`. -/
inductive Done where
  | next
  | ret (value : Option Value)

/-- A call's value from how its body ended, as Core's call does it. -/
def doneValue (ret : SrcType) : Done → Option Value
  | .ret (some value) => some value
  | .ret none => if ret.toCore = .unit then some .unit else none
  | .next => if ret.toCore = .unit then some .unit else none

/-- After a statement that ended so, the next one, `rest`. -/
def Done.then (rest : Option Done) : Done → Option Done
  | .next => rest
  | .ret value => some (.ret value)

def paramEnv (params : List SrcParam) (values : List Value) : Env :=
  Env.bindAll [] (paramBindings params values)

/-- How a statement ended, with the environment it left unless it returned:
on to the next one, a `break`, a `continue`, or a `return`. -/
inductive Out where
  | next (env : Env)
  | brk (env : Env)
  | cont (env : Env)
  | ret (value : Option Value)

/-- The newest binding of `id` given the value `v`, as Core's assignment
writes the cell that binding names; `none` when `id` is not bound. -/
def Env.set : Env → Nat → Value → Option Env
  | [], _, _ => none
  | (x, w) :: rest, id, v => if x = id then some ((x, v) :: rest) else (Env.set rest id v).map ((x, w) :: ·)

/-- After a `let`'s body: the body's binding dropped, as Core's `restoreLocals`. -/
def Out.pop : Out → Out
  | .next env => .next env.tail
  | .brk env => .brk env.tail
  | .cont env => .cont env.tail
  | .ret value => .ret value

/-- After a statement that ended so, the next one, `rest`, in the
environment it left. -/
def Out.then (rest : Env → Option Out) : Out → Option Out
  | .next env => rest env
  | .brk env => some (.brk env)
  | .cont env => some (.cont env)
  | .ret value => some (.ret value)

/-- A call's value from how its body ended, as Core's call does it: a body
that ends with `break` or `continue` traps. -/
def outValue (ret : SrcType) : Out → Option Value
  | .ret (some value) => some value
  | .ret none => if ret.toCore = .unit then some .unit else none
  | .next _ => if ret.toCore = .unit then some .unit else none
  | .brk _ => none
  | .cont _ => none

/-- The environment a statement left, unless it returned. -/
def Out.env? : Out → Option Env
  | .next env => some env
  | .brk env => some env
  | .cont env => some env
  | .ret _ => none

/-- A loop-free ending in the environment `env`. -/
def Out.ofDone (env : Env) : Done → Out
  | .next => .next env
  | .ret value => .ret value

/-- A statement with no loop, assignment, `break` or `continue`: `pstmt`
gives its meaning. -/
def _root_.Lanius.Mini.SrcStmt.loopFree : SrcStmt → Bool
  | .nop => true
  | .let _ _ _ body => body.loopFree
  | .letStruct _ _ _ body => body.loopFree
  | .letCall _ _ _ _ body => body.loopFree
  | .letEnum _ _ _ _ body => body.loopFree
  | .letMatch _ _ _ _ _ _ => true
  | .set _ _ => false
  | .setField _ _ _ => true
  | .setCall _ _ _ => true
  | .then first second => first.loopFree && second.loopFree
  | .if _ a b => a.loopFree && b.loopFree
  | .while _ _ => false
  | .return _ => true
  | .letAlloc _ _ _ _ => true
  | .letView _ _ _ _ _ => true
  | .letLoad _ _ _ _ => true
  | .setByte _ _ _ => true
  | .free _ _ _ => true
  | .letSlice _ _ _ _ _ => true
  | .letIndex _ _ _ _ _ => true
  | .setIndex _ _ _ => true
  | .letEval _ _ _ body => body.loopFree
  | .setEval _ _ => false
  | .ifEval _ a b => a.loopFree && b.loopFree
  | .whileEval _ _ => false
  | .returnEval _ => true
  | .discard _ => true
  | .setIndexEval _ _ _ => true
  | .setFieldEval _ _ _ => true
  | .returnUnit => true
  | .assert _ => true
  | .break => false
  | .continue => false
  | .matchArm _ _ _ _ _ _ _ _ => true
  | .unreachable _ _ => true

/-- The locals a statement may assign, with repeats; a `let`'s body's
include assignments of its own local. -/
def _root_.Lanius.Mini.SrcStmt.writes : SrcStmt → List Nat
  | .nop => []
  | .let _ _ _ body => body.writes
  | .letStruct _ _ _ body => body.writes
  | .letCall _ _ _ _ body => body.writes
  | .letEnum _ _ _ _ body => body.writes
  | .letMatch _ _ _ _ _ _ => []
  | .set id _ => [id]
  | .setField _ _ _ => []
  | .setCall _ _ _ => []
  | .then first second => first.writes ++ second.writes
  | .if _ a b => a.writes ++ b.writes
  | .while _ body => body.writes
  | .return _ => []
  | .letAlloc _ _ _ _ => []
  | .letView _ _ _ _ _ => []
  | .letLoad _ _ _ _ => []
  | .setByte _ _ _ => []
  | .free _ _ _ => []
  | .letSlice _ _ _ _ _ => []
  | .letIndex _ _ _ _ _ => []
  | .setIndex _ _ _ => []
  | .letEval _ _ _ body => body.writes
  | .setEval id _ => [id]
  | .ifEval _ a b => a.writes ++ b.writes
  | .whileEval _ body => body.writes
  | .returnEval _ => []
  | .discard _ => []
  | .setIndexEval _ _ _ => []
  | .setFieldEval _ _ _ => []
  | .returnUnit => []
  | .assert _ => []
  | .break => []
  | .continue => []
  | .matchArm _ _ _ _ _ _ _ _ => []
  | .unreachable _ _ => []

/-- A call's meaning: the callee and the argument values to the value returned. -/
abbrev Calls := Nat → List Value → Option Value

section
variable (call : Calls)

mutual
/-- An effectful expression, with `call` the meaning of its calls. -/
def peff (env : Env) : SrcEff → Option Value
  | .ePure e => pexpr env e
  | .eCall callee args => (peffs env args).bind (call callee)
  | .eApply op left right => applyOp op (peff env left) (peff env right)
  | .eNeg operand => (peff env operand).bind (unary .negate)
  | .eNot operand => (peff env operand).bind (unary .logicalNot)
  | .eCast ty operand => (peff env operand).bind (cast ty)
  | .eIndex _ _ => none
  | .eStruct ty fields => (peffs env fields).map (.structure ty.typeId)
  | .eVariant ty variant payload => (peffs env payload).map (.enumeration ty.typeId variant)
  | .eMatch scrutinee ety _ binders values =>
      (peff env scrutinee).bind fun v => parms env v ety.typeId 0 binders values
  | .eDivide op left right => binary op.toCore (peff env left) (peff env right)
  | .eStride _ => none
  | .arraySlice _ _ => none
  | .eIf condition _ thenValue elseValue =>
      (peff env condition).bind fun c => (asBool c).bind fun b =>
        if b then peff env thenValue else peff env elseValue
  | .eLet id _ value _ body => (peff env value).bind fun v => peff ((id, v) :: env) body
  | .eLen _ => none

def peffs (env : Env) : List SrcEff → Option (List Value)
  | [] => some []
  | e :: es => (peff env e).bind fun v => (peffs env es).map (v :: ·)

/-- Arm `k` matches variant `k` of enum `id`, binding its payload. -/
def parms (env : Env) (v : Value) (id : Nat) : Nat → List (List Nat) → List SrcEff → Option Value
  | _, [], _ => none
  | _, _ :: _, [] => none
  | k, binders :: rest, value :: values =>
      match matchPattern (.enumVariant id k (binders.map .bind)) v with
      | none => parms env v id (k + 1) rest values
      | some bindings => peff (env.bindAll bindings) value
end

/-- A statement, with `call` the meaning of its calls. Statements do not
change the environment of the ones after them: a `let` scopes over its body. -/
def pstmt (env : Env) : SrcStmt → Option Done
  | .nop => some .next
  | .let id _ value body => (pexpr env value).bind fun v => pstmt ((id, v) :: env) body
  | .letStruct id ty fields body =>
      (pexprs env fields).bind fun vs => pstmt ((id, .structure ty.typeId vs) :: env) body
  | .letCall id _ callee args body =>
      ((pexprs env args).bind (call callee)).bind fun v => pstmt ((id, v) :: env) body
  | .letEnum id ty variant payload body =>
      (pexprs env payload).bind fun vs => pstmt ((id, .enumeration ty.typeId variant vs) :: env) body
  | .letMatch _ _ _ _ _ _ => none
  | .set _ _ => none
  | .setField _ _ _ => none
  | .setCall _ _ _ => none
  | .then first second => (pstmt env first).bind (Done.then (pstmt env second))
  | .if condition thenBranch elseBranch =>
      ((pexpr env condition).bind asBool).bind fun b =>
        if b then pstmt env thenBranch else pstmt env elseBranch
  | .while _ _ => none
  | .return value => (pexpr env value).map fun v => .ret (some v)
  | .letAlloc _ _ _ _ => none
  | .letView _ _ _ _ _ => none
  | .letLoad _ _ _ _ => none
  | .setByte _ _ _ => none
  | .free _ _ _ => none
  | .letSlice _ _ _ _ _ => none
  | .letIndex _ _ _ _ _ => none
  | .setIndex _ _ _ => none
  | .letEval id _ value body => (peff call env value).bind fun v => pstmt ((id, v) :: env) body
  | .setEval _ _ => none
  | .ifEval condition thenBranch elseBranch =>
      ((peff call env condition).bind asBool).bind fun b =>
        if b then pstmt env thenBranch else pstmt env elseBranch
  | .whileEval _ _ => none
  | .returnEval value => (peff call env value).map fun v => .ret (some v)
  | .discard value => (peff call env value).map fun _ => .next
  | .setIndexEval _ _ _ => none
  | .setFieldEval _ _ _ => none
  | .returnUnit => some (.ret none)
  | .break => none
  | .continue => none
  | .matchArm _ _ _ _ _ _ _ _ => none
  | .unreachable _ _ => none
  | .assert condition =>
      ((peff call env condition).bind asBool).bind fun b => if b then some .next else none

/-- A loop of at most `fuel` steps: while `test` holds, the body, until it
breaks or returns. A body that ends `continue` goes on as one that ends. -/
def ploop (test : Env → Option Bool) (body : Env → Option Out) : Nat → Env → Option Out
  | 0, _ => none
  | fuel + 1, env =>
    (test env).bind fun b =>
      if b then
        (body env).bind fun o =>
          match o with
          | .next e => ploop test body fuel e
          | .cont e => ploop test body fuel e
          | .brk e => some (.next e)
          | .ret value => some (.ret value)
      else some (.next env)

/-- A statement, with `call` the meaning of its calls and `fuel` the steps
its loops may take: how it ends and the environment it leaves. -/
def mstmt (fuel : Nat) (env : Env) : SrcStmt → Option Out
  | .nop => some (.next env)
  | .let id _ value body => (pexpr env value).bind fun v => (mstmt fuel ((id, v) :: env) body).map Out.pop
  | .letStruct id ty fields body =>
      (pexprs env fields).bind fun vs => (mstmt fuel ((id, .structure ty.typeId vs) :: env) body).map Out.pop
  | .letCall id _ callee args body =>
      ((pexprs env args).bind (call callee)).bind fun v => (mstmt fuel ((id, v) :: env) body).map Out.pop
  | .letEnum id ty variant payload body =>
      (pexprs env payload).bind fun vs =>
        (mstmt fuel ((id, .enumeration ty.typeId variant vs) :: env) body).map Out.pop
  | .letMatch _ _ _ _ _ _ => none
  | .set id value => (pexpr env value).bind fun v => (env.set id v).map .next
  | .setField _ _ _ => none
  | .setCall _ _ _ => none
  | .then first second => (mstmt fuel env first).bind (Out.then fun e => mstmt fuel e second)
  | .if condition thenBranch elseBranch =>
      ((pexpr env condition).bind asBool).bind fun b =>
        if b then mstmt fuel env thenBranch else mstmt fuel env elseBranch
  | .while condition body =>
      ploop (fun e => (pexpr e condition).bind asBool) (fun e => mstmt fuel e body) fuel env
  | .return value => (pexpr env value).map fun v => .ret (some v)
  | .letAlloc _ _ _ _ => none
  | .letView _ _ _ _ _ => none
  | .letLoad _ _ _ _ => none
  | .setByte _ _ _ => none
  | .free _ _ _ => none
  | .letSlice _ _ _ _ _ => none
  | .letIndex _ _ _ _ _ => none
  | .setIndex _ _ _ => none
  | .letEval id _ value body =>
      (peff call env value).bind fun v => (mstmt fuel ((id, v) :: env) body).map Out.pop
  | .setEval id value => (peff call env value).bind fun v => (env.set id v).map .next
  | .ifEval condition thenBranch elseBranch =>
      ((peff call env condition).bind asBool).bind fun b =>
        if b then mstmt fuel env thenBranch else mstmt fuel env elseBranch
  | .whileEval condition body =>
      ploop (fun e => (peff call e condition).bind asBool) (fun e => mstmt fuel e body) fuel env
  | .returnEval value => (peff call env value).map fun v => .ret (some v)
  | .discard value => (peff call env value).map fun _ => .next env
  | .setIndexEval _ _ _ => none
  | .setFieldEval _ _ _ => none
  | .returnUnit => some (.ret none)
  | .break => some (.brk env)
  | .continue => some (.cont env)
  | .matchArm _ _ _ _ _ _ _ _ => none
  | .unreachable _ _ => none
  | .assert condition =>
      ((peff call env condition).bind asBool).bind fun b => if b then some (.next env) else none

end

/-- Function `callee` of `sp` called on `values`, with `fuel` calls deep at
most: `boxed` and `unbox` are the identity, the others run their body. -/
def pcall (sp : SrcProgram) (prims : Prims) : Nat → Calls
  | 0, _, _ => none
  | fuel + 1, callee, values =>
    if prims.isPrim callee then single values
    else
      match sp.funcs[callee]? with
      | none => none
      | some f =>
        if values.length = f.params.length then
          (mstmt (pcall sp prims fuel) fuel (paramEnv f.params values) f.body).bind (outValue f.ret)
        else none

theorem pop_ofDone (id : Nat) (v : Value) (env : Env) :
    (fun d => Out.pop (Out.ofDone ((id, v) :: env) d)) = Out.ofDone env := by
  funext d
  cases d <;> rfl

theorem map_pop_ofDone (id : Nat) (v : Value) (env : Env) (o : Option Done) :
    (o.map (Out.ofDone ((id, v) :: env))).map Out.pop = o.map (Out.ofDone env) := by
  rw [Option.map_map]
  exact congrArg (Option.map · o) (pop_ofDone id v env)

/-- A loop-free statement leaves the environment it got: `mstmt` is `pstmt`. -/
theorem mstmt_loopFree (call : Calls) (fuel : Nat) :
    ∀ (s : SrcStmt) (env : Env), s.loopFree = true →
      mstmt call fuel env s = (pstmt call env s).map (Out.ofDone env) := by
  intro s
  induction s with
  | nop => intro env _; rfl
  | «let» id _ value body ih =>
    intro env h
    simp only [SrcStmt.loopFree] at h
    simp only [mstmt, pstmt]
    cases pexpr env value with
    | none => rfl
    | some v => simp only [Option.bind_some]; rw [ih _ h, map_pop_ofDone]
  | letStruct id ty fields body ih =>
    intro env h
    simp only [SrcStmt.loopFree] at h
    simp only [mstmt, pstmt]
    cases pexprs env fields with
    | none => rfl
    | some vs => simp only [Option.bind_some]; rw [ih _ h, map_pop_ofDone]
  | letCall id _ callee args body ih =>
    intro env h
    simp only [SrcStmt.loopFree] at h
    simp only [mstmt, pstmt]
    cases (pexprs env args).bind (call callee) with
    | none => rfl
    | some v => simp only [Option.bind_some]; rw [ih _ h, map_pop_ofDone]
  | letEnum id ty k payload body ih =>
    intro env h
    simp only [SrcStmt.loopFree] at h
    simp only [mstmt, pstmt]
    cases pexprs env payload with
    | none => rfl
    | some vs => simp only [Option.bind_some]; rw [ih _ h, map_pop_ofDone]
  | «then» first second ih1 ih2 =>
    intro env h
    simp only [SrcStmt.loopFree, Bool.and_eq_true] at h
    simp only [mstmt, pstmt]
    rw [ih1 _ h.1]
    cases pstmt call env first with
    | none => rfl
    | some d =>
      cases d with
      | next => exact ih2 _ h.2
      | ret _ => rfl
  | «if» condition a b iha ihb =>
    intro env h
    simp only [SrcStmt.loopFree, Bool.and_eq_true] at h
    simp only [mstmt, pstmt]
    cases (pexpr env condition).bind asBool with
    | none => rfl
    | some bv => cases bv with
      | true => exact iha _ h.1
      | false => exact ihb _ h.2
  | «return» value => intro env _; simp only [mstmt, pstmt]; cases pexpr env value <;> rfl
  | letEval id _ value body ih =>
    intro env h
    simp only [SrcStmt.loopFree] at h
    simp only [mstmt, pstmt]
    cases peff call env value with
    | none => rfl
    | some v => simp only [Option.bind_some]; rw [ih _ h, map_pop_ofDone]
  | ifEval condition a b iha ihb =>
    intro env h
    simp only [SrcStmt.loopFree, Bool.and_eq_true] at h
    simp only [mstmt, pstmt]
    cases (peff call env condition).bind asBool with
    | none => rfl
    | some bv => cases bv with
      | true => exact iha _ h.1
      | false => exact ihb _ h.2
  | returnEval value => intro env _; simp only [mstmt, pstmt]; cases peff call env value <;> rfl
  | discard value => intro env _; simp only [mstmt, pstmt]; cases peff call env value <;> rfl
  | assert condition =>
    intro env _
    simp only [mstmt, pstmt]
    cases (peff call env condition).bind asBool with
    | none => rfl
    | some bv => cases bv <;> rfl
  | returnUnit => intro env _; rfl
  | set _ _ | «while» _ _ | setEval _ _ | whileEval _ _ | «break» | «continue» =>
    intro env h; simp [SrcStmt.loopFree] at h
  | letMatch _ _ _ _ _ _ | setField _ _ _ | setCall _ _ _ | letAlloc _ _ _ _ | letView _ _ _ _ _ | letLoad _ _ _ _ | setByte _ _ _
  | free _ _ _ | letSlice _ _ _ _ _ | letIndex _ _ _ _ _ | setIndex _ _ _ | setIndexEval _ _ _
  | setFieldEval _ _ _ | matchArm _ _ _ _ _ _ _ _ | unreachable _ _ => intro env _; rfl

theorem outValue_ofDone (ret : SrcType) (env : Env) (d : Done) :
    outValue ret (Out.ofDone env d) = doneValue ret d := by
  cases d with
  | next => rfl
  | ret v => cases v <;> rfl

end Lanius.Faithful
