import Lanius.Semantics.StmtList

namespace Lanius.Semantics

open Lanius Lanius.Core

/- A guard chain is the Core shape
   sequence (ifThenElse condition whenTrue skip) rest. -/
inductive GuardedChain where
  | tail (statement : Stmt)
  | guard (condition : Expr) (whenTrue : Stmt) (rest : GuardedChain)

def GuardedChain.compile : GuardedChain → Stmt
  | .tail statement => statement
  | .guard condition whenTrue rest =>
      .sequence (.ifThenElse condition whenTrue .skip) rest.compile

inductive GuardedChain.Run (program : Program) : State → GuardedChain → Completion → State → Prop where
  | tail {state : State} {statement : Stmt} {completion : Completion} {after : State}
      (run : RunsStmt program state statement completion after) :
      Run program state (.tail statement) completion after
  | guardFalse {state afterCondition : State} {condition : Expr} {whenTrue : Stmt}
      {rest : GuardedChain} {completion : Completion} {after : State}
      (conditionRun : RunsExpr program state condition (.boolean false) afterCondition)
      (restRun : Run program afterCondition rest completion after) :
      Run program state (.guard condition whenTrue rest) completion after
  | guardTrueReturn {state afterCondition after : State} {condition : Expr} {whenTrue : Stmt}
      {rest : GuardedChain} {completion : Completion}
      (conditionRun : RunsExpr program state condition (.boolean true) afterCondition)
      (trueRun : RunsStmt program afterCondition whenTrue completion after)
      (notNext : completion ≠ .next) :
      Run program state (.guard condition whenTrue rest) completion after
  | guardTrueNext {state afterCondition afterTrue after : State} {condition : Expr} {whenTrue : Stmt}
      {rest : GuardedChain} {completion : Completion}
      (conditionRun : RunsExpr program state condition (.boolean true) afterCondition)
      (trueRun : RunsStmt program afterCondition whenTrue .next afterTrue)
      (restRun : Run program afterTrue rest completion after) :
      Run program state (.guard condition whenTrue rest) completion after

theorem GuardedChain.Run.stable
    {program : Program} {state : State} {chain : GuardedChain}
    {completion : Completion} {after : State}
    (run : GuardedChain.Run program state chain completion after) :
    RunsStmt program state chain.compile completion after := by
  induction run with
  | tail run => exact run
  | guardFalse conditionRun restRun ih =>
      rename_i s ac c wt r comp aft
      have branch := RunsStmt.ifThenElseFalse (conditionExpr := c) (thenBranch := wt)
        (elseBranch := .skip) conditionRun (RunsStmt.skip program _)
      simpa [GuardedChain.compile] using RunsStmt.sequenceNext branch ih
  | guardTrueReturn conditionRun trueRun notNext =>
      rename_i s ac aft c wt r comp
      have branch := RunsStmt.ifThenElseTrue (conditionExpr := c) (thenBranch := wt)
        (elseBranch := .skip) conditionRun trueRun
      simpa [GuardedChain.compile] using RunsStmt.sequenceCompleted branch notNext r.compile
  | guardTrueNext conditionRun trueRun restRun ih =>
      rename_i s ac aTrue aft c wt r comp
      have branch := RunsStmt.ifThenElseTrue (conditionExpr := c) (thenBranch := wt)
        (elseBranch := .skip) conditionRun trueRun
      simpa [GuardedChain.compile] using RunsStmt.sequenceNext branch ih

end Lanius.Semantics
