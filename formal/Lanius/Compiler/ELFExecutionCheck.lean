import Lanius.Compiler.EndToEndCheck
import Lanius.X86.EntrypointExitComposition
import Lanius.X86.ProcessLayoutCheck
import Lanius.X86.AuthenticatedStackFootprint

namespace Lanius.Compiler.ELFExecutionCheck

open Lanius
open Lanius.Compiler
open Lanius.Compiler.EndToEndCheck
open Lanius.X86
open Lanius.X86.Machine
open Lanius.X86.ProgramCheck
open Lanius.X86.ProcessLayoutCheck
open Lanius.X86.AuthenticatedStackFootprint
open Lanius.X86.StartupCheck
open Lanius.X86.EntrypointRefinement
open Lanius.X86.StartupExitCheck
open Lanius.X86.ExpressionCheck
open Lanius.X86.ExpressionFunctionCheck
open Lanius.X86.FunctionCheck
open Lanius.X86.ScalarValidator

/- The startup jump is selected from the authenticated entrypoint address. -/
def startupJumpDisplacement? (target : Machine.Address) : Option (BitVec 32) :=
  let base := StartupCheck.code + BitVec.ofNat 64 (jumpBytes (BitVec.ofNat 32 0)).length
  let delta : Int := Int.ofNat target.toNat - Int.ofNat base.toNat
  if _bounds : (-2147483648 : Int) ≤ delta ∧ delta < 2147483648 then
    let displacement := BitVec.ofInt 32 delta
    if target = jumpTarget displacement then some displacement else none
  else none

theorem startupJumpDisplacement_sound {target : Machine.Address} {displacement : BitVec 32}
    (accepted : startupJumpDisplacement? target = some displacement) :
    jumpTarget displacement = target := by
  dsimp [startupJumpDisplacement?] at accepted
  split at accepted
  · split at accepted
    · have equal := Option.some.inj accepted
      rw [← equal]
      symm
      assumption
    · simp_all
  · simp_all

def imageEq (left right : FunctionImage) : Bool :=
  decide (left.address = right.address ∧ left.bytes = right.bytes)

theorem imageEq_sound {left right : FunctionImage} (accepted : imageEq left right = true) :
    left = right := by
  have fields : left.address = right.address ∧ left.bytes = right.bytes :=
    of_decide_eq_true accepted
  cases left with
  | mk leftAddress leftBytes =>
      cases right with
      | mk rightAddress rightBytes =>
          simp only at fields
          cases fields.1
          cases fields.2
          rfl

/- The existential is computed from the authenticated image slices, rather than
   supplied by a runtime caller. -/
def findEntrypointSlice? (target : FunctionImage) :
    (slices : List (ImageCheck.SliceEvidence ImageCheck.lanius elf)) →
      Option { slice : ImageCheck.SliceEvidence ImageCheck.lanius elf //
        slice.image = target ∧ slice ∈ slices }
  | [] => none
  | slice :: rest =>
      if same : imageEq slice.image target then
        some ⟨slice, imageEq_sound same, by simp⟩
      else
        match findEntrypointSlice? target rest with
        | none => none
        | some found =>
            some ⟨found.1, found.2.1, by simp [found.2.2]⟩

inductive Failure where
  | endToEnd (failure : EndToEndCheck.Failure)
  | displacement
  | startup
  | jump
  | entrypoint
deriving DecidableEq, Repr

/- This is the immutable evidence produced by the checker.  In particular,
   startup/jump bytes and the selected target slice are not runtime premises. -/
structure Checked (encoded : String)
    (expectedSources : List Extraction.SourceFile)
    (resolver : optParam ProgramLowering.ExternalBehaviorResolver
      CertificateLoweringCheck.noExternalBehavior) where
  endToEnd : EndToEndCheck.Checked encoded expectedSources resolver
  endToEndAccepted :
    EndToEndCheck.check encoded expectedSources resolver = .ok endToEnd
  displacement : BitVec 32
  displacementAccepted :
    startupJumpDisplacement? endToEnd.program.entrypoint.image.address = some displacement
  startup : StartupEvidence endToEnd.certificate.certificate.certificate.elf
  startupAccepted : StartupCheck.check endToEnd.certificate.certificate.certificate.elf =
    some startup
  jump : JumpEvidence endToEnd.certificate.certificate.certificate.elf displacement
  jumpAccepted : StartupCheck.checkJump
    endToEnd.certificate.certificate.certificate.elf displacement = some jump
  entrySlice : ImageCheck.SliceEvidence ImageCheck.lanius
    endToEnd.certificate.certificate.certificate.elf
  entrySliceMember : entrySlice ∈ endToEnd.image.slices
  entrySliceExact : entrySlice.image = endToEnd.program.entrypoint.image

def check (encoded : String) (expectedSources : List Extraction.SourceFile)
    (resolver : optParam ProgramLowering.ExternalBehaviorResolver
      CertificateLoweringCheck.noExternalBehavior) :
    Except Failure (Checked encoded expectedSources resolver) :=
  match endToEndAccepted : EndToEndCheck.check encoded expectedSources resolver with
  | .error failure => .error (.endToEnd failure)
  | .ok endToEnd =>
      match displacementAccepted :
          startupJumpDisplacement? endToEnd.program.entrypoint.image.address with
      | none => .error .displacement
      | some displacement =>
          match startupAccepted :
              StartupCheck.check endToEnd.certificate.certificate.certificate.elf with
          | none => .error .startup
          | some startup =>
              match jumpAccepted : StartupCheck.checkJump
                  endToEnd.certificate.certificate.certificate.elf displacement with
              | none => .error .jump
              | some jump =>
                  match _entrypointFound : findEntrypointSlice?
                      endToEnd.program.entrypoint.image endToEnd.image.slices with
                  | none => .error .entrypoint
                  | some found =>
                      .ok {
                        endToEnd
                        endToEndAccepted
                        displacement
                        displacementAccepted
                        startup
                        startupAccepted
                        jump
                        jumpAccepted
                        entrySlice := found.1
                        entrySliceMember := found.2.2
                        entrySliceExact := found.2.1 }

/- The public runtime assumptions are the mapped ELF, the initial RIP, and
   image/stack separation.  Startup facts and the dynamic frame-window bound
   are checker-owned. -/
structure RuntimeLayout
    {encoded : String} {expectedSources : List Extraction.SourceFile}
    {resolver : optParam ProgramLowering.ExternalBehaviorResolver
      CertificateLoweringCheck.noExternalBehavior}
    (checked : Checked encoded expectedSources resolver) (before : Machine.State) where
  mapped : Machine.CodeAt before.memory ImageCheck.lanius.base
    checked.endToEnd.certificate.certificate.certificate.elf
  ripAtEntry : before.rip = StartupCheck.entry
  separation : AuthenticatedImageStackDisjoint checked.endToEnd.program
    checked.endToEnd.certificate.certificate.certificate.elf before

def processLayout
    {encoded : String} {expectedSources : List Extraction.SourceFile}
    {resolver : optParam ProgramLowering.ExternalBehaviorResolver
      CertificateLoweringCheck.noExternalBehavior}
    {checked : Checked encoded expectedSources resolver} {before : Machine.State}
    (runtime : RuntimeLayout checked before) :
    ProcessLayout checked.endToEnd.certificate.certificate.certificate.elf before
      checked.endToEnd.program.entrypoint.image.bytes.length checked.displacement :=
  { mapped := runtime.mapped
    entryFunction := checked.endToEnd.program.entrypoint.function
    startup := checked.startup
    jump := checked.jump
    ripAtEntry := runtime.ripAtEntry
    separation := authenticatedImageStackDisjoint_implies checked.endToEnd.program
      runtime.separation
    targetOffset := checked.entrySlice.offset
    targetCodeOffset := checked.entrySlice.codeOffsetBound
    targetBound := by
      simpa [checked.entrySliceExact] using checked.entrySlice.offsetBound
    targetExact := by
      calc
        jumpTarget checked.displacement =
            checked.endToEnd.program.entrypoint.image.address :=
          startupJumpDisplacement_sound checked.displacementAccepted
        _ = checked.entrySlice.image.address :=
          congrArg FunctionImage.address checked.entrySliceExact.symm
        _ = ImageCheck.lanius.base + BitVec.ofNat 64 checked.entrySlice.offset :=
          checked.entrySlice.addressExact }

/- The startup path lowers RSP by 24 bytes before entering the selected
   function.  Runtime image separation is indexed by the computed startup
   footprint, while the dynamic frame-window condition supplies the saved-RBP,
   return-word, and recursive-slot non-wrap facts for the authenticated shape. -/
private theorem reached_stack_code_disjoint
    {elf : List UInt8} {before : Machine.State} {functionLength : Nat}
    {displacement : BitVec 32}
    (process : ProcessLayout elf before functionLength displacement) :
    StackCodeDisjoint (reachedState before displacement)
      ImageCheck.lanius.base elf.length process.entryFunction := by
  have hRsp : (reachedState before displacement).registers rspRegister =
      before.registers rspRegister - 24 := reached_stack process
  intro index bound lane slot slotMember
  have shifted : 24 + slot ∈ startupStackFootprint process.entryFunction := by
    unfold startupStackFootprint
    simp only [List.mem_append, List.mem_cons, List.mem_map]
    exact Or.inr ⟨slot, slotMember, rfl⟩
  have h := process.separation index bound (24 + slot) shifted lane
  rw [hRsp]
  simpa [StartupCheck.base, rspRegister, BitVec.sub_sub, ← BitVec.ofNat_add] using h

private theorem startup_disjoint
    {elf : List UInt8} {before : Machine.State} {functionLength : Nat}
    {displacement : BitVec 32}
    (process : ProcessLayout elf before functionLength displacement)
    {index : Nat} (bound : index < elf.length)
    (slot : Nat) (slotMember : slot ∈ startupStackFootprint process.entryFunction)
    (lane : Fin 8) :
    ImageCheck.lanius.base + BitVec.ofNat 64 index ≠
      before.registers rspRegister - BitVec.ofNat 64 slot + BitVec.ofNat 64 lane.val := by
  exact process.separation index bound slot slotMember lane

private theorem elf_loaded_after_startup
    {elf : List UInt8} {before : Machine.State} {functionLength : Nat}
    {displacement : BitVec 32}
    (process : ProcessLayout elf before functionLength displacement) :
    Machine.CodeAt (afterCall before).memory ImageCheck.lanius.base elf := by
  have loadedAtBase : Machine.CodeAt before.memory ImageCheck.lanius.base elf := process.mapped
  have d1 : ∀ index, index < elf.length → ∀ lane : Fin 8,
      ImageCheck.lanius.base + BitVec.ofNat 64 index ≠
        (afterLoad before).registers rsp - 8 + BitVec.ofNat 64 lane.val := by
    intro index bound lane
    change ImageCheck.lanius.base + BitVec.ofNat 64 index ≠
      before.registers rspRegister - 8 + BitVec.ofNat 64 lane.val
    exact startup_disjoint process bound 8
      (startupStackFootprint_mem process.entryFunction).1 lane
  have first := StartupCheck.keep_write64 (address := ImageCheck.lanius.base)
    (before := before)
    (store := (afterLoad before).registers rsp - 8)
    (value := (afterLoad before).registers rax) loadedAtBase d1
  have loadedFirst : Machine.CodeAt (afterFirstPush before).memory
      ImageCheck.lanius.base elf := by
    simpa [afterFirstPush, afterLoad, afterMove, Machine.State.push64,
      Machine.State.immediate32, Machine.State.move64, StartupCheck.rax,
      StartupCheck.rsp] using first
  have d2 : ∀ index, index < elf.length → ∀ lane : Fin 8,
      ImageCheck.lanius.base + BitVec.ofNat 64 index ≠
        (afterFirstPush before).registers rsp - 8 + BitVec.ofNat 64 lane.val := by
    intro index bound lane
    rw [StartupCheck.after_first_rsp]
    exact startup_disjoint process bound 16
      (startupStackFootprint_mem process.entryFunction).2.1 lane
  have second := StartupCheck.keep_write64 (before := afterFirstPush before)
    (address := ImageCheck.lanius.base)
    (store := (afterFirstPush before).registers rsp - 8)
    (value := (afterFirstPush before).registers r10) loadedFirst d2
  have loadedSecond : Machine.CodeAt (afterSecondPush before).memory
      ImageCheck.lanius.base elf := by
    simpa [afterSecondPush, Machine.State.push64, StartupCheck.r10,
      StartupCheck.rsp] using second
  have loadedSave : Machine.CodeAt (afterSave before).memory
      ImageCheck.lanius.base elf := by
    simpa [afterSave, Machine.State.move64, StartupCheck.r15,
      StartupCheck.rsp] using loadedSecond
  have loadedClear : Machine.CodeAt (afterClear before).memory
      ImageCheck.lanius.base elf := by
    simpa [afterClear, Machine.State.alu32, Machine.State.alu,
      StartupCheck.rbp] using loadedSave
  have d3 : ∀ index, index < elf.length → ∀ lane : Fin 8,
      ImageCheck.lanius.base + BitVec.ofNat 64 index ≠
        (afterClear before).registers rsp - 8 + BitVec.ofNat 64 lane.val := by
    intro index bound lane
    rw [StartupCheck.clear_rsp, StartupCheck.sub_sixteen_eight]
    exact startup_disjoint process bound 24
      (startupStackFootprint_mem process.entryFunction).2.2.1 lane
  have third := StartupCheck.keep_write64 (before := afterClear before)
    (address := ImageCheck.lanius.base)
    (store := (afterClear before).registers rsp - 8)
    (value := (afterClear before).rip + BitVec.ofNat 64 callCode.length)
    loadedClear d3
  simpa [afterCall, Machine.State.call, StartupCheck.rsp] using third

private theorem loaded_after_startup
    {encoded : String} {expectedSources : List Extraction.SourceFile}
    {resolver : optParam ProgramLowering.ExternalBehaviorResolver
      CertificateLoweringCheck.noExternalBehavior}
    {checked : Checked encoded expectedSources resolver} {before : Machine.State}
    (runtime : RuntimeLayout checked before) :
    checked.endToEnd.program.Loaded (reachedState before checked.displacement) := by
  have sound := EndToEndCheck.check_sound checked.endToEnd
  have process := processLayout runtime
  have mappedAfter : Machine.CodeAt
      (reachedState before checked.displacement).memory ImageCheck.lanius.base
      checked.endToEnd.certificate.certificate.certificate.elf := by
    simpa [reachedState, Machine.State.jump] using elf_loaded_after_startup process
  exact sound.loadedFromElf (reachedState before checked.displacement) mappedAfter

private theorem expression_frame_invariant
    {encoded : String} {expectedSources : List Extraction.SourceFile}
    {resolver : optParam ProgramLowering.ExternalBehaviorResolver
      CertificateLoweringCheck.noExternalBehavior}
    {checked : Checked encoded expectedSources resolver} {before : Machine.State}
    (runtime : RuntimeLayout checked before) :
    EntrypointFrame checked.endToEnd.program
      (reachedState before checked.displacement) := by
  let process := processLayout runtime
  cases auth : checked.endToEnd.program with
  | standard standard =>
      cases entry : standard.entrypoint.checked with
      | body supported =>
          have shapeAlloc :
              functionAllocationCount standard.entrypoint.function =
                supported.checkedShape.1.allocations := by
            rw [functionAllocationCount, supported.bodyExact]
            exact body_allocation_count_eq supported.checkedShape.1
          have entryFunctionEq : standard.entrypoint.function =
              checked.endToEnd.program.entrypoint.function := by
            simpa [ProgramCheck.Authenticated.entrypoint] using
              (congrArg (fun c => c.entrypoint.function) auth).symm
          have entryImageEq : standard.entrypoint.image =
              checked.endToEnd.program.entrypoint.image := by
            simpa [ProgramCheck.Authenticated.entrypoint] using
              (congrArg (fun c => c.entrypoint.image) auth).symm
          have processEntry : process.entryFunction = standard.entrypoint.function := by
            dsimp [process, processLayout]
            exact entryFunctionEq.symm
          have frameWindow : DynamicFrameWindow
              (reachedState before checked.displacement)
              (functionAllocationCount standard.entrypoint.function) :=
            dynamic_frame_window_of_slots_le
              (by
                simpa [entryFunctionEq] using
                  (ProgramCheck.Authenticated.entrypoint_allocation_count_le
                    checked.endToEnd.program))
          have countBound : ∀ slot, slot < supported.checkedShape.1.allocations →
              slot < functionAllocationCount standard.entrypoint.function := by
            intro slot bound
            simpa [shapeAlloc] using bound
          have jumpExact : jumpTarget checked.displacement =
              standard.entrypoint.image.address := by
            calc
              jumpTarget checked.displacement =
                  checked.endToEnd.program.entrypoint.image.address :=
                startupJumpDisplacement_sound checked.displacementAccepted
              _ = standard.entrypoint.image.address := by rw [← entryImageEq]
          have mappedAfter : Machine.CodeAt
              (reachedState before checked.displacement).memory ImageCheck.lanius.base
              checked.endToEnd.certificate.certificate.certificate.elf := by
            simpa [reachedState, Machine.State.jump] using
              elf_loaded_after_startup process
          have entryLoaded := checked.entrySlice.loaded mappedAfter
          have standardBytesExact : standard.entrypoint.image.bytes =
              ExpressionFunctionCheck.bodyFunctionBytes supported.checkedShape.1 := by
            simpa [entry] using supported.checkedShape.2
          have checkedBytesExact : checked.endToEnd.program.entrypoint.image.bytes =
              ExpressionFunctionCheck.bodyFunctionBytes supported.checkedShape.1 := by
            rw [← entryImageEq]
            exact standardBytesExact
          have entryLoaded' : Machine.CodeAt
              (reachedState before checked.displacement).memory
              checked.endToEnd.program.entrypoint.image.address
              checked.endToEnd.program.entrypoint.image.bytes := by
            simpa [checked.entrySliceExact] using entryLoaded
          have ripAtEntry : (reachedState before checked.displacement).rip =
              standard.entrypoint.image.address := by
            calc
              (reachedState before checked.displacement).rip =
                  jumpTarget checked.displacement :=
                (reaches_function_layout process).2.1
              _ = standard.entrypoint.image.address := jumpExact
          have loadedFull : Machine.CodeAt
              (reachedState before checked.displacement).memory
              (reachedState before checked.displacement).rip
              (ExpressionFunctionCheck.bodyFunctionBytes supported.checkedShape.1) := by
            rw [ripAtEntry, ← checkedBytesExact]
            simpa [entryImageEq] using entryLoaded'
          have loadedFunction : Machine.CodeAt
              (reachedState before checked.displacement).memory
              (reachedState before checked.displacement).rip
              (framePrologueBytes supported.checkedShape.1.allocations ++
                (supported.checkedShape.1.bodyBytes 0 ++
                  ud2Bytes)) := by
            simpa [ExpressionFunctionCheck.bodyFunctionBytes,
              List.append_assoc] using loadedFull
          have prologueDisjoint : ∀ index, index <
              (moveBytes .w64 rbpRegister rspRegister ++
                immediateBytes .w32 r11Register
                  (frameSizeBits supported.checkedShape.1.allocations) 0 ++
                aluBytes .w64 .subtract rspRegister r11Register).length →
              ∀ lane : Fin 8,
              (reachedState before checked.displacement).rip +
                  BitVec.ofNat 64 ((pushBytes rbpRegister).length + index) ≠
                (reachedState before checked.displacement).registers rspRegister - 8 +
                  BitVec.ofNat 64 lane.val := by
            intro index bound lane
            have total : (pushBytes rbpRegister).length + index <
                checked.endToEnd.program.entrypoint.image.bytes.length := by
              rw [← entryImageEq]
              simp only [supported.checkedShape.2, ExpressionFunctionCheck.bodyFunctionBytes,
                framePrologueBytes, List.length_append] at bound ⊢
              omega
            have h := reached_function_stack_disjoint process
              ((pushBytes rbpRegister).length + index) total lane 8 (by
                simp [entryStackFootprint])
            rw [jumpExact] at h
            simpa [ripAtEntry, BitVec.add_assoc, ← BitVec.ofNat_add] using h
          have bodyLoaded : Machine.CodeAt
              (Machine.prologueState (reachedState before checked.displacement)
                supported.checkedShape.1.allocations).memory
              (Machine.prologueState (reachedState before checked.displacement)
                supported.checkedShape.1.allocations).rip
              (supported.checkedShape.1.bodyBytes 0 ++ ud2Bytes) := by
            apply framePrologue_tail
              supported.checkedShape.1.allocations
              (reachedState before checked.displacement)
              _ loadedFunction
            intro index bound lane
            have total : (framePrologueBytes supported.checkedShape.1.allocations).length + index <
                checked.endToEnd.program.entrypoint.image.bytes.length := by
              rw [← entryImageEq]
              simp only [supported.checkedShape.2, ExpressionFunctionCheck.bodyFunctionBytes,
                framePrologueBytes, List.length_append] at bound ⊢
              omega
            have h := reached_function_stack_disjoint process
              ((framePrologueBytes supported.checkedShape.1.allocations).length + index)
              total lane 8 (by simp [entryStackFootprint])
            rw [jumpExact] at h
            simpa [ripAtEntry, BitVec.add_assoc, ← BitVec.ofNat_add] using h
          have rbpExact :
              (Machine.prologueState (reachedState before checked.displacement)
                supported.checkedShape.1.allocations).registers rbpRegister =
                (reachedState before checked.displacement).registers rspRegister - 8 := by
            simp [Machine.prologueState, Machine.State.alu64, Machine.State.alu,
              Machine.State.immediate32, Machine.State.move64, Machine.State.push64,
              rbpRegister, rspRegister, r11Register, frameSizeBits, frameBytes,
              Alu.result, BitVec.sub_eq_add_neg, BitVec.add_assoc]
          have bodySeparated : ∀ index, index <
              (supported.checkedShape.1.bodyBytes 0 ++ ud2Bytes).length →
              ∀ slot, 0 ≤ slot → slot < supported.checkedShape.1.allocations →
              ∀ lane : Fin 4,
              (Machine.prologueState (reachedState before checked.displacement)
                supported.checkedShape.1.allocations).rip + BitVec.ofNat 64 index ≠
                frameSlotAddress
                  ((Machine.prologueState (reachedState before checked.displacement)
                    supported.checkedShape.1.allocations).registers rbpRegister) slot +
                    BitVec.ofNat 64 lane.val := by
            intro index bound slot _lower slotUpper lane
            let lane8 : Fin 8 := ⟨lane.val, by omega⟩
            have total : (framePrologueBytes supported.checkedShape.1.allocations).length + index <
                checked.endToEnd.program.entrypoint.image.bytes.length := by
              rw [← entryImageEq]
              simp only [supported.checkedShape.2, ExpressionFunctionCheck.bodyFunctionBytes,
                framePrologueBytes, List.length_append] at bound ⊢
              omega
            have h := reached_function_stack_disjoint process
              ((framePrologueBytes supported.checkedShape.1.allocations).length + index)
              total lane8 (16 + 8 * slot)
              (by
                rw [processEntry]
                exact body_frame_slot_mem supported.bodyExact slotUpper)
            have slotAddress := frameWindow.slotAddressExact slot
              (countBound slot slotUpper)
            rw [rbpExact, slotAddress]
            have prologueRip := Machine.framePrologue_rip
              supported.checkedShape.1.allocations
              (reachedState before checked.displacement)
            rw [prologueRip]
            rw [ripAtEntry]
            rw [jumpExact] at h
            simpa [lane8, BitVec.add_assoc, BitVec.ofNat_add] using h
          have savedDisjoint : ∀ slot, slot < supported.checkedShape.1.allocations →
              ∀ i : Fin 8, ∀ j : Fin 4,
              (Machine.prologueState (reachedState before checked.displacement)
                supported.checkedShape.1.allocations).registers rbpRegister +
                  BitVec.ofNat 64 i.val ≠
                frameSlotAddress
                  ((Machine.prologueState (reachedState before checked.displacement)
                    supported.checkedShape.1.allocations).registers rbpRegister) slot +
                  BitVec.ofNat 64 j.val := by
            intro slot bound i j
            simpa [Machine.prologueState, Machine.State.alu64, Machine.State.alu,
              Machine.State.immediate32, Machine.State.move64, Machine.State.push64,
              rbpRegister, rspRegister, r11Register, frameSizeBits, frameBytes,
              Alu.result, BitVec.sub_eq_add_neg, BitVec.add_assoc] using
              frameWindow.savedFrameDisjoint slot (countBound slot bound) i j
          have returnDisjoint : ∀ slot, slot < supported.checkedShape.1.allocations →
              ∀ i : Fin 8, ∀ j : Fin 4,
              (Machine.prologueState (reachedState before checked.displacement)
                supported.checkedShape.1.allocations).registers rbpRegister + 8 +
                  BitVec.ofNat 64 i.val ≠
                frameSlotAddress
                  ((Machine.prologueState (reachedState before checked.displacement)
                    supported.checkedShape.1.allocations).registers rbpRegister) slot +
                  BitVec.ofNat 64 j.val := by
            intro slot bound i j
            simpa [Machine.prologueState, Machine.State.alu64, Machine.State.alu,
              Machine.State.immediate32, Machine.State.move64, Machine.State.push64,
              rbpRegister, rspRegister, r11Register, frameSizeBits, frameBytes,
              Alu.result, BitVec.sub_eq_add_neg, BitVec.add_assoc] using
              frameWindow.returnAddressDisjoint slot (countBound slot bound) i j
          have slotsSeparated : ∀ left right, 0 ≤ left →
              left < supported.checkedShape.1.allocations → 0 ≤ right →
              right < supported.checkedShape.1.allocations → left ≠ right →
              ∀ i j : Fin 4,
              frameSlotAddress
                  ((Machine.prologueState (reachedState before checked.displacement)
                    supported.checkedShape.1.allocations).registers rbpRegister) left +
                  BitVec.ofNat 64 i.val ≠
                frameSlotAddress
                  ((Machine.prologueState (reachedState before checked.displacement)
                    supported.checkedShape.1.allocations).registers rbpRegister) right +
                  BitVec.ofNat 64 j.val := by
            intro left right _leftLower leftUpper _rightLower rightUpper different i j
            simpa [Machine.prologueState, Machine.State.alu64, Machine.State.alu,
              Machine.State.immediate32, Machine.State.move64, Machine.State.push64,
              rbpRegister, rspRegister, r11Register, frameSizeBits, frameBytes,
              Alu.result] using frameWindow.slotsSeparated left right
                (countBound left leftUpper) (countBound right rightUpper) different i j
          have slotAddressExact : ∀ slot, slot < supported.checkedShape.1.allocations →
              frameSlotAddress
                  ((reachedState before checked.displacement).registers rspRegister - 8) slot =
                (reachedState before checked.displacement).registers rspRegister -
                  BitVec.ofNat 64 (16 + 8 * slot) := by
            intro slot bound
            exact frameWindow.slotAddressExact slot (countBound slot bound)
          simpa [EntrypointFrame, auth, entry] using
            (show BodyFrameInvariant supported.checkedShape.1
              (reachedState before checked.displacement) ∧
              (∀ slot, slot < supported.checkedShape.1.allocations →
                frameSlotAddress
                    ((reachedState before checked.displacement).registers rspRegister - 8) slot =
                  (reachedState before checked.displacement).registers rspRegister -
                    BitVec.ofNat 64 (16 + 8 * slot)) from ⟨{
                prologueDisjoint := prologueDisjoint
                body := {
                  loaded := bodyLoaded
                  separated := bodySeparated
                  slotsSeparated := slotsSeparated
                  belowSlotsSeparated := by
                    intro left leftBelow
                    omega }
                savedFrameDisjoint := savedDisjoint
                returnAddressDisjoint := returnDisjoint }, slotAddressExact⟩)
      | _ => simp [EntrypointFrame, entry]
  | direct displacement direct => simp [EntrypointFrame]

/- Execute the authenticated startup and hand its exact reached state to the
   authenticated Core/function preservation theorem. -/
theorem preserves
    {encoded : String} {expectedSources : List Extraction.SourceFile}
    {resolver : optParam ProgramLowering.ExternalBehaviorResolver
      CertificateLoweringCheck.noExternalBehavior}
    {checked : Checked encoded expectedSources resolver}
    (coreBefore : Semantics.State) (before : Machine.State)
    (runtime : RuntimeLayout checked before)
    (environment : PreservationEnvironment checked.endToEnd.program coreBefore
      (reachedState before checked.displacement)) :
    Steps 8 before (reachedState before checked.displacement) ∧
      (reachedState before checked.displacement).rip =
        checked.endToEnd.program.entrypoint.image.address ∧
      (reachedState before checked.displacement).registers rsp = before.registers rsp - 24 ∧
      Machine.read64 (reachedState before checked.displacement).memory
        ((reachedState before checked.displacement).registers rsp) = startupReturnAddress ∧
      TextStackDisjoint (reachedState before checked.displacement)
        checked.endToEnd.program.entrypoint.image.address
        checked.endToEnd.program.entrypoint.image.bytes.length ∧
      checked.endToEnd.program.Preserves coreBefore
        (reachedState before checked.displacement) (loaded_after_startup runtime) environment
        (by
          have reached := reaches_function_layout (processLayout runtime)
          rw [reached.2.1, startupJumpDisplacement_sound checked.displacementAccepted])
        startupReturnAddress
        (reached_return_slot (processLayout runtime)) := by
  have process := processLayout runtime
  have reached := reaches_function_layout process
  have ripAtEntry : (reachedState before checked.displacement).rip =
      checked.endToEnd.program.entrypoint.image.address := by
    rw [reached.2.1, startupJumpDisplacement_sound checked.displacementAccepted]
  have loaded := loaded_after_startup runtime
  have text := reached.2.2.2.2
  rw [startupJumpDisplacement_sound checked.displacementAccepted] at text
  refine ⟨reached.1, ripAtEntry, reached.2.2.1, reached.2.2.2.1,
    text, ?_⟩
  exact (EndToEndCheck.check_sound checked.endToEnd).entrypointPreserves coreBefore
    (reachedState before checked.displacement)
    loaded environment ripAtEntry startupReturnAddress
    (reached_return_slot process)

/- This is the public runtime composition: checker-owned startup and image
   evidence reach the authenticated entrypoint, whose uniform result state is
   then consumed by the authenticated return-to-syscall suffix.  Image/code
   windows are derived from RuntimeLayout's computed separation, and the
   frame theorem consumes only its shape-indexed dynamic window fact. -/
theorem startup_to_exit
    {encoded : String} {expectedSources : List Extraction.SourceFile}
    {resolver : optParam ProgramLowering.ExternalBehaviorResolver
      CertificateLoweringCheck.noExternalBehavior}
    {checked : Checked encoded expectedSources resolver}
    (coreBefore : Semantics.State) (before : Machine.State)
    (runtime : RuntimeLayout checked before)
    (environment : PreservationEnvironment checked.endToEnd.program coreBefore
      (reachedState before checked.displacement)) :
    ∃ coreAfter body value returned count bits,
      Steps (8 + count + 2) before (afterExitLoad returned) ∧
      ReturnedState checked.endToEnd.program coreBefore
        (reachedState before checked.displacement) startupReturnAddress
        coreAfter body value returned count ∧
      ReturnExitResult returned (afterExitLoad returned) bits := by
  let process := processLayout runtime
  have entry := preserves coreBefore before runtime environment
  have loaded := loaded_after_startup runtime
  have mapped : Machine.CodeAt
      (reachedState before checked.displacement).memory ImageCheck.lanius.base
      checked.endToEnd.certificate.certificate.certificate.elf := by
    simpa [reachedState, Machine.State.jump] using elf_loaded_after_startup process
  have entryFunction : process.entryFunction = checked.endToEnd.program.entrypoint.function := by
    rfl
  have entryFrame := expression_frame_invariant runtime
  have composed := X86.EntrypointExitComposition.entrypoint_to_exit
    loaded environment entryFrame entry.2.1 entry.2.2.2.1 checked.startup mapped
      (by
        simpa only [StartupCheck.base, entryFunction] using
          reached_stack_code_disjoint process)
  rcases composed with ⟨coreAfter, body, value, returned, count, bits, state, exit⟩
  refine ⟨coreAfter, body, value, returned, count, bits, ?_, state, exit⟩
  have allSteps := Machine.Steps.trans entry.1
    (Machine.Steps.trans state.steps exit.steps)
  simpa [Nat.add_assoc] using allSteps

end Lanius.Compiler.ELFExecutionCheck
