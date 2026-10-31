import Lanius.Mini.Correct
import Lanius.Mini.Stops

/-! The compiled code of a run that does not return does not return either.
A failed allocation reaches the `ud2` after `bump`'s limit test, a division
by zero or of the least value by -1 raises `#DE`, and every abstract step
and every call takes at least one x86 step, so an abstract run that is
`AStops` for `n` gives an x86 run whose stops before `n` steps are all
faults (`FaultsWithin n`). With `Stops` for every `n`, every run of the
compiled code that stops, stops at a fault (`compileProgram_stops`). -/

namespace Lanius.Mini
open Lanius.X86.Machine

theorem Word.divides_of (word : Word) (operation : DivOp) (a b : BitVec 64)
    (nonzero : b.setWidth word.width.bits ≠ 0)
    (fits : operation.signed = true → a.setWidth word.width.bits ≠ BitVec.intMin _ ∨
      b.setWidth word.width.bits ≠ -1) :
    word.divides operation a b = true := by
  cases word <;> cases operation <;>
    simp_all [Word.divides, DivOp.defined, DivOp.signed, Word.width, X86.Register.Width.bits] <;>
    exact Classical.not_and_iff_not_or_not.mpr fits

/-- The dividend's high half, then a divide whose divisor is zero, or that
divides the least value by -1: the divide faults. -/
theorem division_fault (word : Word) (signed : Bool) (st : State)
    (loaded : CodeAt st.memory st.rip (dividendBytes word signed ++ divisionBytes word.width signed rcxRegister))
    (undefined : ¬((st.registers rcxRegister).setWidth word.width.bits ≠ 0 ∧ (signed = true →
      (st.registers 0).setWidth word.width.bits ≠ BitVec.intMin _ ∨
        (st.registers rcxRegister).setWidth word.width.bits ≠ -1))) :
    ∃ st', Det 1 st st' ∧ Fault st' := by
  obtain ⟨st1, t1, no1, io1, memory1, rip1, kept1, high⟩ := dividend_step word signed st loaded.prefix
  have c1 := loaded.next (s' := st1) memory1 rip1
  have rax1 := kept1 0 (by decide)
  have rcx1 := kept1 rcxRegister (by decide)
  refine ⟨st1, Det.step t1 no1, ?_⟩
  have decoded : decode (divisionBytes word.width signed rcxRegister) = some (match word.width with
      | .w32 => .divide32 signed rcxRegister
      | .w64 => .divide64 signed rcxRegister, (divisionBytes word.width signed rcxRegister).length) := by
    cases word <;> simpa [divisionInstruction, Word.width] using division_decodes _ signed rcxRegister
  by_cases zero : (st.registers rcxRegister).setWidth word.width.bits = 0
  · refine .divideByZero _ c1 word.width signed rcxRegister decoded ?_
    unfold divisionByZero
    rw [rcx1, zero]
    rfl
  · have bad : ¬(signed = true → (st.registers 0).setWidth word.width.bits ≠ BitVec.intMin _ ∨
        (st.registers rcxRegister).setWidth word.width.bits ≠ -1) := fun fits => undefined ⟨zero, fits⟩
    rw [Classical.not_imp, not_or, Classical.not_not, Classical.not_not] at bad
    obtain ⟨rfl, least, minusOne⟩ := bad
    refine .divideOverflow _ c1 word.width true rcxRegister decoded ⟨?_, ?_⟩
    · unfold divisionByZero
      rw [rcx1]
      intro isZero
      exact zero (BitVec.eq_of_toNat_eq (by simpa using isZero))
    · obtain ⟨pos, -⟩ := word.width_bits
      unfold divisionFits divisionDivisor
      rw [signedDividend_eq st1 pos high, rax1, rcx1, least, minusOne, if_pos rfl]
      cases word <;> decide

/-- A division whose source result is undefined faults. -/
theorem div_fails (word : Word) (operation : DivOp) (rel : Rel frame s m) (inFrame : slot < frame.slots)
    (loaded : CodeAt s.memory s.rip (operation.spec word slot))
    (undefined : word.divides operation (m.slots slot) m.acc = false) : Faults s := by
  have split : operation.spec word slot = accToRcxBytes ++ (slotLoadBytes slot ++
      (moveBytes .w64 r11Register rdxRegister ++
      ((dividendBytes word operation.signed ++ divisionBytes word.width operation.signed rcxRegister) ++
      (resultBytes operation.remainder ++ moveBytes .w64 rdxRegister r11Register)))) := by
    simp only [DivOp.spec, List.append_assoc]
  rw [split] at loaded
  let s1 := s.move64 rcxRegister 0 3
  have t1 := accToRcx_step s s1 loaded.prefix rfl
  have c1 := loaded.next (s' := s1) rfl (by simp [s1, State.move64, accToRcx_length])
  let s2 := s1.load64 0 rbpRegister (BitVec.ofInt 32 (frameDisplacement slot)) (slotLoadBytes slot).length
  have t2 := slotLoad_step s1 s2 slot c1.prefix rfl
  have c2 := c1.next (s' := s2) rfl rfl
  let s3 := s2.move64 r11Register rdxRegister (moveBytes .w64 r11Register rdxRegister).length
  have t3 := move_step s2 s3 .w64 r11Register rdxRegister c2.prefix rfl
  have c3 := c2.next (s' := s3) rfl rfl
  have a3 : s3.registers 0 = m.slots slot := by
    simp [s3, s2, s1, State.move64, State.load64, rdxRegister, r11Register, rbpRegister, rcxRegister,
      rel_slot rel inFrame]
  have b3 : s3.registers rcxRegister = m.acc := by
    simp [s3, s2, s1, State.move64, State.load64, rdxRegister, r11Register, rcxRegister, rel.acc]
  have bad : ¬((s3.registers rcxRegister).setWidth word.width.bits ≠ 0 ∧ (operation.signed = true →
      (s3.registers 0).setWidth word.width.bits ≠ BitVec.intMin _ ∨
        (s3.registers rcxRegister).setWidth word.width.bits ≠ -1)) := by
    rintro ⟨nonzero, fits⟩
    rw [b3] at nonzero
    rw [a3, b3] at fits
    rw [Word.divides_of word operation _ _ nonzero fits] at undefined
    cases undefined
  obtain ⟨s4, det4, fault⟩ := division_fault word operation.signed s3 c3.prefix bad
  exact (Det.cons t1 (move_noRead loaded.prefix) (Det.cons t2 (slotLoad_noRead c1.prefix)
    (Det.cons t3 (move_noRead c2.prefix) det4))).faults fault.faults

/-- `bump` past the heap's limit: the end wraps and `jb` jumps to the `ud2`,
or the limit test fails and the run falls through to it. -/
theorem bump_fails (rel : Rel frame s m) (fits : frame.Fits) {shift : Nat} (shiftSmall : shift < 32)
    (loaded : CodeAt s.memory s.rip (bumpSpec shift)) (inside : m.heap.cursor ≤ m.heap.limit)
    (over : m.heap.limit < alignUp m.heap.cursor shift + m.acc.toNat) : Faults s := by
  have atCursor := rel.cursor
  have atLimit := rel.limitNat
  have limitSmall : m.heap.limit < 2 ^ 62 := by rw [rel.limit]; exact fits.heapSmall
  rw [← rel.acc] at over
  generalize m.heap.cursor = cursor at atCursor over inside
  generalize m.heap.limit = limit at atLimit over limitSmall inside
  have c0 := loaded
  simp only [bumpSpec] at c0
  let s1 := s.move64 rcxRegister cursorRegister (moveBytes .w64 rcxRegister cursorRegister).length
  have t1 : Lanius.X86.Machine.Step s s1 := move_step s s1 .w64 _ _ c0.prefix rfl
  have c1 := c0.next (s' := s1) rfl rfl
  let s2 := s1.immediate64 r11Register
    (BitVec.ofNat 64 ((lowHalf (pow2 shift - 1)).toNat + 4294967296 * (highHalf (pow2 shift - 1)).toNat))
    (r11Bytes (pow2 shift - 1)).length
  have t2 : Lanius.X86.Machine.Step s1 s2 := immediate_step s1 s2 .w64 r11Register _ _ c1.prefix rfl
  have c2 := c1.next (s' := s2) rfl rfl
  let s3 := s2.alu64 .add rcxRegister r11Register false (aluBytes .w64 .add rcxRegister r11Register).length
  have t3 : Lanius.X86.Machine.Step s2 s3 := alu_step .w64 s2 s3 .add _ _ c2.prefix false rfl
  have c3 := c2.next (s' := s3) rfl rfl
  let s4 := s3.immediate64 r11Register
    (BitVec.ofNat 64 ((lowHalf (0 - pow2 shift)).toNat + 4294967296 * (highHalf (0 - pow2 shift)).toNat))
    (r11Bytes (0 - pow2 shift)).length
  have t4 : Lanius.X86.Machine.Step s3 s4 := immediate_step s3 s4 .w64 r11Register _ _ c3.prefix rfl
  have c4 := c3.next (s' := s4) rfl rfl
  let s5 := s4.alu64 .and rcxRegister r11Register false (aluBytes .w64 .and rcxRegister r11Register).length
  have t5 : Lanius.X86.Machine.Step s4 s5 := alu_step .w64 s4 s5 .and _ _ c4.prefix false rfl
  have c5 := c4.next (s' := s5) rfl rfl
  let s6 := s5.move64 r11Register rcxRegister (moveBytes .w64 r11Register rcxRegister).length
  have t6 : Lanius.X86.Machine.Step s5 s6 := move_step s5 s6 .w64 _ _ c5.prefix rfl
  have c6 := c5.next (s' := s6) rfl rfl
  let s7 := s6.alu64 .add r11Register 0 false (aluBytes .w64 .add r11Register 0).length
  have t7 : Lanius.X86.Machine.Step s6 s7 := alu_step .w64 s6 s7 .add _ _ c6.prefix false rfl
  have c7 := c6.next (s' := s7) rfl rfl
  have cursorSmall : cursor < 2 ^ 62 := by omega
  have rounded : s5.registers rcxRegister = BitVec.ofNat 64 (alignUp cursor shift) := by
    simp only [s5, s4, s3, s2, s1, State.alu64, State.alu, State.immediate64, State.move64, Alu.result,
      lowHalf_highHalf, BitVec.setWidth_eq, rcxRegister, r11Register, cursorRegister]
    simp only [if_pos, if_neg (show (1 : Register) ≠ 11 by decide)]
    rw [show s.registers 13 = BitVec.ofNat 64 cursor from atCursor]
    exact align_mask cursor shift shiftSmall cursorSmall
  have alignedSmall : alignUp cursor shift < 2 ^ 63 := by
    have le : alignUp cursor shift ≤ cursor + 2 ^ shift - 1 := Nat.div_mul_le_self _ _
    have pow : 2 ^ shift ≤ 2 ^ 31 := Nat.pow_le_pow_right (by omega) (by omega)
    omega
  have accKept : s6.registers 0 = s.registers 0 := by
    simp [s6, s5, s4, s3, s2, s1, State.alu64, State.alu, State.immediate64, State.move64, rcxRegister,
      r11Register]
  have moved : s6.registers r11Register = s5.registers rcxRegister := by simp [s6, State.move64]
  have ended : s7.registers r11Register = BitVec.ofNat 64 (alignUp cursor shift) + s.registers 0 := by
    simp only [s7, State.alu64, State.alu, Alu.result, BitVec.setWidth_eq, if_pos, moved, rounded, accKept]
  have limitKept : s7.registers limitRegister = s.registers limitRegister := by
    simp [s7, s6, s5, s4, s3, s2, s1, State.alu64, State.alu, State.immediate64, State.move64, rcxRegister,
      r11Register, limitRegister]
  have carry : condition s7.flags 2 = decide (2 ^ 64 ≤ alignUp cursor shift + (s.registers 0).toNat) := by
    show s7.flags.getLsbD 0 = _
    simp only [s7, State.alu64, State.alu, Alu.flags, arithmeticFlags_carry, BitVec.setWidth_eq,
      moved, rounded, accKept, BitVec.toNat_ofNat, Nat.mod_eq_of_lt (show alignUp cursor shift < 2 ^ 64 by omega)]
  have prefix6 : Det 6 s s6 :=
    Det.cons t1 (move_noRead c0.prefix) (Det.cons t2 (immediate_noRead c1.prefix)
      (Det.cons t3 (alu_noRead c2.prefix) (Det.cons t4 (immediate_noRead c3.prefix)
        (Det.cons t5 (alu_noRead c4.prefix) (Det.cons t6 (move_noRead c5.prefix) (Det.refl _))))))
  let s7' := s7.branch 2 9 6
  by_cases wraps : 2 ^ 64 ≤ alignUp cursor shift + (s.registers 0).toNat
  · obtain ⟨t7', rip7'⟩ := branch_step_rip s7 s7' 2 9 c7.prefix (by rw [carry]; simpa using wraps) rfl
    have fault : Fault s7' := by
      refine .ud2 ?_
      have tail := c7.suffix.suffix.suffix.prefix
      rw [show s7'.memory = s7.memory from rfl, rip7',
        show ((9 : BitVec 32).signExtend 64) = BitVec.ofNat 64 9 from by decide,
        show s7.rip + BitVec.ofNat 64 6 + BitVec.ofNat 64 9 = s7.rip + BitVec.ofNat 64 (branchBytes 2 9).length +
          BitVec.ofNat 64 limitCompareBytes.length + BitVec.ofNat 64 (branchBytes 6 2).length from by
        simp only [branchBytes, displacementBytes, limitCompareBytes, List.length_cons, List.length_nil,
          List.length_append]
        bv_omega]
      exact tail
    exact (prefix6.trans (Det.pairCons t7 (alu_writes c6.prefix) t7' ⟨_, c7.prefix, branch_decodes 2 9⟩ (Det.refl _))).faults fault.faults
  · obtain ⟨t7', rip7'⟩ := branch_step_rip_not_taken s7 s7' 2 9 c7.prefix (by rw [carry]; simpa using wraps) rfl
    have c7' : CodeAt s7'.memory s7'.rip (limitCompareBytes ++ (branchBytes 6 2 ++ (trapBytes ++
        (moveBytes .w64 cursorRegister r11Register ++ moveBytes .w64 0 rcxRegister)))) := by
      have tail := c7.suffix
      rw [show s7'.memory = s7.memory from rfl, rip7',
        show s7.rip + 6#64 + 0 = s7.rip + BitVec.ofNat 64 (branchBytes 2 9).length from by
          simp [branchBytes, displacementBytes]]
      exact tail
    let s8 := s7'.compare64 r11Register limitRegister limitCompareBytes.length
    have t8 : Lanius.X86.Machine.Step s7' s8 :=
      Lanius.X86.Machine.Step.decoded limitCompareBytes c7'.prefix (.compare64 r11Register limitRegister) 3
        (by decide) rfl rfl
    have c8 := c7'.next (s' := s8) rfl rfl
    have endedNat : (BitVec.ofNat 64 (alignUp cursor shift) + s.registers 0).toNat =
        alignUp cursor shift + (s.registers 0).toNat := by
      rw [BitVec.toNat_add, BitVec.toNat_ofNat]; omega
    have notTaken : condition s8.flags 6 = false := by
      show condition (subtractFlags s7'.flags (s7.registers r11Register) (s7.registers limitRegister))
        (CmpOp.code .u64 .le) = false
      rw [CmpOp.conditionU, ended, limitKept]
      simp only [CmpOp.holdsU, BitVec.ule, decide_eq_false_iff_not, endedNat, atLimit]
      omega
    let s9 := s8.branch 6 2 6
    obtain ⟨t9, rip9⟩ := branch_step_rip_not_taken s8 s9 6 2 c8.prefix notTaken rfl
    have fault : Fault s9 := by
      refine .ud2 ?_
      have tail := c8.suffix.prefix
      rw [show s9.memory = s8.memory from rfl, rip9,
        show s8.rip + 6#64 + 0 = s8.rip + BitVec.ofNat 64 (branchBytes 6 2).length from by
          simp [branchBytes, displacementBytes]]
      exact tail
    exact (prefix6.trans (Det.pairCons t7 (alu_writes c6.prefix) t7' ⟨_, c7.prefix, branch_decodes 2 9⟩
      (Det.pairCons t8 (Writes.of (i := .compare64 r11Register limitRegister) (k := 3) c7'.prefix
        (by decide) rfl) t9 ⟨_, c8.prefix, branch_decodes 6 2⟩ (Det.refl _)))).faults fault.faults

/-- Function `callee`, entered as `Contract` enters it, runs `n` steps
without stopping anywhere but at a fault. -/
def StopsContract (binary : Binary) (imageBase : BitVec 64) (window callee : Nat) (args : List (BitVec 64))
    (heap : Heap) (n : Nat) : Prop :=
  ∀ s : State, window ≤ 2 ^ 62 → CodeAt s.memory imageBase binary.image →
    (∀ index, index < binary.image.length →
      ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index)) →
    (∀ index, index < binary.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index)) →
    s.rip = imageBase + BitVec.ofNat 64 (binary.entries.getD callee 0) →
    (∀ k (bound : k < args.length),
      read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = args[k]) →
    HeapAt window s heap → StackAt binary.guard window s → FaultsWithin n s

variable {binary : Binary} {imageBase : BitVec 64} {place : Place} {instrs : List Instr}

/-- The bytes of a body stop only at faults for as long as its abstract run does. -/
theorem body_stops (body : Body frame binary imageBase place instrs) (fits : frame.Fits) {calls : Calls}
    {stops : StopCalls} {need : Nat}
    (callContract : ∀ callee vals heap value after, calls callee vals heap value after → ∃ needC,
      needC + frameBytes frame.slots + 16 ≤ need ∧ 8 * vals.length + 16 ≤ frame.window - (frameBytes frame.slots + 16) ∧
        Contract binary imageBase needC (frame.window - (frameBytes frame.slots + 16)) callee vals heap value after)
    (stopContract : ∀ callee vals heap n, stops callee vals heap n →
      8 * vals.length + 16 ≤ frame.window - (frameBytes frame.slots + 16) ∧
        StopsContract binary imageBase (frame.window - (frameBytes frame.slots + 16)) callee vals heap n)
    {m : Machine} {n : Nat} (run : AStops calls stops instrs m n) :
    ∀ s, Rel frame s m → FaultsWithin n s := by
  have small := body.small
  have limit : imageLimit = 2 ^ 30 := rfl
  have window := fits.window
  induction run with
  | zero => intro s _; exact FaultsWithin.zero s
  | step head _ ih =>
    intro s rel
    rcases step_simulates body fits callContract rel head with ⟨k, middle, positive, -, det, middleRel⟩ |
      ⟨-, faults⟩
    · exact (det.within (ih middle middleRel)).mono (by omega)
    · exact faults.within _
  | @call m callee args target count n fetched stopping =>
    intro s rel
    obtain ⟨loaded, apart, bound, codeHeap⟩ := body.fetch rel fetched
    obtain ⟨-, argsCount, argsFit, targetFit, positive⟩ := body.fits _ (fetch_mem fetched)
    obtain ⟨room, contract⟩ := stopContract _ _ _ _ stopping
    rw [readSlots_length] at room
    rcases call_simulates (P := False) (Q := FaultsWithin n) (values := List.replicate count 0) (after := m.heap)
      rel fits loaded apart codeHeap body.slots body.entries body.base (by omega)
      (by have := body.entrySmall callee; omega) argsFit argsCount targetFit positive body.image body.imageApart
      body.imageHeap body.guard (by omega) room (fun s a b c d e f g h => .inr (contract s a b c d e f g h))
      (by simp) with ⟨⟨⟩, -⟩ | ⟨k, s2, positive', det, within⟩
    exact (det.within within).mono (by omega)
  | bump fetched inside over =>
    intro s rel
    obtain ⟨loaded, -⟩ := body.fetch rel fetched
    exact (bump_fails rel fits (body.fits _ (fetch_mem fetched)) loaded inside over).within _
  | div fetched undefined =>
    intro s rel
    obtain ⟨loaded, -⟩ := body.fetch rel fetched
    exact (div_fails _ _ rel (body.fits _ (fetch_mem fetched)) loaded undefined).within _

/-- One compiled function stops only at faults for as long as its source
body does, given contracts for its calls. -/
theorem function_stops {prog : Program} (compiled : compileProgram prog = some binary)
    {f : Nat} {func : Func} {code : Code} (codeFound : binary.codes[f]? = some code)
    (compiledFunc : compileFunc (arities prog.funcs) func = some code)
    {depth : Nat} {args : List (BitVec 64)} {heap : Heap} {n : Nat} (length : args.length = func.params)
    (stops : Stops prog depth (Func.entry args) heap func.body n) {need : Nat}
    (callContract : ∀ callee vals calleeHeap result calleeAfter,
      SourceCalls prog depth callee vals calleeHeap result calleeAfter → ∃ needC,
        needC + frameBytes code.slots + 16 ≤ need ∧ 8 * vals.length + 24 ≤ binary.guard ∧
          ∀ inner, Contract binary imageBase needC inner callee vals calleeHeap result calleeAfter)
    (stopContract : ∀ callee vals calleeHeap k, SourceStops prog depth callee vals calleeHeap k →
      8 * vals.length + 24 ≤ binary.guard ∧ ∀ inner, StopsContract binary imageBase inner callee vals calleeHeap k)
    (window : Nat) : StopsContract binary imageBase window f args heap n := by
  intro s bounded loaded apart imageHeap entry params heapAt stack
  rcases function_enter compiled codeFound compiledFunc length s bounded loaded apart imageHeap entry params
    heapAt stack with ⟨-, faults⟩ | ⟨place, k, entered, start, positive, -, det1, fits, body, rel, pc0, heap0,
      startParams⟩
  · exact faults.within _
  let frame := Frame.entered s window code.slots binary.guard
  have checked : frameBytes code.slots + 8 + binary.guard ≤ window := fits.checked
  have run := compileFunc_stops compiledFunc length stops start pc0 heap0 startParams
  have callContract' : ∀ callee vals calleeHeap result calleeAfter,
      SourceCalls prog depth callee vals calleeHeap result calleeAfter → ∃ needC,
        needC + frameBytes frame.slots + 16 ≤ need ∧
          8 * vals.length + 16 ≤ frame.window - (frameBytes frame.slots + 16) ∧
          Contract binary imageBase needC (frame.window - (frameBytes frame.slots + 16)) callee vals calleeHeap
            result calleeAfter := by
    intro callee vals calleeHeap result calleeAfter calls
    obtain ⟨needC, needFits, argsFit, contract⟩ := callContract callee vals calleeHeap result calleeAfter calls
    exact ⟨needC, needFits, by show 8 * vals.length + 16 ≤ window - (frameBytes code.slots + 16); omega,
      contract _⟩
  have stopContract' : ∀ callee vals calleeHeap k, SourceStops prog depth callee vals calleeHeap k →
      8 * vals.length + 16 ≤ frame.window - (frameBytes frame.slots + 16) ∧
        StopsContract binary imageBase (frame.window - (frameBytes frame.slots + 16)) callee vals calleeHeap k := by
    intro callee vals calleeHeap k stopping
    obtain ⟨argsFit, contract⟩ := stopContract callee vals calleeHeap k stopping
    exact ⟨by show 8 * vals.length + 16 ≤ window - (frameBytes code.slots + 16); omega, contract _⟩
  exact (det1.within (body_stops body fits callContract' stopContract' run entered rel)).mono (by omega)

/-- Calling function `callee` with `args` from `heap` is still running after
`n` ticks or stops at a checked fault, nesting completed calls fewer than
`depth` deep. -/
def Program.Stops (prog : Program) (depth callee : Nat) (args : List (BitVec 64)) (heap : Heap) (n : Nat) :
    Prop :=
  ∃ func, prog.funcs[callee]? = some func ∧ args.length = func.params ∧
    Lanius.Mini.Stops prog depth (Func.entry args) heap func.body n

/-- Every compiled function stops only at faults for as long as its source does. -/
theorem compiled_stops {prog : Program} (compiled : compileProgram prog = some binary) (imageBase : BitVec 64) :
    ∀ depth f args heap n, prog.Stops depth f args heap n →
      ∀ window, StopsContract binary imageBase window f args heap n := by
  intro depth
  induction depth using Nat.strongRecOn with
  | _ depth ih =>
  intro f args heap n ⟨func, found, length, stops⟩ window
  obtain ⟨codesCompiled, -, -, -⟩ := compileProgram_spec compiled
  obtain ⟨code, codeFound, compiledFunc⟩ := compileFuncs_get codesCompiled found
  have need := frameNeed_le codeFound
  apply function_stops compiled codeFound compiledFunc length stops (need := binary.stackNeed depth)
  · intro callee vals calleeHeap result calleeAfter ⟨inner, less, innerFunc, innerFound, innerLength, innerExec⟩
    obtain ⟨previous, rfl⟩ : ∃ previous, depth = previous + 1 := ⟨depth - 1, by omega⟩
    obtain ⟨innerCode, innerCodeFound, innerCompiled⟩ := compileFuncs_get codesCompiled innerFound
    obtain ⟨innerParams, -, innerSlots, -, -⟩ := compileFunc_spec innerCompiled
    have innerNeed := frameNeed_le innerCodeFound
    have innerFrame := frameBytes_slots innerCode.slots
    refine ⟨binary.stackNeed previous, ?_, ?_, fun w => ?_⟩
    · simp only [Binary.stackNeed, Nat.succ_mul] at *
      omega
    · simp only [Binary.guard]
      omega
    · apply (compiled_contract compiled imageBase inner callee vals calleeHeap result calleeAfter
        ⟨innerFunc, innerFound, innerLength, innerExec⟩ w).mono
      simp only [Binary.stackNeed]
      exact Nat.mul_le_mul_right _ (by omega)
  · intro callee vals calleeHeap k ⟨inner, less, innerFunc, innerFound, innerLength, innerStops⟩
    obtain ⟨innerCode, innerCodeFound, innerCompiled⟩ := compileFuncs_get codesCompiled innerFound
    obtain ⟨innerParams, -, innerSlots, -, -⟩ := compileFunc_spec innerCompiled
    have innerNeed := frameNeed_le innerCodeFound
    have innerFrame := frameBytes_slots innerCode.slots
    refine ⟨?_, fun w => ih inner less callee vals calleeHeap k ⟨innerFunc, innerFound, innerLength, innerStops⟩ w⟩
    simp only [Binary.guard]
    omega

/-- **Runs that do not return.** If the source program's function `f` on
`args` from `heap` is, for every `n`, still running after `n` ticks or
stopped at a checked fault (with some bound on the depth of the calls that
complete), then its machine code, entered as in `compileProgram_correct`
with any stack, stops only at faults: it never returns. -/
theorem compileProgram_stops {prog : Program} (compiled : compileProgram prog = some binary)
    {f : Nat} {args : List (BitVec 64)} {heap : Heap}
    (stops : ∀ n, ∃ depth, prog.Stops depth f args heap n)
    (s : State) (imageBase : BitVec 64) (window : Nat) (bounded : window ≤ 2 ^ 62)
    (loaded : CodeAt s.memory imageBase binary.image)
    (apart : ∀ index, index < binary.image.length →
      ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index))
    (imageHeap : ∀ index, index < binary.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index))
    (entry : s.rip = imageBase + BitVec.ofNat 64 (binary.entries.getD f 0))
    (params : ∀ k (bound : k < args.length),
      read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = args[k])
    (heapAt : HeapAt window s heap) (stack : StackAt binary.guard window s) : Faults s :=
  Faults.of_within fun n => by
    obtain ⟨depth, stopsAt⟩ := stops n
    exact compiled_stops compiled imageBase depth f args heap n stopsAt window s bounded loaded apart imageHeap
      entry params heapAt stack

end Lanius.Mini
