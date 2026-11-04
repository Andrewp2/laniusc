module

public import Lanius.Faithful.GenB.SelfBModel5
public import Lanius.Faithful.SelfPre.EvalSlots
public import Lanius.Mini.Frontend

@[expose] public section

open Lanius.Mini
open Lanius.Faithful.SelfPre

/-- Every function the front end builds nests its expressions at most `2 ^ 55`
unchecked slot steps (`SrcStmt.slotNest`, SelfPre/EvalSlots): the premise
`PreCompileSourceV5` adds for the front end to supply. Why it should hold:
expressions nest no deeper than the source's parse, and monomorphization and
match lowering copy expressions without nesting them deeper. A proof through
those copies is long, so the intended route is a front-end check, as for the
lets' slots (`FrontEndStmtDepthV2`): `lim_funcs` rejecting a function whose
`slot_nest` is past `depth_limit()` (`2 ^ 40`). -/
def Lanius.Open.FrontEndSlotNest : Prop :=
  ∀ (W : List (BitVec 32)) (p : Lanius.Mini.SrcProgram),
    Lanius.Mini.frontEndWords grammar W = some p →
    ∀ f ∈ p.funcs, Lanius.Faithful.SelfPre.SrcStmt.slotNest f.body ≤ 2 ^ 55
