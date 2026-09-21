import Lanius.X86.Machine.Encoding
import Lanius.X86.Transport
import Lanius.Semantics.Rules

namespace Lanius.X86.ParameterReturn

open Lanius Lanius.Core Lanius.Semantics
open Lanius.X86.Transport Lanius.X86.Machine

/- The small Core fragment accepted by backend/parameter.lani.  This is a
   source-side contract; it does not run, or assume the correctness of, that
   Lanius emitter. -/
def body (localId : VarId) (trailingSkip : Bool) : Stmt :=
  let returned := Stmt.returnValue (some (.local localId))
  if trailingSkip then .sequence returned .skip else returned

structure Supported (function : Function) where
  position : Fin function.parameters.length
  atMostSix : function.parameters.length ≤ 6
  allI32 : ∀ parameter ∈ function.parameters,
    parameter.2 = .scalar (.signed .i32)
  parameterIdsDistinct : (function.parameters.map Prod.fst).Nodup
  -- The transport is a signed-i32 word stream, so Core IDs must survive it.
  parameterIdsBound : ∀ parameter ∈ function.parameters, parameter.1 ≤ 2147483647
  functionIdBound : function.id ≤ 2147483647
  resultI32 : function.returnType = .scalar (.signed .i32)
  internal : function.external = none
  trailingSkip : Bool
  bodyExact : function.body = some (body (function.parameters.get position).1 trailingSkip)

private theorem encodedParameters_i32 (parameters : List (VarId × Ty))
    (types : ∀ parameter ∈ parameters, parameter.2 = .scalar (.signed .i32)) :
    parameters.mapM (fun (id, type) => do
      return [Int.ofNat id, ← typeTag type]) =
      some (parameters.map fun parameter => [Int.ofNat parameter.1, 1]) := by
  let f : (VarId × Ty) → Option (List Int) := fun (id, type) => do
    return [Int.ofNat id, ← typeTag type]
  let g : (VarId × Ty) → List Int := fun p => [Int.ofNat p.1, 1]
  have loopExact : ∀ (xs : List (VarId × Ty)) (acc : List (List Int)),
      (∀ parameter ∈ xs, parameter.2 = .scalar (.signed .i32)) →
      List.mapM.loop f xs acc = some (acc.reverse ++ xs.map g) := by
    intro xs
    induction xs with
    | nil =>
        intro acc _
        simp [List.mapM.loop]
    | cons head tail ih =>
        intro acc types'
        rcases head with ⟨id, type⟩
        have typeExact : type = .scalar (.signed .i32) := types' (id, type) (by simp)
        have tailTypes : ∀ parameter ∈ tail, parameter.2 = .scalar (.signed .i32) := by
          intro parameter member
          exact types' parameter (by simp [member])
        have tailRun := ih (g (id, type) :: acc) tailTypes
        change (f (id, type)).bind (fun output =>
          List.mapM.loop f tail (output :: acc)) = _
        rw [show f (id, type) = some (g (id, type)) by simp [f, g, typeExact, typeTag]]
        simp only [Option.bind_some]
        rw [tailRun]
        simp [g, List.append_assoc]
  change List.mapM f parameters = _
  simp only [List.mapM]
  simpa [f, g] using loopExact parameters [] types

private theorem encodeParameters_i32 (parameters : List (VarId × Ty))
    (types : ∀ parameter ∈ parameters, parameter.2 = .scalar (.signed .i32)) :
    encodeParameters parameters =
      some (parameters.flatMap fun parameter => [Int.ofNat parameter.1, 1]) := by
  unfold encodeParameters
  rw [encodedParameters_i32 parameters types]
  simp [List.flatMap]

theorem Supported.transport (checked : Supported function) :
    encodeFunction function =
      some ([1, 64, Int.ofNat function.id, 1, Int.ofNat function.parameters.length,
        if checked.trailingSkip then 6 else 4] ++
        function.parameters.flatMap (fun parameter => [Int.ofNat parameter.1, 1]) ++
        (if checked.trailingSkip then [2] else []) ++
        [10, 1, 1, Int.ofNat (function.parameters.get checked.position).1] ++
        (if checked.trailingSkip then [0] else [])) := by
  have parameters := encodeParameters_i32 function.parameters checked.allI32
  cases trailing : checked.trailingSkip <;>
    simp [encodeFunction, checked.bodyExact, checked.resultI32, checked.internal,
      parameters, body, encodeStmt, encodeExpr, typeTag, trailing]

/- SysV AMD64 integer argument registers, in the order used by
   backend/parameter.lani (these are architectural register indices). -/
def argumentRegister (position : Fin 6) : Machine.Register :=
  match position.val with
  | 0 => ⟨7, by decide⟩ | 1 => ⟨6, by decide⟩ | 2 => ⟨2, by decide⟩
  | 3 => ⟨1, by decide⟩ | 4 => ⟨8, by decide⟩ | _ => ⟨9, by decide⟩

def moveBytes (position : Fin 6) : List UInt8 :=
  let register := (argumentRegister position).val
  if register < 8 then [137, UInt8.ofNat (192 + register * 8)]
  else [68, 137, UInt8.ofNat (192 + (register - 8) * 8)]

def bytes (position : Fin 6) : List UInt8 := moveBytes position ++ [195]

theorem move_decodes (position : Fin 6) :
    Machine.decode (moveBytes position) =
      some (.move32 0 (argumentRegister position), (moveBytes position).length) := by
  revert position
  decide

def Supported.argument (checked : Supported function) : Fin 6 :=
  ⟨checked.position.val, Nat.lt_of_lt_of_le checked.position.isLt checked.atMostSix⟩

end Lanius.X86.ParameterReturn
