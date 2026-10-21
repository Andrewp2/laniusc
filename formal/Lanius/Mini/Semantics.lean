import Lanius.Mini.Compiler

/-! Source semantics over 64-bit words. Arithmetic wraps; an `s32` operation
acts on the low 32 bits and zero-extends its result, and its comparisons are
signed; a `u64` operation uses all 64 bits, unsigned. Statements have a
big-step semantics; the index bounds the call depth of the derivation, which is
what bounds the stack the compiled code uses. A function's non-parameter locals
start at zero. -/

namespace Lanius.Mini

abbrev Env := Nat → BitVec 64

def BinOp.apply {n : Nat} : BinOp → BitVec n → BitVec n → BitVec n
  | .add, a, b => a + b
  | .sub, a, b => a - b
  | .mul, a, b => a * b
  | .and, a, b => a &&& b
  | .or, a, b => a ||| b
  | .xor, a, b => a ^^^ b

/-- Signed comparisons. -/
def CmpOp.holds : CmpOp → BitVec 32 → BitVec 32 → Bool
  | .eq, a, b => a == b
  | .ne, a, b => a != b
  | .lt, a, b => a.slt b
  | .le, a, b => a.sle b
  | .gt, a, b => b.slt a
  | .ge, a, b => b.sle a

/-- Unsigned comparisons. -/
def CmpOp.holdsU : CmpOp → BitVec 64 → BitVec 64 → Bool
  | .eq, a, b => a == b
  | .ne, a, b => a != b
  | .lt, a, b => a.ult b
  | .le, a, b => a.ule b
  | .gt, a, b => b.ult a
  | .ge, a, b => b.ule a

/-- The low 32 bits of a word. -/
abbrev low (a : BitVec 64) : BitVec 32 := a.setWidth 32

/-- A 32-bit result, zero-extended. -/
abbrev widen (a : BitVec 32) : BitVec 64 := a.setWidth 64

def Word.apply : Word → BinOp → BitVec 64 → BitVec 64 → BitVec 64
  | .s32, operation, a, b => widen (operation.apply (low a) (low b))
  | .u64, operation, a, b => operation.apply a b

def Word.holds : Word → CmpOp → BitVec 64 → BitVec 64 → Bool
  | .s32, operation, a, b => operation.holds (low a) (low b)
  | .u64, operation, a, b => operation.holdsU a b

def Expr.eval (env : Env) : Expr → BitVec 64
  | .lit value => value
  | .var index => env index
  | .neg operand => widen (-low (operand.eval env))
  | .binary word operation left right => word.apply operation (left.eval env) (right.eval env)
  | .compare word operation left right =>
      if word.holds operation (left.eval env) (right.eval env) then 1 else 0

def Expr.evalAll (env : Env) : List Expr → List (BitVec 64)
  | [] => []
  | e :: rest => e.eval env :: Expr.evalAll env rest

def Env.set (env : Env) (index : Nat) (value : BitVec 64) : Env :=
  fun other => if other = index then value else env other

/-- `values` stored at `slot`, `slot + 1`, ... -/
def Env.setMany (env : Env) : Nat → List (BitVec 64) → Env
  | _, [] => env
  | slot, value :: rest => Env.setMany (env.set slot value) (slot + 1) rest

/-- Parameters hold the arguments; every other local starts at zero. -/
def Func.entry (args : List (BitVec 64)) : Env := fun index => args.getD index 0

inductive Outcome where
  | normal (env : Env)
  | returned (values : List (BitVec 64))

/-- `Exec prog depth env stmt outcome`: running `stmt` from `env` ends in
`outcome`, with calls nested fewer than `depth` deep. -/
inductive Exec (prog : Program) : Nat → Env → Stmt → Outcome → Prop where
  | skip {depth : Nat} {env : Env} : Exec prog depth env .skip (.normal env)
  | assign {depth : Nat} {env : Env} {index : Nat} {value : Expr} :
      Exec prog depth env (.assign index value) (.normal (env.set index (value.eval env)))
  | seq {depth : Nat} {env middle : Env} {first second : Stmt} {outcome : Outcome} :
      Exec prog depth env first (.normal middle) → Exec prog depth middle second outcome →
      Exec prog depth env (.seq first second) outcome
  | seqReturned {depth : Nat} {env : Env} {first second : Stmt} {value : List (BitVec 64)} :
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
  | loopReturned {depth : Nat} {env : Env} {condition : Expr} {body : Stmt} {value : List (BitVec 64)} :
      condition.eval env ≠ 0 → Exec prog depth env body (.returned value) →
      Exec prog depth env (.loop condition body) (.returned value)
  | call {depth inner target count callee : Nat} {env : Env} {args : List Expr} {func : Func}
      {value : List (BitVec 64)} :
      prog.funcs[callee]? = some func → args.length = func.params → value.length = count → inner < depth →
      Exec prog inner (Func.entry (Expr.evalAll env args)) func.body (.returned value) →
      Exec prog depth env (.call target count callee args) (.normal (env.setMany target value))
  | ret {depth : Nat} {env : Env} {values : List Expr} :
      Exec prog depth env (.ret values) (.returned (Expr.evalAll env values))

/-- Calling function `callee` with `args` returns `value`, nesting calls fewer
than `depth` deep. -/
def Program.Returns (prog : Program) (depth callee : Nat) (args : List (BitVec 64))
    (value : List (BitVec 64)) : Prop :=
  ∃ func, prog.funcs[callee]? = some func ∧ args.length = func.params ∧
    Exec prog depth (Func.entry args) func.body (.returned value)

end Lanius.Mini
