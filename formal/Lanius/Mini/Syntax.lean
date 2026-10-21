/-! Source language of the mini compiler: i32 code with comparisons, `if`,
`while`, and functions with parameters and direct calls.

Locals are resolved to frame indices; a function's parameters are its first
locals. Comparisons produce 1 or 0, which is how `bool` values reach this
language; conditions test for nonzero. Calls are statements (`target = f(args)`),
so expression evaluation stays a total function.

The Lanius twin of this file uses `enum Stmt { ..., Seq(Box<Stmt>, Box<Stmt>) }`;
`Box<T>` is `T` here and `Vec<T>` is `List T`. -/

namespace Lanius.Mini

inductive BinOp where
  | add | sub | mul | and | or | xor
  deriving DecidableEq, Repr

/-- Signed comparisons. -/
inductive CmpOp where
  | eq | ne | lt | le | gt | ge
  deriving DecidableEq, Repr

inductive Expr where
  | lit (value : BitVec 32)
  | var (index : Nat)
  | neg (operand : Expr)
  | binary (operation : BinOp) (left right : Expr)
  | compare (operation : CmpOp) (left right : Expr)
  deriving DecidableEq, Repr

inductive Stmt where
  | skip
  | assign (index : Nat) (value : Expr)
  | seq (first second : Stmt)
  | ite (condition : Expr) (thenBranch elseBranch : Stmt)
  /-- `while condition { body }` -/
  | loop (condition : Expr) (body : Stmt)
  /-- `target = callee(args)` -/
  | call (target : Nat) (callee : Nat) (args : List Expr)
  | ret (value : Expr)
  deriving Repr

structure Func where
  params : Nat
  /-- All locals, parameters included. -/
  locals : Nat
  body : Stmt
  deriving Repr

structure Program where
  funcs : List Func
  deriving Repr

end Lanius.Mini
