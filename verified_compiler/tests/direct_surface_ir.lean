import verified_compiler.tests.direct_surface_boolean
import verified_compiler.tests.direct_ir_builder_navigation
import Lanius.Extraction.WriterProof

namespace SurfaceBooleanProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.Memory IRBuilderNavigationProof

def atom := Extracted.«verified::lean_typed_body».Functions.«surface_atom_output».core
def eventType := ((Extracted.«ir::body_tree».Functions.«shape».core.parameters[0]?).getD (0, .unit)).2
def atomParts : Expr × List (Pattern × Expr) := match atom.body with
  | some (.letLocal _ _ _ (.letLocal _ _ _ (.returnValue (some (.matchValue scrutinee arms))))) => (scrutinee, arms)
  | _ => (.value .unit, [])
def armBinding (ordinal : Nat) : VarId := match ((atomParts.2)[ordinal]?) with
  | some (Pattern.enumVariant _ _ [Pattern.bind id], _) => id | _ => 0
def booleanEvent (value : Bool) : Value :=
  source_value Extracted.«ir::body_events».Types.«Event».«ExpressionBoolean» [.boolean value]
def Context.atomCall (context : Context state) (index : Nat) : Expr :=
  .call atom.id ([context.views, .signed .i32 index, .signed .i32 context.position].map Expr.value)

/-- The actual atom call's read-only prefix. This selects one source scope,
    not another IR; clients prove the selected writer in that scope. -/
def Context.atomScope (context : Context state) (_tree : Ready region state) (index : Nat) : State :=
  (({ state with locals := [] }).bindLocals
    [(atom.argumentId 0, context.views), (atom.argumentId 1, .signed .i32 index),
      (atom.argumentId 2, .signed .i32 context.position)])
    |>.bindLocal (atom.bindingId 0) context.value
    |>.bindLocal (atom.bindingId 1) (.rawSlice eventType region.eventsAddress region.eventsLength)

/-- Read and bind the native View/event prefix once. Callers close the actual
    remaining body; no successful printer execution is assumed here. -/
theorem actualViewEvents (context : Context state) (tree : Ready region referenceState)
    (representation : context.tree = tree.value)
    (views : state.local? viewsId = some context.views) (formed : state.CellsWellFormed)
    (body : ∃ after, RunsStmt extractedProgram
      ((state.bindLocal viewId context.value).bindLocal eventsId
        (.rawSlice eventType region.eventsAddress region.eventsLength)) rest completion after ∧
      WriterFrame ((state.bindLocal viewId context.value).bindLocal eventsId
        (.rawSlice eventType region.eventsAddress region.eventsLength)) after address output) :
    ∃ after, RunsStmt extractedProgram state
      (.letLocal viewId viewTy (.index (.local viewsId) (.value (.signed .i32 0)))
        (.letLocal eventsId eventsTy (.field (.field (.local viewId) 0) 0) rest)) completion after ∧
      WriterFrame state after address output := by
  let viewed := state.bindLocal viewId context.value
  have readView := context.readView
  have treeRead : StableExpr 2 extractedProgram viewed (.field (.local viewId) 0) context.tree viewed := by core_expr
  have eventsRead : StableExpr 3 extractedProgram viewed (.field (.field (.local viewId) 0) 0)
      (.rawSlice eventType region.eventsAddress region.eventsLength) viewed := by
    rw [representation] at treeRead
    exact StableExpr.field treeRead rfl
  apply RunsStmt.letPureWriter
  · core_run
  · exact formed
  · apply RunsStmt.letPureWriter
    · core_run
    · core_formed
    · exact body

#print axioms actualViewEvents

/-- Prove the native reads and match scope once. Every public leaf theorem
    below discharges the selected branch using its checked writer contract. -/
theorem actualSelectedAtom (context : Context state) (tree : Ready region state) (value : Value)
    (representation : context.tree = tree.value) (inside : index < region.count)
    (event : region.events index = value)
    (selection : selectedArm value atomParts.2 = some (bindings, expression))
    (formed : state.CellsWellFormed)
    (branch : ∃ after, RunsExpr extractedProgram ((context.atomScope tree index).bindLocals bindings)
      expression (.signed .i32 (context.position + output.length : Nat)) after ∧
      WriterFrame ((context.atomScope tree index).bindLocals bindings) after
        (context.address + context.position) output) :
    ∃ after, RunsExpr extractedProgram state (context.atomCall index)
      (.signed .i32 (context.position + output.length : Nat)) after ∧
      WriterFrame state after (context.address + context.position) output := by
  core_call_framed Lanius.Extraction.RunsExpr.callWriter atom as callee
  let viewed := callee.bindLocal (atom.bindingId 0) context.value
  let current := viewed.bindLocal (atom.bindingId 1) (.rawSlice eventType region.eventsAddress region.eventsLength)
  have readEvent := (tree.reheap (after := current) rfl).eventReads index inside
  rw [event] at readEvent
  have writer := Lanius.Extraction.RunsExpr.matchWriter
    (program := extractedProgram) (before := current) (scrutinee := atomParts.1)
    (by core_run) selection (by core_formed) branch
  apply actualViewEvents (context.reheap (after := callee) rfl) tree representation (by core_local) (by core_formed)
  core_writer

/-- Read the boolean from the already-built IR and emit its Lean literal. -/
theorem actualAtom (context : Context state) (tree : Ready region state) (value : Bool)
    (representation : context.tree = tree.value) (inside : index < region.count)
    (event : region.events index = booleanEvent value)
    (room : context.position + (bytes value).length ≤ context.capacity)
    (environment : WriterEnvironment state) :
    ∃ after, RunsExpr extractedProgram state (context.atomCall index)
      (.signed .i32 (context.position + (bytes value).length : Nat)) after ∧
      WriterFrame state after (context.address + context.position) (bytes value) := by
  have formed := environment.formed
  apply actualSelectedAtom context tree (booleanEvent value) representation inside event
    (bindings := [(armBinding 0, .boolean value)]) (by rfl) environment.formed
  let branch := (context.atomScope tree index).bindLocals [(armBinding 0, .boolean value)]
  let leaf : Context branch := { context with readView := context.readView, readable := context.readable }
  have writer := actualCall leaf value room (environment.reheap rfl rfl (by core_formed))
  core_writer_expr

/-- A writer call immediately hands the same built tree to the next consumer.
    No endpoint or event validation is repeated after printing. -/
theorem actualAtom_preservesIR (context : Context state) (value : Bool)
    (tree : Ready region reference)
    (separate : ReadOnlyMemory reference.heap state.heap context.address (context.words * 4))
    (representation : context.tree = tree.value) (inside : index < region.count)
    (event : region.events index = booleanEvent value)
    (room : context.position + (bytes value).length ≤ context.capacity)
    (environment : WriterEnvironment state) :
    ∃ after, ∃ retained : Ready region after,
      RunsExpr extractedProgram state (context.atomCall index)
        (.signed .i32 (context.position + (bytes value).length : Nat)) after ∧
      WriterFrame state after (context.address + context.position) (bytes value) ∧
      retained.value = tree.value := by
  obtain ⟨after, run, frame⟩ := actualAtom context (tree.ofReads separate.reads) value
    representation inside event room environment
  exact ⟨after, tree.afterOutput separate frame.output (by omega)
    (by have storage := context.storage; omega), run, frame, rfl⟩

#print axioms actualAtom_preservesIR
#print axioms actualAtom
#print axioms actualSelectedAtom

end SurfaceBooleanProof
