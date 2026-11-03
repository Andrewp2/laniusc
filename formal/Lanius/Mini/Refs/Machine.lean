module

public import Lanius.Mini.Refs.Model
public import Lanius.Mini.CompileCorrect

@[expose] public section

/-! # References: the code templates on the machine (F5)

The code of a place (`RPlace.code`), a read and a write through a
reference (`loadSlots`, `storeSlots`) are mini statements built from
existing constructors (assignments, 1-, 4- and 8-byte loads and stores, an
`if`, a division), so the existing compilation proofs (`compileStmt_correct`,
`compileStmt_stops`, `compileStmt_fits`) cover them once their slots are
below the function's locals (`Stmt.within`). Untrusted.
-/

namespace Lanius.Mini

/-- Every index code of the place is within the locals, its slot too. -/
def RPlace.IndexesWithin (base : Nat) (arities : List Arity) (results : Nat) : RPlace → Prop
  | .home _ => True
  | .deref _ => True
  | .field b _ => b.IndexesWithin base arities results
  | .index b _ code slot => b.IndexesWithin base arities results ∧ code.within base arities results = true ∧ slot < base

/-- The most temporaries an index code of the place uses. -/
def RPlace.indexTemps : RPlace → Nat
  | .home _ => 0
  | .deref _ => 0
  | .field b _ => b.indexTemps
  | .index b _ code _ => max b.indexTemps code.temps

/-- A reference code template whose slots are within the locals: a read, a
write, or a place's address. -/
def RefCode (base : Nat) (arities : List Arity) (results : Nat) (stmt : Stmt) : Prop :=
  (∃ (ty : SrcType) (r target : Nat), r < base ∧ target + ty.size ≤ base ∧ stmt = ty.loadSlots r target) ∨
    (∃ (ty : SrcType) (r slot : Nat), r < base ∧ slot + ty.size ≤ base ∧ stmt = ty.storeSlots r slot) ∨
    ∃ (c : RCtx) (t : Nat) (p : RPlace) (ty : SrcType), p.code c t = some (stmt, ty) ∧ t < base ∧
      (∀ k ∈ p.slots c, k < base) ∧ p.IndexesWithin base arities results

end Lanius.Mini
