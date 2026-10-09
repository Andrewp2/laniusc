import SelfCore
import Lanius.Semantics.CallProof
import Lanius.Semantics.PureProof
import Lanius.Semantics.SourceValue
import verified_compiler.tests.direct_ir_type_ref

namespace IRShapeProof

open Lanius Lanius.Core Lanius.Semantics
abbrev Kind := Extracted.«ir::body_tree».Types.«NodeKind»
abbrev Rule := Extracted.«ir::body_tree».Types.«ChildRule»
private def node := Extracted.«ir::body_tree».Functions.«node».core
private def expected := Extracted.«ir::body_tree».Functions.«expected».core
private def arm := Extracted.«ir::body_tree».Functions.«arm_shape».core
private def shape := Extracted.«ir::body_tree».Functions.«shape».core
private def cast := Extracted.«ir::body_tree».Functions.«cast_shape».core
private def matchHeader := Extracted.«ir::body_tree».Functions.«match_shape».core

def kindValue : Kind → Value
  | .ExpressionNode => source_value Extracted.«ir::body_tree».Types.«NodeKind».«ExpressionNode» []
  | .PlaceNode => source_value Extracted.«ir::body_tree».Types.«NodeKind».«PlaceNode» []
  | .StatementNode => source_value Extracted.«ir::body_tree».Types.«NodeKind».«StatementNode» []
  | .ArmNode => source_value Extracted.«ir::body_tree».Types.«NodeKind».«ArmNode» []
  | .BindingNode => source_value Extracted.«ir::body_tree».Types.«NodeKind».«BindingNode» []
  | .InvalidNode => source_value Extracted.«ir::body_tree».Types.«NodeKind».«InvalidNode» []
def ruleValue : Rule → Value
  | .NoChildren => source_value Extracted.«ir::body_tree».Types.«ChildRule».«NoChildren» []
  | .Expressions => source_value Extracted.«ir::body_tree».Types.«ChildRule».«Expressions» []
  | .PlaceThenExpression => source_value Extracted.«ir::body_tree».Types.«ChildRule».«PlaceThenExpression» []
  | .ExpressionThenArms => source_value Extracted.«ir::body_tree».Types.«ChildRule».«ExpressionThenArms» []
  | .BindingsThenExpression => source_value Extracted.«ir::body_tree».Types.«ChildRule».«BindingsThenExpression» []
  | .Places => source_value Extracted.«ir::body_tree».Types.«ChildRule».«Places» []
  | .Statements => source_value Extracted.«ir::body_tree».Types.«ChildRule».«Statements» []
  | .ExpressionThenStatements => source_value Extracted.«ir::body_tree».Types.«ChildRule».«ExpressionThenStatements» []

def shapeValue (kind : Value) (arity : Int) (rule : Value) : Value :=
  source_value Extracted.«ir::body_tree».Types.«Shape».mk [kind, .signed .i32 arity, rule]
def nodeCall (kind : Value) (arity : Int) (rule : Value) : Expr :=
  .call node.id ([kind, .signed .i32 arity, rule].map Expr.value)

@[core_pure_rule] theorem actualNode (kind rule : Value) (arity : Int) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (nodeCall kind arity rule) (shapeValue kind arity rule) after ∧
      PureFrame state after := by
  core_call node
  core_stmt

-- The contract composes through a real caller-local argument, without
-- interpreting the callee body again or replacing the caller's cell.
example (id : VarId) (kind rule : Value) (arity : Int) (formed : state.CellsWellFormed)
    (found : state.local? id = some kind) :
    ∃ after, RunsExpr extractedProgram state
      (.call node.id [.local id, .value (.signed .i32 arity), .value rule])
      (shapeValue kind arity rule) after ∧ PureFrame state after := by core_pure_expr

/-- Child categories are determined by the parent rule and child position,
    not by the child's claimed kind. -/
def expectedKind : Rule → Int → Nat → Kind
  | .NoChildren, _, _ => .InvalidNode
  | .Expressions, _, _ => .ExpressionNode
  | .PlaceThenExpression, child, _ => if child = 0 then .PlaceNode else .ExpressionNode
  | .ExpressionThenArms, child, _ => if child = 0 then .ExpressionNode else .ArmNode
  | .BindingsThenExpression, child, arity => if child = (arity : Int) - 1 then .ExpressionNode else .BindingNode
  | .Places, _, _ => .PlaceNode
  | .Statements, _, _ => .StatementNode
  | .ExpressionThenStatements, child, _ => if child = 0 then .ExpressionNode else .StatementNode

def expectedCall (rule : Rule) (child : Int) (arity : Nat) : Expr :=
  .call expected.id ([ruleValue rule, .signed .i32 child, .signed .i32 arity].map Expr.value)

theorem actualExpected (rule : Rule) (child : Int) (arity : Nat) (fits : arity < 2 ^ 31)
    (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (expectedCall rule child arity)
      (kindValue (expectedKind rule child arity)) after ∧ PureFrame state after := by
  have predecessor := eval_i32_predecessor extractedProgram.target arity fits
  cases rule <;> simp only [expectedKind] <;> (try split) <;>
    dsimp only [expectedCall, ruleValue, kindValue]
  all_goals
    (core_call_pure expected as callee; core_pure)

def armValue (ordinal count : Int) : Value :=
  source_value Extracted.«ir::body_events».Types.«MatchArm».mk [.signed .i32 ordinal, .signed .i32 count]
def armCall (ordinal count : Int) : Expr := .call arm.id [.value (armValue ordinal count)]
def armShape (ordinal count : Int) : Value :=
  if count ≤ -1 ∨ ordinal < -1 ∨ (ordinal = -1 ∧ count ≠ 0) then
    shapeValue (kindValue .InvalidNode) (-1) (ruleValue .NoChildren)
  else shapeValue (kindValue .ArmNode) (wrapSigned extractedProgram.target .i32 (count + 1))
    (ruleValue .BindingsThenExpression)

@[core_pure_rule] theorem actualArm (ordinal count : Int) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (armCall ordinal count) (armShape ordinal count) after ∧
      PureFrame state after := by
  dsimp only [armShape]
  split <;> dsimp only [armCall, armValue, shapeValue, kindValue, ruleValue]
  all_goals (core_call_pure arm as callee; core_pure)

def armEvent (ordinal count : Int) : Value :=
  source_value Extracted.«ir::body_events».Types.«Event».«MatchArmHeader» [armValue ordinal count]

theorem actualArmEvent (ordinal count : Int) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call shape.id [.value (armEvent ordinal count)])
      (armShape ordinal count) after ∧ PureFrame state after := by
  core_call_pure shape as callee
  core_pure

theorem actualMissingArmPayload (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call shape.id
      [.value (source_value Extracted.«ir::body_events».Types.«Event».«MatchArmHeader» [])])
      (shapeValue (kindValue .InvalidNode) (-1) (ruleValue .NoChildren)) after ∧ PureFrame state after := by
  core_call_pure shape as callee
  core_pure

def castShape (target : IRTypeRefProof.Reference) : Value :=
  if IRTypeRefProof.sameType target .I32 || IRTypeRefProof.sameType target .Usize then
    shapeValue (kindValue .ExpressionNode) 1 (ruleValue .Expressions)
  else shapeValue (kindValue .InvalidNode) (-1) (ruleValue .NoChildren)

@[core_pure_rule] theorem actualCast (target : IRTypeRefProof.Reference) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call cast.id [.value (IRTypeRefProof.referenceValue target)])
      (castShape target) after ∧ PureFrame state after := by
  dsimp only [castShape]
  split <;> dsimp only [shapeValue, kindValue, ruleValue]
  all_goals (core_call_pure cast as callee; core_pure)

def castEvent (target : IRTypeRefProof.Reference) : Value :=
  source_value Extracted.«ir::body_events».Types.«Event».«ExpressionCast»
    [source_value Extracted.«ir::body_events».Types.«CastTarget».mk [IRTypeRefProof.referenceValue target]]

theorem actualCastEvent (target : IRTypeRefProof.Reference) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call shape.id [.value (castEvent target)])
      (castShape target) after ∧ PureFrame state after := by
  core_call_pure shape as callee
  core_pure

def matchHeaderValue (result : IRTypeRefProof.Reference) (id count : Int) : Value :=
  source_value Extracted.«ir::body_events».Types.«MatchHeader».mk
    [IRTypeRefProof.referenceValue result, .signed .i32 id, .signed .i32 count]
def matchShape (result : IRTypeRefProof.Reference) (id count : Int) : Value :=
  if count ≤ 0 ∨ id < 0 ∨ IRTypeRefProof.isValid result = false then
    shapeValue (kindValue .InvalidNode) (-1) (ruleValue .NoChildren)
  else shapeValue (kindValue .ExpressionNode) (wrapSigned extractedProgram.target .i32 (count + 1))
    (ruleValue .ExpressionThenArms)

@[core_pure_rule] theorem actualMatchHeader (result : IRTypeRefProof.Reference) (id count : Int)
    (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call matchHeader.id [.value (matchHeaderValue result id count)])
      (matchShape result id count) after ∧ PureFrame state after := by
  dsimp only [matchShape]
  split <;> dsimp only [matchHeaderValue, shapeValue, kindValue, ruleValue]
  all_goals (core_call_pure matchHeader as callee; core_pure)

def matchEvent (result : IRTypeRefProof.Reference) (id count : Int) : Value :=
  source_value Extracted.«ir::body_events».Types.«Event».«ExpressionMatch» [matchHeaderValue result id count]

theorem actualMatchEvent (result : IRTypeRefProof.Reference) (id count : Int) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call shape.id [.value (matchEvent result id count)])
      (matchShape result id count) after ∧ PureFrame state after := by
  core_call_pure shape as callee
  core_pure

open Extracted.«ir::body_events».Types.«Event» in
/-- Fixed-arity events share semantic categories: unary expressions consume
    one expression, binary expressions two, and assignments a place followed
    by an expression. Statements retain their own child categories. -/
def fixedShapes : List (Value × Value) :=
  [(source_value ExpressionPointerNull [], shapeValue (kindValue .ExpressionNode) 0 (ruleValue .NoChildren))] ++
  ([source_value ExpressionUnaryPositive [], source_value ExpressionUnaryNot [],
    source_value ExpressionUnaryNegate [], source_value ExpressionI32SliceDataPointer [],
    source_value ExpressionStringDataPointer []].map fun event =>
      (event, shapeValue (kindValue .ExpressionNode) 1 (ruleValue .Expressions))) ++
  ([source_value ExpressionBinaryAndThen [], source_value ExpressionBinaryOrElse [],
    source_value ExpressionBinaryEqual [], source_value ExpressionBinaryNotEqual [],
    source_value ExpressionBinaryLess [], source_value ExpressionBinaryLessEqual [],
    source_value ExpressionBinaryGreater [], source_value ExpressionBinaryGreaterEqual [],
    source_value ExpressionBinaryAdd [], source_value ExpressionBinarySubtract [],
    source_value ExpressionBinaryMultiply [], source_value ExpressionBinaryDivide [],
    source_value ExpressionBinaryRemainder [], source_value ExpressionBinaryBitAnd [],
    source_value ExpressionBinaryBitOr [], source_value ExpressionBinaryBitXor [],
    source_value ExpressionBinaryShiftLeft [], source_value ExpressionBinaryShiftRight [],
    source_value ExpressionIndex [], source_value ExpressionI32SliceFromRawParts []].map fun event =>
      (event, shapeValue (kindValue .ExpressionNode) 2 (ruleValue .Expressions))) ++
  ([source_value ExpressionAssignmentSet [], source_value ExpressionAssignmentAdd [],
    source_value ExpressionAssignmentSubtract [], source_value ExpressionAssignmentMultiply [],
    source_value ExpressionAssignmentDivide [], source_value ExpressionAssignmentRemainder [],
    source_value ExpressionAssignmentBitXor [], source_value ExpressionAssignmentShiftLeft [],
    source_value ExpressionAssignmentShiftRight [], source_value ExpressionAssignmentBitAnd [],
    source_value ExpressionAssignmentBitOr []].map fun event =>
      (event, shapeValue (kindValue .ExpressionNode) 2 (ruleValue .PlaceThenExpression))) ++
  [(source_value PlaceIndex [], shapeValue (kindValue .PlaceNode) 2 (ruleValue .PlaceThenExpression)),
   (source_value StatementSkip [], shapeValue (kindValue .StatementNode) 0 (ruleValue .NoChildren)),
   (source_value StatementExpression [], shapeValue (kindValue .StatementNode) 1 (ruleValue .Expressions)),
   (source_value StatementSequence [], shapeValue (kindValue .StatementNode) 2 (ruleValue .Statements)),
   (source_value StatementIf [], shapeValue (kindValue .StatementNode) 3 (ruleValue .ExpressionThenStatements)),
   (source_value StatementWhile [], shapeValue (kindValue .StatementNode) 2 (ruleValue .ExpressionThenStatements)),
   (source_value StatementReturnVoid [], shapeValue (kindValue .StatementNode) 0 (ruleValue .NoChildren)),
   (source_value StatementReturnValue [], shapeValue (kindValue .StatementNode) 1 (ruleValue .Expressions))]

theorem actualFixedShapes (state : State) (formed : state.CellsWellFormed) (event result : Value)
    (listed : (event, result) ∈ fixedShapes) :
    ∃ after, RunsExpr extractedProgram state (.call shape.id [.value event]) result after ∧
      PureFrame state after := by
  simp only [fixedShapes, List.map, List.mem_append, List.mem_cons, List.not_mem_nil] at listed
  repeat' (rcases listed with listed | listed)
  all_goals (core_call_pure shape as callee; core_pure)

example : fixedShapes.length = 45 := by decide

open Extracted.«ir::body_events».Types.«Event» in
/-- These payloads do not influence child structure. Keeping them arbitrary
    avoids imposing typing or payload-validation obligations on classification. -/
def payloadShapes (payload : Value) : List (Value × Value) :=
  ([source_value ExpressionInteger [payload], source_value ExpressionUsize [payload],
    source_value ExpressionBoolean [payload], source_value ExpressionString [payload],
    source_value ExpressionLocal [payload], source_value ExpressionConstant [payload]].map fun event =>
      (event, shapeValue (kindValue .ExpressionNode) 0 (ruleValue .NoChildren))) ++
  [(source_value ExpressionField [payload], shapeValue (kindValue .ExpressionNode) 1 (ruleValue .Expressions)),
   (source_value ExpressionTypedSliceFromRawParts [payload], shapeValue (kindValue .ExpressionNode) 2 (ruleValue .Expressions)),
   (source_value MatchBinding [payload], shapeValue (kindValue .BindingNode) 0 (ruleValue .NoChildren)),
   (source_value PlaceLocal [payload], shapeValue (kindValue .PlaceNode) 0 (ruleValue .NoChildren)),
   (source_value PlaceField [payload], shapeValue (kindValue .PlaceNode) 1 (ruleValue .Places)),
   (source_value StatementLet [payload], shapeValue (kindValue .StatementNode) 2 (ruleValue .ExpressionThenStatements)),
   (source_value StatementLetUninitialized [payload], shapeValue (kindValue .StatementNode) 1 (ruleValue .Statements))]

theorem actualPayloadShapes (state : State) (formed : state.CellsWellFormed) (payload event result : Value)
    (listed : (event, result) ∈ payloadShapes payload) :
    ∃ after, RunsExpr extractedProgram state (.call shape.id [.value event]) result after ∧
      PureFrame state after := by
  simp only [payloadShapes, List.map, List.mem_append, List.mem_cons, List.not_mem_nil] at listed
  repeat' (rcases listed with listed | listed)
  all_goals (core_call_pure shape as callee; core_pure)

open Extracted.«ir::body_events».Types.«Event» in
def countedShapes (id ordinal count : Int) : List (Value × Value) :=
  ([source_value ExpressionStruct [source_value Extracted.«ir::body_events».Types.«StructFields».mk
      [.signed .i32 id, .signed .i32 count]],
    source_value ExpressionEnumeration [source_value Extracted.«ir::body_events».Types.«EnumVariant».mk
      [.signed .i32 id, .signed .i32 ordinal, .signed .i32 count]],
    source_value ExpressionCall [source_value Extracted.«ir::body_events».Types.«CallHeader».mk
      [.signed .i32 id, .signed .i32 count]]].map fun event =>
        (event, shapeValue (kindValue .ExpressionNode) count (ruleValue .Expressions)))

theorem actualCountedShapes (state : State) (formed : state.CellsWellFormed) (id ordinal count : Int)
    (event result : Value) (listed : (event, result) ∈ countedShapes id ordinal count) :
    ∃ after, RunsExpr extractedProgram state (.call shape.id [.value event]) result after ∧
      PureFrame state after := by
  simp only [countedShapes, List.map, List.mem_cons, List.not_mem_nil] at listed
  repeat' (rcases listed with listed | listed)
  all_goals (core_call_pure shape as callee; core_pure)

example (payload : Value) : (payloadShapes payload).length = 13 := rfl
example (id ordinal count : Int) : (countedShapes id ordinal count).length = 3 := rfl

#print axioms actualNode
#print axioms actualExpected
#print axioms actualArm
#print axioms actualArmEvent
#print axioms actualMissingArmPayload
#print axioms actualFixedShapes
#print axioms actualPayloadShapes
#print axioms actualCountedShapes
#print axioms actualCast
#print axioms actualCastEvent
#print axioms actualMatchHeader
#print axioms actualMatchEvent

/-- Logical descriptions of represented source events. Constructors use the
    semantic classification tables/models, never successful evaluator runs. -/
inductive Classifies : Value → Value → Prop where
  | fixed (listed : (event, result) ∈ fixedShapes) : Classifies event result
  | payload (listed : (event, result) ∈ payloadShapes payload) : Classifies event result
  | counted {symbol ordinal count : Int}
      (listed : (event, result) ∈ countedShapes symbol ordinal count) : Classifies event result
  | arm {ordinal count : Int} : Classifies (armEvent ordinal count) (armShape ordinal count)
  | cast {target : IRTypeRefProof.Reference} : Classifies (castEvent target) (castShape target)
  | matching {result : IRTypeRefProof.Reference} {symbol count : Int} :
      Classifies (matchEvent result symbol count) (matchShape result symbol count)

@[core_pure_rule] theorem actualEvent (classified : Classifies event result)
    (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call shape.id [.value event]) result after ∧
      PureFrame state after := by
  cases classified with
  | fixed listed => exact actualFixedShapes state formed _ _ listed
  | payload listed => exact actualPayloadShapes state formed _ _ _ listed
  | counted listed => exact actualCountedShapes state formed _ _ _ _ _ listed
  | arm => exact actualArmEvent _ _ formed
  | cast => exact actualCastEvent _ formed
  | matching => exact actualMatchEvent _ _ _ formed

#print axioms actualEvent

end IRShapeProof
