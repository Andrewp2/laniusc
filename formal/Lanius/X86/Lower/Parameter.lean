import Lanius.Core.Equality
import Lanius.CallContracts
import Lanius.X86.Buffer.Reservation

namespace Lanius.X86.Lower.Parameter

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.CallContracts

def body (localId : VarId) (trailingSkip : Bool) : Stmt :=
  let returned := Stmt.returnValue (some (.local localId))
  if trailingSkip then .sequence returned .skip else returned

/-- Exact Core input to the first lowering case. This record is not a
substitute IR semantics: its body and parameters are those of `function`. -/
structure Checked (function : Function) where
  position : Fin function.parameters.length
  registerArguments : function.parameters.length ≤ 6
  types : ∀ parameter ∈ function.parameters, parameter.2 = .scalar (.signed .i32)
  distinct : (function.parameters.map Prod.fst).Nodup
  idsBound : ∀ parameter ∈ function.parameters, parameter.1 ≤ 2147483647
  functionIdBound : function.id ≤ 2147483647
  resultType : function.returnType = .scalar (.signed .i32)
  internal : function.external = none
  trailingSkip : Bool
  bodyExact : function.body = some (body (function.parameters.get position).1 trailingSkip)

def check? (function : Function) : Option (Checked function) := do
  let actual ← function.body
  let (localId, trailingSkip) ← match actual with
    | .returnValue (some (.local id)) => some (id, false)
    | .sequence (.returnValue (some (.local id))) .skip => some (id, true)
    | _ => none
  let position := function.parameters.findIdx (fun parameter => parameter.1 == localId)
  if positionBound : position < function.parameters.length then
    if registerArguments : function.parameters.length ≤ 6 then
      if types : ∀ parameter ∈ function.parameters, parameter.2 = .scalar (.signed .i32) then
        if distinct : (function.parameters.map Prod.fst).Nodup then
          if idsBound : ∀ parameter ∈ function.parameters, parameter.1 ≤ 2147483647 then
            if functionIdBound : function.id ≤ 2147483647 then
              if resultType : function.returnType = .scalar (.signed .i32) then
                if internal : function.external = none then
                  let position : Fin function.parameters.length := ⟨position, positionBound⟩
                  let expected := body (function.parameters.get position).1 trailingSkip
                  match present : function.body with
                  | none => none
                  | some actual => do
                      let equal ← Core.Equality.statement? actual expected
                      pure ⟨position, registerArguments, types, distinct, idsBound, functionIdBound,
                        resultType, internal, trailingSkip, present.trans (congrArg some equal.equal)⟩
                else none
              else none
            else none
          else none
        else none
      else none
    else none
  else none

/-- Serialize the actual Core function as data for the Lanius backend.
The executable compiler, not this serializer, must identify the parameter
and choose its machine register. No native instructions are emitted here. -/
def Checked.words (checked : Checked function) : List Int :=
  [1, 64, (function.id : Int), 1, (function.parameters.length : Int), if checked.trailingSkip then 6 else 4] ++
    function.parameters.flatMap (fun parameter => [(parameter.1 : Int), 1]) ++
    (if checked.trailingSkip then [2] else []) ++
    [10, 1, 1, ((function.parameters.get checked.position).1 : Int)] ++
    (if checked.trailingSkip then [0] else [])

theorem Checked.executes (checked : Checked function) (program : Program)
    (found : before.local? (function.parameters.get checked.position).1 = some value) :
    Executes program before (body (function.parameters.get checked.position).1 checked.trailingSkip)
      (.returned (some value)) before := by
  have run := executesReturnValue (Buffer.local_evaluates program found)
  cases checked.trailingSkip <;> simp only [body, Bool.false_eq_true, ↓reduceIte]
  · exact run
  · exact executesSequenceReturned run

end Lanius.X86.Lower.Parameter
