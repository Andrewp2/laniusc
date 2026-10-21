import verified_compiler.tests.direct_ir_type_cache_store

namespace IRTypeCacheFillProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRTypeRefProof IRExpressionKindProof IRTypeCacheProof IRTypeCacheStoreProof

private def uncached := Extracted.«lowering::body_expression».Functions.«expression_kind_uncached».core
private def hasKind := Extracted.«verified::surface_expr».Functions.«has_kind».core

inductive Literal where
  | integer | boolean (flag : Bool) | string

def Literal.kind : Literal → Reference
  | .integer => .I32 | .boolean _ => .Bool | .string => .String
def Literal.operator : Literal → Value
  | .integer => source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«LiteralInteger» []
  | .boolean true => source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«LiteralTrue» []
  | .boolean false => source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«LiteralFalse» []
  | .string => source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«LiteralString» []
private def literalTag := source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Literal» []
def Literal.value (literal : Literal) (fields : Fin 4 → Value) : Value :=
  source_value Extracted.«verified::surface_expr».Types.«ExpressionNode».mk
    [literalTag, literal.operator, fields 0, fields 1, fields 2, fields 3]
def nodeType : Ty := match source_value Extracted.«verified::surface_expr».Types.«ExpressionNode».mk [] with
  | .structure id _ => .structure id | _ => .unit

/-- Unused environment fields stay arbitrary; literal inference reads only
    the node and the allocation-table descriptor, never its contents. -/
structure Environment where
  header : Fin 5 → Value
  countCell : Value
  middle : Fin 6 → Value
  table : Value
  allocationTail : List Value
  tail : List Value

def Environment.suffix (env : Environment) : List Value :=
  [env.middle 0, env.middle 1, env.middle 2, env.middle 3, env.middle 4, env.middle 5,
    .structure (match source_value Extracted.«lowering::allocation».Types.«Index».mk [] with
      | .structure id _ => id | _ => 0) (env.table :: env.allocationTail)] ++ env.tail

structure Input (before : State) extends Query where
  literal : Literal
  nodes : Nat
  fields : Fin 4 → Value
  env : Environment
  nodeRead : readRawSliceIndex extractedProgram before nodeType nodes capacity node = .ok (literal.value fields)

def Input.context (input : Input before) : Value :=
  input.toQuery.context input.env.header (.rawSlice nodeType input.nodes input.capacity)
    input.env.countCell input.env.suffix
def Input.uncachedCall (input : Input before) : Expr :=
  .call uncached.id ([input.context, .signed .i32 input.count, .signed .i32 input.node,
    .signed .i32 input.depth.toInt].map Expr.value)
def Input.call (input : Input before) : Expr :=
  input.toQuery.call input.env.header (.rawSlice nodeType input.nodes input.capacity)
    input.env.countCell input.env.suffix
def Input.reheap (input : Input before) (same : after.heap = before.heap) : Input after :=
  { input with nodeRead := by simpa only [readRawSliceIndex, same] using input.nodeRead }

@[core_pure_rule] private theorem literalTagEqual (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call hasKind.id [.value literalTag, .value literalTag])
      (.boolean true) after ∧ PureFrame before after := by
  core_call_pure hasKind as callee
  core_pure

/-- The uncached query computes the literal's type from the actual AST node. -/
theorem actualLiteral (input : Input before) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before input.uncachedCall (known input.literal.kind) after ∧
      PureFrame before after := by
  core_facts [input.toQuery]
  have knownInteger := fun {state : State} (h : state.CellsWellFormed) => actualKnown .I32 (by decide) h
  have knownBoolean := fun {state : State} (h : state.CellsWellFormed) => actualKnown .Bool (by decide) h
  have knownString := fun {state : State} (h : state.CellsWellFormed) => actualKnown .String (by decide) h
  cases shape : input.literal <;> try (rename_i flag; cases flag)
  all_goals
    have nodeRead := input.nodeRead
    rw [shape] at nodeRead
    core_call_pure uncached as callee
    core_pure

/-- Both empty entries and entries checked with an insufficient budget must
    compute the node again. The two writable words may not overlap. -/
structure Miss (before : State) extends Input before where
  oldCode : Int
  oldDepth : Int
  codeRead : readRawSliceIndex extractedProgram before (.scalar (.signed .i32)) codes capacity node =
    .ok (.signed .i32 oldCode)
  depthRead : readRawSliceIndex extractedProgram before (.scalar (.signed .i32)) depths capacity node =
    .ok (.signed .i32 oldDepth)
  missed : oldCode < 0 ∨ depth.toInt < oldDepth
  codeRoom : before.heap.Readable (codes + node * 4) 4
  depthRoom : before.heap.Readable (depths + node * 4) 4
  separate : codes + node * 4 + 4 ≤ depths + node * 4 ∨ depths + node * 4 + 4 ≤ codes + node * 4

def Miss.slot (input : Miss before) : Slot before := {
  toQuery := input.toQuery, oldCode := input.oldCode, oldDepth := input.oldDepth
  codeRead := input.codeRead, depthRead := input.depthRead, missed := input.missed
  codeRoom := input.codeRoom, depthRoom := input.depthRoom, separate := input.separate }

def Miss.reheap (input : Miss before) (same : after.heap = before.heap) : Miss after :=
  { input with
    nodeRead := by simpa only [readRawSliceIndex, same] using input.nodeRead
    codeRead := by simpa only [readRawSliceIndex, same] using input.codeRead
    depthRead := by simpa only [readRawSliceIndex, same] using input.depthRead
    codeRoom := by simpa only [same] using input.codeRoom
    depthRoom := by simpa only [same] using input.depthRoom }

private theorem Miss.inference (input : Miss before) :
    Inference input.toQuery input.env.header (.rawSlice nodeType input.nodes input.capacity)
      input.env.countCell input.env.suffix input.literal.kind before.heap := by
  intro state same formed
  exact actualLiteral (input.toInput.reheap same) formed

/-- The literal branch discharges inference; successful execution is not a premise. -/
theorem actualMiss (input : Miss before) (formed : before.CellsWellFormed)
    (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before input.toInput.call (known input.literal.kind) after ∧
      MemoryEffect (Stored input.toQuery input.literal.kind) before after :=
  actualStore input.slot input.env.header (.rawSlice nodeType input.nodes input.capacity)
    input.env.countCell input.env.suffix input.literal.kind (by cases input.literal <;> rfl)
    input.inference formed unique noViews

/-- Literal computation, exact cache writes and subsequent reuse, all derived. -/
theorem actualFillAndReuse (input : Miss before) (formed : before.CellsWellFormed)
    (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = []) :
    ∃ cached after, RunsExpr extractedProgram before input.toInput.call (known input.literal.kind) cached ∧
      MemoryEffect (Stored input.toQuery input.literal.kind) before cached ∧
      RunsExpr extractedProgram cached input.toInput.call (known input.literal.kind) after ∧ PureFrame cached after :=
  actualStoreAndReuse input.slot input.env.header (.rawSlice nodeType input.nodes input.capacity)
    input.env.countCell input.env.suffix input.literal.kind (by cases input.literal <;> rfl)
    input.inference formed unique noViews

#print axioms actualLiteral
#print axioms actualMiss
#print axioms actualFillAndReuse

end IRTypeCacheFillProof
