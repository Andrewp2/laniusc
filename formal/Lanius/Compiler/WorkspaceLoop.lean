import Lanius.Compiler.ParserModel
import Lanius.Separation

namespace Lanius.Compiler.Parser

open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.Core

universe u v

/-! ## Workspace-growing compiler loops

Several parser operations share one control contract: normal completion may
extend the logical workspace, while capacity exhaustion returns immediately.
Keeping that contract structural allows an enclosing proof to compose any of
those operations without knowing which parser algorithm produced it.
-/

/-- Result of a compiler loop that may append to a logical workspace.

`completed` carries the append closure from the caller's workspace and a
loop-specific continuation invariant. `full` carries the workspace reached
before capacity exhaustion and a representation witness for that terminal
state.  Early return is a control-flow distinction, not permission to discard
the compiler artifact already constructed. -/
inductive WorkspaceLoopOutcome
    (capacity : Nat) (beforeWorkspace : LogicalWorkspace)
    (fullCompletion : Nat → Completion)
    (Completed : LogicalWorkspace → List Int → State → Sort u)
    (Terminal : LogicalWorkspace → List Int → State → Sort v) :
    State → Completion → Prop where
  | completed
      (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (after : State)
      (growth : WorkspaceAppendClosure capacity beforeWorkspace workspace)
      (invariant : Completed workspace workspaceValues after) :
      WorkspaceLoopOutcome capacity beforeWorkspace fullCompletion Completed
        Terminal after .next
  | full
      (workspace : LogicalWorkspace) (workspaceValues : List Int)
      (after : State)
      (growth : WorkspaceAppendClosure capacity beforeWorkspace workspace)
      (terminal : Terminal workspace workspaceValues after)
      (stateCount : Nat)
      (wellFormed : StateWellFormed after) :
      WorkspaceLoopOutcome capacity beforeWorkspace fullCompletion Completed
        Terminal after (fullCompletion stateCount)

/-- Rebase a nested loop's result from an intermediate workspace to its
caller's workspace. Early returns are unchanged; normal growth composes. -/
theorem WorkspaceLoopOutcome.prepend_growth
    (firstGrowth : WorkspaceAppendClosure capacity beforeWorkspace
      middleWorkspace)
    (outcome : WorkspaceLoopOutcome capacity middleWorkspace fullCompletion
      Completed Terminal after completion) :
    WorkspaceLoopOutcome capacity beforeWorkspace fullCompletion Completed
      Terminal after completion := by
  cases outcome with
  | completed workspace workspaceValues after growth invariant =>
      exact .completed workspace workspaceValues after
        (firstGrowth.trans growth) invariant
  | full workspace workspaceValues after growth terminal stateCount wellFormed =>
      exact .full workspace workspaceValues after (firstGrowth.trans growth)
        terminal stateCount wellFormed

end Lanius.Compiler.Parser
