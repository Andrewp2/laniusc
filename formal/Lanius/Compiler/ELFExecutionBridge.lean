import Lanius.Compiler.ELFExecutionCheck

namespace Lanius.Compiler.ELFExecutionBridge

open Lanius
open Lanius.Core
open Lanius.Compiler
open Lanius.Compiler.CertificateLoweringCheck
open Lanius.Compiler.ELFExecutionCheck
open Lanius.X86
open Lanius.X86.Machine
open Lanius.X86.EntrypointRefinement
open Lanius.X86.ProgramCheck
open Lanius.X86.ProcessLayoutCheck
open Lanius.X86.StartupExitCheck

private theorem slice_for_image
    {encoded : String} {expectedSources : List Extraction.SourceFile}
    {resolver : optParam ProgramLowering.ExternalBehaviorResolver
      CertificateLoweringCheck.noExternalBehavior}
    {checked : ELFExecutionCheck.Checked encoded expectedSources resolver}
    {image : FunctionImage}
    (member : image ∈ checked.endToEnd.certificateImage.image.functions) :
    ∃ slice, slice ∈ checked.endToEnd.image.slices ∧ slice.image = image := by
  have member' : image ∈ checked.endToEnd.image.slices.map (fun item => item.image) := by
    rw [checked.endToEnd.image.slicesExact]
    exact member
  rcases List.mem_map.mp member' with ⟨slice, sliceMember, imageExact⟩
  exact ⟨slice, sliceMember, imageExact⟩

private theorem reached_slice_disjoint
    {elf : List UInt8} {before : Machine.State}
    {functionLength : Nat} {displacement : BitVec 32}
    (process : ProcessLayout elf before functionLength displacement)
    (slice : ImageCheck.SliceEvidence ImageCheck.lanius elf)
    (slot : Nat) (slotMember : slot ∈ entryStackFootprint process.entryFunction)
    (index : Nat) (bound : index < slice.image.bytes.length) (lane : Fin 8) :
    slice.image.address + BitVec.ofNat 64 index ≠
      (reachedState before displacement).registers rspRegister -
        BitVec.ofNat 64 slot + BitVec.ofNat 64 lane.val := by
  have hRsp : (reachedState before displacement).registers Machine.rspRegister =
      before.registers Machine.rspRegister - 24 := reached_stack process
  have sourceBound : slice.offset + index < elf.length := by
    have offsetBound := slice.offsetBound
    omega
  have shifted : 24 + slot ∈ startupStackFootprint process.entryFunction := by
    unfold startupStackFootprint
    simp only [List.mem_append, List.mem_cons, List.mem_map]
    exact Or.inr ⟨slot, slotMember, rfl⟩
  have separated := process.separation (slice.offset + index) sourceBound
    (24 + slot) shifted lane
  rw [slice.addressExact, hRsp]
  simp only [BitVec.ofNat_add] at separated
  simpa [StartupCheck.base, Machine.rspRegister, BitVec.add_assoc,
    BitVec.sub_sub] using separated

/- The ordinary authenticated program carries only the text-stack condition
   that the process layout can derive after the startup jump. -/
def standardEnvironment
    {encoded : String} {expectedSources : List Extraction.SourceFile}
    {resolver : optParam ProgramLowering.ExternalBehaviorResolver
      CertificateLoweringCheck.noExternalBehavior}
    {checked : ELFExecutionCheck.Checked encoded expectedSources resolver}
    {program : ProgramCheck.Checked _ _}
    (programExact : checked.endToEnd.program = .standard program)
    (coreBefore : Semantics.State) (formed : coreBefore.CellsWellFormed)
    (before : Machine.State)
    (runtime : RuntimeLayout checked before) :
    PreservationEnvironment checked.endToEnd.program coreBefore
      (reachedState before checked.displacement) := by
  have process := processLayout runtime
  have textStack := reached_textStack process
  have rip := (reaches_function_layout process).2.1
  rw [startupJumpDisplacement_sound checked.displacementAccepted] at rip textStack
  rw [← rip] at textStack
  rw [programExact]
  exact ProgramCheck.PreservationEnvironment.standard coreBefore _ formed (by
    simpa only [programExact, Authenticated.entrypoint] using textStack)

/- The direct branch uses the caller as the dynamic entry function.  Its
   caller/callee slices are both members of the checker-owned ELF image, so
   RuntimeLayout's separation transports to every frame slot required by the
   direct-call proof. -/
noncomputable def directEnvironment
    {encoded : String} {expectedSources : List Extraction.SourceFile}
    {resolver : optParam ProgramLowering.ExternalBehaviorResolver
      CertificateLoweringCheck.noExternalBehavior}
    {checked : ELFExecutionCheck.Checked encoded expectedSources resolver}
    {directDisplacement : BitVec 32}
    {program : DirectChecked
      checked.endToEnd.certificate.certificate.backend.executable
      checked.endToEnd.certificateImage.image directDisplacement}
    (programExact : checked.endToEnd.program = .direct directDisplacement program)
    (coreBefore : Semantics.State) (formed : coreBefore.CellsWellFormed)
    (before : Machine.State) (runtime : RuntimeLayout checked before) :
    PreservationEnvironment checked.endToEnd.program coreBefore
      (reachedState before checked.displacement) := by
  let process := processLayout runtime
  have processEntry : process.entryFunction = program.caller := by
    change checked.endToEnd.program.entrypoint.function = program.caller
    rw [programExact]
    rfl
  have imageMember : ∀ {function : Function} {functionImage : FunctionImage},
      (∃ evidence, evidence ∈ program.functions ∧ evidence.function = function ∧
        evidence.image = functionImage) →
      functionImage ∈ checked.endToEnd.certificateImage.image.functions := by
    intro function functionImage member
    rw [← program.imagesExact]
    rcases member with ⟨evidence, evidenceMember, _, imageExact⟩
    exact List.mem_map.mpr ⟨evidence, evidenceMember, imageExact⟩
  have callerMember : program.callerImage ∈
      checked.endToEnd.certificateImage.image.functions := by
    exact imageMember program.callerEvidenceMember
  have calleeMember : program.calleeImage ∈
      checked.endToEnd.certificateImage.image.functions := by
    exact imageMember program.calleeEvidenceMember
  let callerSlice : ImageCheck.SliceEvidence ImageCheck.lanius
      checked.endToEnd.certificate.certificate.certificate.elf :=
    Classical.choose (slice_for_image callerMember)
  have callerSliceSpec : callerSlice ∈ checked.endToEnd.image.slices ∧
      callerSlice.image = program.callerImage := by
    dsimp [callerSlice]
    exact Classical.choose_spec (slice_for_image callerMember)
  have callerSliceMember := callerSliceSpec.1
  have callerSliceExact := callerSliceSpec.2
  let calleeSlice : ImageCheck.SliceEvidence ImageCheck.lanius
      checked.endToEnd.certificate.certificate.certificate.elf :=
    Classical.choose (slice_for_image calleeMember)
  have calleeSliceSpec : calleeSlice ∈ checked.endToEnd.image.slices ∧
      calleeSlice.image = program.calleeImage := by
    dsimp [calleeSlice]
    exact Classical.choose_spec (slice_for_image calleeMember)
  have calleeSliceMember := calleeSliceSpec.1
  have calleeSliceExact := calleeSliceSpec.2
  have callerDisjoint : ∀ index, index < program.callerImage.bytes.length →
      ∀ slot, slot ∈ entryStackFootprint program.caller → ∀ lane : Fin 8,
      program.callerImage.address + BitVec.ofNat 64 index ≠
        (reachedState before checked.displacement).registers rspRegister -
          BitVec.ofNat 64 slot + BitVec.ofNat 64 lane.val := by
    intro index bound slot slotMember lane
    have bound' : index < callerSlice.image.bytes.length := by
      simpa only [callerSliceExact] using bound
    have slotMember' : slot ∈ entryStackFootprint process.entryFunction := by
      rw [processEntry]
      exact slotMember
    have separated := reached_slice_disjoint process callerSlice slot slotMember'
      index bound' lane
    simpa only [callerSliceExact] using separated
  have calleeDisjoint : ∀ index, index < program.calleeImage.bytes.length →
      ∀ slot, slot ∈ entryStackFootprint program.caller → ∀ lane : Fin 8,
      program.calleeImage.address + BitVec.ofNat 64 index ≠
        (reachedState before checked.displacement).registers rspRegister -
          BitVec.ofNat 64 slot + BitVec.ofNat 64 lane.val := by
    intro index bound slot slotMember lane
    have bound' : index < calleeSlice.image.bytes.length := by
      simpa only [calleeSliceExact] using bound
    have slotMember' : slot ∈ entryStackFootprint process.entryFunction := by
      rw [processEntry]
      exact slotMember
    have separated := reached_slice_disjoint process calleeSlice slot slotMember'
      index bound' lane
    simpa only [calleeSliceExact] using separated
  have footprint :
      8 ∈ entryStackFootprint program.caller ∧
      16 ∈ entryStackFootprint program.caller ∧
      32 ∈ entryStackFootprint program.caller ∧
      40 ∈ entryStackFootprint program.caller := by
    rcases program.callerChecked.callerSupported.bodyExact with body | body <;>
      simp [entryStackFootprint, body]
  have reached := reaches_function_layout process
  have ripAtCaller : (reachedState before checked.displacement).rip =
      program.callerImage.address := by
    have rip := reached.2.1
    rw [startupJumpDisplacement_sound checked.displacementAccepted] at rip
    simpa only [programExact, Authenticated.entrypoint] using rip
  have callerBytes := program.callerChecked.bytesExact
  have prologue : DirectCallFunctionCheck.prologueDisjoint
      (reachedState before checked.displacement) := by
    intro index bound lane
    have bound' : (pushBytes rbpRegister).length + index <
        program.callerImage.bytes.length := by
      rw [callerBytes]
      simp only [DirectCallFunctionCheck.functionBytes, framePrologueBytes,
        List.length_append] at bound ⊢
      omega
    have separated := callerDisjoint ((pushBytes rbpRegister).length + index)
      bound' 8 footprint.1 lane
    simpa [ripAtCaller, BitVec.add_assoc, ← BitVec.ofNat_add] using separated
  have tail : DirectCallFunctionCheck.tailDisjoint
      (reachedState before checked.displacement) directDisplacement := by
    intro index bound lane
    have bound' : (framePrologueBytes 1).length + index <
        program.callerImage.bytes.length := by
      rw [callerBytes]
      simp only [DirectCallFunctionCheck.functionBytes, framePrologueBytes,
        DirectCallFunctionCheck.tailBytes, List.length_append] at bound ⊢
      omega
    have separated := callerDisjoint ((framePrologueBytes 1).length + index)
      bound' 8 footprint.1 lane
    simpa [ripAtCaller, BitVec.add_assoc, ← BitVec.ofNat_add] using separated
  have prologueRip :
      (Machine.prologueState (reachedState before checked.displacement) 1).rip =
        (reachedState before checked.displacement).rip +
          BitVec.ofNat 64 (framePrologueBytes 1).length := by
    simp [Machine.prologueState, framePrologueBytes, Machine.State.alu64,
      Machine.State.alu, Machine.State.immediate32, Machine.State.move64,
      Machine.State.push64, rbpRegister, rspRegister, r11Register,
      BitVec.ofNat_add, BitVec.add_assoc]
  have prologueRsp :
      (Machine.prologueState (reachedState before checked.displacement) 1).registers
          rspRegister =
        (reachedState before checked.displacement).registers rspRegister - 24 := by
    simp [Machine.prologueState, Machine.State.push64, Machine.State.move64,
      Machine.State.immediate32, Machine.State.alu64, Machine.State.alu,
      Alu.result, frameSizeBits, frameBytes, rbpRegister, rspRegister,
      r11Register, BitVec.sub_eq_add_neg, BitVec.add_assoc]
  have prologueRsp' :
      (Machine.prologueState (reachedState before checked.displacement) 1).registers
          DirectCallCheck.stackRegister =
        (reachedState before checked.displacement).registers
          DirectCallCheck.stackRegister - 24 := by
    simpa [DirectCallCheck.stackRegister, Machine.rspRegister] using prologueRsp
  have call : DirectCallFunctionCheck.callDisjoint
      (reachedState before checked.displacement) directDisplacement := by
    intro index bound lane
    have bound' : (framePrologueBytes 1).length +
        (callBytes directDisplacement).length + index <
        program.callerImage.bytes.length := by
      rw [callerBytes]
      simp only [DirectCallFunctionCheck.functionBytes, framePrologueBytes,
        DirectCallFunctionCheck.epilogueBytes, DirectCallFunctionCheck.trapBytes,
        List.length_append] at bound ⊢
      omega
    have separated := callerDisjoint
      ((framePrologueBytes 1).length + (callBytes directDisplacement).length + index)
      bound' 32 footprint.2.2.1 lane
    rw [prologueRip, prologueRsp]
    simpa [ripAtCaller, BitVec.add_assoc, BitVec.sub_sub,
      ← BitVec.ofNat_add] using separated
  have calleePrologue : calleeCodePrologueDisjoint
      (reachedState before checked.displacement) program.calleeImage := by
    intro index bound lane
    exact calleeDisjoint index bound 8 footprint.1 lane
  have calleeCall : calleeCodeCallDisjoint
      (reachedState before checked.displacement) program.calleeImage := by
    intro index bound lane
    have separated := calleeDisjoint index bound 32 footprint.2.2.1 lane
    rw [prologueRsp']
    simpa [DirectCallCheck.stackRegister, Machine.rspRegister, BitVec.sub_sub,
      ← BitVec.ofNat_add] using separated
  have layout : DirectLayout program
      (reachedState before checked.displacement) :=
    { prologue, tail, call, calleePrologue, calleeCall }
  rw [programExact]
  exact PreservationEnvironment.direct formed layout

/- The checker-owned standard path now reaches the x86 exit boundary without
   making callers reconstruct or assume a preservation environment. -/
theorem standard_startup_to_exit
    {encoded : String} {expectedSources : List Extraction.SourceFile}
    {resolver : optParam ProgramLowering.ExternalBehaviorResolver
      CertificateLoweringCheck.noExternalBehavior}
    {checked : ELFExecutionCheck.Checked encoded expectedSources resolver}
    {program : ProgramCheck.Checked _ _}
    (programExact : checked.endToEnd.program = .standard program)
    (coreBefore : Semantics.State) (formed : coreBefore.CellsWellFormed)
    (before : Machine.State)
    (runtime : RuntimeLayout checked before) :
    ∃ coreAfter body value returned count bits,
      Machine.Steps (8 + count + 2) before (afterExitLoad returned) ∧
      ReturnedState checked.endToEnd.program coreBefore
        (reachedState before checked.displacement) startupReturnAddress
        coreAfter body value returned count ∧
      ReturnExitResult returned (afterExitLoad returned) bits := by
  exact startup_to_exit coreBefore before runtime
    (standardEnvironment programExact coreBefore formed before runtime)

/- The direct authenticated program now reaches the same real startup/exit
   boundary.  `formed` is the remaining semantic initial-state condition; all
   five machine layout obligations are derived above from the ELF separation
   and authenticated caller/callee slices. -/
theorem direct_startup_to_exit
    {encoded : String} {expectedSources : List Extraction.SourceFile}
    {resolver : optParam ProgramLowering.ExternalBehaviorResolver
      CertificateLoweringCheck.noExternalBehavior}
    {checked : ELFExecutionCheck.Checked encoded expectedSources resolver}
    {directDisplacement : BitVec 32}
    {program : DirectChecked
      checked.endToEnd.certificate.certificate.backend.executable
      checked.endToEnd.certificateImage.image directDisplacement}
    (programExact : checked.endToEnd.program = .direct directDisplacement program)
    (coreBefore : Semantics.State) (formed : coreBefore.CellsWellFormed)
    (before : Machine.State) (runtime : RuntimeLayout checked before) :
    ∃ coreAfter body value returned count bits,
      Machine.Steps (8 + count + 2) before (afterExitLoad returned) ∧
      ReturnedState checked.endToEnd.program coreBefore
        (reachedState before checked.displacement) startupReturnAddress
        coreAfter body value returned count ∧
      ReturnExitResult returned (afterExitLoad returned) bits := by
  exact startup_to_exit coreBefore before runtime
    (directEnvironment programExact coreBefore formed before runtime)

/- The canonical empty Core state has a preservation environment for either
   authenticated program representation; the constructor split stays here. -/
noncomputable def canonicalEnvironment
    {encoded : String} {expectedSources : List Extraction.SourceFile}
    {resolver : optParam ProgramLowering.ExternalBehaviorResolver
      CertificateLoweringCheck.noExternalBehavior}
    (checked : ELFExecutionCheck.Checked encoded expectedSources resolver)
    (before : Machine.State) (runtime : RuntimeLayout checked before) :
    PreservationEnvironment checked.endToEnd.program
      ({} : Semantics.State)
      (reachedState before checked.displacement) := by
  have formed : ({ } : Semantics.State).CellsWellFormed := by
    intro cell member
    simp at member
  cases programCase : checked.endToEnd.program with
  | standard program =>
      simpa only [programCase] using
        standardEnvironment programCase ({ } : Semantics.State) formed before runtime
  | direct displacement program =>
      simpa only [programCase] using
        directEnvironment programCase ({ } : Semantics.State) formed before runtime

/- The public entrypoint uses only the authenticated checker result and the
   actual runtime layout.  The constructor split is kept inside this bridge;
   callers do not provide branch equalities, Core formation, or layout facts. -/
theorem canonical_startup_to_exit
    {encoded : String} {expectedSources : List Extraction.SourceFile}
    {resolver : optParam ProgramLowering.ExternalBehaviorResolver
      CertificateLoweringCheck.noExternalBehavior}
    (checked : ELFExecutionCheck.Checked encoded expectedSources resolver)
    (before : Machine.State) (runtime : RuntimeLayout checked before) :
    ∃ coreAfter body value returned count bits,
      Machine.Steps (8 + count + 2) before (afterExitLoad returned) ∧
      ReturnedState checked.endToEnd.program
        ({} : Semantics.State)
        (reachedState before checked.displacement) startupReturnAddress
        coreAfter body value returned count ∧
      ReturnExitResult returned (afterExitLoad returned) bits := by
  exact startup_to_exit ({ } : Semantics.State) before runtime
    (canonicalEnvironment checked before runtime)

end Lanius.Compiler.ELFExecutionBridge
