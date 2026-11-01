import Lanius.Mini.SourceStops

/-! # Every outcome of a compiled call, from any Core state

`compileSource_outcome_from` puts `compileSource_correct_from` and
`compileSource_stops_from` together for any stack window: the compiled `f`,
entered from an x86 state that represents a Core state `st`, either faults
(every run of it that stops, stops at a fault), or returns deterministically
what a completed Core call `f(args)` returns, with its heap representing
Core's final heap, or Core's call reaches an undefined trap. -/

namespace Lanius.Mini

open Lanius.X86.Machine
open Lanius.Core (Value)

/-- `compileSource_correct_from` for any stack window: the compiled `f`
returns, or the window is below what the run needs and it faults. -/
theorem compileSource_contract_from {sp : SrcProgram} {binary : Binary}
    (compiled : compileSource sp = some binary) {f : Nat} {func : SrcFunc}
    (found : sp.funcs[f]? = some func) {args : List Value} {bits : List (BitVec 64)}
    (typed : FieldsHold (paramTypes func.params) args (Func.entry bits) 0)
    (bitsLen : bits.length = paramsSize func.params) {fuel : Nat} {v : Value}
    {st final : Semantics.State} {heap : Heap} (fresh : st.Fresh) (hc : HeapCorr st.heap st.world heap)
    (runs : Semantics.evalExpr fuel sp.toCore st (.call f (args.map Core.Expr.value)) = .done v final)
    (fits : final.heap.nextAddress ≤ heap.limit) :
    ∃ depth results after, func.ret.HoldsAt v (Func.entry results) 0 ∧ results.length = func.ret.size ∧
      HeapCorr final.heap final.world after ∧
      ∀ imageBase window, Contract binary imageBase (binary.stackNeed depth) window f bits heap results after := by
  obtain ⟨_, _, funcs, lowered, compiledProgram⟩ := compileSource_some compiled
  cases fuel with
  | zero => simp [Semantics.evalExpr] at runs
  | succ k =>
    obtain ⟨func', values, afterArgs, completed, c, argsRun, found', _, bodyRun, result, rfl⟩ :=
      call_inv (List.getElem?_eq_some_iff.mp found).1 runs
    rw [found] at found'
    cases found'
    obtain ⟨rfl, rfl⟩ := evalExprs_values argsRun
    obtain ⟨_, _, depth, results, after, returns, holds, len, hc'⟩ :=
      body_sound (mp := { funcs := funcs }) (hp := heap) lowered (stmt_sound lowered k) found
        fresh hc typed bitsLen bodyRun result fits
    refine ⟨depth, results, after, holds, len, hc', fun imageBase window => ?_⟩
    rcases compileOptimized_some compiledProgram with original | ⟨q, accepted, optimized⟩
    · exact compiled_contract original imageBase depth f bits heap results after returns window
    · exact compiled_contract optimized imageBase depth f bits heap results after (returns.validated accepted) window

/-- Every outcome of the compiled `f` entered from an x86 state that
represents the Core state `st` (premises as in `compileSource_stops_from`):
it faults, or Core's call completes within the heap's limit and the compiled
code returns its results with a heap that represents Core's final heap, or
Core's call reaches an undefined trap within the heap's limit. -/
theorem compileSource_outcome_from {sp : SrcProgram} {binary : Binary}
    (compiled : compileSource sp = some binary) {f : Nat} {func : SrcFunc}
    (found : sp.funcs[f]? = some func) {args : List Value} {bits : List (BitVec 64)}
    (typed : FieldsHold (paramTypes func.params) args (Func.entry bits) 0)
    (bitsLen : bits.length = paramsSize func.params) {st : Semantics.State} {heap : Heap}
    (fresh : st.Fresh) (hc : HeapCorr st.heap st.world heap) (within : st.heap.nextAddress ≤ heap.limit)
    (s : State) (imageBase : BitVec 64) (window : Nat) (bounded : window ≤ 2 ^ 62)
    (loaded : CodeAt s.memory imageBase binary.image)
    (apart : ∀ index, index < binary.image.length →
      ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index))
    (imageHeap : ∀ index, index < binary.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index))
    (entry : s.rip = imageBase + BitVec.ofNat 64 (binary.entries.getD f 0))
    (params : ∀ k (bound : k < bits.length),
      read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = bits[k])
    (heapAt : HeapAt window s heap) (stack : StackAt binary.guard window s) :
    Faults s ∨
    (∃ fuel v final, Semantics.evalExpr fuel sp.toCore st (.call f (args.map Core.Expr.value)) = .done v final ∧
      final.heap.nextAddress ≤ heap.limit ∧
      ∃ results after, func.ret.HoldsAt v (Func.entry results) 0 ∧ results.length = func.ret.size ∧
        HeapCorr final.heap final.world after ∧ ∃ n s', Steps n s s' ∧ Det n s s' ∧ Returned window s s' results after) ∨
    ∃ fuel r st', Semantics.evalExpr fuel sp.toCore st (.call f (args.map Core.Expr.value)) = .trapped r st' ∧
      undefinedTrap r = true ∧ st'.heap.nextAddress ≤ heap.limit := by
  by_cases fails : ∀ fuel, Failing heap.limit (Semantics.evalExpr fuel sp.toCore st (.call f (args.map Core.Expr.value)))
  · exact .inl (compileSource_stops_from compiled found typed bitsLen fresh hc within fails s imageBase window bounded
      loaded apart imageHeap entry params heapAt stack)
  · obtain ⟨fuel, notFailing⟩ := Classical.not_forall.mp fails
    rcases not_failing notFailing with ⟨v, final, done, fits⟩ | ⟨r, st', trapped, undefined, bound⟩
    · obtain ⟨depth, results, after, holds, len, hc', contract⟩ :=
        compileSource_contract_from compiled found typed bitsLen fresh hc done fits
      rcases contract imageBase window s bounded loaded apart imageHeap entry params heapAt stack with
        ⟨n, s', run, det, ret⟩ | ⟨-, faults⟩
      · exact .inr (.inl ⟨fuel, v, final, done, fits, results, after, holds, len, hc', n, s', run, det, ret⟩)
      · exact .inl faults
    · exact .inr (.inr ⟨fuel, r, st', trapped, undefined, bound⟩)

end Lanius.Mini
