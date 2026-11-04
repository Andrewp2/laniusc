module

public import Lanius.Mini.Refs.Model

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **A write after a right side with effects** (`x.f = g(&mut x)`). An
assignment through a place computes the place's address into slot `t` first
(`RPlace.code`, as Core resolves the place first), then runs the right side's
code `rhs`, which may call functions that write the place's cell through
references, then stores (`storeSlots`). Suppose `rhs`, run from the slots
the place's code leaves, keeps `t`, leaves the homes holding for Core's state
`st₁` after the right side, and leaves in the slots from `slot` its value
`v`, which names only homes older than the place's. Then the whole code ends
with the homes holding for Core's write of `v` at the path into the cell's
value in `st₁` (`replaceProjectedValue`, then `assignCell`, as `CoreAssign`
has it), and only the sub-place's bytes differ from `rhs`'s heap. Homes do
not move, so the address computed before `rhs` still names the place. `rhs`
may be any code: for a compound assignment it also loads the old value. `R`
is whatever else `rhs` gives. -/
def Lanius.Open.AssignAfterRhs : Prop :=
  ∀ (sx : Statics) (bud : Budget) (places : List Addressed) (st st₁ st' : State) (hp : Heap) (c : RCtx)
    (p : RPlace) (t : Nat) (code rhs : Stmt) (ty : SrcType) (cell : Lanius.CellId)
    (path : List ValueProjection) (old v root root' : Value) (cprog : Lanius.Core.Program) (prog : Program)
    (depth : Nat) (env : Env) (scratch : List Nat) (slot : Nat) (R : Env → Heap → Prop),
    Homes sx bud places st hp → RefsAgree c places st env → p.code c t = some (code, ty) →
    p.Resolves cprog st cell path → p.IndexRuns cprog st prog depth hp env t scratch →
    Semantics.readCellProjection st cell path = .ok old → t ∉ scratch → ty.tagsFit = true →
    (∀ env₀ : Env, (∀ k, k ∉ scratch → k ≠ t → env₀ k = env k) → ∃ (env₁ : Env) (hp₁ : Heap),
      Exec prog depth env₀ hp rhs (.normal env₁ hp₁) ∧ env₁ t = env₀ t ∧ Homes sx bud places st₁ hp₁ ∧
      (∀ i x, places[i]? = some x → x.cell = cell → ty.HoldsAt sx (places.drop (i + 1)) v env₁ slot) ∧
      R env₁ hp₁) →
    Semantics.readCellProjection st₁ cell [] = .ok root →
    Semantics.replaceProjectedValue root path v = .ok root' → st₁.assignCell cell root' = some st' →
    ∃ (env₁ : Env) (hp₁ hp' : Heap), R env₁ hp₁ ∧
      Exec prog depth env hp (.seq code (.seq rhs (ty.storeSlots t slot))) (.normal env₁ hp') ∧
      Homes sx bud places st' hp' ∧ { hp' with bytes := hp₁.bytes } = hp₁ ∧
      ∃ x ∈ places, ∃ address, x.cell = cell ∧ x.sub path = some (address, ty) ∧
        ∀ b, (b < address ∨ address + ty.span ≤ b) → hp'.bytes b = hp₁.bytes b
