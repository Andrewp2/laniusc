import verified_compiler.tests.direct_ir_body_production_scalar_cache

namespace IRBodyProductionScalar

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyProductionInputs IRTypeRefProof IRExpressionKindProof
open IRTypeCacheProof IRTypeCacheStoreProof
open IRTypeCacheFillProof (Literal)

variable {before after : State}

def inferenceCall (input : Inputs) (workspace : Workspace) (locals : Value)
    (count root : Nat) (depth : Int32) : Expr :=
  .call Extracted.«lowering::body_expression».Functions.«expression_kind».core.id
    ([bodyContext input workspace locals, .signed .i32 count, .signed .i32 root,
      .signed .i32 depth.toInt].map Expr.value)

/-- Only the selected cache planes are mutable during inference. Arena
    snapshots remain readable through this narrower actual footprint. -/
def ScalarStorage.cacheWrites (storage : ScalarStorage workspace state slots) (address : Nat) : Prop :=
  (storage.codes ≤ address ∧ address < storage.codes + slots * 4) ∨
  (storage.depths ≤ address ∧ address < storage.depths + slots * 4)

/-- The second real inference call reads the entry established by the first.
    Its BodyContext is the same actual context, not a test-only cache caller. -/
theorem actualReuse (storage : ScalarStorage workspace initial slots)
    (input : Inputs) (locals : Value) (entry : Entry before)
    (capacity : entry.capacity = storage.arena.capacity)
    (codes : entry.codes = storage.codes) (depths : entry.depths = storage.depths)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (inferenceCall input workspace locals entry.count entry.node entry.depth)
      (known entry.kind) after ∧ PureFrame before after := by
  let environment := storage.cacheEnvironment input locals
  obtain ⟨after, run, frame⟩ := IRTypeCacheProof.actualHit entry environment.header
    (.rawSlice expressionNodeType storage.arena.nodes storage.arena.capacity)
    environment.countCell environment.suffix formed
  have context := storage.cacheContext input locals entry.toQuery capacity codes depths
  change RunsExpr extractedProgram before
    (.call Extracted.«lowering::body_expression».Functions.«expression_kind».core.id
      ([entry.toQuery.context environment.header
          (.rawSlice expressionNodeType storage.arena.nodes storage.arena.capacity)
          environment.countCell environment.suffix,
        .signed .i32 entry.count, .signed .i32 entry.node, .signed .i32 entry.depth.toInt].map Expr.value))
    (known entry.kind) after at run
  rw [context] at run
  exact ⟨after, run, frame⟩

theorem ScalarStorage.storedFootprint (storage : ScalarStorage workspace state slots)
    (used : count ≤ slots) (inside : root < count) (depth : Int32) (positive : 0 < depth.toInt)
    (stored : Stored (storage.cacheQuery count used root inside depth positive) kind first last) :
    HeapWritesOn first last storage.cacheWrites := by
  obtain ⟨middle, code, budget⟩ := stored
  have codeWrite : HeapRegionWrite first middle (storage.codes + root * 4) 4 := by
    simpa only [ScalarStorage.cacheQuery, i32Bytes, List.length_map, List.length_range] using HeapRegionWrite.ofBytes code
  have depthWrite : HeapRegionWrite middle last (storage.depths + root * 4) 4 := by
    simpa only [ScalarStorage.cacheQuery, i32Bytes, List.length_map, List.length_range] using HeapRegionWrite.ofBytes budget
  have selected : root < slots := Nat.lt_of_lt_of_le inside used
  have contains (base address : Nat)
      (range : base + root * 4 ≤ address ∧ address < base + root * 4 + 4) :
      base ≤ address ∧ address < base + slots * 4 := by
    have endBound : base + root * 4 + 4 ≤ base + slots * 4 := by
      simpa only [Nat.succ_eq_add_one, Nat.add_mul, Nat.one_mul, Nat.add_assoc] using
        Nat.add_le_add_left (Nat.mul_le_mul_right 4 (Nat.succ_le_of_lt selected)) base
    exact ⟨Nat.le_trans (Nat.le_add_right _ _) range.1,
      Nat.lt_of_lt_of_le range.2 endBound⟩
  have codeFootprint := codeWrite.footprint.weaken (larger := storage.cacheWrites)
    (fun address range => Or.inl (contains storage.codes address range))
  have depthFootprint := depthWrite.footprint.weaken (larger := storage.cacheWrites)
    (fun address range => Or.inr (contains storage.depths address range))
  exact codeFootprint.trans depthFootprint

/-- At the reached cleared arena, literal inference derives the kind and
    its actual two cache writes. Neither is an original-input premise. -/
theorem actualInferLiteral (storage : ScalarStorage workspace before slots)
    (input : Inputs) (locals : Value) (count : Nat) (used : count ≤ slots)
    (root : Nat) (inside : root < count) (depth : Int32) (positive : 0 < depth.toInt)
    (literal : Literal) (fields : Fin 4 → Value)
    (native : readRawSliceIndex extractedProgram before IRTypeCacheFillProof.nodeType
      storage.arena.nodes storage.arena.capacity root = .ok (literal.value fields))
    (cleared : readRawSliceIndex extractedProgram before (.scalar (.signed .i32))
      storage.codes storage.arena.capacity root = .ok (.signed .i32 (-1)))
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap)
    (noViews : before.i32ArrayViews = []) :
    ∃ cached, RunsExpr extractedProgram before (inferenceCall input workspace locals count root depth)
      (known literal.kind) cached ∧
      MemoryEffect (Stored (storage.cacheQuery count used root inside depth positive) literal.kind) before cached := by
  let miss := storage.literalMiss input locals count used root inside depth positive literal fields native cleared
  obtain ⟨cached, run, effect⟩ := IRTypeCacheFillProof.actualMiss miss formed unique noViews
  have context := storage.cacheContext input locals miss.toQuery rfl rfl rfl
  change miss.toQuery.context (storage.cacheEnvironment input locals).header
    (.rawSlice IRTypeCacheFillProof.nodeType storage.arena.nodes storage.arena.capacity)
    (storage.cacheEnvironment input locals).countCell (storage.cacheEnvironment input locals).suffix =
    bodyContext input workspace locals at context
  change RunsExpr extractedProgram before
    (.call Extracted.«lowering::body_expression».Functions.«expression_kind».core.id
      ([miss.toQuery.context (storage.cacheEnvironment input locals).header
          (.rawSlice IRTypeCacheFillProof.nodeType storage.arena.nodes storage.arena.capacity)
          (storage.cacheEnvironment input locals).countCell (storage.cacheEnvironment input locals).suffix,
        .signed .i32 count, .signed .i32 root, .signed .i32 depth.toInt].map Expr.value))
    (known literal.kind) cached at run
  rw [context] at run
  exact ⟨cached, run, effect⟩

/-- The one real negation above a produced integer closes the existing cold
    child/parent inference rule, including all four actual cache writes. -/
theorem actualInferNegative (storage : ScalarStorage workspace before 2)
    (input : Inputs) (locals : Value) (depth childDepth : Int32)
    (positive : 0 < childDepth.toInt) (predecessor : depth.toInt - 1 = childDepth.toInt)
    (fields : Fin 4 → Value)
    (leafRead : readRawSliceIndex extractedProgram before IRTypeCacheFillProof.nodeType
      storage.arena.nodes storage.arena.capacity 0 = .ok (Literal.integer.value fields))
    (parentRead : readRawSliceIndex extractedProgram before IRTypeCacheFillProof.nodeType
      storage.arena.nodes storage.arena.capacity 1 =
        .ok (IRUnaryInferenceProof.nodeValue .negate 0 (fun _ => .signed .i32 (-1))))
    (cleared : ∀ index, index < 2 → readRawSliceIndex extractedProgram before (.scalar (.signed .i32))
      storage.codes storage.arena.capacity index = .ok (.signed .i32 (-1)))
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap)
    (noViews : before.i32ArrayViews = []) :
    ∃ cached, RunsExpr extractedProgram before (inferenceCall input workspace locals 2 1 depth)
      (known .I32) cached ∧
      MemoryEffect (InferredAndStored (storage.cacheQuery 2 (Nat.le_refl _) 1 (by decide) depth (by omega)) .I32
        (Stored (storage.cacheQuery 2 (Nat.le_refl _) 0 (by decide) childDepth positive) .I32)) before cached := by
  let leaf := storage.literalMiss input locals 2 (Nat.le_refl _) 0 (by decide) childDepth positive
    .integer fields leafRead (cleared 0 (by decide))
  let slot := storage.cacheSlot 2 (Nat.le_refl _) 1 (by decide) depth (by omega) (cleared 1 (by decide))
  let cold : IRUnaryInferenceProof.Cold before := {
    child := leaf.toQuery, root := 1, inside := by change 1 < 2; decide
    depth, predecessor
    nodes := storage.arena.nodes, env := storage.cacheEnvironment input locals
    op := .negate, unused := fun _ => .signed .i32 (-1), nodeRead := parentRead
    leaf, atChild := rfl, sameNodes := rfl, sameEnv := rfl, slot, atRoot := rfl }
  obtain ⟨cached, _, run, effect, _, _⟩ := IRUnaryInferenceProof.actualColdAndReuse cold
    (by change IRUnaryInferenceProof.accepts .negate .I32 = true; decide)
    formed unique noViews
  have context := storage.cacheContext input locals cold.toInput.query rfl rfl rfl
  change cold.toInput.query.context (storage.cacheEnvironment input locals).header
    (.rawSlice IRTypeCacheFillProof.nodeType storage.arena.nodes storage.arena.capacity)
    (storage.cacheEnvironment input locals).countCell (storage.cacheEnvironment input locals).suffix =
    bodyContext input workspace locals at context
  change RunsExpr extractedProgram before
    (.call Extracted.«lowering::body_expression».Functions.«expression_kind».core.id
      ([cold.toInput.query.context (storage.cacheEnvironment input locals).header
          (.rawSlice IRTypeCacheFillProof.nodeType storage.arena.nodes storage.arena.capacity)
          (storage.cacheEnvironment input locals).countCell (storage.cacheEnvironment input locals).suffix,
        .signed .i32 2, .signed .i32 1, .signed .i32 depth.toInt].map Expr.value))
    (known .I32) cached at run
  rw [context] at run
  exact ⟨cached, run, effect⟩

#print axioms actualInferLiteral
#print axioms actualInferNegative
#print axioms ScalarStorage.storedFootprint
#print axioms actualReuse

end IRBodyProductionScalar
