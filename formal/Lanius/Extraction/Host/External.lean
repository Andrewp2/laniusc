import Lanius.CallContracts.Host

namespace Lanius.Extraction.Host

open Lanius.Core Lanius.Semantics

/-- A checked external declaration, shared by input services. The complete
Core program supplies static typing; this checks the evaluator's dispatch and
parameter-binding boundary. -/
structure CheckedExternal (program : Program) (service : HostService) (arity : Nat) where
  function : Function
  found : program.function? function.id = some function
  noBody : function.body = none
  host : function.external = some (.host service)
  parameterCount : function.parameters.length = arity

def checkExternal? (program : Program) (service : HostService) (arity : Nat) (id : FunctionId) :
    Option (CheckedExternal program service arity) :=
  match found : program.function? id with
  | none => none
  | some function =>
      if shape : function.body = none ∧ function.external = some (.host service) ∧
          function.parameters.length = arity then
        some ⟨function, by
          have identity : function.id = id := by simpa using (List.find?_some found)
          simpa only [identity] using found, shape.1, shape.2.1, shape.2.2⟩
      else none

theorem CheckedExternal.bindings (checked : CheckedExternal program service arity)
    (values : List Value) (count : values.length = arity) :
    ∃ bindings, bindParameters checked.function.parameters values = some bindings := by
  simp only [bindParameters, checked.parameterCount, count, BEq.rfl, ite_true]
  exact ⟨_, rfl⟩

end Lanius.Extraction.Host
