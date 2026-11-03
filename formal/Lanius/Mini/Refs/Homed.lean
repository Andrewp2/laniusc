module

public import Lanius.Mini.Refs.Model
public import Lanius.Mini.LowerExpr

@[expose] public section

/-! # References: locals with homes (F5, stage 2)

`Corr` with homed locals (`HomedCorr`): a local the program borrows lives in
its home, not its slots (SEMANTIC_DECISIONS "References: the memory model",
point 2). A binding is homed when its cell is a home's cell; the others are
as in `Corr`. Untrusted; for stage 2's open statements.
-/

namespace Lanius.Mini

open Lanius.Core (Value)
open Lanius.Semantics (State)

/-- A binding whose cell is no home's: it lives in its slots. -/
def Unhomed (places : List Addressed) (frame : Nat → Nat) (b : Binding) : Prop :=
  ∀ x ∈ places, x.cell ≠ frame b.slot

/-- `Corr` with homed locals. Core's locals are the scope's bindings, each
slot's cell given by `frame` (`locals`). A binding without a home (its cell
no home's, `Unhomed`) is as in `Corr`: its cell holds a value its slots
represent, no view roots at it unless it is a viewed array, and a viewed
array's view is there (`values`, `unviewed`, `viewed`). A homed binding's
value is its home's (`Homes.holds`), which the context finds (`refs`:
`RefsAgree`, with the frame block's address in slot `c.frame`), of the
binding's type (`homedTy`). A local the context gives no home is unhomed
(`unhomed`). The homes `places` include the callers' homes, which the
values may name. -/
structure HomedCorr (sx : Statics) (places : List Addressed) (scope : List Binding) (frame : Nat → Nat)
    (c : RCtx) (st : State) (env : Env) : Prop where
  locals : st.locals = scope.map fun b => (b.id, frame b.slot)
  values : ∀ b ∈ scope, Unhomed places frame b → ∃ v,
    st.cellEntry? (frame b.slot) = some ⟨frame b.slot, some v⟩ ∧ b.ty.HoldsAt sx places v env b.slot
  unviewed : ∀ v ∈ st.i32ArrayViews, ∀ b ∈ scope, Unhomed places frame b → viewedType b.ty = false →
    v.root ≠ frame b.slot
  viewed : ∀ b ∈ scope, Unhomed places frame b → ∀ n, b.ty = .view n →
    ∃ w ∈ st.i32ArrayViews, w.root = frame b.slot ∧ w.address = (env b.slot).toNat ∧ w.length = n ∧ 0 < n
  refs : RefsAgree c places st env
  homedTy : ∀ id b offset ty, lookup scope id = some b → c.homes.lookup id = some (offset, ty) → ty = b.ty
  unhomed : ∀ id b, lookup scope id = some b → c.homes.lookup id = none → Unhomed places frame b

end Lanius.Mini
