import Lanius.Separation.CellEffect

namespace Lanius.Extraction.Entry.Scope
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- A postcondition that survives closing temporary lexical scopes. It can
retain buffers, cursors, heap/view resources, and the host world together. -/
structure Post where
  holds : Completion → State → Prop
  restore : ∀ completion caller after, holds completion after → holds completion (restoreLocals caller after)

instance : CoeFun Post (fun _ => Completion → State → Prop) := ⟨Post.holds⟩

/-- Observe the final store through a fixed caller scope. Nested temporary
bindings disappear, while all actual cell, heap, and world updates remain. -/
def Post.inScope (caller : State) (predicate : Completion → State → Prop) : Post :=
  ⟨fun completion after => predicate completion (restoreLocals caller after), fun _ _ _ proved => proved⟩

/-- Once the enclosing statement returns the original bindings, a scoped
loop invariant describes its actual result state, not a projected copy. -/
theorem Post.inScope_iff (sameLocals : after.locals = caller.locals)
    (predicate : Completion → State → Prop) :
    (Post.inScope caller predicate) completion after ↔ predicate completion after := by
  have restored : restoreLocals caller after = after := by
    unfold restoreLocals
    rw [← sameLocals]
  change predicate completion (restoreLocals caller after) ↔ predicate completion after
  rw [restored]

def Post.world (predicate : Completion → Lanius.World.State → Prop) : Post :=
  ⟨fun completion after => predicate completion after.world, fun _ _ _ proved => proved⟩

/-- Forget callee-local mappings when composing a call with fresh caller
bindings. This retains the actual cells and host world, not a copied state. -/
theorem called (effect : CellEffect writes before after) (wellFormed : StateWellFormed before) :
    CellEffect writes before (restoreLocals before after) :=
  ⟨effect.domain.restoreLocals_wellFormed wellFormed effect.wellFormed,
    rfl, effect.world, effect.oldCells, effect.nextCell, effect.domain.restoreLocals⟩

theorem bound (before : State) (id : VarId) (value : Value) (wellFormed : StateWellFormed before) :
    CellEffect CellSet.empty before (restoreLocals before (before.bindLocal id value)) := by
  have effect := bindLocal_effect before id value
  exact ⟨effect.domain.restoreLocals_wellFormed wellFormed (bindLocal_preserves_well_formed _ _ _ wellFormed),
    rfl, effect.world, effect.oldCells, effect.nextCell, effect.domain.restoreLocals⟩

end Lanius.Extraction.Entry.Scope
