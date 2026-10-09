import verified_compiler.tests.direct_ir_body_production_scalar_extract
import verified_compiler.tests.direct_ir_body_production_scalar_reset
import verified_compiler.tests.direct_ir_body_production_scalar_memory

namespace IRBodyProductionScalar

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyProductionInputs

variable {before after : State}

private def source := Extracted.«verified::surface_expr».Functions.«extract».core
def extractCall (tree : Tree) (arena : Arena) (root depth : Nat) : Expr :=
  .call source.id [.value (expressionInput tree root depth), .value arena.value]

def ProducedNodes (storage : ScalarStorage workspace initial slots) (count : Nat) (nodes : Nat → Value)
    (before after : Heap) : Prop :=
  (∀ index, index < count → NativeSnapshot 64 extractedProgram after expressionNodeType
    (storage.bases index) (nodes index) 48) ∧
  NativeSnapshot 64 extractedProgram after (.scalar (.signed .i32)) storage.arena.count (.signed .i32 count) 4 ∧
  HeapWritesOn before after storage.writes


private theorem actualExtractAppendWith (arena : Arena) (capacity : 0 < arena.capacity)
    (zero : readNativeValue 64 extractedProgram before.heap (.scalar (.signed .i32)) arena.count =
      .ok (.signed .i32 0))
    (builder : ∀ {state : State}, state.heap = before.heap → state.CellsWellFormed →
      state.i32ArrayViews = before.i32ArrayViews → ∃ after,
      RunsExpr extractedProgram state (buildCall tree arena index depth) (.signed .i32 root) after ∧
        MemoryEffect relation state after)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (extractAppendCall tree arena index depth)
      (.signed .i32 root) after ∧ MemoryEffect relation before after := by
  have countRead := countCellRead (state := before) (id := expressionCountId)
    (by decide +kernel) (by decide +kernel) (by decide +kernel) arena.countPositive zero
  core_facts [arena]
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _))
    Extracted.«verified::surface_expr».Functions.«extract_append».core as callee
  core_effect (by assumption)

/-- The one real1871 reset/scope wrapper. Its builder continuation is
    internal and is discharged by original native-syntax induction. -/
theorem actualExtractWith (tree : Tree) (storage : ScalarStorage workspace before slots)
    (index depth count root : Nat) (nodes : Nat → Value)
    (builder : ∀ {state : State}, HeapWritesOn before.heap state.heap storage.writes →
      readNativeValue 64 extractedProgram state.heap (.scalar (.signed .i32)) storage.arena.count =
        .ok (.signed .i32 0) → state.CellsWellFormed → state.i32ArrayViews = before.i32ArrayViews →
      ∃ after, RunsExpr extractedProgram state (buildCall tree storage.arena index depth)
        (.signed .i32 root) after ∧ MemoryEffect (ProducedNodes storage count nodes) state after)
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before (extractCall tree storage.arena index depth)
      (.signed .i32 root) after ∧ MemoryEffect (ProducedNodes storage count nodes) before after := by
  core_facts [storage, storage.arena]
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) source as callee
  apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _)
  · core_pure_guard
  · intro selected guardFrame
    apply RunsStmt.letEffect (MemoryEffect.scopeStable _)
    · core_run
    · core_formed
    · core_state ready
      have same : ready.heap = before.heap := guardFrame.heap
      have readyFormed : ready.CellsWellFormed := by core_formed
      have readyViews : ready.i32ArrayViews = [] := guardFrame.views.trans noViews
      obtain ⟨resetHeap, resetRun, zero, resetWrite⟩ := actualExtractResetCount (before := ready) storage.arena
        (by core_local) (by simpa only [same] using storage.countRoom)
        (by rw [same]; exact unique) readyViews
      let reset : State := { ready with heap := resetHeap }
      have resetFormed : reset.CellsWellFormed := readyFormed
      have resetFootprint : HeapWritesOn before.heap reset.heap storage.writes := by
        have narrow := resetWrite.footprint.weaken (larger := storage.writes) (fun address range => Or.inl range)
        simpa only [reset, same, ScalarStorage.writes] using narrow
      obtain ⟨completed, built, effect⟩ := actualExtractAppendWith (before := reset) storage.arena
        (Nat.lt_of_lt_of_le storage.positive storage.bound) zero.read (by
          intro state heap cells views
          exact builder (by simpa only [heap] using resetFootprint) (by simpa only [heap] using zero.read)
            cells (views.trans guardFrame.views)) resetFormed
      change RunsExpr extractedProgram reset
        (.call Extracted.«verified::surface_expr».Functions.«extract_append».core.id
          [.value (expressionInput tree index depth), .value storage.arena.value])
        (.signed .i32 root) completed at built
      have returnRun : RunsExpr extractedProgram reset
          (.call Extracted.«verified::surface_expr».Functions.«extract_append».core.id
          [.local (source.argumentId 0), .local (source.argumentId 1)]) (.signed .i32 root) completed :=
        RunsExpr.callArguments (by core_arguments) built
      have body : RunsStmt extractedProgram ready
          (match source.bindingStatement 0 with | .letLocal _ _ _ rest => rest | _ => .skip)
          (.returned (some (.signed .i32 root))) completed :=
        .sequenceNext (.expression resetRun) (.returnValue returnRun)
      have final : ProducedNodes storage count nodes ready.heap completed.heap := by
        rcases effect.2.2.2 with ⟨native, storedCount, builtWrites⟩
        refine ⟨native, storedCount, ?_⟩
        have finalWrite : HeapWritesOn before.heap completed.heap storage.writes := resetFootprint.trans builtWrites
        simpa only [same] using finalWrite
      exact ⟨completed, body, effect.1, effect.2.1, effect.2.2.1, final⟩

#print axioms actualExtractWith

end IRBodyProductionScalar
