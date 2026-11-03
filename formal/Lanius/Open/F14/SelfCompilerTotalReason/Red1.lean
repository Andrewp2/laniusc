import Lanius.Open.F14.SelfCompilerTotalReason.Stmt
import Lanius.Open.F14.CostGivesSelfCost.Stmt

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.X86.Machine
open Lanius.Faithful
open Lanius.Faithful.Self
open Lanius.Faithful.SelfRep
open Lanius.Faithful.SelfDriver
open Lanius.Faithful.SelfCompiler
open Lanius.Faithful.SelfLive
open Lanius.Faithful.SelfPanics
open Lanius.Faithful.SelfAgree
open Lanius.Faithful.SelfShort
open Lanius.Faithful.Termination
open Lanius.Faithful.SelfBounded
open Lanius.Faithful.SelfTotal

/-- `selfCompiler_total_reason_of_bounds`'s proof with the wrapped compile's
cost giving the self program's a cost (`CostGivesSelfCost`) in place of
`CompileBounded`: a compile with no cost has a wrapped cost past the limit. -/
theorem Lanius.Open.SelfCompilerTotalReason.red1 (h : Lanius.Open.CostGivesSelfCost) :
    Lanius.Open.SelfCompilerTotalReason := by
  intro B compiled files fit wordsLt room limit roomLt enough small s imageBase window bounded loaded apart
    imageHeap entry params heapAt stack
  have short : (∀ fuel, Failing limit (selfRun (filesWords files) room fuel)) → SelfShortW files room limit :=
    fun fails => by
      rcases failing_short fit wordsLt roomLt (by omega) fails with panics | room | heap
      · refine .inr (.inr ⟨panics.1, costW_total _, fun N k hk => Nat.lt_of_not_le fun le => ?_⟩)
        obtain ⟨c, hc⟩ := h _ wordsLt N k hk (by omega)
        rw [panics.1 N] at hc
        cases hc
      · exact .inl room
      · exact .inr (.inl heap)
  exact (selfCompiler_outcome compiled fit wordsLt roomLt enough (by omega) s imageBase window bounded loaded
    apart imageHeap entry params heapAt stack).imp_left fun
    | .inl ⟨fails, faults⟩ => .inl ⟨fails, short fails, faults⟩
    | .inr stack => .inr stack
