import Lanius.Semantics.LoopRun
import Lanius.Semantics.StatementProof

namespace Lanius.Semantics

open Lanius.Core

-- A false guard must skip a trapping body even with no useful body contract.
example (program : Program) (state : State) :
    RunsStmt program state
      (.whileLoop (.value (.boolean false))
        (.expression (.binary .divide (.value (.signed .i32 1)) (.value (.signed .i32 0)))))
      .next state := .whileFalse (.ofStable .value rfl)

-- Unbounded in the number of iterations: a counter decreases to zero. The
-- frame also retains heap, world, view registry, and the lexical environment.
theorem countdown (program : Program) (state : State) (count : Nat)
    (bound : count < 2 ^ 31) (counter : state.cellId? 1 = some cell)
    (initial : state.local? 1 = some (.signed .i32 count)) :
    ∃ after, RunsStmt program state
      (.whileLoop (.binary .notEqual (.local 1) (.value (.signed .i32 0)))
        (.sequence (.expression (.assign .add (.local 1) (.value (.signed .i32 (-1)))))
          .continueLoop)) .next after ∧ after.local? 1 = some (.signed .i32 0) ∧
      after.heap = state.heap ∧ after.world = state.world ∧
      after.i32ArrayViews = state.i32ArrayViews := by
  let invariant := fun n (s : State) => n ≤ count ∧ s.cellId? 1 = some cell ∧
    s.local? 1 = some (.signed .i32 n) ∧ s.heap = state.heap ∧
    s.world = state.world ∧ s.i32ArrayViews = state.i32ArrayViews
  apply RunsStmt.whileCount invariant
    (fun s => s.local? 1 = some (.signed .i32 0) ∧ s.heap = state.heap ∧
      s.world = state.world ∧ s.i32ArrayViews = state.i32ArrayViews)
  · intro s facts
    obtain ⟨_, _, localFound, heap, world, views⟩ := facts
    refine ⟨s, .ofStable (threshold := 2) ?_ rfl, localFound, heap, world, views⟩
    apply StableExpr.binary (.local localFound) .value (by decide)
    rfl
  · intro n s facts
    obtain ⟨smaller, cellFound, localFound, heap, world, views⟩ := facts
    obtain ⟨after, assigned⟩ := assignLocal_exists s 1 _ (.signed .i32 n) cell cellFound localFound
    have value : wrapSigned program.target .i32 ((n + 1 : Nat) + (-1)) = n := by
      rw [show ((n + 1 : Nat) : Int) + (-1) = n by omega]
      exact wrapSigned_i32_nat_lt _ _ (by omega)
    have addition := StableExpr.assignAddI32 program s 1 cell (n + 1 : Nat) (-1) after
      cellFound localFound (by simpa only [value] using assigned)
    have unchanged := assignCell_state (assignLocal_assignCell 1 cell _ cellFound assigned)
    refine ⟨s, after, .continueLoop, .ofStable (threshold := 2) ?_ rfl,
      .sequenceNext (.expression (.ofStable addition (by rw [unchanged]))) ?_, Or.inr rfl, ?_⟩
    · apply StableExpr.binary (.local localFound) .value (by decide)
      simp [evalBinaryValue, scalarEqual]
      omega
    · refine ⟨1, ?_, rfl⟩
      intro fuel enough
      cases fuel <;> simp_all [execStmt.eq_def]
    · refine ⟨by omega, ?_, assignLocal_finds_assigned 1 cell _ cellFound assigned, ?_, ?_, ?_⟩
      · rw [unchanged]; exact cellFound
      · simpa only [unchanged] using heap
      · simpa only [unchanged] using world
      · simpa only [unchanged] using views
  · exact ⟨Nat.le_refl _, counter, initial, rfl, rfl, rfl⟩

#print axioms countdown

private def checkedGuard : Expr := .binary .notEqual (.local 1) (.value (.signed .i32 0))
private def checkedBody : Stmt :=
  .ifThenElse (.binary .equal (.local 1) (.value (.signed .i32 3)))
    (.returnValue (some (.value (.signed .i32 (-1)))))
    (.expression (.assign .add (.local 1) (.value (.signed .i32 (-1)))))

-- A genuine decreasing loop with an early rejection: counts below three
-- reach zero; larger counts return at three without executing later steps.
theorem checkedCountdown (program : Program) (state : State) (count : Nat)
    (bound : count < 2 ^ 31) (counter : state.cellId? 1 = some cell)
    (initial : state.local? 1 = some (.signed .i32 count)) :
    ∃ completion after, RunsStmt program state (.whileLoop checkedGuard checkedBody) completion after ∧
      (if count < 3 then completion = .next ∧ after.local? 1 = some (.signed .i32 0)
       else completion = .returned (some (.signed .i32 (-1))) ∧
         after.local? 1 = some (.signed .i32 3)) ∧
      after.heap = state.heap ∧ after.world = state.world ∧
      after.i32ArrayViews = state.i32ArrayViews := by
  let invariant := fun n (s : State) => n ≤ count ∧ (3 ≤ count → 3 ≤ n) ∧
    s.cellId? 1 = some cell ∧ s.local? 1 = some (.signed .i32 n) ∧
    s.heap = state.heap ∧ s.world = state.world ∧ s.i32ArrayViews = state.i32ArrayViews
  apply RunsStmt.whileCountOrReturn invariant
  · intro s ⟨_, stopped, _, found, heap, world, views⟩
    refine ⟨s, ?_, ?_⟩
    · dsimp only [checkedGuard]; core_run
    · rw [if_pos (show count < 3 by omega)]
      exact ⟨⟨rfl, found⟩, heap, world, views⟩
  · intro n s ⟨smaller, stopped, cellFound, found, heap, world, views⟩
    refine ⟨s, ?_, ?_⟩
    · dsimp only [checkedGuard]; core_run
    by_cases rejected : n + 1 = 3
    · right
      refine ⟨s, some (.signed .i32 (-1)), ?_, ?_⟩
      · dsimp only [checkedBody]; core_stmt
      · rw [if_neg (show ¬count < 3 by omega)]
        exact ⟨⟨rfl, by simpa [rejected] using found⟩, heap, world, views⟩
    · left
      obtain ⟨after, assigned⟩ := assignLocal_exists s 1 _ (.signed .i32 n) cell cellFound found
      have value : wrapSigned program.target .i32 ((n + 1 : Nat) + (-1)) = n := by
        rw [show ((n + 1 : Nat) : Int) + (-1) = n by omega]
        exact wrapSigned_i32_nat_lt _ _ (by omega)
      have decrement := RunsExpr.ofStable
        (StableExpr.assignAddI32 program s 1 cell (n + 1 : Nat) (-1) after
          cellFound found (by simpa only [value] using assigned))
        (by rw [assignCell_state (assignLocal_assignCell _ _ _ cellFound assigned)])
      have unchanged := assignCell_state (assignLocal_assignCell _ _ _ cellFound assigned)
      refine ⟨after, .next, ?_, Or.inl rfl, by omega, ?_, ?_, ?_, ?_, ?_, ?_⟩
      · dsimp only [checkedBody]; core_stmt
      · omega
      · rw [unchanged]; exact cellFound
      · exact assignLocal_finds_assigned _ _ _ cellFound assigned
      all_goals simpa only [unchanged] using (by assumption)
  · exact ⟨Nat.le_refl _, fun h => h, counter, initial, rfl, rfl, rfl⟩

#print axioms checkedCountdown
#print axioms RunsStmt.whileCountOrReturn

end Lanius.Semantics
