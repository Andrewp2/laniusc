import verified_compiler.tests.direct_ir_type_cache_fill
import Lanius.Semantics.EffectProof

namespace IRUnaryInferenceProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRTypeRefProof IRExpressionKindProof IRTypeCacheProof
open IRTypeCacheStoreProof
open IRTypeCacheFillProof (Environment nodeType)

private def source := Extracted.«lowering::body_expression».Functions.«expression_kind_uncached».core
def operationSource := Extracted.«lowering::body_expression».Functions.«unary_operation».core
private def kindSource := Extracted.«lowering::body_expression».Functions.«unary_kind».core
private def hasKind := Extracted.«verified::surface_expr».Functions.«has_kind».core

inductive Operation where
  | positive | negate | not

def Operation.sourceValue : Operation → Value
  | .positive => source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«UnaryPositive» []
  | .negate => source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«UnaryNegate» []
  | .not => source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«UnaryNot» []
def Operation.targetValue : Operation → Value
  | .positive => source_value Extracted.«backend::syntax».Types.«UnaryOperation».«UnaryPositive» []
  | .negate => source_value Extracted.«backend::syntax».Types.«UnaryOperation».«UnaryNegate» []
  | .not => source_value Extracted.«backend::syntax».Types.«UnaryOperation».«UnaryNot» []
private def unaryTag := source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Unary» []
private def literalTag := source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Literal» []

@[core_pure_rule] theorem actualOperation (op : Operation) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call operationSource.id [.value op.sourceValue])
      op.targetValue after ∧ PureFrame before after := by
  cases op <;> (core_call_pure operationSource as callee; core_pure)

@[core_pure_rule] private theorem unaryIsLiteral (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call hasKind.id [.value unaryTag, .value literalTag])
      (.boolean false) after ∧ PureFrame before after := by
  core_call_pure hasKind as callee
  core_pure

@[core_pure_rule] private theorem unaryIsUnary (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call hasKind.id [.value unaryTag, .value unaryTag])
      (.boolean true) after ∧ PureFrame before after := by
  core_call_pure hasKind as callee
  core_pure

/-- Source-language unary typing, independent of the numeric type encoding. -/
def Operation.kind : Operation → Reference
  | .not => .Bool | .positive | .negate => .I32
def accepts : Operation → Reference → Bool
  | .not, .Bool => true
  | .positive, .I32 | .negate, .I32 => true
  | _, _ => false
def outcome (op : Operation) (status : Status) (kind : Reference) : Value :=
  match status with
  | .KnownExpression => if accepts op kind then known op.kind else unsupported
  | _ => result status kind

private theorem sameBoolean (kind : Reference) : sameType kind .Bool = accepts .not kind := by
  cases kind <;> simp [sameType, isInvalid, typeCode, nominalCode, accepts]
  all_goals split <;> simp_all <;> omega

private theorem sameInteger (kind : Reference) : sameType kind .I32 = accepts .positive kind := by
  cases kind <;> simp [sameType, isInvalid, typeCode, nominalCode, accepts]
  all_goals split <;> simp_all <;> omega

private theorem acceptsNegate (kind : Reference) : accepts .negate kind = accepts .positive kind := by
  cases kind <;> rfl

/-- The real typing decision accepts exactly the language's scalar operand
    types and leaves existing failures untouched, for every represented type. -/
@[core_pure_rule] theorem actualDecision (op : Operation) (status : Status) (kind : Reference)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call kindSource.id [.value op.targetValue, .value (result status kind)])
      (outcome op status kind) after ∧ PureFrame before after := by
  have boolean := fun {state : State} (h : state.CellsWellFormed) => actualSame kind .Bool h
  have integer := fun {state : State} (h : state.CellsWellFormed) => actualSame kind .I32 h
  simp only [sameBoolean] at boolean
  simp only [sameInteger] at integer
  have knownBoolean := fun {state : State} (h : state.CellsWellFormed) => actualKnown .Bool (by decide) h
  have knownInteger := fun {state : State} (h : state.CellsWellFormed) => actualKnown .I32 (by decide) h
  cases status
  · cases op <;> simp only [outcome, Operation.kind, acceptsNegate]
    all_goals split <;> (core_call_pure kindSource as callee; core_pure)
  all_goals (core_call_pure kindSource as callee; core_pure)

def nodeValue (op : Operation) (child : Nat) (unused : Fin 3 → Value) : Value :=
  source_value Extracted.«verified::surface_expr».Types.«ExpressionNode».mk
    [unaryTag, op.sourceValue, .signed .i32 child, unused 0, unused 1, unused 2]

/-- Readable unary syntax. The child query is independent of whether its
    cache is warm, empty or checked with an insufficient depth budget. -/
structure Input (before : State) where
  child : Query
  root : Nat
  inside : root < child.count
  depth : Int32
  predecessor : depth.toInt - 1 = child.depth.toInt
  nodes : Nat
  env : Environment
  op : Operation
  unused : Fin 3 → Value
  nodeRead : readRawSliceIndex extractedProgram before nodeType nodes child.capacity root =
    .ok (nodeValue op child.node unused)

def Input.context (input : Input before) : Value :=
  input.child.context input.env.header (.rawSlice nodeType input.nodes input.child.capacity)
    input.env.countCell input.env.suffix
def Input.call (input : Input before) : Expr :=
  .call source.id ([input.context, .signed .i32 input.child.count, .signed .i32 input.root,
    .signed .i32 input.depth.toInt].map Expr.value)

def Input.query (input : Input before) : Query :=
  { input.child with
    node := input.root
    depth := input.depth
    inside := input.inside
    positive := by
      have := input.predecessor
      have := input.child.positive
      omega }
def Input.cachedCall (input : Input before) : Expr :=
  input.query.call input.env.header (.rawSlice nodeType input.nodes input.child.capacity)
    input.env.countCell input.env.suffix
def Input.reheap (input : Input before) (same : after.heap = before.heap) : Input after :=
  { input with
    nodeRead := by simpa only [readRawSliceIndex, same] using input.nodeRead }

/-- Recursive traversal retains a child's proved writes. The closed cold-child
    theorem below supplies the callback from the real literal inference code. -/
theorem actualWith (input : Input before) (kind : Reference)
    (child : ∀ {state : State}, state.heap = before.heap → state.CellsWellFormed →
      state.i32ArrayViews = before.i32ArrayViews →
      ∃ after, RunsExpr extractedProgram state
        (input.child.call input.env.header (.rawSlice nodeType input.nodes input.child.capacity)
          input.env.countCell input.env.suffix) (known kind) after ∧ MemoryEffect relation state after)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before input.call (outcome input.op .KnownExpression kind) after ∧
      MemoryEffect relation before after := by
  core_facts 4 [input]
  have depthBound := input.depth.toInt_lt
  have subtract := eval_i32_subNonneg extractedProgram.target input.depth.toInt 1 (by omega) (by omega)
  rw [input.predecessor] at subtract
  have decision := fun {state : State} (h : state.CellsWellFormed) => actualDecision input.op .KnownExpression kind h
  have operation := fun {state : State} (h : state.CellsWellFormed) => actualOperation input.op h
  have notInvalid : evalBinaryValue extractedProgram.target .equal input.op.targetValue
      (source_value Extracted.«backend::syntax».Types.«UnaryOperation».«InvalidUnaryOperation» []) =
      .ok (.boolean false) := by cases input.op <;> rfl
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) source as callee
  core_effect (by assumption)

/-- A warm child is the read-only specialization of the same traversal.
    Both acceptance and rejection follow the source's scalar typing rule. -/
theorem actual (input : Input before) (entry : Entry before) (atChild : entry.toQuery = input.child)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before input.call
      (outcome input.op .KnownExpression entry.kind) after ∧ PureFrame before after := by
  have child {state : State} (same : state.heap = before.heap) (h : state.CellsWellFormed)
      (_views : state.i32ArrayViews = before.i32ArrayViews) :=
    actualHit ({ entry with
      codeRead := by simpa only [readRawSliceIndex, same] using entry.codeRead
      depthRead := by simpa only [readRawSliceIndex, same] using entry.depthRead } : Entry state)
      input.env.header (.rawSlice nodeType input.nodes input.child.capacity) input.env.countCell input.env.suffix h
  obtain ⟨after, run, cells, world, views, heap⟩ := actualWith (relation := fun first last => last = first)
    input entry.kind (fun same h views => by
      obtain ⟨after, run, frame⟩ := child same h views
      exact ⟨after, by simpa only [atChild] using run, frame.cells, frame.world, frame.views, frame.heap⟩) formed
  exact ⟨after, run, formed, cells, run.choose_spec.2, heap, world, views⟩

/-- Storage for the parent miss is the slot selected by the real root query. -/
structure Miss (before : State) extends Input before where
  entry : Entry before
  atChild : entry.toQuery = child
  slot : Slot before
  atRoot : slot.toQuery = toInput.query

theorem Miss.inference (input : Miss before) (accepted : accepts input.op input.entry.kind = true) :
    Inference input.toInput.query input.env.header (.rawSlice nodeType input.nodes input.child.capacity)
      input.env.countCell input.env.suffix input.op.kind before.heap := by
  intro state same formed
  let entry : Entry state := { input.entry with
    codeRead := by simpa only [readRawSliceIndex, same] using input.entry.codeRead
    depthRead := by simpa only [readRawSliceIndex, same] using input.entry.depthRead }
  have run := actual (input.toInput.reheap same) entry input.atChild formed
  simp only [entry, Input.reheap, outcome, accepted, ↓reduceIte] at run
  exact run

/-- The public query computes a unary result, stores exactly its two cache
    words and reuses it on the next call. All intermediate executions follow
    from the native AST/cache input and the source typing rule. -/
theorem actualFillAndReuse (input : Miss before) (accepted : accepts input.op input.entry.kind = true)
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap)
    (noViews : before.i32ArrayViews = []) :
    ∃ cached after,
      RunsExpr extractedProgram before input.toInput.cachedCall (known input.op.kind) cached ∧
      MemoryEffect (Stored input.toInput.query input.op.kind) before cached ∧
      RunsExpr extractedProgram cached input.toInput.cachedCall (known input.op.kind) after ∧
      PureFrame cached after := by
  have inference : Inference input.slot.toQuery input.env.header (.rawSlice nodeType input.nodes input.child.capacity)
      input.env.countCell input.env.suffix input.op.kind before.heap := by
    rw [input.atRoot]
    exact input.inference accepted
  have run := actualStoreAndReuse input.slot input.env.header (.rawSlice nodeType input.nodes input.child.capacity)
    input.env.countCell input.env.suffix input.op.kind (by cases input.op <;> rfl) inference formed unique noViews
  simpa only [input.atRoot, Input.cachedCall] using run

/-- A real unary node above a literal, with misses at both cache entries.
    The two views share one native arena, context and query storage. -/
structure Cold (before : State) extends Input before where
  leaf : IRTypeCacheFillProof.Miss before
  atChild : leaf.toQuery = child
  sameNodes : leaf.nodes = nodes
  sameEnv : leaf.env = env
  slot : Slot before
  atRoot : slot.toQuery = toInput.query

/-- Both recursive inference and its four writes are derived from native
    syntax/cache storage. The second parent query is an actual cache hit. -/
theorem actualColdAndReuse (input : Cold before) (accepted : accepts input.op input.leaf.literal.kind = true)
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap)
    (noViews : before.i32ArrayViews = []) :
    ∃ cached after, RunsExpr extractedProgram before input.toInput.cachedCall (known input.op.kind) cached ∧
      MemoryEffect (InferredAndStored input.toInput.query input.op.kind
        (Stored input.leaf.toQuery input.leaf.literal.kind)) before cached ∧
      RunsExpr extractedProgram cached input.toInput.cachedCall (known input.op.kind) after ∧ PureFrame cached after := by
  have infer : EffectfulInference input.slot.toQuery input.env.header (.rawSlice nodeType input.nodes input.child.capacity)
      input.env.countCell input.env.suffix input.op.kind before.heap (Stored input.leaf.toQuery input.leaf.literal.kind) := by
    rw [input.atRoot]
    intro state same h views
    obtain ⟨after, run, effect⟩ := actualWith (input.toInput.reheap same) input.leaf.literal.kind
      (relation := Stored input.leaf.toQuery input.leaf.literal.kind) (fun currentHeap currentFormed currentViews => by
        have leaf := IRTypeCacheFillProof.actualMiss (input.leaf.reheap (currentHeap.trans same)) currentFormed
          (by rw [currentHeap, same]; exact unique) (currentViews.trans views)
        simpa only [IRTypeCacheFillProof.Miss.reheap, IRTypeCacheFillProof.Input.call,
          input.atChild, input.sameNodes, input.sameEnv, Input.reheap] using leaf) h
    simp only [Input.reheap, outcome, accepted, ↓reduceIte] at run
    refine ⟨after, run, effect, effect.2.2.2.writable ?_⟩
    rw [same, ← input.atRoot]
    exact ⟨input.slot.codeRoom, input.slot.depthRoom, unique⟩
  obtain ⟨cached, run, effect⟩ := actualStoreWith input.slot input.env.header
    (.rawSlice nodeType input.nodes input.child.capacity) input.env.countCell input.env.suffix input.op.kind
    (by cases input.op <;> rfl) infer formed noViews
  obtain ⟨middle, _, stored⟩ := effect.2.2.2
  obtain ⟨after, reuse, pure⟩ := actualHit (input.slot.entry input.op.kind (by cases input.op <;> rfl) stored)
    input.env.header (.rawSlice nodeType input.nodes input.child.capacity) input.env.countCell input.env.suffix
    (by core_formed)
  change RunsExpr extractedProgram cached (input.slot.toQuery.call input.env.header
    (.rawSlice nodeType input.nodes input.child.capacity) input.env.countCell input.env.suffix) (known input.op.kind) after at reuse
  exact ⟨cached, after, by simpa only [input.atRoot, Input.cachedCall] using run,
    by simpa only [input.atRoot] using effect,
    by simpa only [input.atRoot, Input.cachedCall] using reuse, pure⟩

#print axioms actualOperation
#print axioms actualDecision
#print axioms actual
#print axioms actualFillAndReuse
#print axioms actualColdAndReuse

end IRUnaryInferenceProof
