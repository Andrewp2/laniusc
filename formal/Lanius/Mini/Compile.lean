import Lanius.Mini.Asm

/-! The compiler. Expressions leave their value in the accumulator. A binary
operator's left operand waits in temporary slot `base + depth`, above the
`base` local slots, while the right operand is computed one level deeper. -/

namespace Lanius.Mini

def compileExpr (base : Nat) : Expr → Nat → List Instr
  | .lit value, _ => [.imm value]
  | .var index, _ => [.load index]
  | .neg operand, depth => compileExpr base operand depth ++ [.neg]
  | .binary operation left right, depth =>
      compileExpr base left depth ++ [.store (base + depth)] ++
        compileExpr base right (depth + 1) ++ [.op operation (base + depth)]

def compileStmt (base : Nat) : Stmt → List Instr
  | .assign index value => compileExpr base value 0 ++ [.store index]
  | .ret value => compileExpr base value 0 ++ [.ret]

def compileBody (base : Nat) : List Stmt → List Instr
  | [] => []
  | stmt :: rest => compileStmt base stmt ++ compileBody base rest

/-- Every local an expression reads is below `locals`. -/
def Expr.within (locals : Nat) : Expr → Bool
  | .lit _ => true
  | .var index => index < locals
  | .neg operand => operand.within locals
  | .binary _ left right => left.within locals && right.within locals

/-- Temporary slots an expression's code uses. -/
def Expr.temps : Expr → Nat
  | .lit _ | .var _ => 0
  | .neg operand => operand.temps
  | .binary _ left right => max left.temps (right.temps + 1)

def Stmt.within (locals : Nat) : Stmt → Bool
  | .assign index value => index < locals && value.within locals
  | .ret value => value.within locals

def Stmt.temps : Stmt → Nat
  | .assign _ value | .ret value => value.temps

/-- Slots an instruction addresses are below the frame's slot count. -/
def Instr.fits (slots : Nat) : Instr → Prop
  | .load slot | .store slot | .op _ slot => slot < slots
  | .imm _ | .neg | .ret => True

def bodyTemps : List Stmt → Nat
  | [] => 0
  | stmt :: rest => max stmt.temps (bodyTemps rest)

/-- Frames are bounded so every slot displacement fits a signed 32-bit field. -/
def frameLimit : Nat := 2 ^ 24

structure Code where
  /-- Frame slots: the locals, then the deepest expression's temporaries. -/
  slots : Nat
  instrs : List Instr
  deriving DecidableEq, Repr

def compileFunc (func : Func) : Option Code :=
  let slots := func.locals + bodyTemps func.body
  if func.body.all (·.within func.locals) && decide (slots ≤ frameLimit) then
    some { slots, instrs := compileBody func.locals func.body }
  else none

end Lanius.Mini
