import Lanius.Mini.EvalStops
import Lanius.Mini.StopsValidate
import Lanius.Mini.SourceCorrect

/-! The verified compiler's top-level theorem for runs that do not complete:
if Core's call of a source function fails at every fuel (it runs out of fuel,
stops at a trap the compiled code checks, or completes with the heap past the
mini heap's limit, but never reaches an undefined trap), the machine code that
`compileSource` produces faults: every run of it from the entry ends at a
checked fault, or does not end. Together with `compileSource_correct` this
covers every call whose Core run reaches no undefined trap. -/

namespace Lanius.Mini

open Lanius.X86.Machine
open Lanius.Core (Value)

theorem evalExprs_values_done {P : Core.Program} {st : Semantics.State} :
    ∀ (vs : List Value) (extra : Nat),
      Semantics.evalExprs (vs.length + extra + 1) P st (vs.map Core.Expr.value) = .done vs st
  | [], _ => by simp [Semantics.evalExprs]
  | v :: rest, extra => by
    have ih := evalExprs_values_done (P := P) (st := st) rest extra
    rw [show (v :: rest).length + extra + 1 = (rest.length + extra + 1) + 1 by simp only [List.length_cons]; omega]
    simp only [List.map_cons, Semantics.evalExprs, Semantics.evalExpr, ih]

/-- `compileSource_stops` from any Core state whose cells are fresh and whose
heap the mini heap represents, within its limit. -/
theorem compileSource_stops_from {sp : SrcProgram} {binary : Binary}
    (compiled : compileSource sp = some binary) {f : Nat} {func : SrcFunc}
    (found : sp.funcs[f]? = some func) {args : List Value} {bits : List (BitVec 64)}
    (typed : FieldsHold (paramTypes func.params) args (Func.entry bits) 0)
    (bitsLen : bits.length = paramsSize func.params) {st : Semantics.State} {heap : Heap}
    (fresh : st.Fresh) (hc : HeapCorr st.heap heap) (within : st.heap.nextAddress ≤ heap.limit)
    (fails : ∀ fuel, Failing heap.limit (Semantics.evalExpr fuel sp.toCore st (.call f (args.map Core.Expr.value))))
    (s : State) (imageBase : BitVec 64) (window : Nat) (bounded : window ≤ 2 ^ 62)
    (loaded : CodeAt s.memory imageBase binary.image)
    (apart : ∀ index, index < binary.image.length →
      ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index))
    (imageHeap : ∀ index, index < binary.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index))
    (entry : s.rip = imageBase + BitVec.ofNat 64 (binary.entries.getD f 0))
    (params : ∀ k (bound : k < bits.length),
      read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = bits[k])
    (heapAt : HeapAt window s heap) (stack : StackAt binary.guard window s) : Faults s := by
  obtain ⟨returns, _, funcs, lowered, compiledProgram⟩ := compileSource_some compiled
  have stops : ∀ n, ∃ depth, Program.Stops { funcs := funcs } depth f bits heap n := fun n => by
    obtain ⟨d, g, gFound, arity, body⟩ := callee_stops (mp := { funcs := funcs }) lowered returns
      (stmtStops_all lowered returns n) (evalExprs_values_done args 0) found fresh hc within typed bitsLen fails
    exact ⟨d, g, gFound, arity, body⟩
  exact compileOptimized_stops compiledProgram stops s imageBase window bounded loaded apart imageHeap entry params
    heapAt stack

/-- Core's call `f(args)` from the empty state fails at every fuel, and `bits`
lay the arguments out by parameter type. Then the compiled `f`, entered by a
near call with `bits` in its parameter slots and a `heap` whose cursor is 1,
whose bytes from 1 up are zero, and whose limit is at least 1, faults: it
ends only at a checked fault, or runs forever. -/
theorem compileSource_stops {sp : SrcProgram} {binary : Binary}
    (compiled : compileSource sp = some binary) {f : Nat} {func : SrcFunc}
    (found : sp.funcs[f]? = some func) {args : List Value} {bits : List (BitVec 64)}
    (typed : FieldsHold (paramTypes func.params) args (Func.entry bits) 0)
    (bitsLen : bits.length = paramsSize func.params) {heap : Heap} (start : heap.cursor = 1)
    (zero : ∀ a, 1 ≤ a → heap.bytes a = 0) (small : heap.limit < 2 ^ 62) (room : 1 ≤ heap.limit)
    (fails : ∀ fuel, Failing heap.limit (Semantics.evalExpr fuel sp.toCore {} (.call f (args.map Core.Expr.value))))
    (s : State) (imageBase : BitVec 64) (window : Nat) (bounded : window ≤ 2 ^ 62)
    (loaded : CodeAt s.memory imageBase binary.image)
    (apart : ∀ index, index < binary.image.length →
      ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index))
    (imageHeap : ∀ index, index < binary.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index))
    (entry : s.rip = imageBase + BitVec.ofNat 64 (binary.entries.getD f 0))
    (params : ∀ k (bound : k < bits.length),
      read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = bits[k])
    (heapAt : HeapAt window s heap) (stack : StackAt binary.guard window s) : Faults s := by
  have hc := HeapCorr.empty start zero small
  exact compileSource_stops_from compiled found typed bitsLen (st := {}) ⟨fun _ mem => by simp at mem, rfl⟩ hc
    (by rw [← hc.cursor, start]; exact room) fails s imageBase window bounded loaded apart imageHeap entry params
    heapAt stack

/-- A Core result that is not `Failing`: a completion within the limit or an
undefined trap. -/
theorem not_failing {α : Type} {limit : Nat} {out : Semantics.Outcome α} (h : ¬Failing limit out) :
    (∃ v st, out = .done v st ∧ st.heap.nextAddress ≤ limit) ∨
    ∃ r st, out = .trapped r st ∧ undefinedTrap r = true := by
  cases out with
  | done v st => exact .inl ⟨v, st, rfl, Nat.le_of_not_lt h⟩
  | trapped r st =>
    refine .inr ⟨r, st, rfl, ?_⟩
    cases u : undefinedTrap r with
    | true => rfl
    | false => exact absurd u h
  | exited _ _ => exact absurd trivial h
  | outOfFuel => exact absurd trivial h

/-- The verified compiler's behaviour theorem. A run of the compiled `f` from
its entry (premises as in `compileSource_correct`, with any window) that ends
at a state with no step that is not a fault (the caller's exit, say) comes
from a Core call that completes, with the heap within its limit, or that
reaches an undefined trap. The completion is `compileSource_correct`'s, which
gives the results the compiled code returns. -/
theorem compileSource_behaviour {sp : SrcProgram} {binary : Binary}
    (compiled : compileSource sp = some binary) {f : Nat} {func : SrcFunc}
    (found : sp.funcs[f]? = some func) {args : List Value} {bits : List (BitVec 64)}
    (typed : FieldsHold (paramTypes func.params) args (Func.entry bits) 0)
    (bitsLen : bits.length = paramsSize func.params) {heap : Heap} (start : heap.cursor = 1)
    (zero : ∀ a, 1 ≤ a → heap.bytes a = 0) (small : heap.limit < 2 ^ 62) (room : 1 ≤ heap.limit)
    (s : State) (imageBase : BitVec 64) (window : Nat) (bounded : window ≤ 2 ^ 62)
    (loaded : CodeAt s.memory imageBase binary.image)
    (apart : ∀ index, index < binary.image.length →
      ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index))
    (imageHeap : ∀ index, index < binary.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index))
    (entry : s.rip = imageBase + BitVec.ofNat 64 (binary.entries.getD f 0))
    (params : ∀ k (bound : k < bits.length),
      read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = bits[k])
    (heapAt : HeapAt window s heap) (stack : StackAt binary.guard window s)
    {m : Nat} {u : State} (run : Steps m s u) (stuck : ∀ v, ¬Lanius.X86.Machine.Step u v) (clean : ¬Lanius.X86.Machine.Fault u) :
    (∃ fuel v final, Semantics.evalExpr fuel sp.toCore {} (.call f (args.map Core.Expr.value)) = .done v final ∧
      final.heap.nextAddress ≤ heap.limit) ∨
    ∃ fuel r st, Semantics.evalExpr fuel sp.toCore {} (.call f (args.map Core.Expr.value)) = .trapped r st ∧
      undefinedTrap r = true := by
  by_cases fails : ∀ fuel, Failing heap.limit
      (Semantics.evalExpr fuel sp.toCore {} (.call f (args.map Core.Expr.value)))
  · exact (clean (compileSource_stops compiled found typed bitsLen start zero small room fails s imageBase window
      bounded loaded apart imageHeap entry params heapAt stack m s u (DataEq.refl s) run stuck)).elim
  · obtain ⟨fuel, notFailing⟩ := Classical.not_forall.mp fails
    rcases not_failing notFailing with ⟨v, final, done, fits⟩ | ⟨r, st, trapped, undefined⟩
    · exact .inl ⟨fuel, v, final, done, fits⟩
    · exact .inr ⟨fuel, r, st, trapped, undefined⟩

end Lanius.Mini
