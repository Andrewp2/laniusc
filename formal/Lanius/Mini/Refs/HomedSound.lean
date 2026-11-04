module

public import Lanius.Mini.Refs.HomedLemmas
public import Lanius.Mini.LowerEval

@[expose] public section

/-! # References: the simulation over `HomedCorr` (F5 stage 2, P2)

Stage 2's induction carries `HomedCorr` with the context `RCtx.ofScope`, a
function of the scope (stage 2 plan 2.1), in place of `Corr`. Until the
lowering gives locals homes (leafC's S6), `ofScope` has none, and the
statements over `HomedCorr` (`StmtSoundH`, `EvalSoundH`, with `HMatches` and
`HSimulates`) are the ones over `Corr` (`StmtSound.homed`,
`StmtSoundH.plain`, `EvalSound.homed`, `EvalSoundH.plain`): every binding is
unhomed, and its cell is apart from the places. `sound_both_homed` is
`sound_both` restated. The case proofs move onto `HomedCorr` one by one
(P3), each using the other direction for the cases not yet moved.

The frame invariant stays `FrameCorr` here: it becomes `Homes` together with
the lowering's lending without a copy (S6a), which changes `ArrayCall`'s
code.
-/

namespace Lanius.Mini

open Lanius.Core (Value)
open Lanius.Semantics (State Completion evalExpr execStmt)

/-- A reference type's referent; any other type itself. -/
def SrcType.referentOf : SrcType → SrcType
  | .ref r => r
  | .i32 => .i32
  | .bool => .bool
  | .uint k => .uint k
  | .struct id fs => .struct id fs
  | .enum id vs => .enum id vs
  | .ptr => .ptr
  | .slice e => .slice e
  | .array e n => .array e n
  | .unit => .unit
  | .isize => .isize
  | .char => .char
  | .float f => .float f
  | .sint k => .sint k
  | .view n => .view n
  | .str => .str

/-- The context of a scope, its frame block's address in slot `fs`: each
local's slot and referent as `lookup` finds them. No local has a home yet
(the lowering gives none until S6). -/
def RCtx.ofScope (fs : Nat) (scope : List Binding) : RCtx where
  frame := fs
  homes := []
  slotOf id := match lookup scope id with
    | some b => b.slot
    | none => 0
  refTy id := match lookup scope id with
    | some b => b.ty.referentOf
    | none => .unit

theorem RCtx.ofScope_homes (fs : Nat) (scope : List Binding) : (RCtx.ofScope fs scope).homes = [] := rfl

/-- `Corr` gives the scope's context's reference facts: a local holding a
reference is a reference binding, held by `RefTo`. -/
theorem Corr.refsAgree {sx : Statics} {places : List Addressed} {scope : List Binding} {frame : Nat → Nat}
    {st : State} {env : Env} (corr : Corr sx places scope frame st env) (fs : Nat) :
    RefsAgree (RCtx.ofScope fs scope) places st env where
  homes := fun _ _ _ found => by simp [RCtx.ofScope] at found
  refs := by
    intro id T cell path _ h
    obtain ⟨cl, hid, hentry⟩ := coreLocal_entry h
    rw [corr.cellId] at hid
    cases hl : lookup scope id with
    | none => simp [hl] at hid
    | some b =>
      simp only [hl, Option.map_some, Option.some.injEq] at hid
      subst hid
      obtain ⟨v, entry, holds⟩ := corr.values b (lookup_mem hl).1
      rw [entry] at hentry
      have same : v = .reference T cell path := by simpa using hentry
      subst same
      obtain ⟨r, hty, hto, -⟩ := holds.reference
      simp only [RCtx.ofScope, hl, hty, SrcType.referentOf]
      exact hto

/-- `Corr` is `HomedCorr` at the scope's context. -/
theorem Corr.homed {sx : Statics} {places : List Addressed} {scope : List Binding} {frame : Nat → Nat}
    {st : State} {env : Env} (corr : Corr sx places scope frame st env) (fs : Nat) :
    HomedCorr sx places scope frame (RCtx.ofScope fs scope) st env :=
  HomedCorr.ofCorr corr (corr.refsAgree fs) rfl

/-- `HomedCorr` with the scope's cells apart from the places is `Corr`. -/
theorem HomedCorr.plain {sx : Statics} {places : List Addressed} {scope : List Binding} {frame : Nat → Nat}
    {c : RCtx} {st : State} {env : Env} (hc : HomedCorr sx places scope frame c st env)
    (apart : ∀ x ∈ places, ∀ b ∈ scope, x.cell ≠ frame b.slot) : Corr sx places scope frame st env :=
  ⟨hc.locals, apart, fun b mem => hc.values b mem fun x xm => apart x xm b mem,
    fun v vm b mem nv => hc.unviewed v vm b mem (fun x xm => apart x xm b mem) nv,
    fun b mem n hty => hc.viewed b mem (fun x xm => apart x xm b mem) n hty⟩

/-- Places below `base` are apart from a scope laid out from `base`. -/
theorem Layout.apart_below {scope : List Binding} {frame : Nat → Nat} {base next : Nat}
    (fr : Layout scope frame base next) {places : List Addressed} (under : ∀ x ∈ places, x.cell < base) :
    ∀ x ∈ places, ∀ b ∈ scope, x.cell ≠ frame b.slot :=
  fun x xm b bm => Nat.ne_of_lt (Nat.lt_of_lt_of_le (under x xm) (fr.above b bm))

/-- `Matches` over `HomedCorr` at the scope's context, frame slot `fs`. -/
inductive HMatches (sx : Statics) (bud : Budget) (places : List Addressed) (ret : SrcType) (scope : List Binding)
    (frame : Nat → Nat) (fs : Nat) (st : State) : Completion → Outcome → Prop where
  | next {env : Env} {hp : Heap} : HomedCorr sx places scope frame (RCtx.ofScope fs scope) st env →
      HeapCorr st.heap st.world hp → FrameCorr sx bud places st hp →
      HMatches sx bud places ret scope frame fs st .next (.normal env hp)
  | returned {v : Option Value} {bits : List (BitVec 64)} {hp : Heap} :
      RetHolds sx places ret v bits → bits.length = ret.size → HeapCorr st.heap st.world hp →
      FrameCorr sx bud places st hp → HMatches sx bud places ret scope frame fs st (.returned v) (.returned bits hp)
  | broke {env : Env} {hp : Heap} : HomedCorr sx places scope frame (RCtx.ofScope fs scope) st env →
      HeapCorr st.heap st.world hp → FrameCorr sx bud places st hp →
      HMatches sx bud places ret scope frame fs st .breakLoop (.broke env hp)
  | continued {env : Env} {hp : Heap} : HomedCorr sx places scope frame (RCtx.ofScope fs scope) st env →
      HeapCorr st.heap st.world hp → FrameCorr sx bud places st hp →
      HMatches sx bud places ret scope frame fs st .continueLoop (.continued env hp)

theorem Matches.homed {sx : Statics} {bud : Budget} {places : List Addressed} {ret : SrcType}
    {scope : List Binding} {frame : Nat → Nat} {st : State} {c : Completion} {out : Outcome}
    (m : Matches sx bud places ret scope frame st c out) (fs : Nat) :
    HMatches sx bud places ret scope frame fs st c out := by
  cases m with
  | next corr hc fc => exact .next (corr.homed fs) hc fc
  | returned holds len hc fc => exact .returned holds len hc fc
  | broke corr hc fc => exact .broke (corr.homed fs) hc fc
  | continued corr hc fc => exact .continued (corr.homed fs) hc fc

theorem HMatches.plain {sx : Statics} {bud : Budget} {places : List Addressed} {ret : SrcType}
    {scope : List Binding} {frame : Nat → Nat} {fs : Nat} {st : State} {c : Completion} {out : Outcome}
    (m : HMatches sx bud places ret scope frame fs st c out)
    (apart : ∀ x ∈ places, ∀ b ∈ scope, x.cell ≠ frame b.slot) :
    Matches sx bud places ret scope frame st c out := by
  cases m with
  | next hc' hc fc => exact .next (hc'.plain apart) hc fc
  | returned holds len hc fc => exact .returned holds len hc fc
  | broke hc' hc fc => exact .broke (hc'.plain apart) hc fc
  | continued hc' hc fc => exact .continued (hc'.plain apart) hc fc

/-- `Simulates` with `HMatches`. -/
abbrev HSimulates (sx : Statics) (bud : Budget) (places : List Addressed) (mp : Program) (hp : Heap) (ret : SrcType)
    (scope : List Binding) (frame : Nat → Nat) (fs : Nat) (base : Nat) (st : State) (env : Env) (stmt : Stmt)
    (c : Completion) (st' : State) : Prop :=
  st'.Fresh ∧ Keeps places base st st' ∧ ∃ d out, Exec mp d env hp stmt out ∧
    HMatches sx bud places ret scope frame fs st' c out

/-- `StmtSound` over `HomedCorr` at the scope's context. -/
def StmtSoundH (sp : SrcProgram) (mp : Program) (fuel : Nat) : Prop :=
  ∀ {bud : Budget} {sx : Statics} [StaticsOf sp sx] {places : List Addressed} {hp : Heap} {s : SrcStmt} {ret : SrcType}
    {scope : List Binding} {next : Nat} {stmt : Stmt} {frame : Nat → Nat} {fs : Nat} {base : Nat} {st : State}
    {env : Env} {c : Completion} {st' : State},
    s.lower (sp.sigsAt bud) sp.decls ret scope next = some stmt →
    HomedCorr sx places scope frame (RCtx.ofScope fs scope) st env → Layout scope frame base next → st.Fresh →
    base ≤ st.nextCell → HeapCorr st.heap st.world hp → FrameCorr sx bud places st hp →
    (∀ x ∈ places, x.cell < base) →
    execStmt fuel sp.toCore st s.toCore = .done c st' → st'.heap.nextAddress ≤ hp.limit →
    HSimulates sx bud places mp hp ret scope frame fs base st env stmt c st'

/-- `EvalSound` over `HomedCorr` at the scope's context, the scope's cells
apart from the places. -/
def EvalSoundH (sp : SrcProgram) (mp : Program) (fuel : Nat) : Prop :=
  ∀ {bud : Budget} {sx : Statics} [StaticsOf sp sx] {places : List Addressed} {hp : Heap} {e : SrcEff}
    {scope : List Binding} {slot : Nat} {ev : Evaluated} {frame : Nat → Nat} {fs : Nat} {base : Nat} {st : State}
    {env : Env} {v : Value} {st' : State},
    e.eval (sp.sigsAt bud) sp.decls scope slot = some ev →
    HomedCorr sx places scope frame (RCtx.ofScope fs scope) st env →
    (∀ x ∈ places, ∀ b ∈ scope, x.cell ≠ frame b.slot) → Layout scope frame base slot → st.Fresh →
    HeapCorr st.heap st.world hp → FrameCorr sx bud places st hp →
    evalExpr fuel sp.toCore st e.toCore = .done v st' → st'.heap.nextAddress ≤ hp.limit →
    Evaluates sx bud places mp hp slot st env ev v st'

theorem StmtSound.homed {sp : SrcProgram} {mp : Program} {fuel : Nat} (sound : StmtSound sp mp fuel) :
    StmtSoundH sp mp fuel := by
  intro bud sx _ places hp s ret scope next stmt frame fs base st env c st' lowered hc fr fresh le heap fc
    under run bound
  obtain ⟨fresh', keeps, d, out, exec, m⟩ :=
    sound lowered (hc.plain (fr.apart_below under)) fr fresh le heap fc under run bound
  exact ⟨fresh', keeps, d, out, exec, m.homed fs⟩

theorem StmtSoundH.plain {sp : SrcProgram} {mp : Program} {fuel : Nat} (sound : StmtSoundH sp mp fuel) :
    StmtSound sp mp fuel := by
  intro bud sx _ places hp s ret scope next stmt frame base st env c st' lowered corr fr fresh le heap fc
    under run bound
  obtain ⟨fresh', keeps, d, out, exec, m⟩ :=
    sound (fs := 0) lowered (corr.homed 0) fr fresh le heap fc under run bound
  exact ⟨fresh', keeps, d, out, exec, m.plain (fr.apart_below under)⟩

theorem EvalSound.homed {sp : SrcProgram} {mp : Program} {fuel : Nat} (sound : EvalSound sp mp fuel) :
    EvalSoundH sp mp fuel := by
  intro bud sx _ places hp e scope slot ev frame fs base st env v st' lowered hc apart fr fresh heap fc run bound
  exact sound lowered (hc.plain apart) fr fresh heap fc run bound

theorem EvalSoundH.plain {sp : SrcProgram} {mp : Program} {fuel : Nat} (sound : EvalSoundH sp mp fuel) :
    EvalSound sp mp fuel := by
  intro bud sx _ places hp e scope slot ev frame base st env v st' lowered corr fr fresh heap fc run bound
  exact sound (fs := 0) lowered (corr.homed 0) corr.apart fr fresh heap fc run bound

/-- `sound_both` over `HomedCorr`. -/
theorem sound_both_homed {sp : SrcProgram} {mp : Program}
    (lowered : lowerFuncs (sigs sp.funcs) (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs) :
    ∀ fuel, StmtSoundH sp mp fuel ∧ EvalSoundH sp mp fuel :=
  fun fuel => ⟨StmtSound.homed (sound_both lowered fuel).1, EvalSound.homed (sound_both lowered fuel).2⟩

end Lanius.Mini
