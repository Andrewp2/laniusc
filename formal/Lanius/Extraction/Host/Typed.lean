import Lanius.Extraction.Host.MemoryPath
import Lanius.Extraction.ExtractorContract
import Lanius.Semantics.Prefix

namespace Lanius.Extraction.Host

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.Typing

/-- Runtime typing supplies both the exact backing-array length and the
signed range of every element. Root-only views need no projection traversal. -/
private theorem typed_root_array (typed : RuntimeStateHasType program context state store)
    (member : view ∈ state.i32ArrayViews) (rooted : view.projections = []) :
    ∃ elements,
      readCellProjection state view.root view.projections = .ok (.array elements) ∧
      elements.length = view.length ∧ ∀ element ∈ elements, ∃ word : Int,
        element = .signed .i32 word ∧ -2147483648 ≤ word ∧ word ≤ 2147483647 := by
  obtain ⟨rootType, entry, rootValue, _, found, initialized, valueTyped, projected⟩ :=
    (typed.views view member).1
  rw [rooted] at projected
  cases projected
  cases valueTyped with
  | array elements elementType length elementsTyped =>
      refine ⟨elements, ?_, length, ?_⟩
      · cases entry with
        | mk id value =>
            change value = some (.array elements) at initialized
            subst value
            simp [readCellProjection, found, rooted, projectedValue]
      · intro element present
        obtain ⟨index, bound, equal⟩ := List.mem_iff_getElem.mp present
        have selected : elements[index]? = some element := by simp [List.getElem?_eq_getElem bound, equal]
        obtain ⟨type, typeFound, elementTyped⟩ := ValuesHaveTypes.getElem?_aligned index elementsTyped selected
        have typeEq := replicate_getElem?_some _ _ _ _ typeFound
        subst type
        cases elementTyped with
        | signed type word lower upper => exact ⟨word, rfl, lower, upper⟩

private theorem runtime_registry (typed : RuntimeStateHasType program context after store)
    (roots : ∀ view ∈ after.i32ArrayViews, view.projections = [])
    (distinct : after.i32ArrayViews.Pairwise fun left right => left.root ≠ right.root)
    (addresses : after.i32ArrayViews.Pairwise fun left right => left.address ≠ right.address) :
    Allocation.Registry after := by
  refine ⟨typed.typed.wellFormed, fun view member => (typed.views view member).2, roots, distinct, ?_, addresses⟩
  intro view member
  obtain ⟨elements, read, length, values⟩ := typed_root_array typed member (roots view member)
  exact ⟨elements, read, length, fun element present =>
    let ⟨word, equal, _⟩ := values element present
    ⟨word, equal⟩⟩

theorem RepresentableViews.ofRuntime (typed : RuntimeStateHasType program context after store)
    (roots : ∀ view ∈ after.i32ArrayViews, view.projections = []) : RepresentableViews after := by
  intro view member words contents word present
  obtain ⟨elements, read, _, values⟩ := typed_root_array typed member (roots view member)
  have expected : readCellProjection after view.root view.projections = .ok (.array (signedI32Values words)) := by
    simp [readCellProjection, contents, roots view member, projectedValue]
  have equal : elements = signedI32Values words := Value.array.inj (Except.ok.inj (read.symm.trans expected))
  obtain ⟨actual, actualEq, lower, upper⟩ := values (.signed .i32 word)
    (equal.symm ▸ List.mem_map.mpr ⟨word, present, rfl⟩)
  have same : word = actual := by simpa only [Value.signed.injEq, true_and] using actualEq
  exact same.symm ▸ And.intro lower upper

/-- Reuse the language's runtime invariant at a pure heap/view boundary.
No parser-specific workspace arithmetic or per-write range proof is needed. -/
theorem MemoryFrame.ofRuntime (frame : HeapFrame before after)
    (typed : RuntimeStateHasType program context after store) : MemoryFrame before after := by
  have finish (initial : ViewLayout before) : Allocation.Registry after := runtime_registry typed
    (by simpa only [frame.views] using initial.roots)
    (by simpa only [frame.views] using initial.distinct)
    (by simpa only [frame.views] using initial.addresses)
  exact ⟨fun initial => finish (.ofRegistry initial),
    fun initial _ => RepresentableViews.ofRuntime typed (finish (.ofRegistry initial)).roots,
    ⟨[], by simpa using frame.views⟩, congrArg (fun heap => heap.remaining) frame.heap,
    fun initial => .ofRegistry (finish initial)⟩

/-- Finish a borrowed-allocation prefix and cell-only suffix at the runtime
typing boundary. The middle state is evidence, not an additional execution. -/
theorem MemoryPath.ofRuntime (path : MemoryPath before after)
    (typed : RuntimeStateHasType program context after store) : MemoryFrame before after := by
  obtain ⟨boundary, prefixFrame, suffixFrame⟩ := path
  exact prefixFrame.trans (MemoryFrame.ofRuntime suffixFrame typed)

/-- Cell-content transformations such as capacity extension leave native
metadata unchanged. Transfer the layout path, then use typing of the actual
final state to recover its complete native registry and word ranges. -/
theorem MemoryPath.ofMetadata (path : MemoryPath logicalBefore logicalAfter)
    (startHeap : before.heap = logicalBefore.heap)
    (startViews : before.i32ArrayViews = logicalBefore.i32ArrayViews)
    (startNext : before.nextCell = logicalBefore.nextCell)
    (finishHeap : after.heap = logicalAfter.heap)
    (finishViews : after.i32ArrayViews = logicalAfter.i32ArrayViews)
    (typed : RuntimeStateHasType program context after store) : MemoryFrame before after := by
  obtain ⟨boundary, prefixFrame, suffixFrame⟩ := path
  have viewsEq : after.i32ArrayViews = boundary.i32ArrayViews := finishViews.trans suffixFrame.views
  have finish (initial : ViewLayout before) : Allocation.Registry after := by
    have logicalLayout : ViewLayout logicalBefore := initial.frame
      ⟨startHeap.symm, startViews.symm⟩ (Nat.le_of_eq startNext)
    have boundaryLayout := prefixFrame.layout logicalLayout
    exact runtime_registry typed (by simpa only [viewsEq] using boundaryLayout.roots)
      (by simpa only [viewsEq] using boundaryLayout.distinct)
      (by simpa only [viewsEq] using boundaryLayout.addresses)
  obtain ⟨fresh, freshEq⟩ := prefixFrame.views
  exact ⟨fun initial => finish (.ofRegistry initial),
    fun initial _ => RepresentableViews.ofRuntime typed (finish (.ofRegistry initial)).roots,
    ⟨fresh, by rw [viewsEq, freshEq, startViews]⟩,
    (congrArg (fun heap => heap.remaining) (finishHeap.trans suffixFrame.heap)).trans
      (prefixFrame.remaining.trans (congrArg (fun heap => heap.remaining) startHeap.symm)),
    fun initial => .ofRegistry (finish initial)⟩

/-- Native layout evidence may cross an arbitrary cell-only suffix before
runtime typing closes the complete memory invariant. In particular, a padded
frontend need not assume typing of its shortened logical source array, or
force every later collector/emitter write to repeat a signed-range proof. -/
structure MemoryTail (program : Program) (before after : State) : Prop where
  frame : ∀ {final context store}, HeapFrame after final →
    RuntimeStateHasType program context final store → MemoryFrame before final

theorem MemoryTail.finish (memory : MemoryTail program before after)
    (typed : RuntimeStateHasType program context after store) : MemoryFrame before after :=
  memory.frame (.refl after) typed

theorem MemoryTail.thenHeap (memory : MemoryTail program before middle)
    (frame : HeapFrame middle after) : MemoryTail program before after :=
  ⟨fun following typed => memory.frame (frame.trans following) typed⟩

theorem MemoryTail.prepend (memory : MemoryTail program middle after)
    (frame : MemoryFrame before middle) : MemoryTail program before after :=
  ⟨fun following typed => frame.trans (memory.frame following typed)⟩

/-- A file boundary retains enough native evidence to recover the complete
registry from runtime typing, even after its temporary scopes are closed. -/
structure NativeReady (program : Program) (views : List I32ArrayView) (after : State) : Prop where
  frame : ∀ {final context store}, HeapFrame after final → RuntimeStateHasType program context final store →
    Allocation.Registry final ∧ RepresentableViews final ∧ ∃ fresh, final.i32ArrayViews = views ++ fresh

theorem MemoryTail.ready (memory : MemoryTail program before after)
    (registry : Allocation.Registry before) (representable : RepresentableViews before) :
    NativeReady program before.i32ArrayViews after := by
  refine ⟨?_⟩
  intro final context store frame typed
  have complete := memory.frame frame typed
  exact ⟨complete.registry registry, complete.representable registry representable, complete.views⟩

theorem NativeReady.thenHeap (ready : NativeReady program views middle) (frame : HeapFrame middle after) :
    NativeReady program views after :=
  ⟨fun following typed => ready.frame (frame.trans following) typed⟩

theorem NativeReady.finish (ready : NativeReady program views after)
    (typed : RuntimeStateHasType program context after store) :
    Allocation.Registry after ∧ RepresentableViews after ∧ ∃ fresh, after.i32ArrayViews = views ++ fresh :=
  ready.frame (.refl after) typed

/-- Recover typing inside the actual source scopes from an executed prefix,
without assuming or first running the continuation. -/
theorem checked_prefix_type (checked : CoreSynthesis.Program.CheckedProgram artifacts)
    (statementTyped : StmtHasType checked.core returnType context inLoop statement)
    (beforeTyped : RuntimeStateHasType checked.core context before beforeStore)
    (reached : Prefix.Reaches checked.core before statement ready continuation) :
    ∃ nextContext nextStore, StmtHasType checked.core returnType nextContext inLoop continuation ∧
      RuntimeStateHasType checked.core nextContext ready nextStore :=
  reached.typed checked.typed (ExtractorContract.checkedProgram_constantsClosed checked)
    (ExtractorContract.checkedProgram_opaqueResponsesWellTyped checked) statementTyped beforeTyped

/-- Typing of an already-established evaluation; this does not run it again. -/
theorem checked_evaluation_type (checked : CoreSynthesis.Program.CheckedProgram artifacts)
    (expressionTyped : ExprHasType checked.core context expression type)
    (beforeTyped : RuntimeStateHasType checked.core context before beforeStore)
    (evaluated : Evaluates checked.core before expression value after) :
    ∃ afterStore, RuntimeStateHasType checked.core context after afterStore := by
  obtain ⟨fuel, evaluated⟩ := evaluated
  have preserved := evalExpr_has_runtime_type checked.typed
    (ExtractorContract.checkedProgram_constantsClosed checked)
    (ExtractorContract.checkedProgram_opaqueResponsesWellTyped checked) fuel beforeTyped expressionTyped
  rw [evaluated] at preserved
  obtain ⟨afterStore, _, _, typed, _, _⟩ := preserved
  exact ⟨afterStore, typed⟩

/-- Whole-statement typing closes intermediate memory obligations from the
actual entry state; no internal state or terminal typing is assumed. -/
theorem checked_statement_type (checked : CoreSynthesis.Program.CheckedProgram artifacts)
    (statementTyped : StmtHasType checked.core returnType context inLoop statement)
    (beforeTyped : RuntimeStateHasType checked.core context before beforeStore)
    (executed : Executes checked.core before statement completion after) :
    ∃ afterStore, RuntimeStateHasType checked.core context after afterStore := by
  obtain ⟨fuel, executed⟩ := executed
  have preserved := execStmt_has_runtime_type checked.typed
    (ExtractorContract.checkedProgram_constantsClosed checked)
    (ExtractorContract.checkedProgram_opaqueResponsesWellTyped checked) statementTyped fuel beforeTyped
  rw [executed] at preserved
  obtain ⟨afterStore, _, _, typed, _⟩ := preserved
  exact ⟨afterStore, typed⟩

/-- Connect an already-proved evaluation to native-memory preservation using
the accepted program's type proof. The input runtime invariant is ordinary
state typing; no second execution, axiom, or source-specific range proof is
introduced. Heap/view preservation remains explicit because raw views can
alias even in a well-typed program. -/
theorem checked_evaluation (checked : CoreSynthesis.Program.CheckedProgram artifacts)
    (expressionTyped : ExprHasType checked.core context expression type)
    (beforeTyped : RuntimeStateHasType checked.core context before beforeStore)
    (evaluated : Evaluates checked.core before expression value after)
    (path : MemoryPath before after) :
    ∃ afterStore, RuntimeStateHasType checked.core context after afterStore ∧ MemoryFrame before after := by
  obtain ⟨afterStore, typed⟩ := checked_evaluation_type checked expressionTyped beforeTyped evaluated
  exact ⟨afterStore, typed, path.ofRuntime typed⟩

end Lanius.Extraction.Host
