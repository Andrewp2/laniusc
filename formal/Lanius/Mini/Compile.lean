import Lanius.Mini.Asm

/-! The compiler, to the abstract machine. Expressions leave their value in the
accumulator. A binary operator's left operand waits in temporary slot
`base + depth`, above the `base` local slots, while the right operand is
computed one level deeper. Call arguments are evaluated into consecutive
temporaries, which the call copies into the callee's parameter slots.
Statement code is placed at a known offset `pos`, so jumps are absolute
offsets within the function. -/

namespace Lanius.Mini

def compileExpr (base : Nat) : Expr → Nat → List Instr
  | .lit value, _ => [.imm value]
  | .var index, _ => [.load index]
  | .neg operand, depth => compileExpr base operand depth ++ [.neg]
  | .binary operation left right, depth =>
      compileExpr base left depth ++ [.store (base + depth)] ++
        compileExpr base right (depth + 1) ++ [.op operation (base + depth)]
  | .compare operation left right, depth =>
      compileExpr base left depth ++ [.store (base + depth)] ++
        compileExpr base right (depth + 1) ++ [.cmp operation (base + depth)]

/-- Argument `k` is evaluated into temporary `base + k`. -/
def compileArgs (base : Nat) : List Expr → Nat → List Instr
  | [], _ => []
  | arg :: rest, k => compileExpr base arg (k + 1) ++ [.store (base + k)] ++ compileArgs base rest (k + 1)

def argSlots (base : Nat) : List Expr → Nat → List Nat
  | [], _ => []
  | _ :: rest, k => (base + k) :: argSlots base rest (k + 1)

def compileStmt (base : Nat) (pos : Nat) : Stmt → List Instr
  | .skip => []
  | .assign index value => compileExpr base value 0 ++ [.store index]
  | .seq first second =>
      let firstCode := compileStmt base pos first
      firstCode ++ compileStmt base (pos + codeSize firstCode) second
  | .ite condition thenBranch elseBranch =>
      let conditionCode := compileExpr base condition 0
      let thenStart := pos + codeSize conditionCode + 8
      let thenCode := compileStmt base thenStart thenBranch
      let elseStart := thenStart + codeSize thenCode + 5
      let elseCode := compileStmt base elseStart elseBranch
      conditionCode ++ [.jz elseStart] ++ thenCode ++ [.jmp (elseStart + codeSize elseCode)] ++ elseCode
  | .loop condition body =>
      let conditionCode := compileExpr base condition 0
      let bodyStart := pos + codeSize conditionCode + 8
      let bodyCode := compileStmt base bodyStart body
      conditionCode ++ [.jz (bodyStart + codeSize bodyCode + 5)] ++ bodyCode ++ [.jmp pos]
  | .call target callee args =>
      compileArgs base args 0 ++ [.call callee (argSlots base args 0), .store target]
  | .ret value => compileExpr base value 0 ++ [.ret]

/-- Every local an expression reads is below `locals`. -/
def Expr.within (locals : Nat) : Expr → Bool
  | .lit _ => true
  | .var index => index < locals
  | .neg operand => operand.within locals
  | .binary _ left right => left.within locals && right.within locals
  | .compare _ left right => left.within locals && right.within locals

def Expr.allWithin (locals : Nat) : List Expr → Bool
  | [] => true
  | arg :: rest => arg.within locals && Expr.allWithin locals rest

/-- Locals are in range, and each call names a function and passes it as many
arguments as it has parameters. -/
def Stmt.within (locals : Nat) (arities : List Nat) : Stmt → Bool
  | .skip => true
  | .assign index value => index < locals && value.within locals
  | .seq first second => first.within locals arities && second.within locals arities
  | .ite condition thenBranch elseBranch =>
      condition.within locals && thenBranch.within locals arities && elseBranch.within locals arities
  | .loop condition body => condition.within locals && body.within locals arities
  | .call target callee args =>
      target < locals && arities[callee]? == some args.length && Expr.allWithin locals args
  | .ret value => value.within locals

/-- Temporary slots an expression's code uses. -/
def Expr.temps : Expr → Nat
  | .lit _ | .var _ => 0
  | .neg operand => operand.temps
  | .binary _ left right => max left.temps (right.temps + 1)
  | .compare _ left right => max left.temps (right.temps + 1)

/-- Temporaries used by arguments from position `k` on. -/
def argsTemps : List Expr → Nat → Nat
  | [], _ => 0
  | arg :: rest, k => max (k + 1 + arg.temps) (argsTemps rest (k + 1))

def Stmt.temps : Stmt → Nat
  | .skip => 0
  | .assign _ value => value.temps
  | .seq first second => max first.temps second.temps
  | .ite condition thenBranch elseBranch => max condition.temps (max thenBranch.temps elseBranch.temps)
  | .loop condition body => max condition.temps body.temps
  | .call _ _ args => argsTemps args 0
  | .ret value => value.temps

/-- Zero the non-parameter locals `first, ..., first + count - 1`. -/
def zeroLocals (first : Nat) : Nat → List Instr
  | 0 => []
  | count + 1 => .store first :: zeroLocals (first + 1) count

/-- Frames are bounded so every slot displacement fits a signed 32-bit field. -/
def frameLimit : Nat := 2 ^ 20

structure Code where
  /-- Frame slots: the locals, then the deepest statement's temporaries. -/
  slots : Nat
  instrs : List Instr
  deriving DecidableEq, Repr

def compileFunc (arities : List Nat) (func : Func) : Option Code :=
  let slots := func.locals + func.body.temps
  if decide (func.params ≤ func.locals) && func.body.within func.locals arities &&
      decide (slots ≤ frameLimit) then
    let init := Instr.imm 0 :: zeroLocals func.params (func.locals - func.params)
    some { slots, instrs := init ++ compileStmt func.locals (codeSize init) func.body }
  else none

def arities : List Func → List Nat
  | [] => []
  | func :: rest => func.params :: arities rest

def compileFuncs (arities : List Nat) : List Func → Option (List Code)
  | [] => some []
  | func :: rest =>
    match compileFunc arities func, compileFuncs arities rest with
    | some code, some codes => some (code :: codes)
    | _, _ => none

end Lanius.Mini
