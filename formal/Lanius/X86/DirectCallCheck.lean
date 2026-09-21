import Lanius.X86.Machine.ControlEncoding
import Lanius.X86.Machine.ScalarEncoding
import Lanius.Semantics.Call

namespace Lanius.X86.DirectCallCheck

open Lanius Lanius.Core Lanius.Semantics
open Lanius.X86
open Lanius.X86.Machine

/-!
  A small certificate for the direct-call fragment used by the x86 backend.

  A call and its return are deliberately authenticated separately: the return
  instruction is in the callee image, not immediately after the five-byte
  call in the caller image.  The machine theorem below therefore composes an
  actual decoded `CALL`, an explicit callee preservation witness, and an
  actual decoded `RET`.

  The supported ABI is the scalar SysV subset already used by
  `ParameterReturn`: at most six signed-i32 parameters in the usual argument
  registers and a signed-i32 result in RAX.  The caller's expression/body is
  not assumed to have succeeded; its Core call contract is supplied through
  the compositional hypotheses to `preserves`.
-/

def resultRegister : Register := 0
def stackRegister : Register := 4

def argumentRegister (position : Nat) : Register :=
  match position with
  | 0 => ⟨7, by decide⟩
  | 1 => ⟨6, by decide⟩
  | 2 => ⟨2, by decide⟩
  | 3 => ⟨1, by decide⟩
  | 4 => ⟨8, by decide⟩
  | _ => ⟨9, by decide⟩

def callBytes (displacement : BitVec 32) : List UInt8 :=
  Machine.callBytes displacement

def returnBytes : List UInt8 := Machine.returnBytes

def representedValue (machine : Machine.State) (register : Register) : Value → Prop
  | .signed .i32 value =>
      ((machine.registers register).setWidth 32).toInt = value
  | _ => False

/- This relation is intentionally independent of a caller body.  It records
   the ABI state that a direct call consumes, while `preserves` obtains the
   Core call result from the call semantics below. -/
def argumentsRepresented (machine : Machine.State) (values : List Value) : Prop :=
  ∀ index (bound : index < values.length),
    representedValue machine (argumentRegister index) values[index]

structure Supported (function : Function) : Type where
  atMostSix : function.parameters.length ≤ 6
  allI32 : ∀ parameter ∈ function.parameters,
    parameter.2 = .scalar (.signed .i32)
  resultI32 : function.returnType = .scalar (.signed .i32)
  internal : function.external = none
  bodyPresent : ∃ body, function.body = some body

private def shape? (function : Function) : Option (Supported function) :=
  match function with
  | ⟨_, parameters, returnType, some body, none⟩ =>
      if atMostSix : parameters.length ≤ 6 then
        if allI32 : ∀ parameter ∈ parameters,
            parameter.2 = .scalar (.signed .i32) then
          if resultI32 : returnType = .scalar (.signed .i32) then
            some {
              atMostSix := atMostSix
              allI32 := allI32
              resultI32 := resultI32
              internal := rfl
              bodyPresent := ⟨body, rfl⟩ }
          else none
        else none
      else none
  | _ => none

/- The target equation is the architectural rel32 equation.  It is checked
   against the caller address rather than inferred from a decoded displacement,
   so a malformed patch or target is rejected by `check`. -/
structure Checked (function : Function) (arity : Nat)
    (caller target : Machine.Address) (displacement : BitVec 32)
    (callEmitted returnEmitted : List UInt8) where
  supported : Supported function
  arityExact : arity = function.parameters.length
  callExact : callEmitted = callBytes displacement
  returnExact : returnEmitted = returnBytes
  targetExact : target = caller + BitVec.ofNat 64 (callBytes displacement).length +
    displacement.signExtend 64
  callDecoded : Machine.decode callEmitted =
    some (.call displacement, callEmitted.length)
  returnDecoded : Machine.decode returnEmitted =
    some (.returnNear, returnEmitted.length)

def check (function : Function) (arity : Nat) (caller target : Machine.Address)
    (displacement : BitVec 32) (callEmitted returnEmitted : List UInt8) :
    Option (Checked function arity caller target displacement callEmitted returnEmitted) :=
  match shape? function with
  | none => none
  | some supported =>
      if arityExact : arity = function.parameters.length then
        if callExact : callEmitted = callBytes displacement then
          if returnExact : returnEmitted = returnBytes then
            if targetExact : target = caller +
                BitVec.ofNat 64 (callBytes displacement).length +
                displacement.signExtend 64 then
              some {
                supported := supported
                arityExact := arityExact
                callExact := callExact
                returnExact := returnExact
                targetExact := targetExact
                callDecoded := by
                  rw [callExact]
                  have length : (callBytes displacement).length = 5 := by
                    simp [callBytes, Machine.callBytes, displacementBytes, wordBytes]
                  rw [length]
                  exact Machine.call_decodes displacement
                returnDecoded := by
                  rw [returnExact]
                  simpa [returnBytes] using Machine.return_decodes }
            else none
          else none
        else none
      else none

theorem check_sound {function : Function} {arity : Nat}
    {caller target : Machine.Address} {displacement : BitVec 32}
    {callEmitted returnEmitted : List UInt8}
    {checked : Checked function arity caller target displacement callEmitted returnEmitted}
    (accepted : check function arity caller target displacement callEmitted returnEmitted =
      some checked) :
    (callEmitted = callBytes displacement) ∧
      (returnEmitted = returnBytes) ∧
      (target = caller + BitVec.ofNat 64 (callBytes displacement).length +
        displacement.signExtend 64) := by
  unfold check at accepted
  split at accepted
  next _ => simp at accepted
  next supported =>
    split at accepted
    next arityExact =>
      split at accepted
      next callExact =>
        split at accepted
        next returnExact =>
          split at accepted
          next targetExact =>
            cases accepted
            exact ⟨callExact, returnExact, targetExact⟩
          next _ => simp at accepted
        next _ => simp at accepted
      next _ => simp at accepted
    next _ => simp at accepted

/- A callee witness is the only machine assumption about the body.  It is
   intentionally a preservation contract, not a claim that the caller as a
   whole executed successfully.  The call itself and the return instruction
   remain proved from their authenticated bytes below. -/
structure CalleePreservation (entry after : Machine.State)
    (target : Machine.Address) (values : List Value) (result : Int) where
  steps : ∃ count, Machine.Steps count entry after
  resultFrom : entry.rip = target → argumentsRepresented entry values →
    ((after.registers resultRegister).setWidth 32).toInt = result
  stack : after.registers stackRegister = entry.registers stackRegister
  stable : ∀ register, register ≠ resultRegister → register ≠ stackRegister →
    after.registers register = entry.registers register
  memory : after.memory = entry.memory
  flags : after.flags = entry.flags

structure MachineRun (before callAfter calleeAfter after : Machine.State)
    (displacement : BitVec 32) (calleeCount : Nat) (result : Int) where
  callStep : Machine.Step before callAfter
  calleeSteps : Machine.Steps calleeCount callAfter calleeAfter
  returnStep : Machine.Step calleeAfter after
  result : ((after.registers resultRegister).setWidth 32).toInt = result
  rip : after.rip = before.rip + BitVec.ofNat 64 (Machine.callBytes displacement).length
  stack : after.registers stackRegister = before.registers stackRegister
  stable : ∀ register, register ≠ resultRegister → register ≠ stackRegister →
    after.registers register = before.registers register
  memory : after.memory =
    Machine.write64 before.memory (before.registers stackRegister - 8)
      (before.rip + BitVec.ofNat 64 (Machine.callBytes displacement).length)
  flags : after.flags = before.flags


/- This is the connected Core-to-machine theorem.  The arguments/body/frame
   premises are exactly those consumed by `thresholdInternalCall`; no
   successful execution of an enclosing caller is assumed. -/
theorem preserves (checked : Checked function arity caller target displacement
    callEmitted returnEmitted) (program : Program)
    (coreBefore : Lanius.Semantics.State)
    (arguments : List Expr) (values : List Value) (body : Stmt)
    (bindings : List (VarId × Value))
    (afterArguments calleeState completed : Lanius.Semantics.State)
    (machineBefore callAfter calleeAfter : Machine.State)
    (result : Int)
    (ripAtCaller : machineBefore.rip = caller)
    (callAfterExact : callAfter = machineBefore.call displacement
      (Machine.callBytes displacement).length)
    (functionFound : program.function? function.id = some function)
    (bodyFound : function.body = some body)
    {argumentsFuel bodyFuel : Nat}
    (argumentsContract : ThresholdPureList argumentsFuel program coreBefore
      arguments values afterArguments)
    (parametersBind : bindParameters function.parameters values = some bindings)
    (calleeShape : calleeState =
      ({ afterArguments with locals := [] }).bindLocals bindings)
    (bodyContract : StableStmt bodyFuel program calleeState body
      (.returned (some (.signed .i32 result))) completed)
    (calleeFrame : CallerFrame coreBefore calleeState)
    (bodyFrame : PureFrame calleeState completed)
    (argumentsExact : values.length = arity)
    (argumentsConvention : argumentsRepresented machineBefore values)
    (loadedCall : Machine.CodeAt machineBefore.memory machineBefore.rip callEmitted)
    (calleePreservation : CalleePreservation callAfter calleeAfter target values result)
    (loadedReturn : Machine.CodeAt calleeAfter.memory calleeAfter.rip returnEmitted) :
    ThresholdPure (max argumentsFuel bodyFuel + 1) program coreBefore
        (.call function.id arguments) (.signed .i32 result)
        (restoreLocals coreBefore completed) ∧
      ∃ calleeCount machineAfter, MachineRun machineBefore callAfter calleeAfter machineAfter
        displacement calleeCount result := by
  have core := thresholdInternalCall program coreBefore function arguments body values bindings
    afterArguments calleeState completed (.signed .i32 result) functionFound bodyFound
    argumentsContract parametersBind calleeShape bodyContract calleeFrame bodyFrame
  obtain ⟨calleeCount, calleeSteps⟩ := calleePreservation.steps
  let machineAfter' := calleeAfter.returnNear
  have callLoaded : Machine.CodeAt machineBefore.memory machineBefore.rip
      (callBytes displacement) := by
    rw [checked.callExact] at loadedCall
    exact loadedCall
  have callStep : Machine.Step machineBefore callAfter := by
    apply Machine.call_step machineBefore callAfter displacement callLoaded
    exact callAfterExact
  have targetRip : callAfter.rip = target := by
    simp [callAfterExact, Machine.State.call, checked.targetExact, ripAtCaller,
      callBytes]
  have representedAtCallee : argumentsRepresented callAfter values := by
    intro index bound
    have valuesBound : values.length ≤ 6 := by
      rw [argumentsExact, checked.arityExact]
      exact checked.supported.atMostSix
    have indexBound : index < 6 := Nat.lt_of_lt_of_le bound valuesBound
    have registerNe : argumentRegister index ≠ stackRegister := by
      have cases : index = 0 ∨ index = 1 ∨ index = 2 ∨ index = 3 ∨
          index = 4 ∨ index = 5 := by omega
      rcases cases with rfl | rfl | rfl | rfl | rfl | rfl <;> decide
    have registerNe4 : argumentRegister index ≠ 4 := by
      simpa [stackRegister] using registerNe
    have registerValue : callAfter.registers (argumentRegister index) =
        machineBefore.registers (argumentRegister index) := by
      rw [callAfterExact]
      simp [Machine.State.call, registerNe4]
    simpa [representedValue, registerValue] using argumentsConvention index bound
  have calleeTarget : callAfter.rip = target := targetRip
  have returnLoaded' : Machine.CodeAt calleeAfter.memory calleeAfter.rip returnBytes := by
    rw [checked.returnExact] at loadedReturn
    exact loadedReturn
  have returnStep : Machine.Step calleeAfter machineAfter' := by
    apply Machine.return_step calleeAfter machineAfter' returnLoaded'
    rfl
  have resultAfter : ((machineAfter'.registers resultRegister).setWidth 32).toInt = result := by
    simpa [machineAfter', Machine.State.returnNear, resultRegister] using
      calleePreservation.resultFrom calleeTarget representedAtCallee
  have stackAfter : machineAfter'.registers stackRegister = machineBefore.registers stackRegister := by
    have stackAtCallee : calleeAfter.registers stackRegister =
        machineBefore.registers stackRegister - 8 := by
      rw [calleePreservation.stack, callAfterExact]
      simp [Machine.State.call, stackRegister]
    rw [show machineAfter'.registers stackRegister =
        calleeAfter.registers stackRegister + 8 by
          simp [machineAfter', Machine.State.returnNear, stackRegister]]
    rw [stackAtCallee]
    exact BitVec.sub_add_cancel _ _
  have stableAfter : ∀ register, register ≠ resultRegister → register ≠ stackRegister →
      machineAfter'.registers register = machineBefore.registers register := by
    intro register notResult notStack
    have notStack' : register ≠ 4 := by simpa [stackRegister] using notStack
    simp [machineAfter', Machine.State.returnNear,
      calleePreservation.stable register notResult notStack, callAfterExact,
      Machine.State.call, notStack']
  have memoryAfter : machineAfter'.memory =
      Machine.write64 machineBefore.memory
        (machineBefore.registers stackRegister - 8)
        (machineBefore.rip + BitVec.ofNat 64 (callBytes displacement).length) := by
    simp [machineAfter', Machine.State.returnNear, calleePreservation.memory,
      callAfterExact, Machine.State.call, callBytes, stackRegister]
  have flagsAfter : machineAfter'.flags = machineBefore.flags := by
    simp [machineAfter', Machine.State.returnNear, calleePreservation.flags,
      callAfterExact, Machine.State.call]
  have returnAddress : Machine.read64 calleeAfter.memory (calleeAfter.registers stackRegister) =
      machineBefore.rip + BitVec.ofNat 64 (callBytes displacement).length := by
    have stackAtCallee : calleeAfter.registers stackRegister =
        machineBefore.registers stackRegister - 8 := by
      rw [calleePreservation.stack, callAfterExact]
      simp [Machine.State.call, stackRegister]
    rw [calleePreservation.memory, stackAtCallee]
    rw [callAfterExact]
    change Machine.read64
      (Machine.write64 machineBefore.memory
        (machineBefore.registers stackRegister - 8)
        (machineBefore.rip + BitVec.ofNat 64 (Machine.callBytes displacement).length))
      (machineBefore.registers stackRegister - 8) = _
    exact Machine.read64_write64 _ _ _
  refine ⟨core, ?_⟩
  refine ⟨calleeCount, machineAfter', ?_⟩
  refine ⟨callStep, calleeSteps, returnStep, resultAfter, ?_, stackAfter,
    stableAfter, memoryAfter, flagsAfter⟩
  have returnAddress' : Machine.read64 calleeAfter.memory (calleeAfter.registers 4) =
      machineBefore.rip + BitVec.ofNat 64 (callBytes displacement).length := by
    simpa [stackRegister] using returnAddress
  simpa [machineAfter', Machine.State.returnNear, targetRip, calleeTarget, ripAtCaller,
    callBytes] using returnAddress'

end Lanius.X86.DirectCallCheck
