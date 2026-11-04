module

public import Lanius.Mini.Refs.Machine

@[expose] public section

open Lanius.Mini

/-- **The reference code fits a function.** A read through a reference
(`loadSlots`), a write (`storeSlots`) and a place's address code
(`RPlace.code`), with their slots below the function's locals `base` (and
the place's index codes within them), are within the locals (`Stmt.within`,
the condition of `compileStmt_correct`, `compileStmt_stops` and
`compileStmt_fits`). The loads and stores use one temporary, and a place's
code two besides its index codes' (`Stmt.temps`, which the frame's slots
count). -/
def Lanius.Open.RefCodeWithin : Prop :=
  (∀ (ty : SrcType) (r target base : Nat) (arities : List Arity) (results : Nat),
    r < base → target + ty.size ≤ base →
    (ty.loadSlots r target).within base arities results = true ∧ (ty.loadSlots r target).temps ≤ 1) ∧
  (∀ (ty : SrcType) (r slot base : Nat) (arities : List Arity) (results : Nat),
    r < base → slot + ty.size ≤ base →
    (ty.storeSlots r slot).within base arities results = true ∧ (ty.storeSlots r slot).temps ≤ 1) ∧
  ∀ (c : RCtx) (t : Nat) (p : RPlace) (code : Stmt) (ty : SrcType) (base : Nat) (arities : List Arity)
    (results : Nat),
    p.code c t = some (code, ty) → t < base → (∀ k ∈ p.slots c, k < base) →
    p.IndexesWithin base arities results →
    code.within base arities results = true ∧ code.temps ≤ max 2 p.indexTemps
