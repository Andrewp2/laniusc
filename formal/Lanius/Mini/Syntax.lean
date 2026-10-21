/-! Source language of the mini compiler, milestone 1: straight-line i32 code.

Locals are resolved to frame indices. The Lanius twin of this file uses
`enum Expr { ..., Binary(BinOp, Box<Expr>, Box<Expr>) }`; `Box<T>` is `T` here. -/

namespace Lanius.Mini

inductive BinOp where
  | add | sub | mul | and | or | xor
  deriving DecidableEq, Repr

inductive Expr where
  | lit (value : BitVec 32)
  | var (index : Nat)
  | neg (operand : Expr)
  | binary (operation : BinOp) (left right : Expr)
  deriving DecidableEq, Repr

inductive Stmt where
  | assign (index : Nat) (value : Expr)
  | ret (value : Expr)
  deriving DecidableEq, Repr

structure Func where
  locals : Nat
  body : List Stmt
  deriving DecidableEq, Repr

end Lanius.Mini
