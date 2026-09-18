import Lanius.Separation.CellEffect

namespace Lanius.Separation

open Lanius.Core Lanius.Semantics

/-- Pure Core storage operations may change cells or bind fresh locals while
leaving the byte heap and raw-view registrations unchanged. Borrowing a new
string is deliberately excluded from this frame. -/
structure HeapFrame (before after : State) : Prop where
  heap : after.heap = before.heap
  views : after.i32ArrayViews = before.i32ArrayViews

theorem HeapFrame.refl (state : State) : HeapFrame state state := ⟨rfl, rfl⟩

theorem HeapFrame.trans (first : HeapFrame before middle) (second : HeapFrame middle after) :
    HeapFrame before after := ⟨second.heap.trans first.heap, second.views.trans first.views⟩

theorem HeapFrame.ofStoreEffect (effect : StoreEffect writes before after) : HeapFrame before after :=
  ⟨effect.heap, effect.views⟩

theorem HeapFrame.closeLocal (before : State) (id : VarId) (value : Value)
    (frame : HeapFrame (before.bindLocal id value) after) :
    HeapFrame before (restoreLocals before after) := ⟨frame.heap, frame.views⟩

theorem HeapFrame.closeCall (before : State) (bindings : List (VarId × Value))
    (frame : HeapFrame (enterCall before bindings) after) :
    HeapFrame before (restoreLocals before after) :=
  ⟨frame.heap.trans (enterCall_effect before bindings).heap,
    frame.views.trans (enterCall_effect before bindings).views⟩

theorem CellEffect.modifiesOnly (effect : CellEffect writes before after)
    (frame : HeapFrame before after) : ModifiesOnly writes before after :=
  ⟨⟨effect.oldCells, effect.nextCell, frame.heap, effect.world, frame.views, effect.domain⟩, effect.locals⟩

end Lanius.Separation
