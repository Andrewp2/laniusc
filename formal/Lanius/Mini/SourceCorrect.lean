import Lanius.Mini.Correct
import Lanius.Mini.LowerStmt

/-! The verified compiler's top-level theorem for the Core subset: if Core
evaluates a call of a source function to a value, the machine code that
`compileSource` produces returns slots representing that value, provided the
stack has room for the call's nesting depth. -/

namespace Lanius.Mini

open Lanius.X86.Machine
open Lanius.Core (Value)

theorem evalExprs_values {P : Core.Program} {st : Semantics.State} :
    ∀ {vs : List Value} {fuel : Nat} {values : List Value} {st' : Semantics.State},
      Semantics.evalExprs fuel P st (vs.map Core.Expr.value) = .done values st' →
      values = vs ∧ st' = st := by
  intro vs
  induction vs with
  | nil =>
    intro fuel values st' run
    cases fuel with
    | zero => simp [Semantics.evalExprs] at run
    | succ fuel =>
      simp only [List.map_nil, Semantics.evalExprs, Semantics.Outcome.done.injEq] at run
      exact ⟨run.1.symm, run.2.symm⟩
  | cons v rest ih =>
    intro fuel values st' run
    cases fuel with
    | zero => simp [Semantics.evalExprs] at run
    | succ fuel =>
      cases fuel with
      | zero => simp [Semantics.evalExprs, Semantics.evalExpr] at run
      | succ fuel =>
        simp only [List.map_cons, Semantics.evalExprs, Semantics.evalExpr] at run
        split at run
        · rename_i rvs fin restRun
          simp only [Semantics.Outcome.done.injEq] at run
          obtain ⟨rfl, rfl⟩ := run
          obtain ⟨rfl, rfl⟩ := ih restRun
          exact ⟨rfl, rfl⟩
        all_goals simp at run

/-- Core's empty heap and a mini heap whose cursor is 1 and whose bytes from 1
up are zero. -/
theorem HeapCorr.empty {heap : Heap} (start : heap.cursor = 1) (zero : ∀ a, 1 ≤ a → heap.bytes a = 0)
    (small : heap.limit < 2 ^ 62) : HeapCorr ({} : Semantics.State).heap heap :=
  { cursor := start, pos := Nat.le_refl _, unbounded := rfl, small
    sized := fun _ mem => by cases mem
    below := fun _ mem => by cases mem
    apart := fun _ mem => by cases mem
    unique := fun _ mem => by cases mem
    bytes := fun _ mem => by cases mem
    zero }

/-- Core runs `f(args)` from the empty state to `v`, ending with its heap's
next free address at `final.heap.nextAddress`, and `bits` lay the arguments
out by parameter type (a struct one slot per field). Then the compiled `f`,
entered by a near call with `bits` in its parameter slots and a `heap` whose
cursor is 1, whose bytes from 1 up are zero, and whose limit Core's final
next address does not pass, returns `results` representing `v` in the same
slots, laid out the same way, with the heap's cursor at Core's final next
address. -/
theorem compileSource_correct {sp : SrcProgram} {binary : Binary}
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
        HeapAt window s heap →
        ∃ n s', Steps n s s' ∧ Returned window s s' results after := by
  obtain ⟨_, _, funcs, lowered, compiledProgram⟩ := compileSource_some compiled
  cases fuel with
  | zero => simp [Semantics.evalExpr] at runs
  | succ k =>
    obtain ⟨func', values, afterArgs, completed, argsRun, found', _, bodyRun, rfl⟩ := call_inv runs
    rw [found] at found'
    cases found'
    obtain ⟨rfl, rfl⟩ := evalExprs_values argsRun
    obtain ⟨_, _, depth, results, after, returns, holds, len, hc⟩ :=
      body_sound (mp := { funcs := funcs }) (hp := heap) lowered (stmt_sound lowered k) found
        ⟨fun _ mem => by simp at mem, rfl⟩ (HeapCorr.empty start zero small) typed bitsLen bodyRun fits
    exact ⟨depth, results, after, holds, len, hc.cursor,
      fun s imageBase window enough bounded loaded apart imageHeap entry params heapAt =>
        compileProgram_correct compiledProgram returns s imageBase window enough bounded loaded apart
          imageHeap entry params heapAt⟩

end Lanius.Mini
