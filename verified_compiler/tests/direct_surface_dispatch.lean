import verified_compiler.tests.direct_surface_integer

namespace SurfaceDispatchProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction
open IRBuilderNavigationProof IRTypeRefProof SurfaceBooleanProof

def classifier := Extracted.«verified::lean_body_shape».Functions.«surface_atom».core
def resultType := Extracted.«ir::body_tree».Functions.«result_type».core
def expression := Extracted.«verified::lean_typed_body».Functions.«surface_expression_output».core
def referenceType := ((Extracted.«ir::type_ref».Functions.«is_invalid».core.parameters[0]?).getD (0, .unit)).2
private def classifierArms : List (Pattern × Expr) := match classifier.body with
  | some (.sequence _ (.letLocal _ _ _ (.returnValue (some (.matchValue _ arms))))) =>
    arms
  | _ => []
private def booleanBinding : VarId := match classifierArms[3]? with
  | some (Pattern.enumVariant _ _ [Pattern.bind id], _) => id
  | _ => 0

/-- Read an existing annotation, without reconstructing a typing derivation. -/
theorem actualResultType (tree : Ready region state) (kind : Reference)
    (annotations : region.hasResultTypes = true) (inside : index < region.count)
    (read : readRawSliceIndex extractedProgram state referenceType
      region.resultAddress region.resultLength index = .ok (referenceValue kind))
    (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call resultType.id [.value tree.value, .value (.signed .i32 index)])
      (referenceValue kind) after ∧ PureFrame state after := by
  core_call_pure resultType as callee
  core_pure

def _root_.SurfaceBooleanProof.Context.expressionCall (context : Context state) (index : Nat) : Expr :=
  .call expression.id ([context.views, .signed .i32 index, .signed .i32 context.position].map Expr.value)

/-- Immutable semantic metadata already stored in the native View. Fixing
    these fields supports names, constructors, and calls without another IR. -/
structure Metadata where
  types : Value
  names : Value
  functions : Value
  functionIndex : Int
  unit : Int
def _root_.SurfaceBooleanProof.Context.metadata (context : Context state) : Metadata :=
  ⟨context.types, context.names, context.functions, context.functionIndex, context.unit⟩

/-- Scalar-only trees need no catalog scope. Other expressions fix the
    existing metadata; output writes and child navigation retain it. -/
inductive Scope where
  | unrestricted
  | fixed (metadata : Metadata)
def Scope.Matches (scope : Scope) (context : Context state) : Prop := match scope with
  | .unrestricted => True
  | .fixed metadata => context.metadata = metadata

/-- A recursive writer contract quantifies over preserved native inputs and
    writable buffers. Parent steps carry the naming scope without new reads;
    final induction discharges every child contract. -/
def Writer (entry : {state : State} → Context state → Nat → Expr)
    (reference : Lanius.Memory.Heap) (tree : Value) (index : Nat) (output : List UInt8)
    (scope : Scope := .unrestricted) : Prop :=
  ∀ {state} (context : Context state), Protected context reference → context.tree = tree →
    scope.Matches context → context.position + output.length ≤ context.capacity → WriterEnvironment state →
    ∃ after, RunsExpr extractedProgram state (entry context index)
      (.signed .i32 (context.position + output.length : Nat)) after ∧
      WriterFrame state after (context.address + context.position) output

theorem _root_.SurfaceBooleanProof.Protected.reheap {before after : State} {context : Context before}
    (input : Protected context reference)
    (heap : after.heap = before.heap) : Protected (context.reheap heap) reference :=
  ⟨by simpa only [Context.reheap, heap] using input.memory, input.viewRead⟩

/-- Forward a checked leaf through the actual expression dispatcher. The
    public integer/boolean contracts below discharge both continuations. -/
theorem actualDispatch (context : Context state) (tree : Ready region state) (index : Nat)
    (representation : context.tree = tree.value) (formed : state.CellsWellFormed)
    (classify : ∀ caller, caller.heap = state.heap → caller.CellsWellFormed →
      ∃ after, RunsExpr extractedProgram caller
        (.call classifier.id [.value tree.value, .value (.signed .i32 index)])
        (.boolean true) after ∧ PureFrame caller after)
    (write : ∀ caller, caller.heap = state.heap → caller.i32ArrayViews = state.i32ArrayViews → caller.CellsWellFormed →
      ∃ after, RunsExpr extractedProgram caller (context.atomCall index)
        (.signed .i32 (context.position + output.length : Nat)) after ∧
        WriterFrame caller after (context.address + context.position) output) :
    ∃ after, RunsExpr extractedProgram state (context.expressionCall index)
      (.signed .i32 (context.position + output.length : Nat)) after ∧
      WriterFrame state after (context.address + context.position) output := by
  core_call_framed Lanius.Extraction.RunsExpr.callWriter expression as callee
  let viewed := callee.bindLocal (expression.bindingId 0) context.value
  let current := viewed.bindLocal (expression.bindingId 1)
    (.rawSlice eventType region.eventsAddress region.eventsLength)
  apply actualViewEvents (context.reheap (after := callee) rfl) tree representation (by core_local) (by core_formed)
  apply RunsStmt.guardWriterTrue
  · simp
  · have classified := classify current rfl (by core_formed)
    rw [← representation] at classified
    core_pure_expr
  · intro ready frame
    have writer := write ready frame.heap frame.views (by core_formed)
    core_writer

/-- Integer literals accepted by the real dispatcher: negatives other than
    minimum i32 are represented by unary-negation nodes in the typed IR. -/
theorem actualIntegerClassifier (tree : Ready region state) (value : Int)
    (inside : index < region.count) (event : region.events index = SurfaceIntegerProof.integerEvent value)
    (allowed : 0 ≤ value ∨ value = -2147483648) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call classifier.id [.value tree.value, .value (.signed .i32 index)])
      (.boolean true) after ∧ PureFrame state after := by
  core_call_pure classifier as callee
  have read := (tree.reheap (after := callee) rfl).eventReads index inside
  rw [event] at read
  rcases allowed with nonnegative | rfl <;> core_pure

theorem actualBooleanClassifier (tree : Ready region state) (value : Bool)
    (inside : index < region.count) (event : region.events index = booleanEvent value)
    (annotations : region.hasResultTypes = true)
    (annotation : readRawSliceIndex extractedProgram state referenceType
      region.resultAddress region.resultLength index = .ok (referenceValue .Bool))
    (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call classifier.id [.value tree.value, .value (.signed .i32 index)])
      (.boolean true) after ∧ PureFrame state after := by
  core_call_pure classifier as callee
  let events := callee.bindLocal (classifier.bindingId 0)
    (.rawSlice eventType region.eventsAddress region.eventsLength)
  let current := events.bindLocal booleanBinding (.boolean value)
  have read := (tree.reheap (after := callee) rfl).eventReads index inside
  rw [event] at read
  have lookup := actualResultType (tree.reheap (after := current) rfl) .Bool annotations inside annotation
    (by core_formed)
  have branch : ∃ after, RunsExpr extractedProgram current
      ((classifierArms[3]?).getD (.wildcard, .value .unit)).2 (.boolean true) after ∧
      PureFrame current after := by
    apply RunsExpr.callFramedPureArguments
    · core_pure_arguments
    · intro middle frame
      exact actualSame .Bool .Bool frame.afterFormed
  core_pure

theorem actualIntegerExpression (context : Context state) (tree : Ready region state) (value : Int)
    (representation : context.tree = tree.value) (inside : index < region.count)
    (event : region.events index = SurfaceIntegerProof.integerEvent value)
    (canonical : -2147483648 ≤ value ∧ value < 2147483648)
    (allowed : 0 ≤ value ∨ value = -2147483648)
    (room : context.position + (OutputSignedProof.bytes value).length ≤ context.capacity)
    (environment : WriterEnvironment state) :
    ∃ after, RunsExpr extractedProgram state (context.expressionCall index)
      (.signed .i32 (context.position + (OutputSignedProof.bytes value).length : Nat)) after ∧
      WriterFrame state after (context.address + context.position) (OutputSignedProof.bytes value) := by
  apply actualDispatch context tree index representation environment.formed
  · intro caller heap callerFormed
    exact actualIntegerClassifier (tree.reheap heap) value inside event allowed callerFormed
  · intro caller heap views callerFormed
    exact SurfaceIntegerProof.actualAtom (context.reheap heap) (tree.reheap heap) value
      representation inside event canonical room (environment.reheap heap views callerFormed)

theorem actualBooleanExpression (context : Context state) (tree : Ready region state) (value : Bool)
    (representation : context.tree = tree.value) (inside : index < region.count)
    (event : region.events index = booleanEvent value) (annotations : region.hasResultTypes = true)
    (annotation : readRawSliceIndex extractedProgram state referenceType
      region.resultAddress region.resultLength index = .ok (referenceValue .Bool))
    (room : context.position + (bytes value).length ≤ context.capacity)
    (environment : WriterEnvironment state) :
    ∃ after, RunsExpr extractedProgram state (context.expressionCall index)
      (.signed .i32 (context.position + (bytes value).length : Nat)) after ∧
      WriterFrame state after (context.address + context.position) (bytes value) := by
  apply actualDispatch context tree index representation environment.formed
  · intro caller heap callerFormed
    exact actualBooleanClassifier (tree.reheap heap) value inside event annotations
      (by simpa only [readRawSliceIndex, heap] using annotation) callerFormed
  · intro caller heap views callerFormed
    exact SurfaceBooleanProof.actualAtom (context.reheap heap) (tree.reheap heap) value
      representation inside event room (environment.reheap heap views callerFormed)

#print axioms actualResultType
#print axioms actualIntegerClassifier
#print axioms actualBooleanClassifier
#print axioms actualDispatch
#print axioms actualIntegerExpression
#print axioms actualBooleanExpression

end SurfaceDispatchProof
