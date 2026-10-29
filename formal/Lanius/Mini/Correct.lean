import Lanius.Mini.Simulation

/-! The top-level theorem: calling a compiled function by a near call returns
what the source function returns, provided the stack has room for the call's
nesting depth. -/

namespace Lanius.Mini
open Lanius.X86.Machine

theorem compileFuncs_cons {arities : List Arity} {func : Func} {rest : List Func} {codes : List Code}
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

theorem compileFuncs_length {arities : List Arity} :
    ∀ {funcs : List Func} {codes : List Code}, compileFuncs arities funcs = some codes →
      codes.length = funcs.length
  | [], codes, compiled => by simp only [compileFuncs, Option.some.injEq] at compiled; subst compiled; rfl
  | func :: rest, codes, compiled => by
    obtain ⟨code, codes', -, restCompiled, rfl⟩ := compileFuncs_cons compiled
    simp [compileFuncs_length restCompiled]

theorem compileFuncs_get {arities : List Arity} :
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
    {depth : Nat} {args value : List (BitVec 64)} {heap after : Heap} (length : args.length = func.params)
    (exec : Exec prog depth (Func.entry args) heap func.body (.returned value after))
    {window : Nat} (room : frameBytes code.slots + 16 ≤ window)
    (callContract : ∀ callee vals calleeHeap result calleeAfter,
      SourceCalls prog depth callee vals calleeHeap result calleeAfter → ∃ inner,
        frameBytes code.slots + 16 + inner ≤ window ∧ 8 * vals.length + 16 ≤ inner ∧
          Contract binary imageBase inner callee vals calleeHeap result calleeAfter) :
    Contract binary imageBase window f args heap value after := by
  intro s bounded loaded apart imageHeap entry params heapAt
  obtain ⟨codesCompiled, entries, imageEq, imageSmall⟩ := compileProgram_spec compiled
  obtain ⟨paramsFit, -, slotsEq, slotLimit', -⟩ := compileFunc_spec compiledFunc
  have limit : code.slots ≤ 2 ^ 20 := slotLimit'
  have imageLimitEq : imageLimit = 2 ^ 30 := rfl
  obtain ⟨pre, post, offset, split, at_, preLength⟩ := linkFrom_at binary.entries binary.codes 0 f code codeFound
  rw [← entries] at at_
  have entryOffset : binary.entries.getD f 0 = offset := by simp [List.getD, at_]
  have imageLength : binary.image.length = pre.length + code.size + post.length := by
    rw [imageEq, split]; simp only [List.length_append, Code.image_length]
  have codeSizeEq : code.size = 24 + codeSize code.instrs := rfl
  have codeImage : CodeAt s.memory s.rip
      (framePrologueBytes code.slots ++ stackCheckBytes ++
        encodeFrom ⟨offset + 24, code.slots, binary.entries⟩ 0 code.instrs) := by
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
  have heapApartAt : ∀ index, index < code.size → ¬s.InHeap (s.rip + BitVec.ofNat 64 index) := by
    intro index bound
    rw [entry, entryOffset, BitVec.add_assoc, ← BitVec.ofNat_add]
    exact imageHeap _ (by omega)
  have prologueLength := framePrologueBytes_length code.slots
  have pushBelow : ∀ lane : Fin 8,
      Below (s.registers rspRegister) window (s.registers rspRegister - 8 + BitVec.ofNat 64 lane.val) := by
    intro lane
    rw [show s.registers rspRegister - 8 = s.registers rspRegister - BitVec.ofNat 64 8 from rfl,
      depth_lane _ _ _ (by omega)]
    exact below_depth _ (by omega) (by omega) (by omega)
  have steps1 : Steps 4 s (prologueState s code.slots) ∧ Det 4 s (prologueState s code.slots) := by
    apply framePrologue_det code.slots s codeImage.prefix.prefix
    intro index bound lane
    have pushLength : (pushBytes rbpRegister).length = 1 := by decide
    have restLength : (moveBytes .w64 rbpRegister rspRegister ++
        immediateBytes .w32 r11Register (frameSizeBits code.slots) 0 ++
        aluBytes .w64 .subtract rspRegister r11Register).length = 12 := by
      simp only [framePrologueBytes, List.length_append] at prologueLength ⊢
      omega
    rw [pushLength]
    simpa using ne_of_below (apartAt (1 + index) (by omega)) (pushBelow lane)
  let framed := prologueState s code.slots
  have memoryFramed : framed.memory =
      write64 s.memory (s.registers rspRegister - 8) (s.registers rbpRegister) := by
    simp [framed, prologueState, State.alu64, State.alu, State.immediate32, State.move64,
      State.push64, rspRegister, rbpRegister]
  have checkLoaded : CodeAt framed.memory framed.rip (stackCompareBytes ++ (branchBytes 6 2 ++ trapBytes)) := by
    rw [memoryFramed, framePrologue_rip, prologueLength]
    have := codeImage.prefix.suffix
    rw [prologueLength] at this
    apply CodeAt.write64 this
    intro index bound lane
    have := apartAt (13 + index) (by simp only [stackCheckBytes, stackCompareBytes, branchBytes, trapBytes,
      displacementBytes, List.length_append, List.length_cons, List.length_nil] at bound; omega)
    rw [BitVec.ofNat_add, ← BitVec.add_assoc] at this
    exact ne_of_below this (pushBelow lane)
  have checkRoom : (framed.registers stackRegister).toNat ≤ (framed.registers rspRegister).toNat := by
    have stack := heapAt.stack
    have := frameBytes_le code.slots
    simp [framed, prologueState, State.alu64, State.alu, State.immediate32, State.move64,
      State.push64, rspRegister, rbpRegister, r11Register, stackRegister, Alu.result, frameSizeBits] at stack ⊢
    omega
  obtain ⟨checkSteps, checkDet, checkRip⟩ := stackCheck_det framed checkLoaded checkRoom
  let entered := stackChecked framed
  have memoryEntered : entered.memory =
      write64 s.memory (s.registers rspRegister - 8) (s.registers rbpRegister) := memoryFramed
  have ripEntered : entered.rip = s.rip + BitVec.ofNat 64 24 := by
    rw [checkRip, framePrologue_rip, prologueLength, BitVec.add_assoc, ← BitVec.ofNat_add]
  let frame : Frame :=
    { top := s.registers rspRegister
      window := window
      slots := code.slots
      base := s.rip + BitVec.ofNat 64 24
      saved := s.registers rbpRegister
      preserved := s.registers
      entry := s.memory }
  have fits : frame.Fits :=
    ⟨limit, room, bounded, by show (s.registers limitRegister).toNat < 2 ^ 62; rw [← heapAt.limit]; exact heapAt.small,
      heapAt.apart, heapAt.stack⟩
  have body : Body frame binary imageBase ⟨offset + 24, code.slots, binary.entries⟩ code.instrs :=
    { loaded := by
        have := codeImage.suffix
        rwa [List.length_append, prologueLength, stackCheckBytes_length] at this
      apart := by
        intro index bound
        have := apartAt (24 + index) (by omega)
        rwa [BitVec.ofNat_add, ← BitVec.add_assoc] at this
      slots := rfl
      entries := rfl
      base := by
        show s.rip + _ = _
        rw [entry, entryOffset, BitVec.add_assoc, ← BitVec.ofNat_add]
      small := by
        show offset + 24 + codeSize code.instrs ≤ imageLimit
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
        exact this
      codeHeap := by
        intro index bound
        have := heapApartAt (24 + index) (by omega)
        rwa [BitVec.ofNat_add, ← BitVec.add_assoc] at this
      imageHeap := imageHeap }
  let start : Machine :=
    { pc := 0
      acc := entered.registers 0
      slots := fun slot => read64 entered.memory (frameSlotAddress (s.registers rspRegister - 8) slot)
      heap := heap }
  have rel : Rel frame entered start :=
    { rip := by rw [ripEntered]; simp [frame, start]
      rbp := by
        simp [entered, framed, stackChecked, State.branch, State.compare64, frame, prologueState, State.alu64, State.alu, State.immediate32, State.move64,
          State.push64, rspRegister, rbpRegister, r11Register]
      rsp := by
        simp [entered, framed, stackChecked, State.branch, State.compare64, frame, prologueState, State.alu64, State.alu, State.immediate32, State.move64,
          State.push64, rspRegister, rbpRegister, r11Register, Alu.result, frameSizeBits]
        have := frameBytes_le code.slots
        bv_omega
      acc := rfl
      slots := fun _ _ => rfl
      saved := by simp only [frame, memoryEntered, read64_write64]
      preserved := by
        intro register other
        obtain ⟨-, -, four, five, eleven, -⟩ := not_scratch other
        simp [entered, framed, stackChecked, State.branch, State.compare64, frame, prologueState, State.alu64, State.alu, State.immediate32, State.move64,
          State.push64, rspRegister, rbpRegister, r11Register, four, five, eleven]
      unchanged := by
        intro address outside _
        rw [memoryEntered, write64_frame _ _ _ _ (fun lane => ne_of_below outside (pushBelow lane))]
      cursor := by
        have := heapAt.cursor
        simp only [cursorRegister] at this
        simp [entered, framed, stackChecked, State.branch, State.compare64, prologueState, State.alu64, State.alu, State.immediate32, State.move64,
          State.push64, rspRegister, rbpRegister, r11Register, cursorRegister, this]
        rfl
      limit := heapAt.limit
      heap := by
        intro a inside
        have inside' : a < frame.heapLimit := by rw [show frame.heapLimit = heap.limit from heapAt.limit.symm]; exact inside
        rw [memoryEntered, write64_frame _ _ _ _ (fun lane => heap_ne_below fits inside' (pushBelow lane))]
        exact heapAt.bytes a inside }
  have startParams : ∀ index, index < func.params → start.slots index = args.getD index 0 := by
    intro index below
    have bound : index < slotLimit := by unfold slotLimit; omega
    show read64 entered.memory (frameSlotAddress (s.registers rspRegister - 8) index) = args.getD index 0
    rw [memoryEntered, read64_frame _ _ _ _ (by
      intro i lane
      rw [slot_lane _ bound _ (by omega),
        show s.registers rspRegister - 8 = s.registers rspRegister - BitVec.ofNat 64 8 from rfl,
        depth_lane _ _ _ (by omega)]
      exact depth_ne _ (by omega) (by omega) (by omega)), slot_eq _ bound, params index (by omega)]
    simp [List.getD, List.getElem?_eq_getElem (show index < args.length by omega)]
  obtain ⟨m', sources, run, atRet, vals, onHeap⟩ :=
    compileFunc_correct compiledFunc length exec start rfl rfl startParams
  obtain ⟨n, s', steps2, det2, exit⟩ := body_simulates body fits callContract run atRet entered rel
  rw [vals, onHeap] at exit
  refine ⟨_, s', (steps1.1.trans checkSteps).trans steps2, (steps1.2.trans checkDet).trans det2, ?_⟩
  exact
    { rip := exit.rip
      rsp := exit.rsp
      rbp := exit.rbp
      value := exit.value
      results := exit.results
      preserved := exit.preserved
      unchanged := exit.unchanged
      cursor := exit.cursor
      limit := exit.limit
      heap := exit.heap }

/-- Every compiled function meets its contract with the stack its call depth needs. -/
theorem compiled_contract {prog : Program} {binary : Binary} (compiled : compileProgram prog = some binary)
    (imageBase : BitVec 64) :
    ∀ depth f args heap value after, prog.Returns depth f args heap value after →
      Contract binary imageBase (binary.stackNeed depth) f args heap value after := by
  intro depth
  induction depth using Nat.strongRecOn with
  | _ depth ih =>
  intro f args heap value after ⟨func, found, length, exec⟩
  obtain ⟨codesCompiled, -, -, -⟩ := compileProgram_spec compiled
  obtain ⟨code, codeFound, compiledFunc⟩ := compileFuncs_get codesCompiled found
  have need := frameNeed_le codeFound
  have grow : ∀ d, frameNeed binary.codes ≤ binary.stackNeed d := by
    intro d
    simp only [Binary.stackNeed, Nat.succ_mul]
    omega
  apply function_contract compiled found codeFound compiledFunc length exec (by have := grow depth; omega)
  intro callee vals calleeHeap result calleeAfter ⟨inner, less, innerFunc, innerFound, innerLength, innerExec⟩
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
  · apply (ih inner less callee vals calleeHeap result calleeAfter
      ⟨innerFunc, innerFound, innerLength, innerExec⟩).mono
    simp only [Binary.stackNeed]
    exact Nat.mul_le_mul_right _ (by omega)

/-- **The mini compiler is correct.** If the source program's function `f`
returns `values` on `args` from `heap`, leaving `after`, nesting calls fewer
than `depth` deep, then its machine code, loaded anywhere and entered by a
near call with the arguments just below the return address, at least
`binary.stackNeed depth` bytes of stack apart from the image, and `heap` at
r12 (cursor in r13, limit in r14) apart from the image and the stack, returns
to the return address with `values` in the argument slots and the last of
them in eax, `after` in the heap and its cursor in r13. It restores rsp and
rbp, preserves every register other than rax, rcx, r11 and r13, and changes no
memory outside the stack it was given and the heap. -/
theorem compileProgram_correct {prog : Program} {binary : Binary} (compiled : compileProgram prog = some binary)
    {depth f : Nat} {args value : List (BitVec 64)} {heap after : Heap}
    (returns : prog.Returns depth f args heap value after)
    (s : State) (imageBase : BitVec 64) (window : Nat)
    (enough : binary.stackNeed depth ≤ window) (bounded : window ≤ 2 ^ 62)
    (loaded : CodeAt s.memory imageBase binary.image)
    (apart : ∀ index, index < binary.image.length →
      ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index))
    (imageHeap : ∀ index, index < binary.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index))
    (entry : s.rip = imageBase + BitVec.ofNat 64 (binary.entries.getD f 0))
    (params : ∀ k (bound : k < args.length),
      read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = args[k])
    (heapAt : HeapAt window s heap) :
    ∃ n s', Steps n s s' ∧ Returned window s s' value after := by
  obtain ⟨n, s', steps, -, returned⟩ :=
    (compiled_contract compiled imageBase depth f args heap value after returns).mono enough s bounded loaded apart
      imageHeap entry params heapAt
  exact ⟨n, s', steps, returned⟩

end Lanius.Mini
