import Lanius.Extraction.Host.Copy
import Lanius.Extraction.Host.External
import Lanius.Extraction.Host.Arguments

namespace Lanius.Extraction.Host.Arguments

open Lanius.Core Lanius.Semantics Lanius.Memory Lanius.Properties Lanius.CallContracts

/-- The selected argument is copied as bytes, not characters. A shorter
destination gets exactly the requested prefix; the return count agrees. -/
theorem copyExact (selected : world.arguments[index]? = some argument)
    (stored : heap.storeBytes pointer ((Lanius.World.utf8Bytes argument).take capacity) = .ok copied) :
    Lanius.World.call heap world .argRead [.signed .i32 (index : Nat), .pointer pointer, .unsigned .usize capacity] =
      .returned (Lanius.World.i32Result ((Lanius.World.utf8Bytes argument).take capacity).length)
        copied (Lanius.World.record world .argRead) := by
  have nonnegative : ¬ (index : Int) < 0 := by omega
  simp only [Lanius.World.call, Lanius.World.callSimple, Lanius.World.record, nonnegative, if_false,
    Int.toNat_natCast, selected, Lanius.World.copyToHeap]
  have taken : (Lanius.World.utf8Bytes argument).take (min capacity (Lanius.World.utf8Bytes argument).length) =
      (Lanius.World.utf8Bytes argument).take capacity := by rw [← List.take_take, List.take_length]
  rw [taken, stored]
  simp only [List.length_take]

theorem evaluatesRead (checked : CheckedExternal program .argRead 3)
    (initial : Allocation.Registry before) (index capacity : Nat) (argument : String)
    (selected : before.world.arguments[index]? = some argument)
    (member : view ∈ before.i32ArrayViews) (room : capacity ≤ view.length * 4)
    (bounded : capacity ≤ 2147483647)
    (argumentsResult : ArgumentsEvaluateTo program caller arguments
      [.signed .i32 index, .pointer view.address, .unsigned .usize capacity] before) :
    ∃ after, Evaluates program caller (.call checked.function.id arguments)
        (.signed .i32 ((Lanius.World.utf8Bytes argument).take capacity).length) after ∧
      Allocation.Registry after ∧ Frame before after ∧ after.world = Lanius.World.record before.world .argRead ∧
      Copied view ((Lanius.World.utf8Bytes argument).take capacity) after ∧
      PreservesViews before after (I32ViewRangesDisjoint view) := by
  obtain ⟨bindings, bound⟩ := checked.bindings [.signed .i32 index, .pointer view.address, .unsigned .usize capacity] rfl
  apply evaluatesCopy initial argumentsResult checked.found bound checked.noBody checked.host member
    (Nat.le_trans (List.length_take_le _ _) room)
  intro heap copied stored
  simpa only [i32Result_nat (Nat.le_trans (List.length_take_le _ _) bounded)] using copyExact selected stored

end Lanius.Extraction.Host.Arguments
