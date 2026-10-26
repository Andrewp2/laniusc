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

Fuel counts calls only: `peff` and `pstmt` go by the syntax of a body,
with the meaning of its calls a parameter, and `pcall` gives a call with
fuel `n + 1` its body's meaning with calls of fuel `n`. So a function's
certificate unfolds its body without fuel case splits, and a Core run with
fuel `n` has a pure run within the same fuel (`Faithful/Simulation.lean`).
The constructs pure code does not use (loops, assignment, raw memory) have
no pure meaning (`none`).

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
  | .assert condition =>
      ((peff call env condition).bind asBool).bind fun b => if b then some .next else none

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
          (pstmt (pcall sp prims fuel) (paramEnv f.params values) f.body).bind (doneValue f.ret)
        else none

end Lanius.Faithful
