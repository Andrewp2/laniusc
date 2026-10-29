import Lanius.Mini.SourceCorrect

/-! The x86 `Step` relation leaves some flags free, so `compileProgram_correct`
and `compileSource_correct` only say that some run returns. Here every run
does: the compiled code reads a flag only right after an instruction that
determines it (`cmp; setcc`, `test; jz`, `cmp; jbe` in `bump`), so every run of
the same length from the same state ends with the same registers, rip and
memory, and so in a state that has `Returned` the same results. The contracts
of `Simulation.lean` carry `Det` (`StepDet.lean`) alongside their runs. -/

namespace Lanius.Mini
open Lanius.X86.Machine
open Lanius.Core (Value)

/-- `Returned` reads no flags. -/
theorem Returned.congr {window : Nat} {s s' t : State} {values : List (BitVec 64)} {after : Heap}
    (returned : Returned window s s' values after) (same : DataEq s' t) : Returned window s t values after where
  rip := by rw [← same.rip]; exact returned.rip
  rsp := by rw [← same.registers]; exact returned.rsp
  rbp := by rw [← same.registers]; exact returned.rbp
  value := by rw [← same.registers]; exact returned.value
  results := by rw [← same.memory]; exact returned.results
  preserved := by rw [← same.registers]; exact returned.preserved
  unchanged := by rw [← same.memory]; exact returned.unchanged
  cursor := by rw [← same.registers]; exact returned.cursor
  limit := returned.limit
  heap := by rw [← same.memory]; exact returned.heap

/-- **The mini compiler's code returns the same way on every run.** Under the
hypotheses of `compileProgram_correct`, some `n`-step run returns, and every
`n`-step run from `s` ends with the same registers, rip and memory (only the
flags the SDM leaves undefined may differ), so it too has returned `value`
with `after` in the heap. -/
theorem compileProgram_deterministic {prog : Program} {binary : Binary}
    (compiled : compileProgram prog = some binary)
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
    (heapAt : HeapAt window s heap) (stack : StackAt binary.guard window s) :
    ∃ n s', Steps n s s' ∧ Det n s s' ∧ Returned window s s' value after ∧
      ∀ t, Steps n s t → DataEq s' t ∧ Returned window s t value after := by
  obtain ⟨n, s', steps, det, returned⟩ :=
    compileProgram_correct compiled returns s imageBase window enough bounded loaded apart imageHeap entry params
      heapAt stack
  exact ⟨n, s', steps, det, returned, fun t run => ⟨det.final run, returned.congr (det.final run)⟩⟩

/-- `compileProgram_deterministic` through the optimizer: the image is the
original program's or a validated one's, and either returns the same way on
every run. -/
theorem compileOptimized_deterministic {prog : Program} {binary : Binary}
    (compiled : compileOptimized prog = some binary)
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
    (heapAt : HeapAt window s heap) (stack : StackAt binary.guard window s) :
    ∃ n s', Steps n s s' ∧ Det n s s' ∧ Returned window s s' value after ∧
      ∀ t, Steps n s t → DataEq s' t ∧ Returned window s t value after := by
  rcases compileOptimized_some compiled with original | ⟨q, accepted, optimized⟩
  · exact compileProgram_deterministic original returns s imageBase window enough bounded loaded apart imageHeap
      entry params heapAt stack
  · exact compileProgram_deterministic optimized (returns.validated accepted) s imageBase window enough bounded
      loaded apart imageHeap entry params heapAt stack

/-- `compileSource_correct`, with every run of the compiled call returning
the same way: the results representing `v` and the heap cursor at Core's final
next address. -/
theorem compileSource_deterministic {sp : SrcProgram} {binary : Binary}
    (compiled : compileSource sp = some binary) {f : Nat} {func : SrcFunc}
    (found : sp.funcs[f]? = some func) {args : List Value} {bits : List (BitVec 64)}
    (typed : FieldsHold (paramTypes func.params) args (Func.entry bits) 0)
    (bitsLen : bits.length = paramsSize func.params) {fuel : Nat} {v : Value}
    {final : Semantics.State} {heap : Heap} (start : heap.cursor = 1)
    (zero : ∀ a, 1 ≤ a → heap.bytes a = 0) (small : heap.limit < 2 ^ 62)
    (runs : Semantics.evalExpr fuel sp.toCore {} (.call f (args.map Core.Expr.value)) = .done v final)
    (fits : final.heap.nextAddress ≤ heap.limit) :
    ∃ depth results after, func.ret.HoldsAt v (Func.entry results) 0 ∧ results.length = func.ret.size ∧
      after.cursor = final.heap.nextAddress ∧
      ∀ (s : State) (imageBase : BitVec 64) (window : Nat),
        binary.stackNeed depth ≤ window → window ≤ 2 ^ 62 →
        CodeAt s.memory imageBase binary.image →
        (∀ index, index < binary.image.length →
          ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index)) →
        (∀ index, index < binary.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index)) →
        s.rip = imageBase + BitVec.ofNat 64 (binary.entries.getD f 0) →
        (∀ k (bound : k < bits.length),
          read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = bits[k]) →
        HeapAt window s heap → StackAt binary.guard window s →
        ∃ n s', Steps n s s' ∧ Det n s s' ∧ Returned window s s' results after ∧
          ∀ t, Steps n s t → DataEq s' t ∧ Returned window s t results after := by
  obtain ⟨_, _, funcs, lowered, compiledProgram⟩ := compileSource_some compiled
  cases fuel with
  | zero => simp [Semantics.evalExpr] at runs
  | succ k =>
    obtain ⟨func', values, afterArgs, completed, c, argsRun, found', _, bodyRun, result, rfl⟩ := call_inv runs
    rw [found] at found'
    cases found'
    obtain ⟨rfl, rfl⟩ := evalExprs_values argsRun
    obtain ⟨_, _, depth, results, after, returns, holds, len, hc⟩ :=
      body_sound (mp := { funcs := funcs }) (hp := heap) lowered (stmt_sound lowered k) found
        ⟨fun _ mem => by simp at mem, rfl⟩ (HeapCorr.empty start zero small) typed bitsLen bodyRun result fits
    exact ⟨depth, results, after, holds, len, hc.cursor,
      fun s imageBase window enough bounded loaded apart imageHeap entry params heapAt stack =>
        compileOptimized_deterministic compiledProgram returns s imageBase window enough bounded loaded apart
          imageHeap entry params heapAt stack⟩

end Lanius.Mini
