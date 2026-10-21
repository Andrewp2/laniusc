import Lanius.Mini.Syntax

/-! Source semantics. Arithmetic wraps, as Lanius i32 does. Statements have a
big-step semantics; the index bounds the call depth of the derivation, which is
what bounds the stack the compiled code uses. A function's non-parameter locals
start at zero. -/

namespace Lanius.Mini

abbrev Env := Nat → BitVec 32

def BinOp.apply : BinOp → BitVec 32 → BitVec 32 → BitVec 32
  | .add, a, b => a + b
  | .sub, a, b => a - b
  | .mul, a, b => a * b
  | .and, a, b => a &&& b
  | .or, a, b => a ||| b
  | .xor, a, b => a ^^^ b

def CmpOp.holds : CmpOp → BitVec 32 → BitVec 32 → Bool
  | .eq, a, b => a == b
  | .ne, a, b => a != b
  | .lt, a, b => a.slt b
  | .le, a, b => a.sle b
  | .gt, a, b => b.slt a
  | .ge, a, b => b.sle a

def Expr.eval (env : Env) : Expr → BitVec 32
  | .lit value => value
  | .var index => env index
  | .neg operand => -operand.eval env
  | .binary operation left right => operation.apply (left.eval env) (right.eval env)
  | .compare operation left right =>
      if operation.holds (left.eval env) (right.eval env) then 1 else 0

def Expr.evalAll (env : Env) : List Expr → List (BitVec 32)
  | [] => []
  | e :: rest => e.eval env :: Expr.evalAll env rest

def Env.set (env : Env) (index : Nat) (value : BitVec 32) : Env :=
  fun other => if other = index then value else env other

/-- Parameters hold the arguments; every other local starts at zero. -/
def Func.entry (args : List (BitVec 32)) : Env := fun index => args.getD index 0

inductive Outcome where
  | normal (env : Env)
  | returned (value : BitVec 32)

/-- `Exec prog depth env stmt outcome`: running `stmt` from `env` ends in
`outcome`, with calls nested fewer than `depth` deep. -/
inductive Exec (prog : Program) : Nat → Env → Stmt → Outcome → Prop where
  | skip {depth : Nat} {env : Env} : Exec prog depth env .skip (.normal env)
  | assign {depth : Nat} {env : Env} {index : Nat} {value : Expr} :
      Exec prog depth env (.assign index value) (.normal (env.set index (value.eval env)))
  | seq {depth : Nat} {env middle : Env} {first second : Stmt} {outcome : Outcome} :
      Exec prog depth env first (.normal middle) → Exec prog depth middle second outcome →
      Exec prog depth env (.seq first second) outcome
  | seqReturned {depth : Nat} {env : Env} {first second : Stmt} {value : BitVec 32} :
      Exec prog depth env first (.returned value) →
      Exec prog depth env (.seq first second) (.returned value)
  | ifTrue {depth : Nat} {env : Env} {condition : Expr} {thenBranch elseBranch : Stmt} {outcome : Outcome} :
      condition.eval env ≠ 0 → Exec prog depth env thenBranch outcome →
      Exec prog depth env (.ite condition thenBranch elseBranch) outcome
  | ifFalse {depth : Nat} {env : Env} {condition : Expr} {thenBranch elseBranch : Stmt} {outcome : Outcome} :
      condition.eval env = 0 → Exec prog depth env elseBranch outcome →
      Exec prog depth env (.ite condition thenBranch elseBranch) outcome
  | loopDone {depth : Nat} {env : Env} {condition : Expr} {body : Stmt} :
      condition.eval env = 0 → Exec prog depth env (.loop condition body) (.normal env)
  | loopNext {depth : Nat} {env middle : Env} {condition : Expr} {body : Stmt} {outcome : Outcome} :
      condition.eval env ≠ 0 → Exec prog depth env body (.normal middle) →
      Exec prog depth middle (.loop condition body) outcome →
      Exec prog depth env (.loop condition body) outcome
  | loopReturned {depth : Nat} {env : Env} {condition : Expr} {body : Stmt} {value : BitVec 32} :
      condition.eval env ≠ 0 → Exec prog depth env body (.returned value) →
      Exec prog depth env (.loop condition body) (.returned value)
  | call {depth inner target callee : Nat} {env : Env} {args : List Expr} {func : Func} {value : BitVec 32} :
      prog.funcs[callee]? = some func → args.length = func.params → inner < depth →
      Exec prog inner (Func.entry (Expr.evalAll env args)) func.body (.returned value) →
      Exec prog depth env (.call target callee args) (.normal (env.set target value))
  | ret {depth : Nat} {env : Env} {value : Expr} : Exec prog depth env (.ret value) (.returned (value.eval env))

/-- Calling function `callee` with `args` returns `value`, nesting calls fewer
than `depth` deep. -/
def Program.Returns (prog : Program) (depth callee : Nat) (args : List (BitVec 32))
    (value : BitVec 32) : Prop :=
  ∃ func, prog.funcs[callee]? = some func ∧ args.length = func.params ∧
    Exec prog depth (Func.entry args) func.body (.returned value)

end Lanius.Mini
