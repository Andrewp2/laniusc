import Lanius.CallContracts
import Lanius.Properties

namespace Lanius.Semantics.Prefix

open Lanius.Core Lanius.Typing Lanius.Properties

/-- An already-executed prefix reaches an actual source continuation while
its lexical scopes remain open. Unlike a completed statement, this evidence
does not require the continuation to execute first. -/
inductive Reaches (program : Program) : State → Stmt → State → Stmt → Prop where
  | here : Reaches program state statement state statement
  | sequenceHead
      (head : Reaches program before first ready continuation) :
      Reaches program before (.sequence first second) ready continuation
  | sequence
      (head : Executes program before first .next middle)
      (rest : Reaches program middle second ready continuation) :
      Reaches program before (.sequence first second) ready continuation
  | letLocal
      (initializer : Evaluates program before expression value initialized)
      (rest : Reaches program (initialized.bindLocal localId value) body ready continuation) :
      Reaches program before (.letLocal localId type expression body) ready continuation
  | letUninitialized
      (rest : Reaches program (before.bindUninitialized localId) body ready continuation) :
      Reaches program before (.letUninitialized localId type body) ready continuation
  | ifTrue
      (condition : Evaluates program before expression (.boolean true) guarded)
      (branch : Reaches program guarded yes ready continuation) :
      Reaches program before (.ifThenElse expression yes no) ready continuation

theorem Reaches.trans (first : Reaches program before statement middle continuation)
    (second : Reaches program middle continuation after final) :
    Reaches program before statement after final := by
  induction first with
  | here => exact second
  | sequenceHead _ ih => exact .sequenceHead (ih second)
  | sequence head _ ih => exact .sequence head (ih second)
  | letLocal initializer _ ih => exact .letLocal initializer (ih second)
  | letUninitialized _ ih => exact .letUninitialized (ih second)
  | ifTrue condition _ ih => exact .ifTrue condition (ih second)

/-- The continuation's context, store typing, and source typing follow from
the original statement's type proof and the prefix executions already in hand.
No intermediate typing or successful continuation is assumed. -/
theorem Reaches.typed (reach : Reaches program before statement ready continuation)
    (programTyped : ProgramWellTyped program)
    (constantsClosed : ProgramConstantsClosed program)
    (opaqueTyped : ∀ world, OpaqueResponsesWellTyped program world)
    (statementTyped : StmtHasType program returnType context inLoop statement)
    (beforeTyped : RuntimeStateHasType program context before store) :
    ∃ nextContext nextStore, StmtHasType program returnType nextContext inLoop continuation ∧
      RuntimeStateHasType program nextContext ready nextStore := by
  induction reach generalizing context store with
  | here => exact ⟨context, store, statementTyped, beforeTyped⟩
  | sequenceHead _ ih =>
      cases statementTyped with
      | sequence headTyped _ => exact ih headTyped beforeTyped
  | sequence head _ ih =>
      cases statementTyped with
      | sequence headTyped tailTyped =>
          obtain ⟨fuel, head⟩ := head
          have preserved := execStmt_has_runtime_type programTyped constantsClosed opaqueTyped headTyped fuel beforeTyped
          rw [head] at preserved
          obtain ⟨nextStore, _, _, nextTyped, _⟩ := preserved
          exact ih tailTyped nextTyped
  | letLocal initializer _ ih =>
      cases statementTyped with
      | letLocal initializerTyped tailTyped =>
          obtain ⟨fuel, initializer⟩ := initializer
          have preserved := evalExpr_has_runtime_type programTyped constantsClosed opaqueTyped fuel beforeTyped initializerTyped
          rw [initializer] at preserved
          obtain ⟨nextStore, _, _, nextTyped, valueTyped, borrows⟩ := preserved
          exact ih tailTyped (nextTyped.bindLocal _ valueTyped borrows)
  | ifTrue condition _ ih =>
      cases statementTyped with
      | ifThenElse conditionTyped branchTyped _ =>
          obtain ⟨fuel, condition⟩ := condition
          have preserved := evalExpr_has_runtime_type programTyped constantsClosed opaqueTyped fuel beforeTyped conditionTyped
          rw [condition] at preserved
          obtain ⟨nextStore, _, _, nextTyped, _, _⟩ := preserved
          exact ih branchTyped nextTyped
  | letUninitialized _ ih =>
      cases statementTyped with
      | letUninitialized tailTyped => exact ih tailTyped (beforeTyped.bindUninitialized _ _)

end Lanius.Semantics.Prefix
