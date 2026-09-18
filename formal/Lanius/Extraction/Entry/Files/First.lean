import Lanius.Extraction.Entry.Startup.State
import Lanius.Extraction.Entry.Files.Source
import Lanius.Semantics.Prefix.Return

namespace Lanius.Extraction.Entry.Files
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- A first-file entry reached by the checked startup, before imposing any
path validity, file availability, file-size, or handle-freshness conditions. -/
structure First (program : Program) (main : Stmt) (argument countId : VarId)
    (body : Stmt) (allocations : Nat) (before : State) where
  state : State
  registry : Allocation.Registry state
  indexRead : state.local? argument = some (.signed .i32 1)
  countRead : state.local? countId = some (.signed .i32 before.world.arguments.length)
  enough : 1 < before.world.arguments.length
  world : state.world = { before.world with
    calls := before.world.calls ++ [.argc] ++ List.replicate allocations .alloc }
  reached : Prefix.Reaches program before main state (.whileLoop (condition argument countId) body)

/-- Preserve the already-established startup prefix instead of discarding it
when the ordinary file-loading domain cannot be constructed. -/
def CheckedSource.first
    {entry : CheckedArguments program main}
    (source : CheckedSource argument countId body header.continuation)
    (started : Startup.Ready entry sequence pointers literal data framing header before)
    (countIdentity : header.count = countId) :
    First program main argument countId body sequence.buffers.length before := {
  state := started.state.bindLocal argument (.signed .i32 1)
  registry := started.registry.bindLocal argument (.signed .i32 1)
  indexRead := bindLocal_finds_local _ _ _ started.registry.wellFormed
  countRead := (bindLocal_preserves_other_local started.registry.wellFormed source.distinct).trans
    (countIdentity ▸ started.countRead)
  enough := started.enough
  world := started.world
  reached := started.reached.trans source.reaches }

/-- A rejection in the first body completes the true loop branch and then
the actual enclosing main, closing every lexical scope on the way out. -/
theorem First.completeReturn
    (first : First program main argument countId body allocations before)
    (run : Executes program first.state body (.returned value) after) :
    ∃ final, Executes program before main (.returned value) final ∧
      ∀ caller, restoreLocals caller final = restoreLocals caller after := by
  have condition := condition_evaluates program 1 before.world.arguments.length first.indexRead first.countRead
  have different : (1 : Nat) ≠ before.world.arguments.length := Nat.ne_of_lt first.enough
  have conditionTrue : Evaluates program first.state (Files.condition argument countId)
      (.boolean true) first.state := by simpa [different] using condition
  exact first.reached.completeReturn (executesWhileReturned conditionTrue run)

end Lanius.Extraction.Entry.Files
