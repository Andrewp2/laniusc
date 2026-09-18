import Lanius.Extraction.Host.ReadOnly

namespace Lanius.Extraction.Host

open Lanius.Core Lanius.Semantics Lanius.CallContracts

structure CheckedLength (program : Program) where
  function : Function
  found : program.function? function.id = some function
  noBody : function.body = none
  host : function.external = some (.host .argLen)
  parametersBound : ∀ index : Nat, ∃ bindings,
    bindParameters function.parameters [.signed .i32 index] = some bindings

def checkLength? (program : Program) (id : FunctionId) : Option (CheckedLength program) :=
  match found : program.function? id with
  | none => none
  | some function =>
      if shape : function.body = none ∧ function.external = some (.host .argLen) ∧
          function.parameters.length = 1 then
        some ⟨function, by
          have identity : function.id = id := by simpa using (List.find?_some found)
          simpa only [identity] using found,
          shape.1, shape.2.1, by
            intro index
            simp only [bindParameters, shape.2.2, List.length_cons, List.length_nil,
              Nat.reduceAdd, BEq.rfl, ite_true]
            exact ⟨_, rfl⟩⟩
      else none

theorem i32Result_nat (bounded : count ≤ 2147483647) :
    Lanius.World.i32Result (count : Nat) = .signed .i32 count := by
  have lower : (0 : Int) ≤ count := Int.natCast_nonneg _
  have upper : (count : Int) < 2 ^ 32 := by omega
  have sign : ¬ (count : Int) ≥ 2 ^ 31 := by omega
  simp only [Lanius.World.i32Result, Lanius.World.wrapI32,
    Int.emod_eq_of_lt lower upper, if_neg sign]

/-- The returned length is the selected argument's UTF-8 byte count. This
includes both synchronization passes with a nonempty buffer registry. -/
theorem CheckedLength.evaluates (checked : CheckedLength program) (initial : Allocation.Registry before)
    (index : Nat) (argument : String)
    (selected : before.world.arguments[index]? = some argument)
    (bounded : argument.toUTF8.size ≤ 2147483647)
    (argumentsResult : ArgumentsEvaluateTo program caller arguments [.signed .i32 index] before) :
    ∃ after, Evaluates program caller (.call checked.function.id arguments)
        (.signed .i32 argument.toUTF8.size) after ∧
      Allocation.Registry after ∧ Frame before after ∧
      after.world = Lanius.World.record before.world .argLen ∧ PreservesViews before after (fun _ => True) := by
  obtain ⟨bindings, bound⟩ := checked.parametersBound index
  have call (ready : State) (synced : syncI32ViewsToHeap before = .ok ready) :
      Lanius.World.call ready.heap ready.world .argLen [.signed .i32 index] =
      .returned (.signed .i32 argument.toUTF8.size) ready.heap (Lanius.World.record before.world .argLen) := by
    rw [Lanius.Properties.syncI32ViewsToHeap_preserves_world synced]
    have nonnegative : ¬ (index : Int) < 0 := by omega
    simp only [Lanius.World.call, Lanius.World.callSimple, Lanius.World.record,
      nonnegative, if_false, Int.toNat_natCast, selected, i32Result_nat bounded]
  obtain ⟨after, evaluated, registered, frame, world⟩ :=
    evaluatesReadOnly initial argumentsResult checked.found bound checked.noBody checked.host call
  refine ⟨after, evaluated, registered, frame, world, ?_⟩
  intro disjoint kept member _ words contents range
  exact readOnlyPreservesView initial argumentsResult checked.found bound checked.noBody checked.host
    call disjoint member contents range evaluated

end Lanius.Extraction.Host
