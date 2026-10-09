import verified_compiler.tests.direct_ir_body_production_scalar_memory
import verified_compiler.tests.direct_ir_body_production_inputs_storage
import verified_compiler.tests.direct_ir_unary_inference

namespace IRBodyProductionScalar

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyProductionInputs
open IRTypeCacheProof IRTypeCacheFillProof

/-- Reuse inference's existing environment for the one actual BodyContext. -/
def ScalarStorage.cacheEnvironment (storage : ScalarStorage workspace state slots)
    (input : Inputs) (locals : Value) : Environment := {
  header := fun
    | 0 => input.source | 1 => .signed .i32 input.sourceLength
    | 2 => input.tokensValue | 3 => .signed .i32 input.tokenCount | _ => input.tree.value
  countCell := .rawSlice (.structure expressionCountId) storage.arena.count storage.arena.countLength
  middle := fun
    | 0 => workspace.types | 1 => input.resolutions | 2 => input.aliases
    | 3 => workspace.aliasScratch | 4 => .signed .i32 workspace.aliasCapacity | _ => workspace.typeOutput
  table := input.allocationTable
  allocationTail := [input.allocationTail 0, input.allocationTail 1, input.allocationTail 2,
    input.allocationTail 3, input.allocationTail 4]
  tail := [input.signature.value, input.values, input.valueNames, locals,
    IRTypeRefProof.referenceValue input.signature.result, .signed .i32 input.owner.toInt, input.contexts,
    input.sourceCatalog, input.tokenCatalog, input.globalDeclarations, input.trees] }

theorem ScalarStorage.cacheContext (storage : ScalarStorage workspace state slots)
    (input : Inputs) (locals : Value) (query : Query)
    (capacity : query.capacity = storage.arena.capacity)
    (codes : query.codes = storage.codes) (depths : query.depths = storage.depths) :
    query.context (storage.cacheEnvironment input locals).header
      (.rawSlice expressionNodeType storage.arena.nodes storage.arena.capacity)
      (storage.cacheEnvironment input locals).countCell (storage.cacheEnvironment input locals).suffix =
      bodyContext input workspace locals := by
  dsimp only [Query.context, IRExpressionValidationProof.context, ScalarStorage.cacheEnvironment,
    Environment.suffix, bodyContext]
  rw [capacity, codes, depths, ← storage.codesValue, ← storage.depthsValue, storage.arenaValue]
  rfl

/-- A reached produced node uses the live count, not arena capacity, as its
    inference bound. The caller derives this count from the actual extractor. -/
def ScalarStorage.cacheQuery (storage : ScalarStorage workspace state slots)
    (count : Nat) (stored : count ≤ slots) (node : Nat) (inside : node < count)
    (depth : Int32) (positive : 0 < depth.toInt) : Query := {
  node, count, capacity := storage.arena.capacity, codes := storage.codes, depths := storage.depths,
  depth, inside, storage := Nat.le_trans stored storage.bound, fits := storage.arena.fits, positive }

/-- Readable selected depths and the actual reset supply a cache-miss slot,
    without prescribing any stale value in the original-input domain. -/
noncomputable def ScalarStorage.cacheSlot (storage : ScalarStorage workspace state slots)
    (count : Nat) (stored : count ≤ slots)
    (node : Nat) (inside : node < count) (depth : Int32) (positive : 0 < depth.toInt)
    (cleared : readRawSliceIndex extractedProgram state (.scalar (.signed .i32)) storage.codes storage.arena.capacity node =
      .ok (.signed .i32 (-1))) : IRTypeCacheStoreProof.Slot state := by
  let values := originalReadableDepths storage.depthsRoom storage.bound
  let oldDepths := values.choose
  have depthRead := values.choose_spec
  exact {
    toQuery := storage.cacheQuery count stored node inside depth positive
    oldCode := -1, oldDepth := (oldDepths node).toInt,
    codeRead := cleared, depthRead := depthRead node (Nat.lt_of_lt_of_le inside stored)
    missed := Or.inl (by decide)
    codeRoom := storage.codesRoom.subrange (start := node * 4) (length := 4) (by omega)
    depthRoom := storage.depthsRoom.subrange (start := node * 4) (length := 4) (by omega)
    separate := by
      dsimp only [ScalarStorage.cacheQuery]
      have := storage.codeDepths
      omega }

/-- The genuinely produced native literal closes the existing inference input. -/
noncomputable def ScalarStorage.literalMiss (storage : ScalarStorage workspace state slots)
    (input : Inputs) (locals : Value) (count : Nat) (stored : count ≤ slots)
    (node : Nat) (inside : node < count) (depth : Int32) (positive : 0 < depth.toInt)
    (literal : Literal) (fields : Fin 4 → Value)
    (native : readRawSliceIndex extractedProgram state IRTypeCacheFillProof.nodeType storage.arena.nodes storage.arena.capacity node =
      .ok (literal.value fields))
    (cleared : readRawSliceIndex extractedProgram state (.scalar (.signed .i32)) storage.codes storage.arena.capacity node =
      .ok (.signed .i32 (-1))) : Miss state := by
  let slot := storage.cacheSlot count stored node inside depth positive cleared
  exact {
    toQuery := slot.toQuery
    literal, nodes := storage.arena.nodes, fields, env := storage.cacheEnvironment input locals
    nodeRead := native
    oldCode := slot.oldCode, oldDepth := slot.oldDepth
    codeRead := slot.codeRead, depthRead := slot.depthRead, missed := slot.missed
    codeRoom := slot.codeRoom, depthRoom := slot.depthRoom, separate := slot.separate }

#print axioms ScalarStorage.cacheContext
#print axioms ScalarStorage.literalMiss
#print axioms ScalarStorage.cacheSlot

end IRBodyProductionScalar
