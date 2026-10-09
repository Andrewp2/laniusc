import Lanius.Execution
import Lanius.Semantics.CallProof
import Lanius.Semantics.PureProof
import GeneratedDirectCore

namespace NestedEnumProof

open Lanius Lanius.Core Lanius.Semantics
open Extracted.«app::main».Functions

-- These contracts concern the real fresh output, not a separately constructed
-- Core program. PureFrame retains caller storage and the runtime world.
@[core_pure_rule] theorem innerNumber (value : Int) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call inner_value.core.id [.value (.enumeration 0 1 [.signed .i32 value])])
      (.signed .i32 value) after ∧ PureFrame state after := by
  core_call_pure inner_value.core as callee
  core_pure

@[core_pure_rule] theorem innerEmpty (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call inner_value.core.id [.value (.enumeration 0 0 [])])
      (.signed .i32 3) after ∧ PureFrame state after := by
  core_call_pure inner_value.core as callee
  core_pure

@[core_pure_rule] theorem outerNumber (value : Int) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call unwrap.core.id [.value (.enumeration 1 1 [.enumeration 0 1 [.signed .i32 value]])])
      (.signed .i32 value) after ∧ PureFrame state after := by
  core_call_pure unwrap.core as callee
  core_pure

theorem outerEmpty (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call unwrap.core.id [.value (.enumeration 1 1 [.enumeration 0 0 []])])
      (.signed .i32 3) after ∧ PureFrame state after := by
  core_call_pure unwrap.core as callee
  core_pure

theorem outerNothing (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call unwrap.core.id [.value (.enumeration 1 0 [])])
      (.signed .i32 5) after ∧ PureFrame state after := by
  core_call_pure unwrap.core as callee
  core_pure

theorem roundtripValue (value : Int) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call roundtrip.core.id [.value (.signed .i32 value)])
      (.signed .i32 value) after ∧ PureFrame state after := by
  core_call_pure roundtrip.core as callee
  core_pure

theorem nestedNumber (value : Int) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call nested_value.core.id [.value (.enumeration 1 1 [.enumeration 0 1 [.signed .i32 value]])])
      (.signed .i32 value) after ∧ PureFrame state after := by
  core_call_pure nested_value.core as callee
  core_pure

theorem nestedEmpty (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call nested_value.core.id [.value (.enumeration 1 1 [.enumeration 0 0 []])])
      (.signed .i32 3) after ∧ PureFrame state after := by
  core_call_pure nested_value.core as callee
  core_pure

theorem nestedNothing (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call nested_value.core.id [.value (.enumeration 1 0 [])])
      (.signed .i32 5) after ∧ PureFrame state after := by
  core_call_pure nested_value.core as callee
  core_pure

theorem matchPayload (value : Int) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call match_payload.core.id [.value (.signed .i32 value)])
      (.signed .i32 value) after ∧ PureFrame state after := by
  core_call_pure match_payload.core as callee
  core_pure

theorem matchSource (value : Int) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call match_source.core.id [.value (.signed .i32 value)])
      (.signed .i32 value) after ∧ PureFrame state after := by
  core_call_pure match_source.core as callee
  core_pure

theorem shadowedNumber (value : Int) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call shadowed.core.id [.value (.enumeration 1 1 [.enumeration 0 1 [.signed .i32 value]])])
      (.signed .i32 value) after ∧ PureFrame state after := by
  core_call_pure shadowed.core as callee
  core_pure

example : (match Lanius.Execution.run 1024
    { program := extractedProgram, entrypoint := extractedEntrypoint } {} with
  | .returned (.signed .i32 7) _ => true | _ => false) = true := by decide

#print axioms roundtripValue
#print axioms matchPayload
#print axioms matchSource
#print axioms shadowedNumber

end NestedEnumProof
