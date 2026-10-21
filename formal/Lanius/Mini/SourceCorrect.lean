import Lanius.Mini.Correct
import Lanius.Mini.LowerStmt

/-! The verified compiler's top-level theorem for the Core subset: if Core
evaluates a call of a source function to a value, the machine code that
`compileSource` produces returns bits representing that value, provided the
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

theorem compileSource_some {sp : SrcProgram} {binary : Binary} (compiled : compileSource sp = some binary) :
    ∃ funcs, lowerFuncs (sigs sp.funcs) sp.funcs = some funcs ∧
      compileProgram { funcs := funcs } = some binary := by
  simp only [compileSource] at compiled
  split at compiled
  · simp at compiled
  · rename_i funcs lowered
    exact ⟨funcs, lowered, compiled⟩

/-- Core runs `f(args)` from the empty state to `v`, and the arguments have
the parameter types. Then the compiled `f`, entered by a near call with the
arguments' bits in its parameter slots, returns bits representing `v`. -/
theorem compileSource_correct {sp : SrcProgram} {binary : Binary}
    (compiled : compileSource sp = some binary) {f : Nat} {func : SrcFunc}
    (found : sp.funcs[f]? = some func) {args : List Value} {bits : List (BitVec 32)}
    (typed : ArgsHold (paramTypes func.params) args bits) {fuel : Nat} {v : Value}
    {final : Semantics.State}
    (runs : Semantics.evalExpr fuel sp.toCore {} (.call f (args.map Core.Expr.value)) = .done v final) :
    ∃ depth b, func.ret.Holds v b ∧
      ∀ (s : State) (imageBase : BitVec 64) (window : Nat),
        binary.stackNeed depth ≤ window → window ≤ 2 ^ 62 →
        CodeAt s.memory imageBase binary.image →
        (∀ index, index < binary.image.length →
          ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index)) →
        s.rip = imageBase + BitVec.ofNat 64 (binary.entries.getD f 0) →
        (∀ k (bound : k < bits.length),
          read32 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = bits[k]) →
        ∃ n s', Steps n s s' ∧ Returned window s s' b := by
  obtain ⟨funcs, lowered, compiledProgram⟩ := compileSource_some compiled
  cases fuel with
  | zero => simp [Semantics.evalExpr] at runs
  | succ k =>
    obtain ⟨func', values, afterArgs, completed, argsRun, found', _, bodyRun, _⟩ := call_inv runs
    rw [found] at found'
    cases found'
    obtain ⟨rfl, rfl⟩ := evalExprs_values argsRun
    obtain ⟨_, _, depth, b, returns, holds⟩ :=
      body_sound (mp := { funcs := funcs }) lowered (stmt_sound lowered k) found
        (fun _ mem => by simp at mem) typed bodyRun
    exact ⟨depth, b, holds, fun s imageBase window enough bounded loaded apart entry params =>
      compileProgram_correct compiledProgram returns s imageBase window enough bounded loaded apart
        entry params⟩

end Lanius.Mini
