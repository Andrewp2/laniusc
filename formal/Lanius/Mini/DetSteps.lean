import Lanius.Mini.StepDet

/-! Which byte forms the mini compiler emits read or set the flags, for
`Det.cons` and `Det.pair`, and the frame prologue and epilogue as `Det`
runs. -/

namespace Lanius.X86.Machine

variable {s : State}

theorem move_noRead {width : X86.Register.Width} {destination source : Register}
    (loaded : CodeAt s.memory s.rip (moveBytes width destination source)) : NoRead s :=
  NoRead.of loaded (move_decodes width destination source) (by cases width <;> rfl)

theorem immediate_noRead {width : X86.Register.Width} {destination : Register} {low high : BitVec 32}
    (loaded : CodeAt s.memory s.rip (immediateBytes width destination low high)) : NoRead s :=
  NoRead.of loaded (immediate_decodes width destination low high) (by cases width <;> rfl)

theorem alu_noRead {width : X86.Register.Width} {operation : Alu} {destination source : Register}
    (loaded : CodeAt s.memory s.rip (aluBytes width operation destination source)) : NoRead s :=
  NoRead.of loaded (alu_decodes width operation destination source) (by cases width <;> rfl)

theorem alu_writes {width : X86.Register.Width} {operation : Alu} {destination source : Register}
    (loaded : CodeAt s.memory s.rip (aluBytes width operation destination source)) : Writes s :=
  Writes.of loaded (alu_decodes width operation destination source) (by cases width <;> rfl)

theorem test_writes {width : X86.Register.Width} {left right : Register}
    (loaded : CodeAt s.memory s.rip (testBytes width left right)) : Writes s :=
  Writes.of loaded (test_decodes width left right) (by cases width <;> rfl)

theorem compare_writes {left right : Register}
    (loaded : CodeAt s.memory s.rip (compareBytes left right)) : Writes s :=
  Writes.of loaded (compare_decodes left right) rfl

theorem multiply_noRead {width : X86.Register.Width} {destination source : Register}
    (loaded : CodeAt s.memory s.rip (multiplyBytes width destination source)) : NoRead s :=
  NoRead.of loaded (multiply_decodes width destination source) (by cases width <;> rfl)

theorem shift_noRead {width : X86.Register.Width} {operation : Shift} {destination : Register}
    (loaded : CodeAt s.memory s.rip (shiftBytes width operation destination)) : NoRead s :=
  NoRead.of loaded (shift_decodes width operation destination) (by cases width <;> rfl)

theorem negate_noRead {width : X86.Register.Width} {destination : Register}
    (loaded : CodeAt s.memory s.rip (negateBytes width destination)) : NoRead s :=
  NoRead.of loaded (negate_decodes width destination) (by cases width <;> rfl)

theorem push_noRead {source : Register} (loaded : CodeAt s.memory s.rip (pushBytes source)) : NoRead s :=
  NoRead.of loaded (push_decodes source) rfl

theorem pop_noRead {destination : Register} (loaded : CodeAt s.memory s.rip (popBytes destination)) :
    NoRead s :=
  NoRead.of loaded (pop_decodes destination) rfl

theorem return_noRead (loaded : CodeAt s.memory s.rip returnBytes) : NoRead s :=
  NoRead.of loaded return_decodes rfl

theorem call_noRead {displacement : BitVec 32} (loaded : CodeAt s.memory s.rip (callBytes displacement)) :
    NoRead s :=
  NoRead.of loaded (call_decodes displacement) rfl

theorem jump_noRead {displacement : BitVec 32} (loaded : CodeAt s.memory s.rip (jumpBytes displacement)) :
    NoRead s :=
  NoRead.of loaded (jump_decodes displacement) rfl

theorem zeroExtendByte_noRead {destination source : Register}
    (loaded : CodeAt s.memory s.rip (zeroExtendByteBytes destination source)) : NoRead s :=
  NoRead.of loaded (zeroExtendByte_decodes destination source) rfl

theorem loadByte_noRead {destination base : Register} {displacement : Int}
    (loaded : CodeAt s.memory s.rip (loadByteBytes destination base displacement)) : NoRead s :=
  NoRead.of loaded (by simpa using loadByte_decodes destination base displacement []) rfl

theorem storeByte_noRead {source base : Register} {displacement : Int}
    (loaded : CodeAt s.memory s.rip (storeByteBytes source base displacement)) : NoRead s :=
  NoRead.of loaded (by simpa using storeByte_decodes source base displacement []) rfl

theorem memory_noRead {width : X86.Register.Width} {load : Bool} {reg base : Register} {displacement : Int}
    (loaded : CodeAt s.memory s.rip (memoryBytes width load reg base displacement)) : NoRead s :=
  NoRead.of loaded (by simpa using memory_decodes width load reg base displacement [])
    (by cases width <;> cases load <;> rfl)

theorem frameLoad_noRead {slot : Nat} (loaded : CodeAt s.memory s.rip (frameLoadBytes slot)) : NoRead s :=
  NoRead.of loaded (frameLoad_decodes slot) rfl

theorem frameStore_noRead {slot : Nat} (loaded : CodeAt s.memory s.rip (frameStoreBytes slot)) : NoRead s :=
  NoRead.of loaded (frameStore_decodes slot) rfl

/-- The frame prologue, `push rbp; mov rbp, rsp; mov r11d, size; sub rsp, r11`,
under the hypotheses of `framePrologue_steps`. -/
theorem framePrologue_det (slots : Nat) (before : State)
    (loaded : CodeAt before.memory before.rip (framePrologueBytes slots))
    (pushDisjoint : ∀ index, index <
      (moveBytes .w64 rbpRegister rspRegister ++
        immediateBytes .w32 r11Register (frameSizeBits slots) 0 ++
        aluBytes .w64 .subtract rspRegister r11Register).length →
      ∀ lane : Fin 8,
        (before.rip + BitVec.ofNat 64
          ((pushBytes rbpRegister).length + index)) + BitVec.ofNat 64 0 ≠
        (before.registers rspRegister - 8) + BitVec.ofNat 64 lane.val) :
    Steps 4 before (prologueState before slots) ∧ Det 4 before (prologueState before slots) := by
  refine ⟨framePrologue_steps slots before loaded pushDisjoint, ?_⟩
  let pushBytes' := pushBytes rbpRegister
  let rbpBytes' := moveBytes .w64 rbpRegister rspRegister
  let sizeBytes' := immediateBytes .w32 r11Register (frameSizeBits slots) 0
  let subBytes' := aluBytes .w64 .subtract rspRegister r11Register
  have loaded' : CodeAt before.memory before.rip
      (pushBytes' ++ (rbpBytes' ++ (sizeBytes' ++ subBytes'))) := by
    simpa [framePrologueBytes, pushBytes', rbpBytes', sizeBytes', subBytes',
      List.append_assoc] using loaded
  let pushed := before.push64 rbpRegister pushBytes'.length
  have pushLoaded : CodeAt before.memory before.rip pushBytes' := loaded'.prefix
  have pushStep' : Step before pushed := by
    apply prologue_push_step before pushed pushLoaded
    rfl
  have tailAfterPush : CodeAt pushed.memory pushed.rip
      (rbpBytes' ++ (sizeBytes' ++ subBytes')) := by
    have source := loaded'.suffix
    have protectedCode := CodeAt.write64 source (before.registers rbpRegister)
      (by
        intro index bound lane
        simpa [pushed, State.push64, pushBytes', rbpRegister, rspRegister,
          BitVec.ofNat_add, BitVec.add_assoc] using pushDisjoint index bound lane)
    simpa [pushed, State.push64, pushBytes'] using protectedCode
  let rbpSet := pushed.move64 rbpRegister rspRegister rbpBytes'.length
  have rbpLoaded : CodeAt pushed.memory pushed.rip rbpBytes' :=
    tailAfterPush.prefix
  have rbpStep' : Step pushed rbpSet := by
    apply prologue_rbp_step pushed rbpSet rbpLoaded
    rfl
  have tailAfterRbp : CodeAt rbpSet.memory rbpSet.rip
      (sizeBytes' ++ subBytes') := by
    simpa [rbpSet, pushed, State.move64, rbpBytes'] using tailAfterPush.suffix
  let sized := rbpSet.immediate32 r11Register (frameSizeBits slots) sizeBytes'.length
  have sizeLoaded : CodeAt rbpSet.memory rbpSet.rip sizeBytes' :=
    tailAfterRbp.prefix
  have sizeStep' : Step rbpSet sized := by
    apply prologue_size_step rbpSet sized slots sizeLoaded
    rfl
  have subLoaded : CodeAt sized.memory sized.rip subBytes' := by
    simpa [sized, rbpSet, State.immediate32, sizeBytes'] using
      tailAfterRbp.suffix
  let after := sized.alu64 .subtract rspRegister r11Register false subBytes'.length
  have subStep' : Step sized after := by
    apply prologue_sub_step sized after subLoaded false
    rfl
  have all : Det 4 before after :=
    Det.cons pushStep' (push_noRead pushLoaded)
      (Det.cons rbpStep' (move_noRead rbpLoaded)
        (Det.cons sizeStep' (immediate_noRead sizeLoaded)
          (Det.cons subStep' (alu_noRead subLoaded) (Det.refl after))))
  simpa [prologueState, pushed, rbpSet, sized, after, pushBytes', rbpBytes',
    sizeBytes', subBytes'] using all

/-- The frame epilogue, `mov rsp, rbp; pop rbp; ret`. -/
theorem frameEpilogue_det (before : State)
    (loaded : CodeAt before.memory before.rip
      (moveBytes .w64 rspRegister rbpRegister ++ popBytes rbpRegister ++ returnBytes)) :
    Det 3 before (epilogueState before) := by
  let moveBytes' := moveBytes .w64 rspRegister rbpRegister
  let popBytes' := popBytes rbpRegister
  have loaded' : CodeAt before.memory before.rip
      (moveBytes' ++ (popBytes' ++ returnBytes)) := by
    simpa [moveBytes', popBytes', List.append_assoc] using loaded
  let moved := before.move64 rspRegister rbpRegister moveBytes'.length
  have moveLoaded : CodeAt before.memory before.rip moveBytes' := loaded'.prefix
  have moveStep' : Step before moved := by
    apply move_step before moved .w64 rspRegister rbpRegister moveLoaded
    rfl
  have moveTail : CodeAt moved.memory moved.rip (popBytes' ++ returnBytes) := by
    simpa [moved, State.move64, moveBytes'] using loaded'.suffix
  let popped := moved.pop64 rbpRegister popBytes'.length
  have popLoaded : CodeAt moved.memory moved.rip popBytes' := moveTail.prefix
  have popStep' : Step moved popped := by
    apply pop_step moved popped rbpRegister popLoaded
    rfl
  have returnLoaded : CodeAt popped.memory popped.rip returnBytes := by
    simpa [popped, State.pop64, popBytes'] using moveTail.suffix
  have returnStep' : Step popped popped.returnNear := by
    apply return_step popped popped.returnNear returnLoaded
    rfl
  exact Det.cons moveStep' (move_noRead moveLoaded)
    (Det.cons popStep' (pop_noRead popLoaded)
      (Det.cons returnStep' (return_noRead returnLoaded) (Det.refl _)))

/-! ## `syscall` -/

/-- From states that agree but for their flags, the kernel leaves states that
agree but for their flags and r11. -/
theorem Kernel.agree (same : DataEq s t) (ka : Kernel s a) (kb : Kernel t b) :
    (∀ r, r ≠ 11 → a.registers r = b.registers r) ∧ a.rip = b.rip ∧ a.memory = b.memory ∧ a.io = b.io := by
  obtain ⟨R, P, M, F, I⟩ := s
  obtain ⟨R', P', M', G, I'⟩ := t
  obtain ⟨hR, hP, hM, hI⟩ := same
  simp only at hR hP hM hI
  subst hR hP hM hI
  cases ka with
  | write number fd count r11 =>
    cases kb with
    | write number' fd' count' r11' =>
      refine ⟨fun r ne => ?_, rfl, rfl, rfl⟩
      simp only [State.syscalled, if_neg ne]

/-- A `syscall`, then `mov r11, source`, which gives r11 a value the data
determines again. -/
theorem Det.syscall (sa : Step s a) (sys : CodeAt s.memory s.rip [15, 5]) {source : Register}
    (other : source ≠ 11) (kill : CodeAt a.memory a.rip (moveBytes .w64 11 source)) (ab : Step a b) :
    Det 2 s b := by
  have kernelOf : ∀ {t u}, DataEq s t → Step t u → Kernel t u := by
    intro t u same tu
    rcases tu.results with ⟨i, k, d, -⟩ | ⟨-, kernel⟩
    · exact (d.not_syscall (by rw [← same.memory, ← same.rip]; exact sys)).elim
    · exact kernel
  have ka := kernelOf (DataEq.refl s) sa
  have decodes : ∀ {u}, u.memory = a.memory → u.rip = a.rip →
      DecodesAt u (moveInstruction .w64 11 source) (moveBytes .w64 11 source).length :=
    fun memory rip => ⟨_, by rw [memory, rip]; exact kill, move_decodes .w64 11 source⟩
  refine ⟨fun t t' same run => ?_, fun j t u small same run => ?_⟩
  · cases run with
    | cons tu rest =>
      cases rest with
      | cons ut' rest =>
        cases rest
        obtain ⟨registers, rip, memory, io⟩ := Kernel.agree same ka (kernelOf same tu)
        have rb := ab.decodedResults (decodes rfl rfl)
        have ru := ut'.decodedResults (decodes memory.symm rip.symm)
        simp only [Results, moveInstruction] at rb ru
        subst rb ru
        refine ⟨funext fun r => ?_, by simp only [State.move64, rip], memory, io⟩
        simp only [State.move64]
        by_cases eleven : r = 11
        · rw [if_pos eleven, if_pos eleven, registers source other]
        · rw [if_neg eleven, if_neg eleven, registers r eleven]
  · cases run with
    | refl => exact sa.live same
    | cons tu rest =>
      cases rest with
      | refl =>
        obtain ⟨-, rip, memory, -⟩ := Kernel.agree same ka (kernelOf same tu)
        exact ⟨_, .decoded _ (by rw [← memory, ← rip]; exact kill) _ _ (move_decodes .w64 11 source) rfl rfl⟩
      | cons _ _ => omega

end Lanius.X86.Machine
