import Lanius.Faithful.Sim.Func

/-! # Core calls of pure functions mean their pure calls

A call Core completes, of a function of a program whose functions the purity
checker accepts (`PureProg`, outside the driver functions `outside`) and whose
`boxed`/`unbox` prims are the templates (`PrimsOk`), on arguments that mean
pure values (`VRels`), has the pure value `pcall` gives with the same fuel
(`call_sim`). More fuel never changes a pure value (`pcall_mono`). -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State evalExpr evalExprs)

/-- Core evaluates literal arguments to themselves. -/
theorem values_eval {P : Core.Program} : ∀ (vals : List Value) {k : Nat} {st st' : State} {vs : List Value},
    evalExprs k P st (vals.map .value) = .done vs st' → vs = vals ∧ st' = st
  | [], _, _, _, _, run => exprs_nil_inv run
  | x :: rest, _, _, _, _, run => by
    obtain ⟨_, u, s1, us, -, head, tail, rfl⟩ := exprs_cons_inv run
    obtain ⟨rfl, rfl⟩ := value_inv head
    obtain ⟨rfl, rfl⟩ := values_eval rest tail
    exact ⟨rfl, rfl⟩

section
variable {sp : SrcProgram} {prims : Prims} {outside : List Nat}

/-- A completed Core call of a pure function: its pure call's value, with the
invariant kept and every earlier heap read kept. -/
theorem call_sim (pure : PureProg sp prims outside) (primsOk : PrimsOk sp prims)
    {fuel c : Nat} {f : SrcFunc} {args ps : List Value} {st st' : State} {v : Value}
    (found : sp.funcs[c]? = some f) (notOutside : outside.contains c = false) (inv : Inv st)
    (bound : st'.heap.nextAddress ≤ 2 ^ 64)
    (rel : VRels sp.toCore (boxElem sp prims) st.heap (f.params.map SrcParam.ty) args ps)
    (run : evalExpr fuel sp.toCore st (.call c (args.map .value)) = .done v st') :
    ∃ w, pcall sp prims fuel c ps = some w ∧ VRel sp.toCore (boxElem sp prims) st'.heap f.ret v w ∧
      Inv st' ∧ Step st st' := by
  obtain ⟨j, f', values, afterArgs, completed, compl, rfl, argsRun, found', len, body, result, rfl⟩ := call_inv' (inside_of found) run
  obtain ⟨rfl, rfl⟩ := values_eval args argsRun
  rw [found, Option.some.injEq] at found'
  subst found'
  obtain ⟨w, hw, rw, inv', step⟩ := func_sim pure primsOk j found notOutside len inv
    (show completed.heap.nextAddress ≤ 2 ^ 64 from bound) rel body result
  exact ⟨w, hw, rw, inv'.restore _, step.restore _⟩

#print axioms call_sim
#print axioms pcall_mono

end

end Lanius.Faithful
