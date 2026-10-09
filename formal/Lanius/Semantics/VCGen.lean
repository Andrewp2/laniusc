import Lanius.Semantics.StmtList
import Lean.Elab.Tactic.Do

namespace Lanius.Semantics.CoreVCGen

open Lanius Lanius.Core Lean.Order Std.Internal.Do

/-- Total successful execution of actual Core syntax, indexed by its program. -/
@[instance_reducible] def coreWP (program : Program) : WP Stmt Completion (State → Prop) EPost.Nil where
  wpTrans statement := ⟨fun Q _ before => ∃ completion after,
    RunsStmt program before statement completion after ∧ Q completion after⟩
  wp_trans_monotone statement := by
    intro Q Q' _ _ _ weaker before
    rintro ⟨completion, after, run, post⟩
    exact ⟨completion, after, run, weaker completion after post⟩

abbrev coreTriple (program : Program) (statement : Stmt) (P : State → Prop)
    (Q : Completion → State → Prop) : Prop :=
  @Triple _ _ _ _ _ _ statement (coreWP program) P Q ⊥

section
variable (program : Program)

theorem coreTriple_sound {statement : Stmt} {P : State → Prop}
    {Q : Completion → State → Prop} {before : State}
    (contract : coreTriple program statement P Q) (input : P before) :
    ∃ completion after, RunsStmt program before statement completion after ∧ Q completion after := by
  letI := coreWP program
  exact contract.le_wp before input

theorem coreTriple_exec {statement : Stmt} {P : State → Prop}
    {Q : Completion → State → Prop} {before : State}
    (contract : coreTriple program statement P Q) (input : P before) :
    ∃ fuel completion after, execStmt fuel program before statement = .done completion after ∧
      Q completion after := by
  obtain ⟨completion, after, run, post⟩ := coreTriple_sound program contract input
  obtain ⟨fuel, execution⟩ := run.executes
  exact ⟨fuel, completion, after, execution, post⟩

@[spec] theorem core_skip (Q : Completion → State → Prop) :
    coreTriple program .skip (Q .next) Q := by
  letI := coreWP program
  exact ⟨fun state post => ⟨.next, state, RunsStmt.skip program state, post⟩⟩

@[spec] theorem core_sequence (first second : Stmt) (Q : Completion → State → Prop) :
    coreTriple program (.sequence first second)
      ((coreWP program).wp first (fun completion => match completion with
        | .next => (coreWP program).wp second Q ⊥
        | other => Q other) ⊥) Q := by
  classical
  letI := coreWP program
  constructor
  intro before head
  obtain ⟨completion, middle, firstRun, next⟩ := head
  by_cases isNext : completion = .next
  · subst completion
    obtain ⟨completion, after, secondRun, post⟩ := next
    exact ⟨completion, after, RunsStmt.sequenceNext firstRun secondRun, post⟩
  · exact ⟨completion, middle, RunsStmt.sequenceCompleted firstRun isNext second,
      by cases completion <;> simp_all⟩

@[spec] theorem core_returnValue (argument : Expr) (Q : Completion → State → Prop) :
    coreTriple program (.returnValue (some argument))
      (fun before => ∃ value after, RunsExpr program before argument value after ∧
        Q (.returned (some value)) after) Q := by
  letI := coreWP program
  exact ⟨fun _ ⟨value, after, run, post⟩ =>
    ⟨.returned (some value), after, RunsStmt.returnValue run, post⟩⟩

@[spec] theorem core_letLocal (id : VarId) (type : Ty) (initializer : Expr) (body : Stmt)
    (Q : Completion → State → Prop) :
    coreTriple program (.letLocal id type initializer body)
      (fun before => ∃ value ready, RunsExpr program before initializer value ready ∧
        (coreWP program).wp body
          (fun completion after => Q completion (restoreLocals ready after)) ⊥
          (ready.bindLocal id value)) Q := by
  letI := coreWP program
  constructor
  rintro before ⟨value, ready, initial, completion, after, bodyRun, post⟩
  exact ⟨completion, restoreLocals ready after, RunsStmt.letLocal initial bodyRun, post⟩

@[spec] theorem core_ifThenElse (condition : Expr) (yes no : Stmt)
    (Q : Completion → State → Prop) :
    coreTriple program (.ifThenElse condition yes no)
      (fun before => ∃ truth ready, RunsExpr program before condition (.boolean truth) ready ∧
        (coreWP program).wp (if truth then yes else no) Q ⊥ ready) Q := by
  letI := coreWP program
  constructor
  rintro before ⟨truth, ready, guard, completion, after, branch, post⟩
  refine ⟨completion, after, ?_, post⟩
  cases truth
  · exact RunsStmt.ifThenElseFalse guard branch
  · exact RunsStmt.ifThenElseTrue guard branch

@[spec] theorem core_expression (argument : Expr) (Q : Completion → State → Prop) :
    coreTriple program (.expression argument)
      (fun before => ∃ value after, RunsExpr program before argument value after ∧ Q .next after) Q := by
  letI := coreWP program
  exact ⟨fun _ ⟨value, after, run, post⟩ => ⟨.next, after, RunsStmt.expression run, post⟩⟩

end
end Lanius.Semantics.CoreVCGen
