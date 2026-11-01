import Lanius.Faithful.Simulation
import Lanius.Faithful.Gen.SelfCert
import Lanius.Faithful.Gen.SelfPure

/-! # The self program's compiler means its extraction (roadmap V1)

A Core call of the self program's `compile_words`, `front_end_words` or
`grammar` that completes returns a value representing what the extracted Lean
function (`compileWords`, `frontEndWords`, `grammar`) gives at the Lean
values its arguments represent. Each joins `call_sim` (a completed Core call
of a pure function is its pure call) with the function's certificate (a pure
call that returns represents the extraction). -/

namespace Lanius.Faithful.SelfFaithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State evalExpr)
open Lanius.Faithful
open Lanius.Faithful.Self
open Lanius.Faithful.SelfRep
open Lanius.Faithful.SelfCert

/-- The Core values of the self program that are boxes. -/
abbrev boxes : Boxes := boxElem prog prims

/-- `compile_words` called on a Core value that means `x` (the front end's
result) returns a value that means `compileWords x`. -/
theorem compile_words_faithful {fuel : Nat} {st st' : State} {a v p : Value} {x : Option SrcProgram}
    (inv : Inv st) (bound : st'.heap.nextAddress ≤ 2 ^ 64)
    (rel : VRels prog.toCore boxes st.heap ((src_compile_words 11 12).params.map SrcParam.ty) [a] [p])
    (rep : (RepOption 3 RepSrcProgram) x p)
    (run : evalExpr fuel prog.toCore st (.call 6 [.value a]) = .done v st') :
    ∃ w, pcall prog prims fuel 6 [p] = some w ∧ VRel prog.toCore boxes st'.heap (src_compile_words 11 12).ret v w ∧
      (RepOption 2 (RepList 0 RepI32)) (compileWords x) w ∧ Inv st' ∧ Step st st' := by
  obtain ⟨w, hw, rw, inv', step⟩ :=
    call_sim (args := [a]) (ps := [p]) SelfPure.selfPure SelfPure.selfPrims fn_compile_words
      (by decide +kernel) inv bound rel run
  exact ⟨w, hw, rw, cert_compile_words hw rep, inv', step⟩

/-- `front_end_words` called on values that mean a grammar `g` and the
input words `ws` returns a value that means `frontEndWords g ws`. -/
theorem front_end_words_faithful {fuel : Nat} {st st' : State} {a b v p q : Value}
    {g : List Rule} {ws : List (BitVec 32)}
    (inv : Inv st) (bound : st'.heap.nextAddress ≤ 2 ^ 64)
    (rel : VRels prog.toCore boxes st.heap ((src_front_end_words 13 14).params.map SrcParam.ty) [a, b] [p, q])
    (repG : (RepList 35 RepRule) g p) (repW : (RepList 0 RepI32) ws q)
    (run : evalExpr fuel prog.toCore st (.call 7 [.value a, .value b]) = .done v st') :
    ∃ w, pcall prog prims fuel 7 [p, q] = some w ∧ VRel prog.toCore boxes st'.heap (src_front_end_words 13 14).ret v w ∧
      (RepOption 3 RepSrcProgram) (frontEndWords g ws) w ∧ Inv st' ∧ Step st st' := by
  obtain ⟨w, hw, rw, inv', step⟩ :=
    call_sim (args := [a, b]) (ps := [p, q]) SelfPure.selfPure SelfPure.selfPrims fn_front_end_words
      (by decide +kernel) inv bound rel run
  exact ⟨w, hw, rw, cert_front_end_words hw repG repW, inv', step⟩

/-- `grammar()` returns a value that means the grammar table. -/
theorem grammar_faithful {fuel : Nat} {st st' : State} {v : Value}
    (inv : Inv st) (bound : st'.heap.nextAddress ≤ 2 ^ 64)
    (run : evalExpr fuel prog.toCore st (.call 8 []) = .done v st') :
    ∃ w, pcall prog prims fuel 8 [] = some w ∧ VRel prog.toCore boxes st'.heap
        (src_grammar 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32).ret v w ∧
      (RepList 35 RepRule) grammar w ∧ Inv st' ∧ Step st st' := by
  obtain ⟨w, hw, rw, inv', step⟩ :=
    call_sim (args := []) (ps := []) SelfPure.selfPure SelfPure.selfPrims fn_grammar
      (by decide +kernel) inv bound .nil run
  exact ⟨w, hw, rw, cert_grammar hw, inv', step⟩

#print axioms compile_words_faithful
#print axioms front_end_words_faithful
#print axioms grammar_faithful

end Lanius.Faithful.SelfFaithful
