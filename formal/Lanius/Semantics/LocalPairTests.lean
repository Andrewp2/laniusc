import Lanius.Semantics.LocalPair
import Lanius.Semantics.CallProof
import Lanius.Semantics.PureProof

namespace Lanius.Semantics

open Lanius.Core

-- Repeated updates of distinct fresh cells preserve the other value and all
-- caller lookups, even when a caller binding is shadowed by a fresh local.
theorem separateUpdates (formed : base.CellsWellFormed) (found : base.local? 99 = some value) :
    ∃ after, LocalPair base after 17 23 (.signed .i32 7) (.signed .i32 42) ∧
      after.local? 99 = some value := by
  let before := (base.bindLocal 17 (.signed .i32 1)).bindLocal 23 (.signed .i32 2)
  have pair : LocalPair base before 17 23 (.signed .i32 1) (.signed .i32 2) :=
    LocalPair.start formed (by decide)
  obtain ⟨middle, assignedFirst⟩ := assignLocal_exists before 17 _ (.signed .i32 7)
    base.nextCell pair.firstCell pair.first
  have next := pair.assignFirst formed assignedFirst
  obtain ⟨after, assignedSecond⟩ := assignLocal_exists middle 23 _ (.signed .i32 42)
    (base.nextCell + 1) next.secondCell next.second
  have final := next.assignSecond formed assignedSecond
  exact ⟨after, final, final.read (by decide) (by decide) found⟩

example {base : State} (formed : base.CellsWellFormed) : True := by
  fail_if_success
    have alias : LocalPair base ((base.bindLocal 17 .unit).bindLocal 17 .unit) 17 17 .unit .unit :=
      LocalPair.start formed (by decide)
  trivial

#print axioms separateUpdates

private def aggregate : Value := .enumeration 0 1 [.signed .i32 7]
private def produce : Function := {
  id := 3
  parameters := [(17, .scalar (.signed .i32))]
  returnType := .enumeration 0
  body := some (.returnValue (some (.enumValue 0 1 [.local 17]))) }
private def program : Program := {
  functions := [produce]
  enumerations := [{ id := 0, variants := [[], [.scalar (.signed .i32)]] }] }

-- The aggregate RHS is an actual call: it allocates fresh parameter cells
-- and restores locals before assignment. Advancing the second cell must
-- retain the replacement and the original heap.
theorem aggregateCallThenAdvance (formed : base.CellsWellFormed) (noViews : base.i32ArrayViews = []) :
    ∃ after, RunsStmt program ((base.bindLocal 17 (.enumeration 0 0 [])).bindLocal 23 (.signed .i32 0))
      (.sequence (.expression (.assign .set (.local 17) (.call 3 [.value (.signed .i32 7)])))
        (.expression (.assign .add (.local 23) (.value (.signed .i32 1))))) .next after ∧
      LocalPair base after 17 23 aggregate (.signed .i32 1) ∧ after.heap = base.heap := by
  have initialized := (formed.bindLocal 17 (.enumeration 0 0 [])).bindLocal 23 (.signed .i32 0)
  have pair : LocalPair base ((base.bindLocal 17 (.enumeration 0 0 [])).bindLocal 23 (.signed .i32 0))
      17 23 (.enumeration 0 0 []) (.signed .i32 0) := LocalPair.start formed (by decide)
  obtain ⟨middle, replace, next, heap, _, _⟩ := pair.replaceFirst (program := program)
    (expression := .call 3 [.value (.signed .i32 7)]) (replacement := aggregate) formed noViews (by
    core_call_pure produce as callee
    core_pure)
  obtain ⟨after, advance, final, unchanged, _, _⟩ := next.incrementSecond
    (program := program) (index := 0) formed (by decide)
  exact ⟨after, RunsStmt.sequenceNext (RunsStmt.expression replace) (RunsStmt.expression advance),
    final, unchanged.trans heap⟩

#print axioms aggregateCallThenAdvance
#print axioms RunsExpr.assignValueAfter

end Lanius.Semantics
