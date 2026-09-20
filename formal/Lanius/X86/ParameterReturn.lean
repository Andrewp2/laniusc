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

theorem machine_returns (position : Fin 6) (before : Machine.State)
    (loaded : Machine.CodeAt before.memory before.rip (bytes position)) :
    ∃ middle after, Machine.Step before middle ∧ Machine.Step middle after ∧
      after.registers 0 = ((before.registers (argumentRegister position)).setWidth 32).setWidth 64 ∧
      after.rip = Machine.read64 before.memory (before.registers 4) ∧
      after.registers 4 = before.registers 4 + 8 ∧
      (∀ register, register ≠ 0 → register ≠ 4 →
        after.registers register = before.registers register) ∧
      after.memory = before.memory ∧ after.flags = before.flags := by
  let middle := before.move32 0 (argumentRegister position) (moveBytes position).length
  let after := middle.returnNear
  refine ⟨middle, after,
    .decoded (moveBytes position) loaded.prefix _ _ (move_decodes position) rfl,
    .decoded [195] loaded.suffix .returnNear 1 rfl rfl, ?_, ?_, ?_, ?_, rfl, rfl⟩
  · simp [after, middle, Machine.State.returnNear, Machine.State.move32]
  · simp [after, middle, Machine.State.returnNear, Machine.State.move32]
  · simp [after, middle, Machine.State.returnNear, Machine.State.move32]
  · intro register notResult notStack
    simp [after, middle, Machine.State.returnNear, Machine.State.move32, notResult, notStack]

def Supported.argument (checked : Supported function) : Fin 6 :=
  ⟨checked.position.val, Nat.lt_of_lt_of_le checked.position.isLt checked.atMostSix⟩

theorem Supported.executes (checked : Supported function) (program : Program)
    (before : Lanius.Semantics.State) (value : Value)
    (found : before.local? (function.parameters.get checked.position).1 = some value) :
    Executes program before
        (body (function.parameters.get checked.position).1 checked.trailingSkip)
        (.returned (some value)) before := by
  cases trailing : checked.trailingSkip with
  | false =>
      refine ⟨2, ?_⟩
      simp only [body, trailing, Bool.false_eq_true, ↓reduceIte]
      exact execStmt_return 1 program before (.local (function.parameters.get checked.position).1)
        value before (evalExpr_local_of_local? 0 program before
          (function.parameters.get checked.position).1 value found)
  | true =>
      refine ⟨3, ?_⟩
      simp only [body, trailing, ↓reduceIte]
      apply execStmt_sequence_completed 2 program before
        (.returnValue (some (.local (function.parameters.get checked.position).1))) .skip
        (.returned (some value)) before
      · exact execStmt_return 1 program before
          (.local (function.parameters.get checked.position).1) value before
          (evalExpr_local_of_local? 0 program before
            (function.parameters.get checked.position).1 value found)
      · simp

/- This is the connected Core-to-machine contract. `bytesExact` is an
   authentication premise for bytes supplied by an external emitter; it is
   deliberately not a theorem about executing backend/parameter.lani itself. -/
theorem Supported.preserves (checked : Supported function) (program : Program)
    (coreBefore : Lanius.Semantics.State) (machineBefore : Machine.State) (value : Int)
    (localValue : coreBefore.local? (function.parameters.get checked.position).1 =
      some (.signed .i32 value))
    (represented : ((machineBefore.registers (argumentRegister checked.argument)).setWidth 32).toInt = value)
    (emitted : List UInt8) (bytesExact : emitted = bytes checked.argument)
    (loaded : Machine.CodeAt machineBefore.memory machineBefore.rip emitted)
    (returnAddress : Machine.Address)
    (poppedReturn : Machine.read64 machineBefore.memory (machineBefore.registers 4) =
      returnAddress) :
    function.body = some (body (function.parameters.get checked.position).1 checked.trailingSkip) ∧
    Executes program coreBefore
        (body (function.parameters.get checked.position).1 checked.trailingSkip)
        (.returned (some (.signed .i32 value))) coreBefore ∧
      ∃ middle after, Machine.Step machineBefore middle ∧ Machine.Step middle after ∧
        ((after.registers 0).setWidth 32).toInt = value ∧
        after.rip = returnAddress ∧ after.registers 4 = machineBefore.registers 4 + 8 ∧
        (∀ register, register ≠ 0 → register ≠ 4 →
          after.registers register = machineBefore.registers register) ∧
        after.memory = machineBefore.memory ∧ after.flags = machineBefore.flags := by
  refine ⟨checked.bodyExact,
    checked.executes program coreBefore (.signed .i32 value) localValue, ?_⟩
  rw [bytesExact] at loaded
  obtain ⟨middle, after, first, second, result, target, stack, frame, memory, flags⟩ :=
    machine_returns checked.argument machineBefore loaded
  refine ⟨middle, after, first, second, ?_, target.trans poppedReturn, stack, frame, memory, flags⟩
  rw [result]
  simpa using represented

end Lanius.X86.ParameterReturn
