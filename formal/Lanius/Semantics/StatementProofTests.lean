import Lanius.Semantics.StatementProof

namespace Lanius.Semantics.StatementProofTests

open Lanius.Core

-- The output of the first proved effect, not the requested final state,
-- is the input to the second effect.
theorem twoEffects
    (first : RunsExpr program before left .unit middle)
    (second : RunsExpr program middle right .unit after) :
    RunsStmt program before (.sequence (.expression left) (.expression right)) .next after := by
  core_stmt

-- A return makes the following statement unreachable, even if that
-- statement has no available execution contract.
theorem earlyReturn (statement : Stmt) (value : Value) :
    RunsStmt program state (.sequence (.returnValue (some (.value value))) statement)
      (.returned (some value)) state := by
  core_stmt

theorem restoredLocal (value : Value) (formed : state.CellsWellFormed) :
    RunsStmt program state (.letLocal 7 .unit (.value value) (.returnValue (some (.local 7))))
      (.returned (some value)) (restoreLocals state (state.bindLocal 7 value)) := by
  core_stmt

-- Loops are reused only through a proved contract. Their output is the
-- following statement's input; the forward tactic does not unroll them.
theorem suppliedLoop {condition : Expr} {body : Stmt}
    (loop : RunsStmt program before (.whileLoop condition body) .next middle)
    (effect : RunsExpr program middle expression value after) :
    RunsStmt program before (.sequence (.whileLoop condition body) (.returnValue (some expression)))
      (.returned (some value)) after := by
  core_stmt

theorem recordAfterLoop {condition : Expr} {body : Stmt}
    (loop : RunsStmt program before (.whileLoop condition body) .next middle)
    (effect : RunsExpr program middle expression event middle)
    (annotation : middle.local? 7 = some type)
    (capacity : middle.local? 8 = some count) :
    RunsStmt program before
      (.sequence (.whileLoop condition body) (.returnValue (some
        (.structValue 3 [expression, .local 7, .value (.boolean true), .local 8]))))
      (.returned (some (.structure 3 [event, type, .boolean true, count]))) middle := by
  core_stmt

-- A call may write the heap and allocate fresh cells. Its proved cell frame
-- is sufficient to retain caller locals; no individual lookup lemma is needed.
theorem localAfterCall
    (run : RunsExpr program before expression result after)
    (frame : FreshCellFrame before after)
    (found : before.local? 7 = some value) :
    RunsExpr program after (.local 7) value after := by
  core_run

-- The guard evaluates the right call once and retains its actual output
-- state through negation, short-circuit disjunction and branch selection.
theorem effectfulGuard
    (run : RunsExpr program before expression (.boolean true) after) :
    RunsStmt program before
      (.ifThenElse (.binary .logicalOr (.value (.boolean false)) (.unary .logicalNot expression))
        (.returnValue (some (.value (.signed .i32 0))))
        (.returnValue (some (.value (.signed .i32 7)))))
      (.returned (some (.signed .i32 7))) after := by
  core_stmt

theorem suppliedConcrete
    (step : RunsStmt program before (.expression expression) .next middle) :
    RunsStmt program before (.sequence (.expression expression) .skip) .next middle := by
  have direct : RunsStmt program before (.sequence (.expression expression) .skip) .next middle := by
    core_stmt_forward
  clear direct
  core_stmt

theorem restoredOpaqueInitializer
    {program : Program} {before ready after : State}
    (init : RunsExpr program before initializer value ready)
    (bodyRun : RunsStmt program (ready.bindLocal 7 value) body .next
      { after with locals := (ready.bindLocal 7 value).locals }) :
    RunsStmt program before (.letLocal 7 .unit initializer body) .next
      { after with locals := before.locals } := by
  fail_if_success core_stmt_forward
  core_stmt

theorem trueBranch (unreachable : Stmt) (value : Value) :
    RunsStmt program state (.ifThenElse (.value (.boolean true))
      (.returnValue (some (.value value))) unreachable) (.returned (some value)) state := by
  core_stmt

example (program : Program) (state : State) : RunsStmt program state .skip .next state := by
  core_stmt_forward

example : True := by
  fail_if_success
    have wrongValue : RunsStmt ({} : Program) ({} : State)
        (.returnValue (some (.value (.boolean true)))) (.returned (some (.boolean false))) {} := by
      core_stmt
  fail_if_success
    have wrongState : RunsStmt ({} : Program) ({} : State)
        .skip .next (({} : State).bindLocal 7 .unit) := by
      core_stmt
  trivial

-- Synthesis must not invent a contract for an arbitrary memory write.
example : True := by
  fail_if_success
    have impossible : RunsStmt ({} : Program) ({} : State)
        (.expression (.assign .set (.local 7) (.value .unit))) .next {} := by
      core_stmt
  fail_if_success
    have impossible : RunsStmt ({} : Program) ({} : State)
        (.whileLoop (.value (.boolean true)) .skip) .next {} := by
      core_stmt
  trivial

-- Expression execution alone cannot preserve a mutable local's old value.
example (_run : RunsExpr program before expression result after)
    (_found : before.local? 7 = some value) : True := by
  fail_if_success
    have unsupported : after.local? 7 = some value := by core_local
  trivial

#print axioms twoEffects
#print axioms earlyReturn
#print axioms restoredLocal
#print axioms suppliedLoop
#print axioms recordAfterLoop
#print axioms localAfterCall
#print axioms effectfulGuard


-- A fixed comparison result constrains the head before synthesis. Its proof
-- needs the bound, so inferring an unreduced predicate then comparing the
-- completed argument list is not enough.
theorem knownComparisonArgument
    (call : Expr) (run : RunsExpr program before call (.signed .i32 value) middle)
    (nonnegative : 0 ≤ value) :
    RunsExprs program before
      [.binary .less call (.value (.signed .i32 0)), .value .unit]
      [.boolean false, .unit] middle := by
  core_arguments

-- A genuinely unknown result list must still be synthesized.
theorem inferredArgumentList (value : Value) :
    ∃ values, RunsExprs program state [.value value, .value .unit] values state := by
  exact ⟨_, by core_arguments⟩

-- A rejected requested value must not leak assignments into a later proof.
theorem rejectsWrongArgument
    (call : Expr) (run : RunsExpr program before call (.signed .i32 value) middle)
    (nonnegative : 0 ≤ value) : True := by
  fail_if_success
    have wrong : RunsExprs program before
        [.binary .less call (.value (.signed .i32 0)), .value .unit]
        [.boolean true, .unit] middle := by
      core_arguments
  have right : RunsExprs program before
      [.binary .less call (.value (.signed .i32 0)), .value .unit]
      [.boolean false, .unit] middle := by
    core_arguments
  trivial

theorem rejectsWrongArgumentLength : True := by
  fail_if_success
    have wrong : RunsExprs ({} : Program) ({} : State)
        [.value .unit] [] {} := by core_arguments
  trivial

#print axioms knownComparisonArgument
#print axioms inferredArgumentList
#print axioms rejectsWrongArgument
#print axioms rejectsWrongArgumentLength

end Lanius.Semantics.StatementProofTests
