import Lanius.X86.ExpressionCheck
import Lanius.X86.ParameterReturn

namespace Lanius.X86.LocalExpressionCheck

open Lanius Lanius.Core Lanius.Semantics
open Lanius.X86
open Lanius.X86.Machine
open Lanius.X86.ExpressionCheck

/- A local's authenticated machine location.  The register case is the
   parameter ABI; the frame case is the dynamic-local backend protocol. -/
inductive Location where
  | register (register : Register)
  | frame (slot : Nat)

def Location.bodyBytes : Location → List UInt8
  | Location.register reg => moveBytes .w32 ScalarValidator.resultRegister reg
  | Location.frame slot => frameLoadBytes slot

structure Environment (coreBefore : Semantics.State) (machineBefore : Machine.State) where
  id : VarId
  location : Location
  value : Int
  localValue : coreBefore.local? id = some (.signed .i32 value)
  /-- A frame location is bounded by the authenticated allocation window. -/
  frameSlots : Nat
  frameBound : ∀ slot, location = .frame slot → slot < frameSlots
  registerSafe : ∀ register, location = .register register →
    register ≠ ScalarValidator.resultRegister ∧ register ≠ rspRegister
  /-- The same i32 value is present at the authenticated ABI/frame location. -/
  representedRegister : ∀ reg, location = Location.register reg →
    ((machineBefore.registers reg).setWidth 32).toInt = value
  representedFrame : ∀ slot, location = Location.frame slot →
    (read32 machineBefore.memory
      (frameSlotAddress (machineBefore.registers rbpRegister) slot)).toInt = value

/- The same relation is the environment carried by a structural function body:
   a Core local and its authenticated scalar frame slot.  Keep the existing
   parameter/local certificate relation as the single source of truth. -/
abbrev BodyEnvironment := Environment

structure Supported (environment : Environment coreBefore machineBefore)
    (source : Core.Expr) (emitted : List UInt8) where
  id : VarId
  location : Location
  idExact : id = environment.id
  locationExact : location = environment.location
  sourceExact : source = .local environment.id
  bytesExact : emitted = environment.location.bodyBytes

theorem ofInt32_toInt_of_representation {bits : BitVec 32} {value : Int}
    (represented : bits.toInt = value) :
    (BitVec.ofInt 32 value).toInt = value := by
  have lower : -2 ^ 31 ≤ value := by
    simpa [represented] using BitVec.le_toInt bits
  have upper : value < 2 ^ 31 := by
    simpa [represented] using (BitVec.toInt_lt (x := bits))
  exact BitVec.toInt_ofInt_eq_self (by decide) lower upper

theorem bits_eq_ofInt32_of_representation {bits : BitVec 32} {value : Int}
    (represented : bits.toInt = value) :
    bits = BitVec.ofInt 32 value := by
  have valueToInt := ofInt32_toInt_of_representation represented
  apply BitVec.eq_of_toInt_eq
  rw [valueToInt]
  exact represented

theorem Environment.value_toInt
    (environment : Environment coreBefore machineBefore) :
    (BitVec.ofInt 32 environment.value).toInt = environment.value := by
  cases location : environment.location with
  | register reg =>
      exact ofInt32_toInt_of_representation
        (environment.representedRegister reg location)
  | frame slot =>
      exact ofInt32_toInt_of_representation
        (environment.representedFrame slot location)

theorem argumentRegister_safe (position : Fin 6) :
    ParameterReturn.argumentRegister position ≠ ScalarValidator.resultRegister ∧
      ParameterReturn.argumentRegister position ≠ rspRegister := by
  revert position
  decide

theorem parameter_moveBytes (position : Fin 6) :
    ParameterReturn.moveBytes position =
      Machine.moveBytes .w32 ScalarValidator.resultRegister
        (ParameterReturn.argumentRegister position) := by
  revert position
  decide

def Environment.parameter
    {function : Function} (checked : ParameterReturn.Supported function)
    (value : Int) (localValue : coreBefore.local?
      (function.parameters.get checked.position).1 =
      some (.signed .i32 value))
    (represented : ((machineBefore.registers
      (ParameterReturn.argumentRegister checked.argument)).setWidth 32).toInt = value) :
    Environment coreBefore machineBefore :=
  { id := (function.parameters.get checked.position).1
    location := .register (ParameterReturn.argumentRegister checked.argument)
    value := value
    localValue := localValue
    frameSlots := 0
    frameBound := by
      intro slot h
      cases h
    registerSafe := by
      intro reg h
      have regExact : reg = ParameterReturn.argumentRegister checked.argument := by
        cases h
        rfl
      subst reg
      exact argumentRegister_safe checked.argument
    representedRegister := by
      intro reg h
      have regExact : reg = ParameterReturn.argumentRegister checked.argument := by
        cases h
        rfl
      subst reg
      exact represented
    representedFrame := by
      intro slot h
      cases h }

def check (environment : Environment coreBefore machineBefore)
    (source : Core.Expr) (emitted : List UInt8) :
    Option (Supported environment source emitted) :=
  match source with
  | .local id =>
      if idExact : id = environment.id then
        if bytesExact : emitted = environment.location.bodyBytes then
          some {
            id := id
            location := environment.location
            idExact := idExact
            locationExact := rfl
            sourceExact := by simp [idExact]
            bytesExact := bytesExact }
        else none
      else none
  | _ => none

theorem check_sound {environment : Environment coreBefore machineBefore}
    {source : Core.Expr} {emitted : List UInt8}
    {checked : Supported environment source emitted}
    (accepted : check environment source emitted = some checked) :
    check environment source emitted = some checked ∧
      source = .local environment.id ∧ emitted = environment.location.bodyBytes := by
  exact ⟨accepted, checked.sourceExact, checked.bytesExact⟩

/- The local body theorem consumes only authenticated bytes and the actual
   Core local lookup/value relation.  It does not accept a claimed child
   result or post-state. -/
theorem preserves {environment : Environment coreBefore machineBefore}
    {source : Core.Expr} {emitted : List UInt8}
    (checked : Supported environment source emitted) (program : Program)
    (loaded : CodeAt machineBefore.memory machineBefore.rip emitted) :
    ∃ after, Executes program coreBefore
        (.returnValue (some source))
        (.returned (some (.signed .i32 environment.value))) coreBefore ∧
      Step machineBefore after ∧
      after.registers ScalarValidator.resultRegister =
        (BitVec.ofInt 32 environment.value).setWidth 64 ∧
      after.rip = machineBefore.rip +
        BitVec.ofNat 64 environment.location.bodyBytes.length ∧
      after.registers rspRegister = machineBefore.registers rspRegister ∧
      (∀ register, register ≠ ScalarValidator.resultRegister →
        register ≠ rspRegister →
        after.registers register = machineBefore.registers register) ∧
      after.memory = machineBefore.memory ∧ after.flags = machineBefore.flags := by
  have localEval := evalExpr_local_of_local? 0 program coreBefore environment.id
    (.signed .i32 environment.value) environment.localValue
  have coreRun := execStmt_return 1 program coreBefore (.local environment.id)
    (.signed .i32 environment.value) coreBefore localEval
  have coreProof : Executes program coreBefore
      (.returnValue (some source))
      (.returned (some (.signed .i32 environment.value))) coreBefore := by
    exact ⟨2, by simpa [checked.sourceExact] using coreRun⟩
  cases location : environment.location with
    | register reg =>
        let bytes := moveBytes .w32 ScalarValidator.resultRegister reg
        let after := machineBefore.move32 ScalarValidator.resultRegister reg bytes.length
        have bodyLoaded : CodeAt machineBefore.memory machineBefore.rip bytes := by
          simpa [checked.bytesExact, Location.bodyBytes, location, bytes] using loaded
        have moved := move_step machineBefore after .w32
          ScalarValidator.resultRegister reg bodyLoaded (by rfl)
        refine ⟨after, coreProof, moved, ?_, ?_, ?_, ?_, rfl, rfl⟩
        · have represented := congrArg (fun value : BitVec 32 => value.setWidth 64)
            (show (machineBefore.registers reg).setWidth 32 = BitVec.ofInt 32 environment.value
              from bits_eq_ofInt32_of_representation
                (environment.representedRegister reg location))
          simpa [after, Machine.State.move32, ScalarValidator.resultRegister, location] using
            represented
        · simp [after, Machine.State.move32, ScalarValidator.resultRegister,
            Location.bodyBytes, location, bytes]
        · have resultNe : rspRegister ≠ ScalarValidator.resultRegister := by decide
          simp [after, Machine.State.move32, ScalarValidator.resultRegister, rspRegister,
            resultNe]
        · intro other notResult notStack
          have otherNe : other ≠ 0 := by
            simpa [ScalarValidator.resultRegister] using notResult
          simp [after, Machine.State.move32, ScalarValidator.resultRegister,
            otherNe]
    | frame slot =>
        let bytes := frameLoadBytes slot
        let after := machineBefore.load32 ScalarValidator.resultRegister rbpRegister
          (BitVec.ofInt 32 (frameDisplacement slot)) bytes.length
        have bodyLoaded : CodeAt machineBefore.memory machineBefore.rip bytes := by
          simpa [checked.bytesExact, Location.bodyBytes, location, bytes] using loaded
        have loadedStep := frameLoad_step machineBefore after slot bodyLoaded (by rfl)
        refine ⟨after, coreProof, loadedStep, ?_, ?_, ?_, ?_, rfl, rfl⟩
        · have represented := congrArg (fun value : BitVec 32 => value.setWidth 64)
            (show read32 machineBefore.memory
                (frameSlotAddress (machineBefore.registers rbpRegister) slot) =
                BitVec.ofInt 32 environment.value
              from bits_eq_ofInt32_of_representation
                (environment.representedFrame slot location))
          simpa [after, Machine.State.load32, Machine.State.immediate32,
            ScalarValidator.resultRegister, frameSlotAddress, location] using represented
        · simpa [after, Machine.State.load32, Machine.State.immediate32,
            Location.bodyBytes, location, bytes]
        · rfl
        · intro other notResult notStack
          have otherNe : other ≠ 0 := by
            simpa [ScalarValidator.resultRegister] using notResult
          simp [after, Machine.State.load32, Machine.State.immediate32,
            ScalarValidator.resultRegister, otherNe]
/- The register-location instance composes directly with RET, recovering the
   established parameter-return machine trace through the shared local body
   theorem rather than a second local-copy proof. -/
theorem parameter_function
    (position : Fin 6) (environment : Environment coreBefore machineBefore)
    (location : environment.location = .register (ParameterReturn.argumentRegister position))
    (program : Program)
    {source : Core.Expr} {emitted : List UInt8}
    (checked : Supported environment source emitted)
    (loaded : CodeAt machineBefore.memory machineBefore.rip
      (emitted ++ Machine.returnBytes)) :
    ∃ middle after, Executes program coreBefore
        (.returnValue (some source))
        (.returned (some (.signed .i32 environment.value))) coreBefore ∧
      Step machineBefore middle ∧ Step middle after ∧
      after.registers ScalarValidator.resultRegister =
        (BitVec.ofInt 32 environment.value).setWidth 64 ∧
      after.rip = read64 machineBefore.memory (machineBefore.registers rspRegister) ∧
      after.registers rspRegister = machineBefore.registers rspRegister + 8 ∧
      (∀ register, register ≠ ScalarValidator.resultRegister →
        register ≠ rspRegister →
        after.registers register = machineBefore.registers register) ∧
      after.memory = machineBefore.memory ∧ after.flags = machineBefore.flags := by
  have bodyLoaded : CodeAt machineBefore.memory machineBefore.rip emitted := loaded.prefix
  obtain ⟨middle, core, bodyStep, bodyResult, bodyRip, bodyRsp, bodyPreserved,
      bodyMemory, bodyFlags⟩ :=
    preserves checked program bodyLoaded
  have returnLoaded : CodeAt middle.memory middle.rip Machine.returnBytes := by
    have suffix := loaded.suffix
    rw [checked.bytesExact, location] at suffix
    have bodyRip' := bodyRip
    rw [location] at bodyRip'
    rw [← bodyMemory, ← bodyRip'] at suffix
    simpa using suffix
  let after := middle.returnNear
  have returnStep := return_step middle after returnLoaded (by rfl)
  refine ⟨middle, after, core, bodyStep, returnStep, ?_, ?_, ?_, ?_, bodyMemory, bodyFlags⟩
  · simpa [after, Machine.State.returnNear, Machine.State.move32,
      ScalarValidator.resultRegister, rspRegister] using bodyResult
  · change read64 middle.memory (middle.registers rspRegister) =
      read64 machineBefore.memory (machineBefore.registers rspRegister)
    rw [bodyMemory, bodyRsp]
  · change middle.registers rspRegister + 8 = machineBefore.registers rspRegister + 8
    rw [bodyRsp]
  · intro register notResult notStack
    have preserved := bodyPreserved register notResult notStack
    have registerNe : register ≠ 4 := by
      simpa [rspRegister] using notStack
    simpa [after, Machine.State.returnNear, ScalarValidator.resultRegister,
      rspRegister, registerNe] using preserved

/- The generic local theorem now feeds the existing ParameterReturn function
   shape, including its optional trailing skip. -/
theorem parameter_supported
    {function : Function} (checked : ParameterReturn.Supported function)
    (environment : Environment coreBefore machineBefore)
    (idExact : environment.id = (function.parameters.get checked.position).1)
    (location : environment.location =
      .register (ParameterReturn.argumentRegister checked.argument))
    (program : Program)
    {source : Core.Expr} {emitted : List UInt8}
    (bodyChecked : Supported environment source emitted)
    (loaded : CodeAt machineBefore.memory machineBefore.rip
      (emitted ++ Machine.returnBytes)) :
    function.body = some
        (ParameterReturn.body (function.parameters.get checked.position).1
          checked.trailingSkip) ∧
      ∃ middle after, Executes program coreBefore
          (ParameterReturn.body (function.parameters.get checked.position).1
            checked.trailingSkip)
          (.returned (some (.signed .i32 environment.value))) coreBefore ∧
        Step machineBefore middle ∧ Step middle after ∧
        after.registers ScalarValidator.resultRegister =
          (BitVec.ofInt 32 environment.value).setWidth 64 ∧
        after.rip = read64 machineBefore.memory (machineBefore.registers rspRegister) ∧
        after.registers rspRegister = machineBefore.registers rspRegister + 8 ∧
        (∀ register, register ≠ ScalarValidator.resultRegister →
          register ≠ rspRegister →
          after.registers register = machineBefore.registers register) ∧
        after.memory = machineBefore.memory ∧ after.flags = machineBefore.flags := by
  refine ⟨checked.bodyExact, ?_⟩
  obtain ⟨middle, after, core, bodyStep, returnStep, result, rip, stack,
      preserved, memory, flags⟩ :=
    parameter_function checked.argument environment location program bodyChecked loaded
  have core' : Executes program coreBefore
      (.returnValue (some
        (.local (function.parameters.get checked.position).1)))
      (.returned (some (.signed .i32 environment.value))) coreBefore := by
    simpa [bodyChecked.sourceExact, idExact] using core
  rcases core' with ⟨fuel, coreRun⟩
  refine ⟨middle, after, ?_, bodyStep, returnStep, result, rip, stack,
    preserved, memory, flags⟩
  cases trailing : checked.trailingSkip with
  | false =>
      exact ⟨fuel, by simpa [ParameterReturn.body, trailing] using coreRun⟩
  | true =>
      refine ⟨fuel.succ, ?_⟩
      simp only [ParameterReturn.body, trailing, ↓reduceIte]
      apply execStmt_sequence_completed fuel program coreBefore
        (.returnValue (some (.local (function.parameters.get checked.position).1)))
        .skip (.returned (some (.signed .i32 environment.value))) coreBefore
      · exact coreRun
      · simp

/- Public parameter-return projection used by [ProgramCheck.Preserves].  The
   relation keeps the authenticated fast-path bytes and the caller's popped
   return word explicit; its proof is the same Environment-based theorem as
   the local expression certificate, rather than a second preservation path. -/
def parameterResult
    {function : Function} (checked : ParameterReturn.Supported function)
    (program : Program) (coreBefore : Semantics.State)
    (machineBefore : Machine.State)
    (returnAddress : Machine.Address) : Prop :=
  CodeAt machineBefore.memory machineBefore.rip
      (ParameterReturn.bytes checked.argument) ∧
    read64 machineBefore.memory (machineBefore.registers rspRegister) = returnAddress ∧
    ∀ value, (localValue : coreBefore.local?
      (function.parameters.get checked.position).1 = some (.signed .i32 value)) →
      (represented : ((machineBefore.registers
        (ParameterReturn.argumentRegister checked.argument)).setWidth 32).toInt = value) →
      function.body = some (ParameterReturn.body (function.parameters.get checked.position).1
        checked.trailingSkip) ∧
        Executes program coreBefore
          (ParameterReturn.body (function.parameters.get checked.position).1 checked.trailingSkip)
          (.returned (some (.signed .i32 value))) coreBefore ∧
        ∃ middle after, Step machineBefore middle ∧ Step middle after ∧
          ((after.registers ScalarValidator.resultRegister).setWidth 32).toInt = value ∧
          after.rip = returnAddress ∧
          after.registers rspRegister = machineBefore.registers rspRegister + 8 ∧
          (∀ register, register ≠ ScalarValidator.resultRegister →
            register ≠ rspRegister → after.registers register = machineBefore.registers register) ∧
          after.memory = machineBefore.memory ∧ after.flags = machineBefore.flags

theorem parameter_preserves
    {function : Function} (checked : ParameterReturn.Supported function)
    (program : Program) (coreBefore : Semantics.State)
    (machineBefore : Machine.State)
    (loaded : CodeAt machineBefore.memory machineBefore.rip
      (ParameterReturn.bytes checked.argument))
    (returnAddress : Machine.Address)
    (poppedReturn : read64 machineBefore.memory
      (machineBefore.registers rspRegister) = returnAddress) :
    parameterResult checked program coreBefore machineBefore returnAddress := by
  refine ⟨loaded, poppedReturn, ?_⟩
  intro value localValue represented
  let environment := Environment.parameter checked value localValue represented
  let bodyChecked : Supported environment
      (.local (function.parameters.get checked.position).1)
      (Machine.moveBytes .w32 ScalarValidator.resultRegister
        (ParameterReturn.argumentRegister checked.argument)) := {
    id := environment.id
    location := environment.location
    idExact := rfl
    locationExact := rfl
    sourceExact := rfl
    bytesExact := by rfl }
  have loadedFull : CodeAt machineBefore.memory machineBefore.rip
      (Machine.moveBytes .w32 ScalarValidator.resultRegister
        (ParameterReturn.argumentRegister checked.argument) ++ Machine.returnBytes) := by
    simpa [ParameterReturn.bytes, parameter_moveBytes, Machine.returnBytes] using loaded
  obtain ⟨functionBody, middle, after, core, first, second, result,
      target, stack, preserved, memory, flags⟩ :=
    parameter_supported checked environment (by rfl) (by rfl) program bodyChecked loadedFull
  refine ⟨checked.bodyExact, core, ?_⟩
  refine ⟨middle, after, first, second, ?_, ?_, ?_, ?_, memory, flags⟩
  · have envValue : environment.value = value := rfl
    change (BitVec.setWidth 32
      (after.registers ScalarValidator.resultRegister)).toInt = value
    rw [result]
    simpa [envValue] using environment.value_toInt
  · exact target.trans poppedReturn
  · simpa [Machine.rspRegister] using stack
  · simpa [ScalarValidator.resultRegister, Machine.rspRegister] using preserved

end Lanius.X86.LocalExpressionCheck
