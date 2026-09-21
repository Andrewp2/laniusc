import Lanius.X86.ProgramCheck
import Lanius.X86.ProcessLayoutCheck

namespace Lanius.X86.EntrypointRefinement

open Lanius Lanius.Core Lanius.Semantics
open Lanius.X86
open Lanius.X86.Machine
open Lanius.X86.ProgramCheck
open Lanius.X86.ProcessLayoutCheck

def ProtectedCode (before after : Machine.State) (entry : Function) : Prop :=
  ∀ {code : Machine.Address} {bytes : List UInt8},
    Machine.CodeAt before.memory code bytes →
    StackCodeDisjoint before code bytes.length entry →
    Machine.CodeAt after.memory code bytes

/- The only constructor-specific machine premise is selected internally from
   the authenticated entry checker.  Connected body entries use their
   dynamic frame invariant; all established scalar/direct entries have no
   additional frame obligation. -/
def EntrypointFrame (checked : Authenticated executable image)
    (machineBefore : Machine.State) : Prop :=
  match checked with
  | .standard checked =>
      match checked.entrypoint.checked with
      | .body supported =>
          ExpressionFunctionCheck.BodyFrameInvariant supported.checkedShape.1 machineBefore ∧
            (∀ slot, slot < supported.checkedShape.1.allocations →
              frameSlotAddress (machineBefore.registers rspRegister - 8) slot =
                machineBefore.registers rspRegister - BitVec.ofNat 64 (16 + 8 * slot))
      | _ => True
  | .direct _ _ => True

/- A constructor-independent result for the selected entrypoint.  The finite
   instruction count is existential because the standard fragments and the
   direct-call fragment have different authenticated traces.  `protectedCode`
   carries the memory effect needed by the startup/exit suffix without making
   that suffix split on the checker constructor. -/
structure ReturnedState (checked : Authenticated executable image)
    (coreBefore : Semantics.State) (machineBefore : Machine.State)
    (returnAddress : Machine.Address) (coreAfter : Semantics.State)
    (body : Stmt) (value : Value)
    (after : Machine.State) (count : Nat) : Prop where
  bodyExact : checked.entrypoint.function.body = some body
  core : Executes executable.program coreBefore body
    (.returned (some value)) coreAfter
  steps : Machine.Steps count machineBefore after
  rax : LiteralReturn.RaxMatches value ((after.registers 0).setWidth 32)
  rip : after.rip = returnAddress
  stack : after.registers 4 = machineBefore.registers 4 + 8
  protectedCode : ProtectedCode machineBefore after checked.entrypoint.function

def Result (checked : Authenticated executable image)
    (coreBefore : Semantics.State) (machineBefore : Machine.State)
    (returnAddress : Machine.Address) : Prop :=
  ∃ (coreAfter : Semantics.State) (body : Stmt) (value : Value)
      (after : Machine.State) (count : Nat),
    ReturnedState checked coreBefore machineBefore returnAddress coreAfter body value after count

private theorem resultOfTwoSteps
    {checked : Authenticated executable image}
    {coreBefore : Semantics.State} {machineBefore : Machine.State}
    {returnAddress : Machine.Address} {body : Stmt} {value : Value}
    (bodyExact : checked.entrypoint.function.body = some body)
    (core : Executes executable.program coreBefore body
      (.returned (some value)) coreBefore)
    (machine : ∃ middle after, Machine.Step machineBefore middle ∧
      Machine.Step middle after ∧
      LiteralReturn.RaxMatches value ((after.registers 0).setWidth 32) ∧
      after.rip = returnAddress ∧
      after.registers 4 = machineBefore.registers 4 + 8 ∧
      ProtectedCode machineBefore after checked.entrypoint.function) :
    Result checked coreBefore machineBefore returnAddress := by
  rcases machine with ⟨middle, after, first, second, rax, rip, stack, protection⟩
  refine ⟨coreBefore, body, value, after, 2, {
    bodyExact := bodyExact, core := core, steps := ?_, rax := rax,
    rip := rip, stack := stack, protectedCode := protection }⟩
  exact Machine.Steps.cons first (Machine.Steps.cons second (Machine.Steps.refl _))

private theorem unchangedProtected {before after : Machine.State} (entry : Function)
    (memory : after.memory = before.memory) : ProtectedCode before after entry := by
  intro code bytes loaded _disjoint
  change Machine.CodeAt after.memory code bytes
  rw [memory]
  exact loaded

private theorem binaryProtected {before after : Machine.State} (entry : Function)
    (operation : Alu) (left right : Nat)
    (bodyExact : entry.body = some (ScalarValidator.binaryCoreBody operation left right))
    (resultBits : BitVec 32)
    (memory : after.memory = Machine.write32
      (Machine.write64 before.memory (before.registers 4 - 8) (before.registers 5))
      (before.registers 4 - 16) resultBits) : ProtectedCode before after entry := by
  intro code bytes loaded disjoint
  rw [memory]
  have saved := Machine.CodeAt.write64 loaded (before.registers 5) (by
    intro index bound lane
    exact disjoint index bound lane 8
      (by simp [entryStackFootprint, bodyExact, ScalarValidator.binaryCoreBody]))
  exact Machine.CodeAt.write32 saved resultBits (by
    intro index bound lane
    let lane8 : Fin 8 := ⟨lane.val, by omega⟩
    exact disjoint index bound lane8 16
      (by simp [entryStackFootprint, bodyExact, ScalarValidator.binaryCoreBody]))

private theorem directProtected {before after : Machine.State} (entry : Function)
    (callee : Function)
    (bodySupported : DirectCallFunctionCheck.CallerSupported entry callee)
    (displacement : BitVec 32)
    (memory : after.memory =
      (DirectCallFunctionCheck.callAfterState before displacement).memory) :
    ProtectedCode before after entry := by
  rcases bodySupported.bodyExact with bodyExact | bodyExact
  all_goals
    intro code bytes loaded disjoint
    have prologueRsp : (Machine.prologueState before 1).registers 4 =
      before.registers 4 - 24 := by
      simp [Machine.prologueState, Machine.State.alu64, Machine.State.alu,
        Machine.State.immediate32, Machine.State.move64, Machine.State.push64,
        Machine.rspRegister, Machine.rbpRegister, Machine.r11Register,
        Machine.frameSizeBits, Machine.frameBytes, Alu.result,
        BitVec.sub_eq_add_neg, BitVec.add_assoc]
    have prologueMemory : (Machine.prologueState before 1).memory =
      Machine.write64 before.memory (before.registers 4 - 8) (before.registers 5) := by
      rfl
    have callMemory :
      (DirectCallFunctionCheck.callAfterState before displacement).memory =
        Machine.write64 (Machine.prologueState before 1).memory
          ((Machine.prologueState before 1).registers 4 - 8)
          ((Machine.prologueState before 1).rip +
            BitVec.ofNat 64 (Machine.callBytes displacement).length) := by
      rfl
    rw [memory]
    have saved := Machine.CodeAt.write64 loaded (before.registers 5) (by
      intro index bound lane
      exact disjoint index bound lane 8
        (by simp [entryStackFootprint, bodyExact]))
    have returned := Machine.CodeAt.write64
      (address := (Machine.prologueState before 1).registers 4 - 8) saved
      ((Machine.prologueState before 1).rip +
        BitVec.ofNat 64 (Machine.callBytes displacement).length) (by
      intro index bound lane
      have h := disjoint index bound lane 32 (by
        simp [entryStackFootprint, bodyExact])
      rw [prologueRsp]
      simpa [Machine.rspRegister, rspRegister, BitVec.sub_sub] using h)
    rw [callMemory, prologueMemory]
    exact returned

private theorem projectLiteralBits
    {function : Function} {program : Program} {coreBefore : Semantics.State}
    {machineBefore : Machine.State} {returnAddress : Machine.Address}
    {body : Stmt} {value : Value} (bits : BitVec 32)
    (preserved : function.body = some body ∧
      Executes program coreBefore body (.returned (some value)) coreBefore ∧
      ∃ middle after, Machine.Step machineBefore middle ∧
        Machine.Step middle after ∧
        after.registers 0 = bits.setWidth 64 ∧
        (after.registers 0).setWidth 32 = bits ∧
        LiteralReturn.RaxMatches value ((after.registers 0).setWidth 32) ∧
        after.rip = returnAddress ∧
        after.registers 4 = machineBefore.registers 4 + 8 ∧
        (∀ register, register ≠ 0 → register ≠ 4 →
          after.registers register = machineBefore.registers register) ∧
        after.memory = machineBefore.memory ∧ after.flags = machineBefore.flags) :
    ∃ middle after, Machine.Step machineBefore middle ∧ Machine.Step middle after ∧
      LiteralReturn.RaxMatches value ((after.registers 0).setWidth 32) ∧
      after.rip = returnAddress ∧
      after.registers 4 = machineBefore.registers 4 + 8 ∧
      after.memory = machineBefore.memory := by
  apply Exists.imp (fun middle middleProof => ?_) preserved.2.2
  apply Exists.imp (fun after afterProof => ?_) middleProof
  exact ⟨afterProof.1, afterProof.2.1,
    afterProof.2.2.2.2.1, afterProof.2.2.2.2.2.1,
    afterProof.2.2.2.2.2.2.1,
    afterProof.2.2.2.2.2.2.2.2.1⟩

private theorem simpleResult
    {checked : Authenticated executable image}
    {coreBefore : Semantics.State} {machineBefore : Machine.State}
    {returnAddress : Machine.Address}
    {body : Stmt} {value : Value} {bits : BitVec 32}
    (bodyExact : checked.entrypoint.function.body = some body)
    (core : Executes executable.program coreBefore body
      (.returned (some value)) coreBefore)
    (preserved : checked.entrypoint.function.body = some body ∧
      Executes executable.program coreBefore body (.returned (some value)) coreBefore ∧
      ∃ middle after, Machine.Step machineBefore middle ∧ Machine.Step middle after ∧
        after.registers 0 = bits.setWidth 64 ∧
        (after.registers 0).setWidth 32 = bits ∧
        LiteralReturn.RaxMatches value ((after.registers 0).setWidth 32) ∧
        after.rip = returnAddress ∧
        after.registers 4 = machineBefore.registers 4 + 8 ∧
        (∀ register, register ≠ 0 → register ≠ 4 →
          after.registers register = machineBefore.registers register) ∧
        after.memory = machineBefore.memory ∧ after.flags = machineBefore.flags) :
    Result checked coreBefore machineBefore returnAddress := by
  have machine := projectLiteralBits bits preserved
  rcases machine with ⟨middle, after, first, second, rax, rip, stack, memory⟩
  apply resultOfTwoSteps bodyExact core
  exact ⟨middle, after, first, second, rax, rip, stack,
    unchangedProtected checked.entrypoint.function memory⟩

/- Every accepted authenticated entrypoint has one result of this shape. -/
theorem refines (checked : Authenticated executable image)
    (coreBefore : Semantics.State) (machineBefore : Machine.State)
    (loaded : checked.Loaded machineBefore)
    (environment : PreservationEnvironment checked coreBefore machineBefore)
    (frame : EntrypointFrame checked machineBefore)
    (ripAtEntry : machineBefore.rip = checked.entrypoint.image.address)
    (returnAddress : Machine.Address)
    (poppedReturn : Machine.read64 machineBefore.memory
      (machineBefore.registers 4) = returnAddress) :
    Result checked coreBefore machineBefore returnAddress := by
  cases checked with
  | standard checked =>
      cases environment with
      | standard _ _ formed textStack =>
          have loadedStandard := Authenticated.loaded_standard checked machineBefore loaded
          have preserved := checked.entrypoint_preserves coreBefore machineBefore loadedStandard
            formed ripAtEntry textStack returnAddress poppedReturn
          generalize h : checked.entrypoint.checked = entryChecked at preserved frame
          cases entryChecked with
          | literal supported bytesExact =>
              have preserved' : LiteralPreservation checked.entrypoint.function supported
                  executable.program coreBefore machineBefore returnAddress := by
                simpa [ProgramCheck.Preserves, h] using preserved
              exact simpleResult preserved'.1 preserved'.2.1 preserved'
          | literalParameters supported bytesExact =>
              have preserved' : LiteralParametersPreservation checked.entrypoint.function supported
                  executable.program coreBefore machineBefore returnAddress := by
                simpa [ProgramCheck.Preserves, h] using preserved
              exact simpleResult preserved'.1 preserved'.2.1 preserved'
          | literalParametersTrailing supported bytesExact =>
              have preserved' : LiteralParametersTrailingPreservation checked.entrypoint.function supported
                  executable.program coreBefore machineBefore returnAddress := by
                simpa [ProgramCheck.Preserves, h] using preserved
              exact simpleResult preserved'.1 preserved'.2.1 preserved'
          | literalTrailing supported bytesExact =>
              have preserved' : LiteralTrailingPreservation checked.entrypoint.function supported
                  executable.program coreBefore machineBefore returnAddress := by
                simpa [ProgramCheck.Preserves, h] using preserved
              exact simpleResult preserved'.1 preserved'.2.1 preserved'
          | parameter supported bytesExact =>
              have zero := checked.entrypointZeroParameters
              have position := supported.position
              rw [zero] at position
              exact Fin.elim0 position
          | body supported =>
              have frameParts : ExpressionFunctionCheck.BodyFrameInvariant
                  supported.checkedShape.1 machineBefore ∧
                  (∀ slot, slot < supported.checkedShape.1.allocations →
                    frameSlotAddress (machineBefore.registers rspRegister - 8) slot =
                      machineBefore.registers rspRegister -
                        BitVec.ofNat 64 (16 + 8 * slot)) := by
                simpa [EntrypointFrame, h] using frame
              have frame' : ExpressionFunctionCheck.BodyFrameInvariant
                  supported.checkedShape.1 machineBefore := frameParts.1
              have preservedAll : ∀ frame : ExpressionFunctionCheck.BodyFrameInvariant
                  supported.checkedShape.1 machineBefore,
                  ExpressionFunctionCheck.BodySupported.result supported executable.program
                    coreBefore machineBefore returnAddress := by
                simpa [ProgramCheck.Preserves, h] using preserved
              have preserved' := preservedAll frame'
              rcases preserved' with ⟨bodyCoreAfter, body, value, after, count, state⟩
              refine ⟨bodyCoreAfter, body, value, after, count, {
                bodyExact := state.bodyExact
                core := state.core
                steps := state.steps
                rax := state.rax
                rip := state.rip
                stack := state.stack
                protectedCode := ?_ }⟩
              intro code bytes loaded disjoint
              apply state.protectedCode code bytes loaded
              · intro index bound lane
                exact disjoint index bound lane 8
                  (by
                    simp [entryStackFootprint])
              · intro index bound slot slotBound lane
                let lane8 : Fin 8 := ⟨lane.val, by omega⟩
                have h := disjoint index bound lane8
                  (16 + 8 * slot)
                  (body_frame_slot_mem supported.bodyExact slotBound)
                have slotAddress := frameParts.2 slot slotBound
                have rbpExact :
                    (Machine.prologueState machineBefore
                      supported.checkedShape.1.allocations).registers rbpRegister =
                      machineBefore.registers rspRegister - 8 := by
                  simp [Machine.prologueState, Machine.State.alu64, Machine.State.alu,
                    Machine.State.immediate32, Machine.State.move64, Machine.State.push64,
                    rbpRegister, rspRegister, r11Register, frameSizeBits, frameBytes,
                    Alu.result, BitVec.sub_eq_add_neg, BitVec.add_assoc]
                rw [rbpExact, slotAddress]
                simpa [lane8] using h
  | direct displacement checked =>
      cases environment with
      | direct literal formed layout =>
          let callee := DirectCalleeMode.literalEvidence literal
          have preserved := Authenticated.entrypoint_preserves
            (.direct displacement checked) coreBefore machineBefore loaded
            (.direct literal formed layout) ripAtEntry returnAddress poppedReturn
          have preserved' :
              (∃ body, checked.caller.body = some body ∧
                Executes executable.program coreBefore body
                  (.returned (some (.signed .i32 callee.calleeBits.toInt))) coreBefore) ∧
              ∃ after calleeCount, Machine.Steps (calleeCount + 9) machineBefore after ∧
                ((after.registers DirectCallCheck.resultRegister).setWidth 32).toInt =
                  callee.calleeBits.toInt ∧
                after.rip = returnAddress ∧
                after.registers DirectCallCheck.stackRegister =
                  machineBefore.registers DirectCallCheck.stackRegister + 8 ∧
                after.memory =
                  (DirectCallFunctionCheck.callAfterState machineBefore displacement).memory := by
            simpa [Authenticated.Preserves] using preserved
          rcases preserved' with ⟨⟨body, bodyExact, core⟩, after, count, steps, result,
            target, stack, memory⟩
          refine ⟨coreBefore, body, _, after, count + 9, {
            bodyExact := bodyExact
            core := core
            steps := steps
            rax := by
              simpa [DirectCallCheck.resultRegister, LiteralReturn.RaxMatches] using result
            rip := target
            stack := by simpa [DirectCallCheck.stackRegister] using stack
            protectedCode := directProtected checked.caller checked.callee
              checked.callerChecked.callerSupported displacement memory }⟩

end Lanius.X86.EntrypointRefinement
