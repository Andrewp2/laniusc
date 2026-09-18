import Lanius.Extraction.Allocation.Sequence

namespace Lanius.Extraction.Entry.Pointers

open Lanius.Core Lanius.Semantics Lanius.Memory

/-- Pointer queries may synchronize heap bytes, but preserve all state used
to read the remaining pointer checks. -/
structure Frame (before after : State) : Prop where
  cells : after.cells = before.cells
  locals : after.locals = before.locals
  views : after.i32ArrayViews = before.i32ArrayViews
  next : after.nextCell = before.nextCell
  remaining : after.heap.remaining = before.heap.remaining
  world : after.world = before.world

theorem Frame.refl (state : State) : Frame state state := ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩

theorem Frame.trans (first : Frame before middle) (second : Frame middle after) : Frame before after :=
  ⟨second.cells.trans first.cells, second.locals.trans first.locals, second.views.trans first.views,
    second.next.trans first.next, second.remaining.trans first.remaining, second.world.trans first.world⟩

theorem Frame.localRead (frame : Frame before after) (binding : Lanius.VarId) :
    after.local? binding = before.local? binding := by
  have sameCells : after.cell? = before.cell? := by
    funext cell
    simp only [State.cell?, State.cellEntry?, frame.cells]
  simp only [State.local?, State.cellId?, frame.locals, sameCells]

inductive Pointer where
  | localValue (binding : Lanius.VarId)
  | slice (binding : Lanius.VarId)
deriving DecidableEq

def Pointer.name : Pointer → Lanius.VarId
  | .localValue name | .slice name => name

def Pointer.expression : Pointer → Expr
  | .localValue binding => .local binding
  | .slice binding => .i32SliceDataPtr (.local binding)

def Pointer.Ready (state : State) : Pointer → Prop
  | .localValue binding => ∃ address, state.local? binding = some (.pointer address) ∧ address ≠ null
  | .slice binding => ∃ view ∈ state.i32ArrayViews,
      state.local? binding = some (.slice (.scalar (.signed .i32)) view.root view.projections 0 view.length)

/-- Retain which registered slice supplied the actual raw address. A non-null
pointer alone does not justify using it to read a particular buffer. -/
def Pointer.Resolves (state : State) (address : Address) : Pointer → Prop
  | .localValue binding => state.local? binding = some (.pointer address)
  | .slice binding => ∃ view ∈ state.i32ArrayViews, address = view.address ∧
      state.local? binding = some (.slice (.scalar (.signed .i32)) view.root view.projections 0 view.length)

theorem Pointer.Resolves.sliceAddress (resolved : (Pointer.slice binding).Resolves state address)
    (registry : Allocation.Registry state) (member : view ∈ state.i32ArrayViews)
    (read : state.local? binding = some (.slice (.scalar (.signed .i32)) view.root view.projections 0 view.length)) :
    address = view.address := by
  obtain ⟨actual, present, selected, actualRead⟩ := resolved
  have roots : actual.root = view.root := by
    have same := actualRead.symm.trans read
    injection same with same
    injection same
  exact selected.trans (congrArg I32ArrayView.address (registry.view_eq present member roots))

theorem Pointer.Ready.transport {pointer : Pointer} (ready : pointer.Ready before)
    (frame : Frame before after) : pointer.Ready after := by
  cases pointer <;> simpa only [Pointer.Ready, frame.views, frame.localRead] using ready

theorem Pointer.evaluates (pointer : Pointer) (program : Program) (registry : Allocation.Registry before)
    (ready : pointer.Ready before) :
    ∃ address after, Evaluates program before pointer.expression (.pointer address) after ∧
      address ≠ null ∧ Allocation.Registry after ∧ Frame before after ∧ pointer.Resolves before address := by
  cases pointer with
  | localValue binding =>
      obtain ⟨address, read, nonnull⟩ := ready
      exact ⟨address, before, ⟨1, evalLocal_of_local 0 program before binding _ read⟩,
        nonnull, registry, Frame.refl before, read⟩
  | slice binding =>
      obtain ⟨view, member, read⟩ := ready
      obtain ⟨after, evaluated, nonnull, valid, cells, locals, views, next, remaining, world⟩ :=
        registry.evaluatesPointer program member binding read
      exact ⟨view.address, after, evaluated, nonnull, valid, ⟨cells, locals, views, next, remaining, world⟩,
        view, member, rfl, read⟩

/-- Binding a pointer must not invalidate the slice and pointer reads used by
the subsequent entry guard. The distinct-name premise makes shadowing explicit. -/
theorem Pointer.Ready.bindOther {pointer : Pointer} (ready : pointer.Ready state)
    (registry : Allocation.Registry state) (bound : Lanius.VarId) (value : Value)
    (different : match pointer with
      | .localValue queried | .slice queried => bound ≠ queried) :
    pointer.Ready (state.bindLocal bound value) := by
  cases pointer with
  | localValue queried =>
      simpa only [Pointer.Ready,
        Lanius.Separation.bindLocal_preserves_other_local registry.wellFormed different] using ready
  | slice queried =>
      simpa only [Pointer.Ready, State.bindLocal, State.bindCell] using
        (show ∃ view ∈ state.i32ArrayViews,
          (state.bindLocal bound value).local? queried = some
            (.slice (.scalar (.signed .i32)) view.root view.projections 0 view.length) from by
          simpa only [Pointer.Ready, Lanius.Separation.bindLocal_preserves_other_local
            registry.wellFormed different] using ready)

/-- A source-level pointer alias, including its lexical continuation. -/
structure Binding where
  name : Lanius.VarId
  source : Pointer
  continuation : Stmt

def Binding.statement (binding : Binding) : Stmt :=
  .letLocal binding.name (.scalar .rawPtr) binding.source.expression binding.continuation

theorem Binding.executes (binding : Binding) (program : Program) (before : State)
    (completion : Completion) (post : Lanius.World.State → Prop)
    (registry : Allocation.Registry before) (ready : binding.source.Ready before)
    (continuationRun : ∀ queried address, Frame before queried → address ≠ null →
      Allocation.Registry (queried.bindLocal binding.name (.pointer address)) →
      (Pointer.localValue binding.name).Ready (queried.bindLocal binding.name (.pointer address)) →
      ∃ after, Executes program (queried.bindLocal binding.name (.pointer address))
        binding.continuation completion after ∧ post after.world) :
    ∃ after, Executes program before binding.statement completion after ∧ post after.world := by
  obtain ⟨address, queried, evaluated, nonnull, valid, frame, _resolved⟩ :=
    binding.source.evaluates program registry ready
  have read : (queried.bindLocal binding.name (.pointer address)).local? binding.name =
      some (.pointer address) := by
    have fresh := Lanius.Properties.bindCell_finds_fresh_cell queried binding.name
      (some (.pointer address)) valid.wellFormed
    simp only [State.bindLocal, State.local?, State.cellId?, State.bindCell,
      List.find?_cons, beq_self_eq_true]
    exact congrArg (fun cell => cell.bind Cell.value) fresh
  obtain ⟨after, continued, satisfied⟩ := continuationRun queried address frame nonnull
    (valid.bindLocal _ _) ⟨address, read, nonnull⟩
  exact ⟨restoreLocals queried after, executesLetLocal evaluated continued, satisfied⟩

def checkBinding? : (source : Stmt) → Option (Source.CheckedStatement Binding.statement source)
  | .letLocal name (.scalar .rawPtr) (.i32SliceDataPtr (.local source)) continuation =>
      some ⟨⟨name, .slice source, continuation⟩, rfl⟩
  | .letLocal name (.scalar .rawPtr) (.local source) continuation =>
      some ⟨⟨name, .localValue source, continuation⟩, rfl⟩
  | _ => none

end Lanius.Extraction.Entry.Pointers
