import Lanius.Mini.Syntax

/-! Source semantics. Arithmetic wraps, as Lanius i32 does. Milestone 1 has no
loops, so evaluation is a total function. -/

namespace Lanius.Mini

abbrev Env := Nat → BitVec 32

def BinOp.apply : BinOp → BitVec 32 → BitVec 32 → BitVec 32
  | .add, a, b => a + b
  | .sub, a, b => a - b
  | .mul, a, b => a * b
  | .and, a, b => a &&& b
  | .or, a, b => a ||| b
  | .xor, a, b => a ^^^ b

def Expr.eval (env : Env) : Expr → BitVec 32
  | .lit value => value
  | .var index => env index
  | .neg operand => -operand.eval env
  | .binary operation left right => operation.apply (left.eval env) (right.eval env)

def Env.set (env : Env) (index : Nat) (value : BitVec 32) : Env :=
  fun other => if other = index then value else env other

/-- The value a body returns, or `none` if it falls off the end. -/
def run (env : Env) : List Stmt → Option (BitVec 32)
  | [] => none
  | .assign index value :: rest => run (env.set index (value.eval env)) rest
  | .ret value :: _ => some (value.eval env)

def Func.run (func : Func) (args : Env) : Option (BitVec 32) := Mini.run args func.body

end Lanius.Mini
