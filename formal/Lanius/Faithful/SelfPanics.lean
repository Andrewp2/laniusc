import Lanius.Faithful.SelfLive
import Lanius.Faithful.Sim.Wrap
import Lanius.Faithful.Gen.SelfLiveAll
import Lanius.Faithful.Gen.SelfTerm

/-! # The self program's pure compile fails only in `plus` and `times`

The prelude's `plus` and `times` panic when their result overflows. With
the two replaced by their operators, which wrap (`progW`), the pure compile
of any words has a value at some fuel (`compileW_total`): every function
the compile reaches is checked and terminates (`SelfTerm.termOk`), is typed
(`SelfPure.selfPure`), and cannot fail other than at a call
(`SelfPure.livesOk`), so `pcall_live` (Sim/Live.lean) gives each call a
value of its return type. When the self program's own compile has no value,
it is so because `plus` or `times` panicked. -/

namespace Lanius.Faithful.SelfPanics

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Faithful
open Lanius.Faithful.Self
open Lanius.Faithful.SelfRep
open Lanius.Faithful.SelfCert
open Lanius.Faithful.SelfLive
open Lanius.Faithful.Termination

/-- The self program with the prelude's `plus` and `times` replaced by
`return a + b` and `return a * b`, which wrap. -/
def progW : SrcProgram := wrapAt (wrapAt prog SelfPure.ixPlus .plus) SelfPure.ixTimes .times

/-- The pure compile of the words `W` in `progW` with fuel `N`: `grammar()`,
then `front_end_words(grammar(), list)` and `compile_words(..)`, as
`selfCost` runs them in `prog`. -/
def compileW (N : Nat) (W : List (BitVec 32)) : Option Value :=
  (pcall progW prims N 8 []).bind fun g =>
  (pcall progW prims N 7 [g, listVal W]).bind fun fe =>
  pcall progW prims N 6 [fe]

theorem plus_ne_times : SelfPure.ixPlus ≠ SelfPure.ixTimes := by decide

theorem termW : TermOk progW prims SelfTerm.info :=
  termOk_wrapAt (termOk_wrapAt SelfTerm.termOk (by decide +kernel) (by decide +kernel))
    (by decide +kernel) (by decide +kernel)

theorem pureW : PureProg progW prims SelfPure.outside := by
  refine pureProg_wrapAt (pureProg_wrapAt SelfPure.selfPure ?_) ?_
  · intro f hf _ _
    have e := hf.symm.trans fn_plus
    rw [Option.some.injEq] at e
    subst e
    exact pureFunc_fast SelfPure.boxElem_self SelfPure.callTy_self (by decide +kernel)
  · intro f hf _ _
    rw [wrapAt_ne plus_times_ne] at hf
    have e := hf.symm.trans fn_times
    rw [Option.some.injEq] at e
    subst e
    rw [pureFunc_wrapAt]
    exact pureFunc_fast SelfPure.boxElem_self SelfPure.callTy_self (by decide +kernel)
where plus_times_ne : SelfPure.ixPlus ≠ SelfPure.ixTimes := plus_ne_times

theorem primsW : PrimsTy progW prims :=
  primsTy_wrapAt (primsTy_wrapAt (primsTy_of SelfPure.selfPrims) (np_plus : prims.isPrim SelfPure.ixPlus = false))
    (np_times : prims.isPrim SelfPure.ixTimes = false)

theorem liveW : ∀ c f, progW.funcs[c]? = some f → prims.isPrim c = false → SelfPure.outside.contains c = false →
    SelfPure.liveBad.contains c = false → LiveFn SelfPure.liveBad f = true := by
  intro c f hf hp hout hbad
  by_cases e2 : SelfPure.ixTimes = c
  · rw [progW, wrapAt_get, if_pos e2] at hf
    obtain ⟨g, -, rfl⟩ := Option.map_eq_some_iff.mp hf
    exact liveFn_wrap rfl
  · rw [progW, wrapAt_ne e2] at hf
    by_cases e1 : SelfPure.ixPlus = c
    · rw [wrapAt_get, if_pos e1] at hf
      obtain ⟨g, -, rfl⟩ := Option.map_eq_some_iff.mp hf
      exact liveFn_wrap rfl
    · rw [wrapAt_ne e1] at hf
      rcases SelfPure.livesOk c f hf with hw | ok
      · have hm : 0 + c ∈ [SelfPure.ixPlus, SelfPure.ixTimes] := List.elem_iff.mp hw
        simp only [Nat.zero_add, List.mem_cons, List.not_mem_nil, or_false] at hm
        rcases hm with h | h
        · exact absurd h.symm e1
        · exact absurd h.symm e2
      · rw [Nat.zero_add] at ok
        rw [SelfPure.prims_eq] at hp
        exact LiveOk.liveFn ok hp hout hbad

theorem goodW {c : Nat} (ann : (SelfTerm.info.ann c).isSome = true) (hp : prims.isPrim c = false)
    (hout : SelfPure.outside.contains c = false) (hbad : SelfPure.liveBad.contains c = false)
    (vs : List Value) : GoodCall progW prims c vs := by
  obtain ⟨a, ha⟩ := Option.isSome_iff_exists.mp ann
  exact pcall_live termW primsW pureW liveW c a ha hp hout hbad vs

/-- The type of `List<i32>`, `oracle_read`'s value. -/
def listTy : SrcType := .enum 0 [[], [.i32, .struct 1 [.ptr]]]

theorem listVal_pty (W : List (BitVec 32)) : PTy (boxElem progW prims) listTy (listVal W) := by
  have hb : boxElem progW prims 1 = some listTy := by
    rw [progW, boxElem_wrapAt, boxElem_wrapAt, SelfPure.prims_eq, SelfPure.boxElem_self]
    rfl
  unfold listVal
  induction W with
  | nil => exact .enum (k := 0) rfl .nil
  | cons x xs ih =>
    exact .enum (k := 1) rfl (.cons (.scalar ⟨_, rfl, BitVec.le_toInt x, BitVec.toInt_lt⟩)
      (.cons (.box hb ih) .nil))

/-- **With `plus` and `times` wrapping, the pure compile has a value.** -/
theorem compileW_total (W : List (BitVec 32)) : ∃ N v, compileW N W = some v := by
  have f8 : progW.funcs[8]? = some (src_grammar 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32) := by
    rw [progW, wrapAt_ne (by decide), wrapAt_ne (by decide)]
    exact fn_grammar
  have f7 : progW.funcs[7]? = some (src_front_end_words 13 14) := by
    rw [progW, wrapAt_ne (by decide), wrapAt_ne (by decide)]
    exact fn_front_end_words
  have f6 : progW.funcs[6]? = some (src_compile_words 11 12) := by
    rw [progW, wrapAt_ne (by decide), wrapAt_ne (by decide)]
    exact fn_compile_words
  have g8 := goodW (c := 8) (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel) [] _ f8 .nil
  have run : EvSome (fun m => compileW m W) (fun _ => True) := by
    refine EvSome.bind g8 fun g hg _ => ?_
    have g7 := goodW (c := 7) (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)
      [g, listVal W] _ f7 (.cons hg (.cons (listVal_pty W) .nil))
    refine EvSome.bind g7 fun fe hfe _ => ?_
    have g6 := goodW (c := 6) (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide +kernel)
      [fe] _ f6 (.cons hfe .nil)
    obtain ⟨N, v, -, hN⟩ := g6
    exact ⟨N, v, trivial, hN⟩
  obtain ⟨N, v, -, hN⟩ := run
  exact ⟨N, v, hN N (Nat.le_refl N)⟩

/-- The self program's pure compile of the words `W` fails in `plus` or
`times`: the cost semantics gives it no cost at any fuel (`selfCost`), and
with the two wrapping (`progW`) it has a value. -/
def SelfPanics (W : List (BitVec 32)) : Prop :=
  (∀ N, selfCost N W = none) ∧ ∃ N v, compileW N W = some v

theorem selfPanics {W : List (BitVec 32)} (none : ∀ N, selfCost N W = none) : SelfPanics W :=
  ⟨none, compileW_total W⟩

#print axioms compileW_total

end Lanius.Faithful.SelfPanics
