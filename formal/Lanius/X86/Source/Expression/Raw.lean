import Lanius.X86.Source.Expression.Literal
import Lanius.X86.Source.Guarded
import Lanius.X86.Source.Address

namespace Lanius.X86.Source.Expression.Raw

open Lanius.Core Lanius.Semantics Lanius.Extraction

/-- Only the two locals introduced by the selected raw-slice branch. Their
identities are recovered from source, not guessed from another branch. -/
structure Locals where
  slot : VarId
  next : VarId

structure Constants (program : Program) where
  tag : IntegerConstant program
  test : IntegerConstant program
  greaterEqual : IntegerConstant program
  values : tag.value = 15 ∧ test.value = 133 ∧ greaterEqual.value = 13

structure Calls where
  expression : FunctionId
  allocate : FunctionId
  save : FunctionId
  binary : FunctionId
  branch : FunctionId
  trap : FunctionId
  move : FunctionId
  address : FunctionId

def recurseArguments : List Expr := [read 0, read 1, read 2, read 3, read 4,
  read 5, .binary .add (read 6) (number 1), read 7, read 8]
def pointerGuard (literal : Literal.Checked emitters) (calls : Calls) : Expr :=
  .binary .notEqual (.call calls.expression recurseArguments) (.constant literal.constants.pointer.id)
def lengthGuard (literal : Literal.Checked emitters) (calls : Calls) : Expr :=
  .binary .notEqual (.call calls.expression recurseArguments) (.constant literal.layout.signed.id)
def rejected (locals : Locals) : Expr := .binary .less (read locals.slot) (number 0)
def saveArguments (literal : Literal.Checked emitters) (locals : Locals) : List Expr :=
  [read 3, read 4, read 2, read locals.slot, .constant literal.constants.rax.id]

def allocation (literal : Literal.Checked emitters) (calls : Calls) (locals : Locals) (rest : Stmt) : Stmt :=
  .letLocal locals.slot i32 (.call calls.allocate [read 2, number 2])
    (.sequence (.ifThenElse (rejected locals) (returned negativeOne) .skip)
      (.sequence (.expression (.call calls.save (saveArguments literal locals))) rest))

/-- The captured pointer is saved before evaluation of the length operand.
The continuation is inside the actual allocated-slot lexical scope. -/
def preparation (literal : Literal.Checked emitters) (calls : Calls) (locals : Locals) (rest : Stmt) : Stmt :=
  .sequence (.ifThenElse (pointerGuard literal calls) (returned negativeOne) .skip)
    (allocation literal calls locals rest)

def testArguments (literal : Literal.Checked emitters) (constants : Constants emitters.pack.program.core) : List Expr :=
  [read 3, read 4, Literal.field literal.constants.code.id, number 32,
    .constant constants.test.id, .constant literal.constants.rax.id, .constant literal.constants.rax.id]
def branchArguments (constants : Constants program) (locals : Locals) : List Expr :=
  [read 3, read 4, read locals.next, .constant constants.greaterEqual.id,
    .binary .add (read locals.next) (number 8)]
def moveArguments (literal : Literal.Checked emitters) (locals : Locals) : List Expr :=
  [read 3, read 4, read locals.next, number 32, .constant literal.constants.rax.id, .constant literal.constants.rax.id]
def setNext (locals : Locals) (value : Expr) : Stmt := .expression (.assign .set (.local locals.next) value)

/-- The real TEST/JGE/UD2/MOV32 source statements, with their continuation
inside the `next` scope. The JGE target skips exactly the two-byte trap. -/
def guardBody (literal : Literal.Checked emitters) (constants : Constants emitters.pack.program.core)
    (calls : Calls) (locals : Locals) (rest : Stmt) : Stmt :=
  .letLocal locals.next i32 (.call calls.binary (testArguments literal constants))
    (.sequence (setNext locals (.call calls.branch (branchArguments constants locals)))
      (.sequence (setNext locals (.call calls.trap [read 3, read 4, read locals.next]))
        (.sequence (Literal.assign literal.constants.code.id (.call calls.move (moveArguments literal locals))) rest)))

def finish (literal : Literal.Checked emitters) (calls : Calls) (locals : Locals) : Stmt :=
  .sequence (.expression (.call calls.save [read 3, read 4, read 2,
      .binary .subtract (read locals.slot) (number 1), .constant literal.constants.rax.id]))
    (.sequence (.expression (.call calls.address [read 3, read 4, read 2,
      read locals.slot, .constant literal.constants.rax.id])) (returned (.constant literal.layout.slice.id)))
def tail (literal : Literal.Checked emitters) (constants : Constants emitters.pack.program.core)
    (calls : Calls) (locals : Locals) : Stmt :=
  .sequence (.ifThenElse (lengthGuard literal calls) (returned negativeOne) .skip)
    (guardBody literal constants calls locals (finish literal calls locals))
def branch (literal : Literal.Checked emitters) (constants : Constants emitters.pack.program.core)
    (calls : Calls) (locals : Locals) : Stmt :=
  preparation literal calls locals (tail literal constants calls locals)
def selected (constants : Constants program) : Expr := .binary .equal (read 9) (.constant constants.tag.id)

/-- Earlier dispatch conditions are pure tag comparisons, including the
slice/string data-pointer disjunction. Their bodies remain untouched source
AST; this certificate proves that tag15 cannot execute any of them. -/
inductive SkippedGuard (program : Program) where
  | equal (constant : IntegerConstant program) (other : constant.value ≠ 15)
  | either (left right : SkippedGuard program)

def SkippedGuard.expression : SkippedGuard program → Expr
  | .equal constant _ => .binary .equal (read 9) (.constant constant.id)
  | .either left right => .binary .logicalOr left.expression right.expression

def skippedGuard? (program : Program) : Expr → Option (SkippedGuard program)
  | .binary .equal (.local 9) (.constant id) => do
      let constant ← integerConstant? program id
      if other : constant.value ≠ 15 then pure (.equal constant other) else none
  | .binary .logicalOr left right => do pure (.either (← skippedGuard? program left) (← skippedGuard? program right))
  | _ => none

abbrev Prefix (program : Program) := List (SkippedGuard program × Stmt)
def prefixBody : Prefix program → Stmt → Stmt
  | [], rest => rest
  | (guard, body) :: earlier, rest => .sequence (.ifThenElse guard.expression body .skip) (prefixBody earlier rest)

def dispatch (literal : Literal.Checked emitters) (constants : Constants emitters.pack.program.core)
    (calls : Calls) (locals : Locals) (earlier : Prefix emitters.pack.program.core) (rest : Stmt) : Stmt :=
  prefixBody earlier (.sequence (.ifThenElse (selected constants) (branch literal constants calls locals) .skip) rest)

private def split? (program : Program) : Stmt → Option (Prefix program × ConstantId × Stmt × Stmt)
  | .sequence (.ifThenElse guard sourceBody .skip) rest => do
      if let .binary .equal (.local 9) (.constant id) := guard then
        let constant ← integerConstant? program id
        if constant.value == 15 then return ([], id, sourceBody, rest)
      let skipped ← skippedGuard? program guard
      let (earlier, tag, body, rest) ← split? program rest
      pure ((skipped, sourceBody) :: earlier, tag, body, rest)
  | _ => none

structure Helpers (literal : Literal.Checked emitters) where
  allocate : Source.Allocate.Checked emitters.pack.program
  memory : Memory.Checked emitters.pack.program emitters.registerValid emitters.widthValid emitters.rex emitters.fits emitters.word
  store : Memory.CheckedMove emitters.pack.program memory false
  offset : Frame.CheckedDisplacement emitters.pack.program
  save : Slot.Checked emitters.pack.program .save64 store offset
  binary : CheckedGuardedRegister emitters.pack.program emitters.registerForm .binary
  lea : Address.Checked emitters.pack.program memory
  address : Address.CheckedFrame emitters.pack.program lea offset

def Helpers.calls {literal : Literal.Checked emitters} (helpers : Helpers literal) : Calls := {
  expression := literal.wrapper.source.function.id
  allocate := helpers.allocate.internal.source.function.id
  save := helpers.save.internal.source.function.id
  binary := helpers.binary.internal.source.function.id
  branch := emitters.branch.source.function.id
  trap := emitters.trap.source.function.id
  move := (emitters.registerWrappers .move).source.function.id
  address := helpers.address.internal.source.function.id }

/-- Exact source identity of the whole raw branch and its dispatch route.
This authenticates callees and syntax; their execution is proved separately.
No correctness obligation for a recursive operand is hidden in this record. -/
structure Checked (literal : Literal.Checked emitters) where
  helpers : Helpers literal
  constants : Constants emitters.pack.program.core
  locals : Locals
  fresh : 10 ≤ locals.slot ∧ locals.slot < locals.next
  earlier : Prefix emitters.pack.program.core
  otherBranches : Stmt
  bodyExact : literal.otherBranches = dispatch literal constants helpers.calls locals earlier otherBranches

def check? (literal : Literal.Checked emitters) : Option (Checked literal) := do
  let program := emitters.pack.program
  let (earlier, tagId, actual, rest) ← split? program.core literal.otherBranches
  let .sequence _ (.letLocal slot _ _ (.sequence _ (.sequence _ (.sequence _ guarded)))) := actual | none
  let .letLocal next _ (.call _ [_, _, _, _, .constant testId, _, _])
    (.sequence (.expression (.assign .set _ (.call _ [_, _, _, .constant greaterEqualId, _]))) _) := guarded | none
  let tag ← integerConstant? program.core tagId
  let test ← integerConstant? program.core testId
  let greaterEqual ← integerConstant? program.core greaterEqualId
  if values : tag.value = 15 ∧ test.value = 133 ∧ greaterEqual.value = 13 then
    if fresh : 10 ≤ slot ∧ slot < next then
      let constants : Constants program.core := ⟨tag, test, greaterEqual, values⟩
      let locals : Locals := ⟨slot, next⟩
      let allocate ← Source.Allocate.check? program
      let memory ← Memory.check? program emitters.registerValid emitters.widthValid emitters.rex emitters.fits emitters.word
      let store ← Memory.checkMove? program memory false
      let offset ← Frame.checkDisplacement? program
      let save ← Slot.check? program .save64 store offset
      let binary ← checkGuardedRegister? program emitters.registerForm .binary
      let lea ← Address.check? program memory
      let address ← Address.checkFrame? program lea offset
      let helpers : Helpers literal := ⟨allocate, memory, store, offset, save, binary, lea, address⟩
      let equal ← Core.Equality.statement? literal.otherBranches
        (dispatch literal constants helpers.calls locals earlier rest)
      pure ⟨helpers, constants, locals, fresh, earlier, rest, equal.equal⟩
    else none
  else none

theorem SkippedGuard.evaluatesFalse (guard : SkippedGuard program)
    (tag : before.local? 9 = some (.signed .i32 15)) :
    Evaluates program before guard.expression (.boolean false) before := by
  induction guard with
  | equal constant other =>
      apply evaluatesEagerBinary (by decide) (by decide) (Buffer.local_evaluates _ tag) constant.evaluates
      simp [evalBinaryValue, scalarEqual, Ne.symm other]
  | either left right leftRun rightRun => exact evaluatesLogicalOrFalse leftRun rightRun

theorem prefix_skips (earlier : Prefix program)
    (tag : before.local? 9 = some (.signed .i32 15))
    (run : Executes program before rest signal after) :
    Executes program before (prefixBody earlier rest) signal after := by
  induction earlier with
  | nil => exact run
  | cons head earlier recurse =>
      exact executesSequence (executesIfFalse (head.1.evaluatesFalse tag) (executesSkip _ _)) recurse

/-- A proved execution of the selected raw branch is an execution of the
actual remaining emitter body. Untaken branch executions are not premises. -/
theorem Checked.select {literal : Literal.Checked emitters} (checked : Checked literal)
    (tag : before.local? 9 = some (.signed .i32 15))
    (run : Executes emitters.pack.program.core before
      (branch literal checked.constants checked.helpers.calls checked.locals) (.returned value) after) :
    Executes emitters.pack.program.core before literal.otherBranches (.returned value) after := by
  rw [checked.bodyExact]
  apply prefix_skips checked.earlier tag
  have selectedRun : Evaluates emitters.pack.program.core before (selected checked.constants) (.boolean true) before := by
    have constant := checked.constants.tag.evaluates (before := before)
    rw [checked.constants.values.1] at constant
    apply evaluatesEagerBinary (by decide) (by decide) (Buffer.local_evaluates _ tag) constant
    rfl
  exact executesSequenceReturned (executesIfTrue selectedRun run)

end Lanius.X86.Source.Expression.Raw
