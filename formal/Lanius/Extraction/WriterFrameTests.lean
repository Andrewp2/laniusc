import Lanius.Extraction.WriterProof
import Lanius.Semantics.CallProof
import Lanius.Semantics.PureProof

namespace Lanius.Extraction.WriterFrameTests

open Lanius.Core Lanius.Semantics
variable {state : State}

private def source : Core.Function := {
  id := 7, parameters := [(55, .scalar (.signed .i32))], returnType := .scalar (.signed .i32),
  body := some (.returnValue (some (.value (.signed .i32 13)))) }
private def program : Program := { functions := [source] }

theorem call (argument : Int) (formed : state.CellsWellFormed) (unique : Memory.HeapBlockBasesUnique state.heap) :
    ∃ after, RunsExpr program state (.call 7 [.value (.signed .i32 argument)]) (.signed .i32 13) after ∧
      WriterFrame state after 4 [] := by
  core_call_framed Lanius.Extraction.RunsExpr.callWriter source as callee
  exact ⟨callee, by core_stmt,
    ⟨.write (Memory.BytesWrite.refl unique), (CallerFrame.refl (by core_formed)).cells, rfl, rfl⟩⟩

example (formed : state.CellsWellFormed) (unique : Memory.HeapBlockBasesUnique state.heap) : True := by
  fail_if_success
    suffices wrong : ∃ after, RunsExpr program state (.call 7 [.value (.signed .i32 1)]) (.signed .i32 14) after ∧
        WriterFrame state after 4 [] from True.intro
    core_call_framed Lanius.Extraction.RunsExpr.callWriter source as callee
    refine ⟨callee, ?_,
      ⟨.write (Memory.BytesWrite.refl unique), (CallerFrame.refl (by core_formed)).cells, rfl, rfl⟩⟩
    core_stmt
  trivial

#print axioms call

-- The writer's parameter shadows this caller local. Both the let scope and
-- match payload scope must restore it, while retaining the callee's frame.
theorem localWriter (formed : state.CellsWellFormed) (unique : Memory.HeapBlockBasesUnique state.heap) :
    ∃ after, RunsStmt program state
      (.letLocal 55 (.scalar (.signed .i32)) (.value (.signed .i32 42))
        (.returnValue (some (.call 7 [.local 55]))))
      (.returned (some (.signed .i32 13))) after ∧ WriterFrame state after 4 [] := by
  let ready := state.bindLocal 55 (.signed .i32 42)
  have writer := call 42 (state := ready) (by core_formed) unique
  core_writer

theorem matchWriter (formed : state.CellsWellFormed) (unique : Memory.HeapBlockBasesUnique state.heap) :
    ∃ after, RunsExpr program state
      (.matchValue (.value (.enumeration 8 0 [.signed .i32 42]))
        [(.enumVariant 8 0 [.bind 55], .call 7 [.local 55])])
      (.signed .i32 13) after ∧ WriterFrame state after 4 [] := by
  let ready := state.bindLocal 55 (.signed .i32 42)
  have writer := call 42 (state := ready) (by core_formed) unique
  core_writer_expr

#print axioms localWriter
#print axioms matchWriter
#print axioms RunsStmt.guardWriterTrue

-- A returning guard must select its proved condition before descending into
-- the writer continuation. The skipped branch has a deliberately wrong result.
theorem guardedWriter (formed : state.CellsWellFormed) (unique : Memory.HeapBlockBasesUnique state.heap) :
    ∃ after, RunsStmt program state
      (.sequence (.ifThenElse (.value (.boolean false))
        (.returnValue (some (.value (.signed .i32 14)))) .skip)
        (.returnValue (some (.call 7 [.value (.signed .i32 42)]))))
      (.returned (some (.signed .i32 13))) after ∧ WriterFrame state after 4 [] := by
  have writer := call 42 formed unique
  core_writer

example (formed : state.CellsWellFormed) (unique : Memory.HeapBlockBasesUnique state.heap) : True := by
  have writer := call 42 formed unique
  fail_if_success
    have wrong : ∃ after, RunsStmt program state
        (.sequence (.ifThenElse (.value (.boolean true))
          (.returnValue (some (.value (.signed .i32 14)))) .skip)
          (.returnValue (some (.call 7 [.value (.signed .i32 42)]))))
        (.returned (some (.signed .i32 13))) after ∧ WriterFrame state after 4 [] := by core_writer
  trivial

#print axioms guardedWriter

/-- The inner call's parameter cell survives into the outer writer, while
    both calls restore the original caller scope. -/
theorem nestedArgument (formed : state.CellsWellFormed) (unique : Memory.HeapBlockBasesUnique state.heap) :
    ∃ after, RunsExpr program state (.call 7 [.call 7 [.value (.signed .i32 42)]])
      (.signed .i32 13) after ∧ WriterFrame state after 4 [] := by
  have argument : ∃ after, RunsExpr program state (.call 7 [.value (.signed .i32 42)])
      (.signed .i32 13) after ∧ PureFrame state after := by
    core_call_pure source as callee
    core_pure
  apply RunsExpr.writerFramedArguments
  · apply RunsExprs.consPure argument
    intro middle frame
    exact ⟨middle, .nil, PureFrame.refl frame.afterFormed⟩
  · intro middle frame
    exact call 13 frame.afterFormed (by simpa only [frame.heap] using unique)

#print axioms nestedArgument
#print axioms RunsExpr.writerFramedArguments

end Lanius.Extraction.WriterFrameTests
