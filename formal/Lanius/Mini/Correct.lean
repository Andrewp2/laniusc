import Lanius.Mini.Simulation

/-! The top-level theorem: calling a compiled function by a near call returns
what the source function returns, provided the stack has room for the call's
nesting depth. -/

namespace Lanius.Mini
open Lanius.X86.Machine

theorem compileFuncs_cons {arities : List Nat} {func : Func} {rest : List Func} {codes : List Code}
    (compiled : compileFuncs arities (func :: rest) = some codes) :
    ∃ code codes', compileFunc arities func = some code ∧ compileFuncs arities rest = some codes' ∧
      codes = code :: codes' := by
  simp only [compileFuncs] at compiled
  split at compiled
  · contradiction
  · rename_i code first
    split at compiled
    · contradiction
    · rename_i codes' restCompiled
      exact ⟨code, codes', first, restCompiled, (Option.some.inj compiled).symm⟩

theorem compileFuncs_length {arities : List Nat} :
    ∀ {funcs : List Func} {codes : List Code}, compileFuncs arities funcs = some codes →
      codes.length = funcs.length
  | [], codes, compiled => by simp only [compileFuncs, Option.some.injEq] at compiled; subst compiled; rfl
  | func :: rest, codes, compiled => by
    obtain ⟨code, codes', -, restCompiled, rfl⟩ := compileFuncs_cons compiled
    simp [compileFuncs_length restCompiled]

theorem compileFuncs_get {arities : List Nat} :
    ∀ {funcs : List Func} {codes : List Code}, compileFuncs arities funcs = some codes →
      ∀ {f : Nat} {func : Func}, funcs[f]? = some func →
        ∃ code, codes[f]? = some code ∧ compileFunc arities func = some code
  | [], _, _, _, _, found => by simp at found
  | first :: rest, codes, compiled, f, func, found => by
    obtain ⟨code, codes', firstCompiled, restCompiled, rfl⟩ := compileFuncs_cons compiled
    cases f with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at found
      subst found
      exact ⟨code, rfl, firstCompiled⟩
    | succ f =>
      simp only [List.getElem?_cons_succ] at found ⊢
      exact compileFuncs_get restCompiled found

theorem arities_length (funcs : List Func) : (arities funcs).length = funcs.length := by
  induction funcs <;> simp_all [arities]

theorem frameNeed_le : ∀ {codes : List Code} {f : Nat} {code : Code}, codes[f]? = some code →
    frameBytes code.slots + 16 ≤ frameNeed codes
  | [], _, _, found => by simp at found
  | first :: rest, f, code, found => by
    cases f with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at found
      subst found
      simp only [frameNeed]; omega
    | succ f =>
      simp only [List.getElem?_cons_succ] at found
      have := frameNeed_le found
      simp only [frameNeed]; omega

theorem compileProgram_spec {prog : Program} {binary : Binary} (compiled : compileProgram prog = some binary) :
    compileFuncs (arities prog.funcs) prog.funcs = some binary.codes ∧ binary.entries = layout 0 binary.codes ∧
      binary.image = linkFrom binary.entries 0 binary.codes ∧ binary.image.length ≤ imageLimit := by
  simp only [compileProgram] at compiled
  split at compiled
  · contradiction
  · rename_i codes codesCompiled
    split at compiled
    · rename_i small
      simp only [Option.some.injEq] at compiled
      subst compiled
      exact ⟨codesCompiled, rfl, rfl, small⟩
    · contradiction

theorem layout_getD {codes : List Code} {f offset : Nat} (at_ : (layout 0 codes)[f]? = some offset) :
    (layout 0 codes).getD f 0 = offset := by
  simp [List.getD, at_]

/-- One compiled function meets its contract, given contracts for its calls. -/
theorem function_contract {prog : Program} {binary : Binary} (compiled : compileProgram prog = some binary)
    {imageBase : BitVec 64} {f : Nat} {func : Func} {code : Code} (_found : prog.funcs[f]? = some func)
    (codeFound : binary.codes[f]? = some code)
    (compiledFunc : compileFunc (arities prog.funcs) func = some code)
    {depth : Nat} {args : List (BitVec 32)} {value : BitVec 32} (length : args.length = func.params)
    (exec : Exec prog depth (Func.entry args) func.body (.returned value))
    {window : Nat} (room : frameBytes code.slots + 16 ≤ window)
    (callContract : ∀ callee vals result, SourceCalls prog depth callee vals result → ∃ inner,
      frameBytes code.slots + 16 + inner ≤ window ∧ 8 * vals.length + 16 ≤ inner ∧
        Contract binary imageBase inner callee vals result) :
    Contract binary imageBase window f args value := by
  intro s bounded loaded apart entry params
  obtain ⟨codesCompiled, entries, imageEq, imageSmall⟩ := compileProgram_spec compiled
  obtain ⟨paramsFit, -, slotsEq, slotLimit', -⟩ := compileFunc_spec compiledFunc
  have limit : code.slots ≤ 2 ^ 20 := slotLimit'
  have imageLimitEq : imageLimit = 2 ^ 30 := rfl
  obtain ⟨pre, post, offset, split, at_, preLength⟩ := linkFrom_at binary.entries binary.codes 0 f code codeFound
  rw [← entries] at at_
  have entryOffset : binary.entries.getD f 0 = offset := by simp [List.getD, at_]
  have imageLength : binary.image.length = pre.length + code.size + post.length := by
    rw [imageEq, split]; simp only [List.length_append, Code.image_length]
  have codeSizeEq : code.size = 13 + codeSize code.instrs := rfl
  have codeImage : CodeAt s.memory s.rip
      (framePrologueBytes code.slots ++ encodeFrom ⟨offset + 13, code.slots, binary.entries⟩ 0 code.instrs) := by
    have whole := loaded
    rw [imageEq, split] at whole
    have := CodeAt.middle whole
    rw [Nat.zero_add] at preLength
    rw [preLength] at this
    rw [entry, entryOffset, ← prologue_eq]
    exact this
  have apartAt : ∀ index, index < code.size →
      ¬Below (s.registers rspRegister) window (s.rip + BitVec.ofNat 64 index) := by
    intro index bound
    rw [entry, entryOffset, BitVec.add_assoc, ← BitVec.ofNat_add]
    exact apart _ (by omega)
  have prologueLength := framePrologueBytes_length code.slots
  have pushBelow : ∀ lane : Fin 8,
      Below (s.registers rspRegister) window (s.registers rspRegister - 8 + BitVec.ofNat 64 lane.val) := by
    intro lane
    rw [show s.registers rspRegister - 8 = s.registers rspRegister - BitVec.ofNat 64 8 from rfl,
      depth_lane _ _ _ (by omega)]
    exact below_depth _ (by omega) (by omega) (by omega)
  have steps1 : Steps 4 s (prologueState s code.slots) := by
    apply framePrologue_steps code.slots s codeImage.prefix
    intro index bound lane
    have pushLength : (pushBytes rbpRegister).length = 1 := by decide
    have restLength : (moveBytes .w64 rbpRegister rspRegister ++
        immediateBytes .w32 r11Register (frameSizeBits code.slots) 0 ++
        aluBytes .w64 .subtract rspRegister r11Register).length = 12 := by
      simp only [framePrologueBytes, List.length_append] at prologueLength ⊢
      omega
    rw [pushLength]
    simpa using ne_of_below (apartAt (1 + index) (by omega)) (pushBelow lane)
  let entered := prologueState s code.slots
  have memoryEntered : entered.memory =
      write64 s.memory (s.registers rspRegister - 8) (s.registers rbpRegister) := by
    simp [entered, prologueState, State.alu64, State.alu, State.immediate32, State.move64,
      State.push64, rspRegister, rbpRegister]
  have ripEntered : entered.rip = s.rip + BitVec.ofNat 64 13 := by
    rw [framePrologue_rip, prologueLength]
  let frame : Frame :=
    { top := s.registers rspRegister
      window := window
      slots := code.slots
      base := s.rip + BitVec.ofNat 64 13
      saved := s.registers rbpRegister
      preserved := s.registers
      entry := s.memory }
  have fits : frame.Fits := ⟨limit, room, bounded⟩
  have body : Body frame binary imageBase ⟨offset + 13, code.slots, binary.entries⟩ code.instrs :=
    { loaded := by
        have := codeImage.suffix
        rwa [prologueLength] at this
      apart := by
        intro index bound
        have := apartAt (13 + index) (by omega)
        rwa [BitVec.ofNat_add, ← BitVec.add_assoc] at this
      slots := rfl
      entries := rfl
      base := by
        show s.rip + _ = _
        rw [entry, entryOffset, BitVec.add_assoc, ← BitVec.ofNat_add]
      small := by
        show offset + 13 + codeSize code.instrs ≤ imageLimit
        omega
      entrySmall := by
        intro callee
        cases h : binary.entries[callee]? with
        | none => simp [List.getD, h]
        | some other =>
          simp only [List.getD, h, Option.getD_some]
          rw [entries] at h
          have := layout_bound binary.entries binary.codes 0 callee other h
          rw [← imageEq] at this
          omega
      image := loaded
      imageApart := apart
      fits := by
        have := compileFunc_fits compiledFunc
        rw [arities_length, ← compileFuncs_length codesCompiled] at this
        exact this }
  let start : Machine :=
    { pc := 0
      acc := (entered.registers 0).setWidth 32
      slots := fun slot => read32 entered.memory (frameSlotAddress (s.registers rspRegister - 8) slot) }
  have rel : Rel frame entered start :=
    { rip := by rw [ripEntered]; simp [frame, start]
      rbp := by
        simp [entered, frame, prologueState, State.alu64, State.alu, State.immediate32, State.move64,
          State.push64, rspRegister, rbpRegister, r11Register]
      rsp := by
        simp [entered, frame, prologueState, State.alu64, State.alu, State.immediate32, State.move64,
          State.push64, rspRegister, rbpRegister, r11Register, Alu.result, frameSizeBits]
        have := frameBytes_le code.slots
        bv_omega
      acc := rfl
      slots := fun _ _ => rfl
      saved := by simp only [frame, memoryEntered, read64_write64]
      preserved := by
        intro register other
        obtain ⟨-, -, four, five, eleven⟩ := not_scratch other
        simp [entered, frame, prologueState, State.alu64, State.alu, State.immediate32, State.move64,
          State.push64, rspRegister, rbpRegister, r11Register, four, five, eleven]
      unchanged := by
        intro address outside
        rw [memoryEntered, write64_frame _ _ _ _ (fun lane => ne_of_below outside (pushBelow lane))] }
  have startParams : ∀ index, index < func.params → start.slots index = args.getD index 0 := by
    intro index below
    have bound : index < slotLimit := by unfold slotLimit; omega
    show read32 entered.memory (frameSlotAddress (s.registers rspRegister - 8) index) = args.getD index 0
    rw [memoryEntered, read32_write64_frame _ _ _ _ (by
      intro i lane
      rw [slot_lane _ bound _ (by omega),
        show s.registers rspRegister - 8 = s.registers rspRegister - BitVec.ofNat 64 8 from rfl,
        depth_lane _ _ _ (by omega)]
      exact depth_ne _ (by omega) (by omega) (by omega)), slot_eq _ bound, params index (by omega)]
    simp [List.getD, List.getElem?_eq_getElem (show index < args.length by omega)]
  obtain ⟨m', run, atRet, acc⟩ := compileFunc_correct compiledFunc length exec start rfl startParams
  obtain ⟨n, s', steps2, exit⟩ := body_simulates body fits callContract run atRet entered rel
  refine ⟨_, s', steps1.trans steps2, ?_⟩
  exact
    { rip := exit.rip
      rsp := exit.rsp
      rbp := exit.rbp
      value := acc ▸ exit.value
      preserved := exit.preserved
      unchanged := exit.unchanged }

/-- Every compiled function meets its contract with the stack its call depth needs. -/
theorem compiled_contract {prog : Program} {binary : Binary} (compiled : compileProgram prog = some binary)
    (imageBase : BitVec 64) :
    ∀ depth f args value, prog.Returns depth f args value →
      Contract binary imageBase (binary.stackNeed depth) f args value := by
  intro depth
  induction depth using Nat.strongRecOn with
  | _ depth ih =>
  intro f args value ⟨func, found, length, exec⟩
  obtain ⟨codesCompiled, -, -, -⟩ := compileProgram_spec compiled
  obtain ⟨code, codeFound, compiledFunc⟩ := compileFuncs_get codesCompiled found
  have need := frameNeed_le codeFound
  have grow : ∀ d, frameNeed binary.codes ≤ binary.stackNeed d := by
    intro d
    simp only [Binary.stackNeed, Nat.succ_mul]
    omega
  apply function_contract compiled found codeFound compiledFunc length exec (by have := grow depth; omega)
  intro callee vals result ⟨inner, less, innerFunc, innerFound, innerLength, innerExec⟩
  obtain ⟨previous, rfl⟩ : ∃ previous, depth = previous + 1 := ⟨depth - 1, by omega⟩
  obtain ⟨innerCode, innerCodeFound, innerCompiled⟩ := compileFuncs_get codesCompiled innerFound
  obtain ⟨innerParams, -, innerSlots, -, -⟩ := compileFunc_spec innerCompiled
  have innerNeed := frameNeed_le innerCodeFound
  have innerFrame := frameBytes_slots innerCode.slots
  refine ⟨binary.stackNeed previous, ?_, ?_, ?_⟩
  · simp only [Binary.stackNeed, Nat.succ_mul] at *
    omega
  · have := grow previous
    omega
  · apply (ih inner less callee vals result ⟨innerFunc, innerFound, innerLength, innerExec⟩).mono
    simp only [Binary.stackNeed]
    exact Nat.mul_le_mul_right _ (by omega)

/-- **The mini compiler is correct.** If the source program's function `f`
returns `value` on `args`, nesting calls fewer than `depth` deep, then its
machine code, loaded anywhere and entered by a near call with the arguments
just below the return address and at least `binary.stackNeed depth` bytes of
stack apart from the image, returns `value` in eax to the return address. It
restores rsp and rbp, preserves every register other than rax, rcx, r11, and
changes no memory outside the stack it was given. -/
theorem compileProgram_correct {prog : Program} {binary : Binary} (compiled : compileProgram prog = some binary)
    {depth f : Nat} {args : List (BitVec 32)} {value : BitVec 32} (returns : prog.Returns depth f args value)
    (s : State) (imageBase : BitVec 64) (window : Nat)
    (enough : binary.stackNeed depth ≤ window) (bounded : window ≤ 2 ^ 62)
    (loaded : CodeAt s.memory imageBase binary.image)
    (apart : ∀ index, index < binary.image.length →
      ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index))
    (entry : s.rip = imageBase + BitVec.ofNat 64 (binary.entries.getD f 0))
    (params : ∀ k (bound : k < args.length),
      read32 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = args[k]) :
    ∃ n s', Steps n s s' ∧ Returned window s s' value :=
  (compiled_contract compiled imageBase depth f args value returns).mono enough s bounded loaded apart entry params

end Lanius.Mini
