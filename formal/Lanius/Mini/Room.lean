import Lanius.Mini.Correct

/-! The per-function code check (F14): `compileFunc` asks `roomFits (stmtRoom imageLimit body)`
for room before it generates code.

`stmtRoom room s` takes `s.weight` out of `room` (`stmtRoom_eq`): one for each
node, and a call one more for each result it copies back. A body's code is at
least as many bytes as its weight (`weight_le_codeSize`), so a body that fails
the check compiles, without the check, to code over the image limit, which
`compileProgram` rejects as well. So the check changes no result:
`compileProgram` is `compileProgramUnchecked`, the compiler without it
(`compileProgram_unchecked`). -/

set_option linter.unusedSimpArgs false

namespace Lanius.Mini

/-- The nodes of an expression. -/
def Expr.weight : Expr → Nat
  | .lit _ => 1
  | .var _ => 1
  | .neg operand => 1 + operand.weight
  | .binary _ _ left right => 1 + left.weight + right.weight
  | .compare _ _ left right => 1 + left.weight + right.weight
  | .fp _ left right => 1 + left.weight + right.weight

/-- Each argument: its expression and the store of its value. -/
def argsWeight : List Expr → Nat
  | [] => 0
  | arg :: rest => 1 + arg.weight + argsWeight rest

/-- The nodes of a statement; a call weighs one more for each result. -/
def Stmt.weight : Stmt → Nat
  | .skip => 0
  | .assign _ value => 1 + value.weight
  | .seq first second => first.weight + second.weight
  | .ite condition thenBranch elseBranch => 1 + condition.weight + thenBranch.weight + elseBranch.weight
  | .loop condition body => 1 + condition.weight + body.weight
  | .call _ count _ args => 1 + count + argsWeight args
  | .ret values => 1 + argsWeight values
  | .brk => 1
  | .cont => 1
  | .alloc _ _ size => 1 + size.weight
  | .loadByte _ address => 1 + address.weight
  | .storeByte address value => 1 + address.weight + value.weight
  | .loadWord _ _ address => 1 + address.weight
  | .storeWord _ address value => 1 + address.weight + value.weight
  | .divide _ _ _ left right => 1 + left.weight + right.weight
  | .sys _ _ args => 1 + argsWeight args
  | .frame _ _ => 1
  | .static _ _ => 1

/-- The room left of `room` after `w` is taken out, `none` when it does not fit. -/
abbrev takeOut (room w : Nat) : Option Nat := if w ≤ room then some (room - w) else none

/-- Each `≤` the room checks is settled by `omega` from the cases on the totals taken out. -/
macro "room_fin" : tactic => `(tactic| ((try simp (disch := omega) only [if_pos, if_neg]) <;>
  (try simp only [*, if_true, if_false, Option.some.injEq, reduceCtorEq]) <;> omega))

theorem exprRoom_eq (e : Expr) : ∀ room, exprRoom room e = takeOut room e.weight := by
  induction e with
  | lit value => intro room; simp [exprRoom, spend, Expr.weight]
  | var index => intro room; simp [exprRoom, spend, Expr.weight]
  | neg operand ih =>
    intro room
    simp only [exprRoom, spend, ih, takeOut, Expr.weight, argsWeight, Stmt.weight]
    by_cases h1 : 1 ≤ room <;> by_cases h2 : 1 + operand.weight ≤ room <;> room_fin
  | binary word operation left right ihl ihr =>
    intro room
    simp only [exprRoom, spend, ihl, ihr, takeOut, Expr.weight, argsWeight, Stmt.weight]
    by_cases h1 : 1 ≤ room <;> by_cases h2 : 1 + left.weight ≤ room <;> by_cases h3 : 1 + left.weight + right.weight ≤ room <;> room_fin
  | compare word operation left right ihl ihr =>
    intro room
    simp only [exprRoom, spend, ihl, ihr, takeOut, Expr.weight, argsWeight, Stmt.weight]
    by_cases h1 : 1 ≤ room <;> by_cases h2 : 1 + left.weight ≤ room <;> by_cases h3 : 1 + left.weight + right.weight ≤ room <;> room_fin
  | fp operation left right ihl ihr =>
    intro room
    simp only [exprRoom, spend, ihl, ihr, takeOut, Expr.weight, argsWeight, Stmt.weight]
    by_cases h1 : 1 ≤ room <;> by_cases h2 : 1 + left.weight ≤ room <;> by_cases h3 : 1 + left.weight + right.weight ≤ room <;> room_fin

theorem argsRoom_eq (args : List Expr) : ∀ room, argsRoom room args = takeOut room (argsWeight args) := by
  induction args with
  | nil => intro room; simp [argsRoom, argsWeight, takeOut]
  | cons arg rest ih =>
    intro room
    simp only [argsRoom, spend, exprRoom_eq, ih, takeOut, Expr.weight, argsWeight, Stmt.weight]
    by_cases h1 : 1 ≤ room <;> by_cases h2 : 1 + arg.weight ≤ room <;> by_cases h3 : 1 + arg.weight + argsWeight rest ≤ room <;> room_fin

theorem stmtRoom_eq (s : Stmt) : ∀ room, stmtRoom room s = takeOut room s.weight := by
  induction s with
  | skip => intro room; simp [stmtRoom, Stmt.weight, takeOut]
  | assign index value =>
    intro room
    simp only [stmtRoom, spend, exprRoom_eq, takeOut, Expr.weight, argsWeight, Stmt.weight]
    by_cases h1 : 1 ≤ room <;> by_cases h2 : 1 + value.weight ≤ room <;> room_fin
  | seq first second ih1 ih2 =>
    intro room
    simp only [stmtRoom, spend, ih1, ih2, takeOut, Expr.weight, argsWeight, Stmt.weight]
    by_cases h1 : first.weight ≤ room <;> by_cases h2 : first.weight + second.weight ≤ room <;> room_fin
  | ite condition thenBranch elseBranch iht ihe =>
    intro room
    simp only [stmtRoom, spend, exprRoom_eq, iht, ihe, takeOut, Expr.weight, argsWeight, Stmt.weight]
    by_cases h1 : 1 ≤ room <;> by_cases h2 : 1 + condition.weight ≤ room <;> by_cases h3 : 1 + condition.weight + thenBranch.weight ≤ room <;> by_cases h4 : 1 + condition.weight + thenBranch.weight + elseBranch.weight ≤ room <;> room_fin
  | loop condition body ih =>
    intro room
    simp only [stmtRoom, spend, exprRoom_eq, ih, takeOut, Expr.weight, argsWeight, Stmt.weight]
    by_cases h1 : 1 ≤ room <;> by_cases h2 : 1 + condition.weight ≤ room <;> by_cases h3 : 1 + condition.weight + body.weight ≤ room <;> room_fin
  | call target count callee args =>
    intro room
    simp only [stmtRoom, spend, argsRoom_eq, takeOut, Expr.weight, argsWeight, Stmt.weight]
    by_cases h1 : 1 ≤ room <;> by_cases h2 : 1 + count ≤ room <;> by_cases h3 : 1 + count + argsWeight args ≤ room <;> room_fin
  | ret values =>
    intro room
    simp only [stmtRoom, spend, argsRoom_eq, takeOut, Expr.weight, argsWeight, Stmt.weight]
    by_cases h1 : 1 ≤ room <;> by_cases h2 : 1 + argsWeight values ≤ room <;> room_fin
  | brk =>
    intro room
    simp only [stmtRoom, spend, takeOut, Expr.weight, argsWeight, Stmt.weight]
    by_cases h1 : 1 ≤ room <;> room_fin
  | cont =>
    intro room
    simp only [stmtRoom, spend, takeOut, Expr.weight, argsWeight, Stmt.weight]
    by_cases h1 : 1 ≤ room <;> room_fin
  | alloc target shift size =>
    intro room
    simp only [stmtRoom, spend, exprRoom_eq, takeOut, Expr.weight, argsWeight, Stmt.weight]
    by_cases h1 : 1 ≤ room <;> by_cases h2 : 1 + size.weight ≤ room <;> room_fin
  | loadByte target address =>
    intro room
    simp only [stmtRoom, spend, exprRoom_eq, takeOut, Expr.weight, argsWeight, Stmt.weight]
    by_cases h1 : 1 ≤ room <;> by_cases h2 : 1 + address.weight ≤ room <;> room_fin
  | storeByte address value =>
    intro room
    simp only [stmtRoom, spend, exprRoom_eq, takeOut, Expr.weight, argsWeight, Stmt.weight]
    by_cases h1 : 1 ≤ room <;> by_cases h2 : 1 + address.weight ≤ room <;> by_cases h3 : 1 + address.weight + value.weight ≤ room <;> room_fin
  | loadWord width target address =>
    intro room
    simp only [stmtRoom, spend, exprRoom_eq, takeOut, Expr.weight, argsWeight, Stmt.weight]
    by_cases h1 : 1 ≤ room <;> by_cases h2 : 1 + address.weight ≤ room <;> room_fin
  | storeWord width address value =>
    intro room
    simp only [stmtRoom, spend, exprRoom_eq, takeOut, Expr.weight, argsWeight, Stmt.weight]
    by_cases h1 : 1 ≤ room <;> by_cases h2 : 1 + address.weight ≤ room <;> by_cases h3 : 1 + address.weight + value.weight ≤ room <;> room_fin
  | divide word operation target left right =>
    intro room
    simp only [stmtRoom, spend, exprRoom_eq, takeOut, Expr.weight, argsWeight, Stmt.weight]
    by_cases h1 : 1 ≤ room <;> by_cases h2 : 1 + left.weight ≤ room <;> by_cases h3 : 1 + left.weight + right.weight ≤ room <;> room_fin
  | sys kind target args =>
    intro room
    simp only [stmtRoom, spend, argsRoom_eq, takeOut, Expr.weight, argsWeight, Stmt.weight]
    by_cases h1 : 1 ≤ room <;> by_cases h2 : 1 + argsWeight args ≤ room <;> room_fin
  | frame target bytes =>
    intro room
    simp only [stmtRoom, spend, takeOut, Expr.weight, argsWeight, Stmt.weight]
    by_cases h1 : 1 ≤ room <;> room_fin
  | static target offset =>
    intro room
    simp only [stmtRoom, spend, takeOut, Expr.weight, argsWeight, Stmt.weight]
    by_cases h1 : 1 ≤ room <;> room_fin

theorem roomFits_stmtRoom (room : Nat) (s : Stmt) : roomFits (stmtRoom room s) = decide (s.weight ≤ room) := by
  rw [stmtRoom_eq]
  by_cases h : s.weight ≤ room <;> simp [h, takeOut, roomFits]

/-! A body's code is at least as many bytes as its weight. -/

theorem weight_le_codeSize_expr (base : Nat) (e : Expr) :
    ∀ depth, e.weight ≤ codeSize (compileExpr base e depth) := by
  induction e with
  | lit value => intro depth; simp [Expr.weight, compileExpr, codeSize, Instr.size]
  | var index => intro depth; simp [Expr.weight, compileExpr, codeSize, Instr.size]
  | neg operand ih =>
    intro depth; have := ih depth
    simp only [Expr.weight, compileExpr, codeSize_append, codeSize, Instr.size]; omega
  | binary word operation left right ihl ihr =>
    intro depth; have := ihl depth; have := ihr (depth + 1)
    simp only [Expr.weight, compileExpr, codeSize_append, codeSize, Instr.size]; omega
  | compare word operation left right ihl ihr =>
    intro depth; have := ihl depth; have := ihr (depth + 1)
    simp only [Expr.weight, compileExpr, codeSize_append, codeSize, Instr.size]; omega
  | fp operation left right ihl ihr =>
    intro depth; have := ihl depth; have := ihr (depth + 1)
    simp only [Expr.weight, compileExpr, codeSize_append, codeSize, Instr.size]; omega

theorem weight_le_codeSize_args (base : Nat) (args : List Expr) :
    ∀ k, argsWeight args ≤ codeSize (compileArgs base args k) := by
  induction args with
  | nil => intro k; simp [argsWeight]
  | cons arg rest ih =>
    intro k; have := ih (k + 1); have := weight_le_codeSize_expr base arg (k + 1)
    simp only [argsWeight, compileArgs, codeSize_append, codeSize, Instr.size]; omega

theorem weight_le_codeSize (base : Nat) (s : Stmt) :
    ∀ pos brk cont, s.weight ≤ codeSize (compileStmt base pos brk cont s) := by
  induction s with
  | skip => intro pos brk cont; simp [Stmt.weight]
  | assign index value =>
    intro pos brk cont; have := weight_le_codeSize_expr base value 0
    simp only [Stmt.weight, compileStmt, codeSize_append, codeSize, Instr.size]; omega
  | seq first second ih1 ih2 =>
    intro pos brk cont; have := ih1 pos brk cont
    have := ih2 (pos + codeSize (compileStmt base pos brk cont first)) brk cont
    simp only [Stmt.weight, compileStmt, codeSize_append]; omega
  | ite condition thenBranch elseBranch iht ihe =>
    intro pos brk cont; have := weight_le_codeSize_expr base condition 0
    have := iht (pos + codeSize (compileExpr base condition 0) + 9) brk cont
    have := ihe (pos + codeSize (compileExpr base condition 0) + 9 +
      codeSize (compileStmt base (pos + codeSize (compileExpr base condition 0) + 9) brk cont thenBranch) + 5) brk cont
    simp only [Stmt.weight, compileStmt, codeSize_append, codeSize, Instr.size]; omega
  | loop condition body ih =>
    intro pos brk cont; have := weight_le_codeSize_expr base condition 0
    have := ih (pos + codeSize (compileExpr base condition 0) + 9) (pos + codeSize (compileExpr base condition 0)) pos
    simp only [Stmt.weight, compileStmt, codeSize_append, codeSize, Instr.size]; omega
  | call target count callee args =>
    intro pos brk cont; have := weight_le_codeSize_args base args 0
    simp only [Stmt.weight, compileStmt, codeSize_append, codeSize, Instr.size]; omega
  | ret values =>
    intro pos brk cont; have := weight_le_codeSize_args base values 0
    simp only [Stmt.weight, compileStmt, codeSize_append, codeSize, Instr.size]; omega
  | brk => intro pos brk cont; simp [Stmt.weight, compileStmt, codeSize, Instr.size]
  | cont => intro pos brk cont; simp [Stmt.weight, compileStmt, codeSize, Instr.size]
  | alloc target shift size =>
    intro pos brk cont; have := weight_le_codeSize_expr base size 0
    simp only [Stmt.weight, compileStmt, codeSize_append, codeSize, Instr.size]; omega
  | loadByte target address =>
    intro pos brk cont; have := weight_le_codeSize_expr base address 0
    simp only [Stmt.weight, compileStmt, codeSize_append, codeSize, Instr.size]; omega
  | storeByte address value =>
    intro pos brk cont; have := weight_le_codeSize_expr base address 0
    have := weight_le_codeSize_expr base value 1
    simp only [Stmt.weight, compileStmt, codeSize_append, codeSize, Instr.size]; omega
  | loadWord width target address =>
    intro pos brk cont; have := weight_le_codeSize_expr base address 0
    simp only [Stmt.weight, compileStmt, codeSize_append, codeSize, Instr.size]; omega
  | storeWord width address value =>
    intro pos brk cont; have := weight_le_codeSize_expr base address 0
    have := weight_le_codeSize_expr base value 1
    simp only [Stmt.weight, compileStmt, codeSize_append, codeSize, Instr.size]; omega
  | divide word operation target left right =>
    intro pos brk cont; have := weight_le_codeSize_expr base left 0
    have := weight_le_codeSize_expr base right 1
    simp only [Stmt.weight, compileStmt, codeSize_append, codeSize, Instr.size]; omega
  | sys kind target args =>
    intro pos brk cont; have := weight_le_codeSize_args base args 0
    simp only [Stmt.weight, compileStmt, codeSize_append, codeSize, Instr.size]; omega
  | frame target bytes => intro pos brk cont; simp [Stmt.weight, compileStmt, codeSize, Instr.size]
  | static target offset => intro pos brk cont; simp [Stmt.weight, compileStmt, codeSize, Instr.size]

/-! A body's code is at most 64 bytes per unit of weight (`codeSize_le`), so once the
check passes a body's code is at most 64 * 2^30 = 2^36 bytes. -/

theorem BinOp.size_le (o : BinOp) : BinOp.size o ≤ 13 := by cases o <;> decide
theorem Word.prefix_le (w : Word) : Word.prefix w ≤ 1 := by cases w <;> decide
theorem MemWidth.prefix_le (w : MemWidth) : MemWidth.prefix w ≤ 1 := by cases w <;> decide
theorem DivOp.size_le (o : DivOp) (w : Word) : DivOp.size o w ≤ 5 := by
  cases o <;> cases w <;> decide
theorem FOp.size_le (o : FOp) : FOp.size o ≤ 21 := by
  cases o with
  | basic ty operation => cases ty <;> simp [FOp.size, FloatTy.rexSize]
  | fCompare ty operation => cases ty <;> simp [FOp.size, FloatTy.rexSize]
  | fromInt ty word => cases ty <;> cases word <;> simp [FOp.size, FloatTy.rexSize, Word.prefix]
  | widen => simp [FOp.size]
  | narrow => simp [FOp.size]

theorem Expr.weight_pos (e : Expr) : 1 ≤ e.weight := by
  cases e <;> simp only [Expr.weight] <;> omega

theorem codeSize_le_expr (base : Nat) (e : Expr) :
    ∀ depth, codeSize (compileExpr base e depth) ≤ 40 * e.weight := by
  induction e with
  | lit value => intro depth; simp [Expr.weight, compileExpr, codeSize, Instr.size]
  | var index => intro depth; simp [Expr.weight, compileExpr, codeSize, Instr.size]
  | neg operand ih =>
    intro depth; have := ih depth
    simp only [Expr.weight, argsWeight, Stmt.weight, compileExpr, compileArgs, compileStmt, codeSize_append, codeSize, Instr.size, List.length_cons]; omega
  | binary word operation left right ihl ihr =>
    intro depth; have := ihl depth; have := ihr (depth + 1)
    have := BinOp.size_le operation; have := Word.prefix_le word
    simp only [Expr.weight, argsWeight, Stmt.weight, compileExpr, compileArgs, compileStmt, codeSize_append, codeSize, Instr.size, List.length_cons]; omega
  | compare word operation left right ihl ihr =>
    intro depth; have := ihl depth; have := ihr (depth + 1); have := Word.prefix_le word
    simp only [Expr.weight, argsWeight, Stmt.weight, compileExpr, compileArgs, compileStmt, codeSize_append, codeSize, Instr.size, List.length_cons]; omega
  | fp operation left right ihl ihr =>
    intro depth; have := ihl depth; have := ihr (depth + 1); have := FOp.size_le operation
    have := Expr.weight_pos left
    simp only [Expr.weight, argsWeight, Stmt.weight, compileExpr, compileArgs, compileStmt, codeSize_append, codeSize, Instr.size, List.length_cons]; omega

theorem codeSize_le_args (base : Nat) (args : List Expr) :
    ∀ k, codeSize (compileArgs base args k) + 14 * args.length ≤ 64 * argsWeight args := by
  induction args with
  | nil => intro k; simp [argsWeight, compileArgs, codeSize]
  | cons arg rest ih =>
    intro k; have := ih (k + 1); have := codeSize_le_expr base arg (k + 1)
    simp only [Expr.weight, argsWeight, Stmt.weight, compileExpr, compileArgs, compileStmt, codeSize_append, codeSize, Instr.size, List.length_cons]; omega

theorem codeSize_le (base : Nat) (s : Stmt) :
    ∀ pos brk cont, codeSize (compileStmt base pos brk cont s) ≤ 64 * s.weight := by
  induction s with
  | skip => intro pos brk cont; simp [Stmt.weight, compileStmt, codeSize]
  | assign index value =>
    intro pos brk cont; have := codeSize_le_expr base value 0
    simp only [Expr.weight, argsWeight, Stmt.weight, compileExpr, compileArgs, compileStmt, codeSize_append, codeSize, Instr.size, List.length_cons]; omega
  | seq first second ih1 ih2 =>
    intro pos brk cont; have := ih1 pos brk cont
    have := ih2 (pos + codeSize (compileStmt base pos brk cont first)) brk cont
    simp only [Stmt.weight, compileStmt, codeSize_append]; omega
  | ite condition thenBranch elseBranch iht ihe =>
    intro pos brk cont; have := codeSize_le_expr base condition 0
    have := iht (pos + codeSize (compileExpr base condition 0) + 9) brk cont
    have := ihe (pos + codeSize (compileExpr base condition 0) + 9 +
      codeSize (compileStmt base (pos + codeSize (compileExpr base condition 0) + 9) brk cont thenBranch) + 5) brk cont
    simp only [Expr.weight, argsWeight, Stmt.weight, compileExpr, compileArgs, compileStmt, codeSize_append, codeSize, Instr.size, List.length_cons]; omega
  | loop condition body ih =>
    intro pos brk cont; have := codeSize_le_expr base condition 0
    have := ih (pos + codeSize (compileExpr base condition 0) + 9) (pos + codeSize (compileExpr base condition 0)) pos
    simp only [Expr.weight, argsWeight, Stmt.weight, compileExpr, compileArgs, compileStmt, codeSize_append, codeSize, Instr.size, List.length_cons]; omega
  | call target count callee args =>
    intro pos brk cont; have := codeSize_le_args base args 0
    have : (argSlots base args 0).length = args.length := argSlots_length base args 0
    simp only [Expr.weight, argsWeight, Stmt.weight, compileExpr, compileArgs, compileStmt, codeSize_append, codeSize, Instr.size, List.length_cons]; omega
  | ret values =>
    intro pos brk cont; have := codeSize_le_args base values 0
    have : (argSlots base values 0).length = values.length := argSlots_length base values 0
    simp only [Expr.weight, argsWeight, Stmt.weight, compileExpr, compileArgs, compileStmt, codeSize_append, codeSize, Instr.size, List.length_cons]; omega
  | brk => intro pos brk cont; simp [Stmt.weight, compileStmt, codeSize, Instr.size]
  | cont => intro pos brk cont; simp [Stmt.weight, compileStmt, codeSize, Instr.size]
  | alloc target shift size =>
    intro pos brk cont; have := codeSize_le_expr base size 0; have := Expr.weight_pos size
    simp only [Expr.weight, argsWeight, Stmt.weight, compileExpr, compileArgs, compileStmt, codeSize_append, codeSize, Instr.size, List.length_cons]; omega
  | loadByte target address =>
    intro pos brk cont; have := codeSize_le_expr base address 0; have := Expr.weight_pos address
    simp only [Expr.weight, argsWeight, Stmt.weight, compileExpr, compileArgs, compileStmt, codeSize_append, codeSize, Instr.size, List.length_cons]; omega
  | storeByte address value =>
    intro pos brk cont; have := codeSize_le_expr base address 0; have := codeSize_le_expr base value 1
    have := Expr.weight_pos address
    simp only [Expr.weight, argsWeight, Stmt.weight, compileExpr, compileArgs, compileStmt, codeSize_append, codeSize, Instr.size, List.length_cons]; omega
  | loadWord width target address =>
    intro pos brk cont; have := codeSize_le_expr base address 0; have := Expr.weight_pos address
    have := MemWidth.prefix_le width
    simp only [Expr.weight, argsWeight, Stmt.weight, compileExpr, compileArgs, compileStmt, codeSize_append, codeSize, Instr.size, List.length_cons]; omega
  | storeWord width address value =>
    intro pos brk cont; have := codeSize_le_expr base address 0; have := codeSize_le_expr base value 1
    have := Expr.weight_pos address; have := MemWidth.prefix_le width
    simp only [Expr.weight, argsWeight, Stmt.weight, compileExpr, compileArgs, compileStmt, codeSize_append, codeSize, Instr.size, List.length_cons]; omega
  | divide word operation target left right =>
    intro pos brk cont; have := codeSize_le_expr base left 0; have := codeSize_le_expr base right 1
    have := Expr.weight_pos left; have := Word.prefix_le word; have := DivOp.size_le operation word
    simp only [Expr.weight, argsWeight, Stmt.weight, compileExpr, compileArgs, compileStmt, codeSize_append, codeSize, Instr.size, List.length_cons]; omega
  | sys kind target args =>
    intro pos brk cont; have := codeSize_le_args base args 0
    simp only [Expr.weight, argsWeight, Stmt.weight, compileExpr, compileArgs, compileStmt, codeSize_append, codeSize, Instr.size, List.length_cons]; omega
  | frame target bytes => intro pos brk cont; simp [Stmt.weight, compileStmt, codeSize, Instr.size]
  | static target offset => intro pos brk cont; simp [Stmt.weight, compileStmt, codeSize, Instr.size]

/-! The compiler without the check. -/

/-- `compileFunc` without the per-function code check. -/
def compileFuncUnchecked (arities : List Arity) (func : Func) : Option Code :=
  let slots : Nat := func.locals + Stmt.temps func.body
  if decide (func.params ≤ func.locals) && decide (0 < func.results) && decide (func.results ≤ func.locals) &&
      Stmt.within func.body func.locals arities func.results && decide (slots ≤ frameLimit) then
    let init : List Instr := Instr.imm 0 :: zeroLocals func.params (func.locals - func.params)
    some ({ slots := slots, instrs := init ++ compileStmt func.locals (codeSize init) 0 0 func.body } : Code)
  else
    none

def compileFuncsUnchecked (arities : List Arity) : List Func → Option (List Code)
  | [] => some []
  | func :: rest =>
    match compileFuncUnchecked arities func with
    | none => none
    | some code =>
      match compileFuncsUnchecked arities rest with
      | none => none
      | some codes => some (code :: codes)

/-- `compileProgram` without the per-function code check, in `compileProgram_eq`'s form. -/
def compileProgramUnchecked (prog : Program) : Option Binary :=
  match compileFuncsUnchecked (arities prog.funcs) prog.funcs with
  | none => none
  | some codes =>
    if linkedSize codes + prog.statics.length ≤ imageLimit then
      some ({ codes := codes, entries := layout 0 codes,
              image := linkOnto (layout 0 codes) 0 codes prog.statics, statics := prog.statics } : Binary)
    else
      none

/-- The check either passes, or the function's unchecked code is over the image limit. -/
theorem compileFunc_unchecked (arities : List Arity) (func : Func) :
    compileFunc arities func = compileFuncUnchecked arities func ∨
      (compileFunc arities func = none ∧
        ∀ code, compileFuncUnchecked arities func = some code → imageLimit < code.size) := by
  by_cases h : func.body.weight ≤ imageLimit
  · left
    simp only [compileFunc, compileFuncUnchecked, roomFits_stmtRoom, h, decide_true, Bool.and_true]
  · right
    refine ⟨?_, ?_⟩
    · simp only [compileFunc, roomFits_stmtRoom, h, decide_false, Bool.and_false, Bool.false_eq_true, if_false]
    · intro code hc
      simp only [compileFuncUnchecked] at hc
      split at hc
      · simp only [Option.some.injEq] at hc
        subst hc
        have := weight_le_codeSize func.locals func.body
          (codeSize (Instr.imm 0 :: zeroLocals func.params (func.locals - func.params))) 0 0
        simp only [Code.size, codeSize_append]
        omega
      · contradiction

theorem linkedSize_cons (code : Code) (rest : List Code) :
    linkedSize (code :: rest) = code.size + linkedSize rest := rfl

theorem compileFuncs_unchecked (arities : List Arity) :
    ∀ funcs : List Func, compileFuncs arities funcs = compileFuncsUnchecked arities funcs ∨
      (compileFuncs arities funcs = none ∧
        ∀ codes, compileFuncsUnchecked arities funcs = some codes → imageLimit < linkedSize codes)
  | [] => Or.inl rfl
  | func :: rest => by
    have ih := compileFuncs_unchecked arities rest
    rcases compileFunc_unchecked arities func with hf | ⟨hf, big⟩
    · rcases ih with hr | ⟨hr, bigr⟩
      · left; simp only [compileFuncs, compileFuncsUnchecked, hf, hr]
        cases compileFuncUnchecked arities func <;> cases compileFuncsUnchecked arities rest <;> rfl
      · right
        refine ⟨?_, ?_⟩
        · simp only [compileFuncs, hr]
          cases compileFunc arities func <;> rfl
        · intro codes hc
          simp only [compileFuncsUnchecked] at hc
          cases hu : compileFuncUnchecked arities func with
          | none => rw [hu] at hc; contradiction
          | some code =>
            rw [hu] at hc
            cases hus : compileFuncsUnchecked arities rest with
            | none => rw [hus] at hc; contradiction
            | some codes' =>
              rw [hus] at hc
              simp only [Option.some.injEq] at hc
              subst hc
              have := bigr codes' hus
              rw [linkedSize_cons]; omega
    · right
      refine ⟨by simp only [compileFuncs, hf], ?_⟩
      intro codes hc
      simp only [compileFuncsUnchecked] at hc
      cases hu : compileFuncUnchecked arities func with
      | none => rw [hu] at hc; contradiction
      | some code =>
        rw [hu] at hc
        cases hus : compileFuncsUnchecked arities rest with
        | none => rw [hus] at hc; contradiction
        | some codes' =>
          rw [hus] at hc
          simp only [Option.some.injEq] at hc
          subst hc
          have := big code hu
          rw [linkedSize_cons]; omega

/-- The per-function code check changes no result of the compiler. -/
theorem compileProgram_unchecked (prog : Program) : compileProgram prog = compileProgramUnchecked prog := by
  rw [compileProgram_eq]
  simp only [compileProgramUnchecked]
  rcases compileFuncs_unchecked (arities prog.funcs) prog.funcs with h | ⟨h, big⟩
  · rw [h]
    cases compileFuncsUnchecked (arities prog.funcs) prog.funcs <;> rfl
  · rw [h]
    cases hu : compileFuncsUnchecked (arities prog.funcs) prog.funcs with
    | none => rfl
    | some codes =>
      have := big codes hu
      have c : ¬ linkedSize codes + prog.statics.length ≤ imageLimit := by omega
      simp only [c, if_false]

end Lanius.Mini
