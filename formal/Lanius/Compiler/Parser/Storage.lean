import Lanius.Compiler.ParserModel

namespace Lanius.Compiler.Parser

/-- A capacity diagnostic names the actual terminal workspace and reports
its state count. Mere nonzero status is not a resource-exhaustion witness. -/
structure WorkspaceFull (capacity : Nat) (workspace : LogicalWorkspace) (reported : Nat) : Prop where
  count : reported = workspace.states.length
  full : capacity ≤ reported

theorem WorkspaceFull.capacity_le_states (full : WorkspaceFull capacity workspace reported) :
    capacity ≤ workspace.states.length := by rw [← full.count]; exact full.full

theorem WorkspaceFull.excludes_bound (full : WorkspaceFull capacity workspace reported)
    (bounded : workspace.states.length < capacity) : False :=
  Nat.not_le_of_lt bounded full.capacity_le_states

theorem appendLogical.full_workspace
    (status : (appendLogical capacity position seed before).1.status = .full) :
    WorkspaceFull capacity before (appendLogical capacity position seed before).1.stateCount := by
  refine ⟨appendLogical_stateCount_of_full status, ?_⟩
  rw [appendLogical_stateCount_of_full status]
  unfold appendLogical at status
  split at status
  · contradiction
  · split at status
    next full => exact full
    next => contradiction

end Lanius.Compiler.Parser
