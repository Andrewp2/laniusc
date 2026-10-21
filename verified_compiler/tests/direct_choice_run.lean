import Choice
import Lanius.Semantics.CallProof
import Lanius.Semantics.PureProof

open Lanius.Core Lanius.Semantics

/-- The representative emitted Choice/Some(7)/match program returns 7,
    terminates, and retains the caller's memory. -/
theorem choiceReturnsSeven (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«app::main».Functions.«main».core.id []) (.signed .i32 7) after ∧
      PureFrame before after := by
  core_call_pure Extracted.«app::main».Functions.«main».core as callee
  core_pure

#print axioms choiceReturnsSeven
