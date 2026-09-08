import Lanius.Extraction.Parser.Tree.Execution
import Lanius.Extraction.Parser.Tree.Reader
import Lanius.Extraction.Parser.Tree.Iteration
import Lanius.Extraction.Parser.Tree.Resume
import Lanius.Extraction.Parser.Tree.Recursive
import Lanius.Extraction.Parser.Tree.Caller
import Lanius.Extraction.Parser.Tree.Call
import Lanius.Extraction.Parser.Tree.Materialize
import Lanius.Extraction.Parser.Tree.Root
import Lanius.Extraction.Parser.Tree.Failure

open Lanius.Extraction.ParserTreeSource

-- The runtime checker must inspect constant values, including their i32 type.
example : (checkConstantValue? { constants := [⟨4, .scalar (.signed .i32), .signed .i32 3⟩] } 4 3).isSome = true := by decide
example : (checkConstantValue? { constants := [⟨4, .scalar (.signed .i32), .signed .i32 2⟩] } 4 3).isNone = true := by decide
example : (checkConstantValue? { constants := [⟨4, .scalar (.signed .i64), .signed .i64 3⟩] } 4 3).isNone = true := by decide
example : (checkConstantValue? { constants := [] } 4 3).isNone = true := by decide

-- Exercise the actual capacity expression at header/triple boundaries. A
-- trapped or exhausted evaluation is `none`, never a successful rejection.
private def capacityResult (capacity offset count : Int) : Option Bool :=
  let state := ((({} : Lanius.Semantics.State).bindLocal 0 (.signed .i32 capacity)).bindLocal 1
    (.signed .i32 offset)).bindLocal 2 (.signed .i32 count)
  match Lanius.Semantics.evalExpr 32 {} state (Lanius.Extraction.ParserDerivation.capacityCondition 0 1 2) with
  | .done (.boolean rejected) _ => some rejected
  | _ => none

example : capacityResult 0 0 0 = some true := by decide
example : capacityResult 3 0 0 = some true := by decide
example : capacityResult 4 0 0 = some false := by decide
example : capacityResult 4 0 1 = some true := by decide
example : capacityResult 6 0 1 = some true := by decide
example : capacityResult 7 0 1 = some false := by decide
example : capacityResult 8 5 0 = some true := by decide
example : capacityResult 12 5 1 = some false := by decide

#print axioms checkVisit?
#print axioms CheckedVisit.constructor_call
#print axioms CheckedVisit.depth_limit
#print axioms CheckedVisit.output_full
#print axioms CheckedVisit.failure_call
#print axioms Lanius.Extraction.ParserTreeDerivation.children_match
#print axioms Lanius.Extraction.ParserTreeDerivation.state_child
#print axioms CheckedVisit.read_children
#print axioms CheckedVisit.finish
#print axioms CheckedVisit.finish_full
#print axioms CheckedVisit.token_iteration
#print axioms CheckedVisit.resume_child
#print axioms CheckedVisit.child_success
#print axioms CheckedVisit.resume_failure
#print axioms CheckedVisit.child_failure
#print axioms TreeRuntime.At.pending_head
#print axioms TreeRuntime.At.token_step
#print axioms TreeRuntime.At.child_records
#print axioms TreeRuntime.At.child_offsets
#print axioms TreeRuntime.At.finish
#print axioms TreeRuntime.At.bind_slot
#print axioms TreeRuntime.At.recursive_arguments
#print axioms TreeRuntime.At.state_step
#print axioms TreeRuntime.Entry.initialize
#print axioms TreeRuntime.Entry.with_cursors
#print axioms TreeRuntime.At.loop
#print axioms TreeRuntime.Entry.children
#print axioms TreeRuntime.Frame.initialize
#print axioms TreeRuntime.Frame.preserved
#print axioms TreeRuntime.enter
#print axioms CheckedVisit.bind_parameters
#print axioms TreeRuntime.CallEntry.read
#print axioms TreeRuntime.CallEntry.body
#print axioms CheckedVisit.call_state
#print axioms Lanius.Extraction.Source.CheckedProjection.call
#print axioms checkMaterialize?
#print axioms CheckedMaterialize.call
#print axioms checkRoot?
#print axioms CheckedRoot.call
#print axioms Lanius.Extraction.ParserDerivation.ReaderRuntime.Entry.with_checked_count
#print axioms Lanius.Extraction.ParserDerivation.output_capacity_guard_true
#print axioms Lanius.Extraction.ParserDerivation.CheckedReader.execute_full
#print axioms Lanius.Extraction.ParserDerivation.LinkedReader.call_full
#print axioms TreeRuntime.CallEntry.reader_arguments
#print axioms TreeRuntime.CallEntry.reader_full
#print axioms CheckedVisit.record_full_call
#print axioms TreeRuntime.At.state_entry
#print axioms TreeRuntime.At.state_failure
#print axioms TreeRuntime.Result.failure
#print axioms TreeRuntime.At.loop_outcome
#print axioms TreeRuntime.Entry.children_outcome
#print axioms CheckedVisit.call_bounded
#print axioms CheckedMaterialize.call_bounded
#print axioms CheckedMaterialize.reject
