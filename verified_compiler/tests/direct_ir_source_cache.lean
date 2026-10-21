import verified_compiler.tests.direct_ir_type_cache_invariant
import verified_compiler.tests.direct_ir_unary_inference
import verified_compiler.tests.direct_ir_binary_kind
import Lanius.SurfaceElaboration.Classification

namespace IRSourceCacheProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
open IRTypeRefProof IRTypeCacheProof IRTypeCacheStoreProof IRTypeCacheInvariantProof IRUnaryInferenceProof
open IRBinaryKindProof (booleanAccepts scalarResult scalarCases)

/-- The source view of one arena at one binding scope. Nominal type-handle
    interpretation and syntax reconstruction remain caller obligations; scalar
    meanings are fixed by the language, not by successful compiler execution. -/
structure Source where
  context : SurfaceElaboration.Context
  expressions : Nat → Surface.Expr
  ground : Reference → Static.GroundTy
  integer : ground .I32 = .scalar (.signed .i32)
  boolean : ground .Bool = .scalar .bool
  string : ground .String = .scalar .string

/-- Cache facts classify source types; literal decoding and bounds belong to
    lowering. This is tool-proof state, not an emitted typing tree. -/
structure Source.Meaning (source : Source) (node : Nat) (kind : Reference) (_depth : Int) : Prop where
  classification : SurfaceElaboration.ExprClassifies source.context (source.expressions node) (source.ground kind)

def surfaceOperation : Operation → Surface.UnaryOp
  | .positive => .positive | .negate => .negative | .not => .logicalNot

theorem Source.unary (source : Source) (op : Operation)
    (accepted : accepts op kind = true)
    (shape : source.expressions root = .unary (surfaceOperation op) (source.expressions child))
    (operand : source.Meaning child kind childDepth) : source.Meaning root op.kind depth := by
  have same : kind = op.kind := by
    cases op <;> cases kind <;> simp [accepts, Operation.kind] at accepted ⊢
  subst kind
  constructor
  rw [shape]
  have integer : (source.ground .I32).toCore source.context.monomorphization = some (.scalar (.signed .i32)) := by
    rw [source.integer]; rfl
  have boolean : (source.ground .Bool).toCore source.context.monomorphization = some (.scalar .bool) := by
    rw [source.boolean]; rfl
  cases op with
  | positive => exact .unary operand.classification integer integer (.positive (.signed .i32))
  | negate => exact .unary operand.classification integer integer (.negate (.signed .i32))
  | not => exact .unary operand.classification boolean boolean .logicalNot

def surfaceLiteral : IRTypeCacheFillProof.Literal → String → Surface.Literal
  | .integer, text => .integer text
  | .boolean flag, _ => .boolean flag
  | .string, text => .string text

theorem Source.literal (source : Source) (literal : IRTypeCacheFillProof.Literal) (text : String)
    (shape : source.expressions node = .literal (surfaceLiteral literal text)) :
    source.Meaning node literal.kind depth := by
  constructor
  rw [shape]
  apply SurfaceElaboration.ExprClassifies.literal
  cases literal <;> simp only [surfaceLiteral, IRTypeCacheFillProof.Literal.kind,
    Elaboration.literalDefaultType, source.integer, source.boolean, source.string] <;> rfl

/-- Primitive binary classification uses the language's existing operator
    typing rules, independently of the compiler's decision procedure. -/
theorem Source.binaryInteger (source : Source) (op : Surface.BinaryOp)
    (accepted : IRBinaryKindProof.integerAccepts op = true)
    (shape : source.expressions root = .binary op (source.expressions left) (source.expressions right))
    (leftMeaning : source.Meaning left .I32 leftDepth)
    (rightMeaning : source.Meaning right .I32 rightDepth) :
    source.Meaning root (IRBinaryKindProof.integerResult op) depth := by
  constructor
  rw [shape]
  have integer : (source.ground .I32).toCore source.context.monomorphization = some (.scalar (.signed .i32)) := by
    rw [source.integer]; rfl
  have boolean : (source.ground .Bool).toCore source.context.monomorphization = some (.scalar .bool) := by
    rw [source.boolean]; rfl
  cases op <;> simp only [IRBinaryKindProof.integerAccepts, Bool.false_eq_true] at accepted
  all_goals apply (SurfaceElaboration.ExprClassifies.binary leftMeaning.classification rightMeaning.classification
    integer integer (by first | exact integer | exact boolean))
  all_goals first
    | exact .equal (.signed .i32) | exact .notEqual (.signed .i32)
    | exact .less (.signed .i32) | exact .greater (.signed .i32)
    | exact .lessEqual (.signed .i32) | exact .greaterEqual (.signed .i32)
    | exact .add (.signed .i32) | exact .subtract (.signed .i32)
    | exact .multiply (.signed .i32) | exact .divide (.signed .i32)
    | exact .remainder (.signed .i32) | exact .bitAnd (.signed .i32)
    | exact .bitOr (.signed .i32) | exact .bitXor (.signed .i32)
    | exact .shiftLeft (.signed .i32) | exact .shiftRight (.signed .i32)

theorem Source.binaryBoolean (source : Source) (op : Surface.BinaryOp)
    (accepted : booleanAccepts op = true)
    (shape : source.expressions root = .binary op (source.expressions left) (source.expressions right))
    (leftMeaning : source.Meaning left .Bool leftDepth)
    (rightMeaning : source.Meaning right .Bool rightDepth) : source.Meaning root .Bool depth := by
  constructor
  rw [shape]
  have boolean : (source.ground .Bool).toCore source.context.monomorphization = some (.scalar .bool) := by
    rw [source.boolean]; rfl
  cases op <;> simp only [booleanAccepts, Bool.false_eq_true] at accepted
  all_goals apply (SurfaceElaboration.ExprClassifies.binary leftMeaning.classification rightMeaning.classification
    boolean boolean boolean)
  all_goals first | exact .logicalAnd | exact .logicalOr | exact .equal .boolean | exact .notEqual .boolean

/-- Primitive decisions imply the existing language typing judgment. -/
theorem Source.binaryScalar (source : Source) (op : Surface.BinaryOp)
    (accepted : scalarResult op leftKind rightKind = some kind)
    (shape : source.expressions root = .binary op (source.expressions left) (source.expressions right))
    (leftMeaning : source.Meaning left leftKind leftDepth)
    (rightMeaning : source.Meaning right rightKind rightDepth) : source.Meaning root kind depth := by
  rcases scalarCases accepted with ⟨rfl, rfl, integer, rfl⟩ | ⟨rfl, rfl, boolean, rfl⟩
  · exact source.binaryInteger op integer shape leftMeaning rightMeaning
  · exact source.binaryBoolean op boolean shape leftMeaning rightMeaning

/-- The actual warm-child unary computation installs a source-justified parent
    entry and preserves every other classification fact. Its result's meaning and its
    execution are derived, not callback premises. The caller still supplies
    the arena/source correspondence and a sound child entry at this scope. -/
theorem actualFillPreserves (source : Source) (input : Miss before)
    (table : Table input.slot.toQuery before) (sound : table.Sound source.Meaning)
    (child : table.kinds input.child.node = some input.entry.kind)
    (shape : source.expressions input.root = .unary (surfaceOperation input.op) (source.expressions input.child.node))
    (accepted : accepts input.op input.entry.kind = true)
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap)
    (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before input.toInput.cachedCall (IRExpressionKindProof.known input.op.kind) after ∧
      MemoryEffect (Stored input.toInput.query input.op.kind) before after ∧
      source.Meaning input.root input.op.kind input.depth.toInt ∧
      ∃ next : Table input.slot.toQuery after, next.Sound source.Meaning ∧ next.kinds input.root = some input.op.kind := by
  have inside : input.child.node < input.slot.count := by
    have same := congrArg Query.count input.atRoot
    simpa only [same, Input.query] using input.child.inside
  have inferred := source.unary (depth := input.depth.toInt) input.op accepted shape (sound _ inside _ child)
  have atRoot : input.slot.node = input.root := congrArg Query.node input.atRoot
  have justified : source.Meaning input.slot.node input.op.kind input.slot.depth.toInt := by
    rw [atRoot]
    exact ⟨inferred.classification⟩
  have infer : Inference input.slot.toQuery input.env.header (.rawSlice IRTypeCacheFillProof.nodeType input.nodes input.child.capacity)
      input.env.countCell input.env.suffix input.op.kind before.heap := by
    rw [input.atRoot]
    exact input.inference accepted
  obtain ⟨after, run, effect, next, nextSound, found, _⟩ := actualStoreSound input.slot table sound input.op.kind
    (by cases input.op <;> rfl) justified input.env.header (.rawSlice IRTypeCacheFillProof.nodeType input.nodes input.child.capacity)
    input.env.countCell input.env.suffix infer formed unique noViews
  refine ⟨after, ?_, ?_, inferred, next, nextSound, ?_⟩
  · simpa only [input.atRoot, Input.cachedCall] using run
  · simpa only [input.atRoot] using effect
  · rwa [atRoot] at found

/-- Both levels of a cold unary/literal query acquire source classification
    evidence, and the whole native table remains sound. Literal text need not
    decode here: successful value lowering remains a separate obligation. -/
theorem actualColdPreserves (source : Source) (input : Cold before)
    (table : Table input.toInput.query before) (sound : table.Sound source.Meaning)
    (text : String) (leafShape : source.expressions input.leaf.node = .literal (surfaceLiteral input.leaf.literal text))
    (shape : source.expressions input.root = .unary (surfaceOperation input.op) (source.expressions input.child.node))
    (accepted : accepts input.op input.leaf.literal.kind = true)
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before input.toInput.cachedCall (IRExpressionKindProof.known input.op.kind) after ∧
      MemoryEffect (Updates input.toInput.query source.Meaning) before after ∧
      source.Meaning input.root input.op.kind input.depth.toInt ∧
      ∃ next : Table input.toInput.query after, next.Sound source.Meaning := by
  have leaf : source.Meaning input.leaf.node input.leaf.literal.kind input.leaf.depth.toInt :=
    source.literal input.leaf.literal text leafShape
  have child : source.Meaning input.child.node input.leaf.literal.kind input.leaf.depth.toInt := by
    simpa only [input.atChild] using leaf
  have parent := source.unary (depth := input.depth.toInt) input.op accepted shape child
  obtain ⟨cached, after, run, effect, _reuse, _pure⟩ := actualColdAndReuse input accepted formed unique noViews
  obtain ⟨middle, childWrite, parentWrite⟩ := effect.2.2.2
  have updated : Updates input.toInput.query source.Meaning before.heap cached.heap :=
    .store (.store .refl input.leaf.toQuery (by simp only [input.atChild, Input.query, Query.storageKey])
      (by cases input.leaf.literal <;> rfl) leaf childWrite) input.toInput.query rfl
      (by cases input.op <;> rfl) parent parentWrite
  exact ⟨cached, run, ⟨effect.1, effect.2.1, effect.2.2.1, updated⟩, parent, updated.preserves table sound⟩

#print axioms actualFillPreserves
#print axioms actualColdPreserves
#print axioms Updates.preserves

-- The source invariant has ordinary inhabitants, including under arbitrary
-- surrounding scopes. This checks the Boolean domain without assuming a run.
example (context : SurfaceElaboration.Context) (flag : Bool) (depth : Int) :
    let source : Source := {
      context := context
      expressions := fun index => if index = 0 then .unary .logicalNot (.literal (.boolean flag))
        else .literal (.boolean flag)
      ground := fun kind => match kind with
        | .I32 => .scalar (.signed .i32)
        | .Bool => .scalar .bool
        | .String => .scalar .string
        | _ => .unit
      integer := rfl, boolean := rfl, string := rfl }
    source.Meaning 0 .Bool depth := by
  dsimp only
  apply Source.unary (op := .not) (kind := .Bool) (child := 1) (childDepth := depth) _ rfl (by rfl)
  exact ⟨SurfaceElaboration.ExprClassifies.literal rfl⟩

end IRSourceCacheProof
