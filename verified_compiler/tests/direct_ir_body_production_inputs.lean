import verified_compiler.tests.direct_ir_type_ref
import Lanius.Semantics.NativeSnapshotFrame
import Lanius.Semantics.NaturalArithmetic

namespace IRBodyProductionInputs

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRTypeRefProof

def nodeType : Ty := match source_value Extracted.«verified::syntax_tree».Types.«Node».mk [] with
  | .structure id _ => .structure id | _ => .unit
def childType : Ty := match source_value Extracted.«verified::syntax_tree».Types.«Child».mk [] with
  | .structure id _ => .structure id | _ => .unit
abbrev ChildKind := Extracted.«verified::parser».Types.«ChildKind»
def childKindValue : ChildKind → Value
  | .NoChild => source_value Extracted.«verified::parser».Types.«ChildKind».«NoChild» []
  | .TokenChild => source_value Extracted.«verified::parser».Types.«ChildKind».«TokenChild» []
  | .StateChild => source_value Extracted.«verified::parser».Types.«ChildKind».«StateChild» []
def childCode : ChildKind → Int | .NoChild => 0 | .TokenChild => 1 | .StateChild => 2

/-- Original native descriptors; reached records carry their own scoped bytes. -/
structure Tree where
  nodes : Nat
  children : Nat
  nodesLength : Nat
  childrenLength : Nat
  nodeCount : Nat
  childCount : Nat
  nodesBound : nodeCount ≤ nodesLength
  childrenBound : childCount ≤ childrenLength
  nodesFit : nodeCount < 2 ^ 31
  childrenFit : childCount < 2 ^ 31
def Tree.value (tree : Tree) : Value := source_value Extracted.«verified::syntax_tree».Types.«Tree».mk
  [.rawSlice nodeType tree.nodes tree.nodesLength, .rawSlice childType tree.children tree.childrenLength,
    .signed .i32 tree.nodeCount, .signed .i32 tree.childCount]
def nodeValue (production origin finish : Int) (first count : Nat) : Value :=
  source_value Extracted.«verified::syntax_tree».Types.«Node».mk
    [.signed .i32 production, .signed .i32 origin, .signed .i32 finish,
      .signed .i32 first, .signed .i32 count]
structure NativeNode (tree : Tree) (heap : Heap) (index : Nat) where
  production : Int
  origin : Int
  finish : Int
  first : Nat
  count : Nat
  base : Nat
  inside : index < tree.nodeCount
  childrenInside : first + count ≤ tree.childCount
  location : rawSliceElementAddress? extractedProgram nodeType tree.nodes index = .ok base
  snapshot : NativeSnapshot 64 extractedProgram heap nodeType base
    (nodeValue production origin finish first count) 40
def childValue (kind : ChildKind) (payload semantic : Int) : Value :=
  source_value Extracted.«verified::syntax_tree».Types.«Child».mk
    [childKindValue kind, .signed .i32 payload, .signed .i32 semantic]
structure NativeChild (tree : Tree) (heap : Heap) (index : Nat) where
  kind : ChildKind
  payload : Int
  semantic : Int
  base : Nat
  inside : index < tree.childCount
  location : rawSliceElementAddress? extractedProgram childType tree.children index = .ok base
  snapshot : NativeSnapshot 64 extractedProgram heap childType base (childValue kind payload semantic) 24

theorem NativeNode.read (node : NativeNode tree state.heap index) :
    readRawSliceIndex extractedProgram state nodeType tree.nodes tree.nodesLength index =
      .ok (nodeValue node.production node.origin node.finish node.first node.count) := by
  have inside : index < tree.nodesLength := Nat.lt_of_lt_of_le node.inside tree.nodesBound
  simp only [readRawSliceIndex, Nat.not_le_of_lt inside, ↓reduceIte, node.location]
  exact node.snapshot.read
theorem NativeChild.read (child : NativeChild tree state.heap index) :
    readRawSliceIndex extractedProgram state childType tree.children tree.childrenLength index =
      .ok (childValue child.kind child.payload child.semantic) := by
  have inside : index < tree.childrenLength := Nat.lt_of_lt_of_le child.inside tree.childrenBound
  simp only [readRawSliceIndex, Nat.not_le_of_lt inside, ↓reduceIte, child.location]
  exact child.snapshot.read
def NativeNode.afterReads (node : NativeNode tree before index) (reads : HeapReads before after) :
    NativeNode tree after index := { node with snapshot := node.snapshot.afterHeapReads reads }
def NativeChild.afterReads (child : NativeChild tree before index) (reads : HeapReads before after) :
    NativeChild tree after index := { child with snapshot := child.snapshot.afterHeapReads reads }

@[core_pure_rule] theorem actualProduction (node : NativeNode tree heap index)
    (same : before.heap = heap) (formed : before.CellsWellFormed) : ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«verified::syntax_tree».Functions.«production».core.id
        [.value tree.value, .value (.signed .i32 index)]) (.signed .i32 node.production) after ∧ PureFrame before after := by
  subst heap
  have read := node.read (state := before)
  core_facts [tree, node]
  core_call_pure Extracted.«verified::syntax_tree».Functions.«production».core as callee
  core_pure
@[core_pure_rule] theorem actualChildCount (node : NativeNode tree heap index)
    (same : before.heap = heap) (formed : before.CellsWellFormed) : ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«verified::syntax_tree».Functions.«child_count».core.id
        [.value tree.value, .value (.signed .i32 index)]) (.signed .i32 node.count) after ∧ PureFrame before after := by
  subst heap
  have read := node.read (state := before)
  core_facts [tree, node]
  core_call_pure Extracted.«verified::syntax_tree».Functions.«child_count».core as callee
  core_pure
@[core_pure_rule] theorem actualChildCode (kind : ChildKind) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«verified::parser».Functions.«child_code».core.id [.value (childKindValue kind)])
      (.signed .i32 (childCode kind)) after ∧ PureFrame before after := by
  cases kind <;> dsimp only [childKindValue, childCode]
  all_goals (core_call_pure Extracted.«verified::parser».Functions.«child_code».core as callee; core_pure)
@[core_pure_rule] theorem actualChild (node : NativeNode tree heap index) (slot : Nat)
    (bound : slot < node.count) (child : NativeChild tree heap (node.first + slot))
    (requested : Value) (kind : childKindValue child.kind = requested)
    (same : before.heap = heap) (formed : before.CellsWellFormed) : ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«verified::syntax_tree».Functions.«child».core.id
        [.value tree.value, .value (.signed .i32 index), .value (.signed .i32 slot), .value requested])
      (.signed .i32 child.payload) after ∧ PureFrame before after := by
  subst heap
  subst requested
  have nodeRead := node.read (state := before)
  have childRead := child.read (state := before)
  have fits : node.first + slot < 2 ^ 31 := by have := child.inside; have := tree.childrenFit; omega
  have add := eval_i32_addNat extractedProgram.target node.first slot fits
  core_facts [tree, node]
  core_call_pure Extracted.«verified::syntax_tree».Functions.«child».core as callee
  core_pure

@[core_pure_rule] theorem actualStatementChild (node : NativeNode tree heap index) (slot : Nat)
    (bound : slot < node.count) (child : NativeChild tree heap (node.first + slot))
    (kind : child.kind = .StateChild) (same : before.heap = heap) (formed : before.CellsWellFormed) : ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«verified::surface_statement».Functions.«state_child».core.id
        [.value tree.value, .value (.signed .i32 index), .value (.signed .i32 slot)])
      (.signed .i32 child.payload) after ∧ PureFrame before after := by
  subst heap
  have selected : childKindValue child.kind = childKindValue .StateChild := by rw [kind]
  core_call_pure Extracted.«verified::surface_statement».Functions.«state_child».core as callee
  core_pure

@[core_pure_rule] theorem actualDeclarationChild (node : NativeNode tree heap index) (slot : Nat)
    (bound : slot < node.count) (child : NativeChild tree heap (node.first + slot))
    (kind : child.kind = .StateChild) (same : before.heap = heap) (formed : before.CellsWellFormed) : ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«verified::surface_declaration».Functions.«state_child».core.id
        [.value tree.value, .value (.signed .i32 index), .value (.signed .i32 slot)])
      (.signed .i32 child.payload) after ∧ PureFrame before after := by
  subst heap
  have selected : childKindValue child.kind = childKindValue .StateChild := by rw [kind]
  core_call_pure Extracted.«verified::surface_declaration».Functions.«state_child».core as callee
  core_pure

@[core_pure_rule] theorem actualFunctionBody (node : NativeNode tree heap index)
    (production : node.production = 11) (bound : 8 < node.count)
    (child : NativeChild tree heap (node.first + 8)) (kind : child.kind = .StateChild)
    (same : before.heap = heap) (formed : before.CellsWellFormed) : ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«verified::surface_declaration».Functions.«function_body».core.id
        [.value tree.value, .value (.signed .i32 index)]) (.signed .i32 child.payload) after ∧ PureFrame before after := by
  subst heap
  core_call_pure Extracted.«verified::surface_declaration».Functions.«function_body».core as callee
  core_pure

@[core_pure_rule] theorem actualBlockList (node : NativeNode tree heap index)
    (production : node.production = 12) (bound : 1 < node.count)
    (child : NativeChild tree heap (node.first + 1)) (kind : child.kind = .StateChild)
    (same : before.heap = heap) (formed : before.CellsWellFormed) : ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«verified::surface_statement».Functions.«block_statements».core.id
        [.value tree.value, .value (.signed .i32 index)]) (.signed .i32 child.payload) after ∧ PureFrame before after := by
  subst heap
  core_call_pure Extracted.«verified::surface_statement».Functions.«block_statements».core as callee
  core_pure
def listMore (first rest : Int) : Value := source_value Extracted.«verified::surface_statement».Types.«StatementList».«ListMore»
  [source_value Extracted.«verified::surface_statement».Types.«ListEntry».mk [.signed .i32 first, .signed .i32 rest]]
def listEnd : Value := source_value Extracted.«verified::surface_statement».Types.«StatementList».«ListEnd» []
def returnVoid : Value := source_value Extracted.«verified::surface_statement».Types.«Statement».«ReturnVoid» []
def returnValue (surface : Int) : Value := source_value Extracted.«verified::surface_statement».Types.«Statement».«ReturnValue» [.signed .i32 surface]

@[core_pure_rule] theorem actualListEnd (node : NativeNode tree heap index)
    (production : node.production = 74) (same : before.heap = heap) (formed : before.CellsWellFormed) : ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«verified::surface_statement».Functions.«statement_list».core.id
        [.value tree.value, .value (.signed .i32 index)]) listEnd after ∧ PureFrame before after := by
  subst heap
  core_call_pure Extracted.«verified::surface_statement».Functions.«statement_list».core as callee
  core_pure
@[core_pure_rule] theorem actualListMore (node : NativeNode tree heap index)
    (production : node.production = 73) (bound : 1 < node.count)
    (first : NativeChild tree heap node.first) (rest : NativeChild tree heap (node.first + 1))
    (firstKind : first.kind = .StateChild) (restKind : rest.kind = .StateChild)
    (firstPositive : 0 ≤ first.payload) (restPositive : 0 ≤ rest.payload)
    (same : before.heap = heap) (formed : before.CellsWellFormed) : ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«verified::surface_statement».Functions.«statement_list».core.id
        [.value tree.value, .value (.signed .i32 index)]) (listMore first.payload rest.payload) after ∧ PureFrame before after := by
  subst heap
  have first' : NativeChild tree before.heap (node.first + 0) := by simpa only [Nat.add_zero] using first
  have firstBound : 0 < node.count := by omega
  core_call_pure Extracted.«verified::surface_statement».Functions.«statement_list».core as callee
  core_pure
@[core_pure_rule] theorem actualReturnVoid (node : NativeNode tree heap index)
    (production : node.production = 76) (bound : 1 < node.count)
    (child : NativeChild tree heap (node.first + 1)) (kind : child.kind = .StateChild)
    (optional : NativeNode tree heap optionalIndex) (atOptional : child.payload = optionalIndex)
    (optionalProduction : optional.production = 91) (same : before.heap = heap) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«verified::surface_statement».Functions.«read».core.id
        [.value tree.value, .value (.signed .i32 index)]) returnVoid after ∧ PureFrame before after := by
  subst heap
  have optionalRule {state : State} (same : state.heap = before.heap) (formed : state.CellsWellFormed) :
      ∃ after, RunsExpr extractedProgram state (.call Extracted.«verified::syntax_tree».Functions.«production».core.id
        [.value tree.value, .value (.signed .i32 child.payload)]) (.signed .i32 optional.production) after ∧ PureFrame state after := by
    rw [atOptional]
    exact actualProduction optional same formed
  core_call_pure Extracted.«verified::surface_statement».Functions.«read».core as callee
  core_pure
@[core_pure_rule] theorem actualReturnValue (node : NativeNode tree heap index)
    (production : node.production = 76) (bound : 1 < node.count)
    (child : NativeChild tree heap (node.first + 1)) (kind : child.kind = .StateChild)
    (optional : NativeNode tree heap optionalIndex) (atOptional : child.payload = optionalIndex)
    (optionalProduction : optional.production = 90) (optionalBound : 0 < optional.count)
    (expression : NativeChild tree heap optional.first) (expressionKind : expression.kind = .StateChild)
    (expressionPositive : 0 ≤ expression.payload) (same : before.heap = heap) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«verified::surface_statement».Functions.«read».core.id
        [.value tree.value, .value (.signed .i32 index)]) (returnValue expression.payload) after ∧ PureFrame before after := by
  subst heap
  have optionalRule {state : State} (same : state.heap = before.heap) (formed : state.CellsWellFormed) :
      ∃ after, RunsExpr extractedProgram state (.call Extracted.«verified::syntax_tree».Functions.«production».core.id
        [.value tree.value, .value (.signed .i32 child.payload)]) (.signed .i32 optional.production) after ∧ PureFrame state after := by
    rw [atOptional]
    exact actualProduction optional same formed
  have expressionRule {state : State} (same : state.heap = before.heap) (formed : state.CellsWellFormed) :
      ∃ after, RunsExpr extractedProgram state (.call Extracted.«verified::surface_statement».Functions.«state_child».core.id
        [.value tree.value, .value (.signed .i32 child.payload), .value (.signed .i32 0)])
        (.signed .i32 expression.payload) after ∧ PureFrame state after := by
    rw [atOptional]
    exact actualStatementChild optional 0 optionalBound expression expressionKind same formed
  core_call_pure Extracted.«verified::surface_statement».Functions.«read».core as callee
  core_pure

def signatureType : Ty := match source_value Extracted.«lowering::signature_index».Types.«Entry».mk [] with
  | .structure id _ => .structure id | _ => .unit
def functionKind : Value := source_value Extracted.«lowering::declarations».Types.«DeclarationKind».«Function» []
def internalShape : Value := source_value Extracted.«lowering::signatures».Types.«SignatureShape».«InternalFunctionShape» []
def signatureRecord (id : Nat) (result : Reference) : Value :=
  source_value Extracted.«lowering::signatures».Types.«SignatureRecord».mk
    [.signed .i32 id, functionKind, internalShape, .signed .i32 0, referenceValue result]
structure Signature where
  address : Nat
  length : Nat
  count : Nat
  id : Nat
  result : Reference
  tail : Fin 10 → Value
  starts : Fin 3 → Value
  inside : id < count
  bound : count ≤ length
  fits : count < 2 ^ 31
def Signature.value (input : Signature) : Value := source_value Extracted.«lowering::signature_index».Types.«Table».mk
  [.rawSlice signatureType input.address input.length, .signed .i32 input.count,
    input.tail 0, input.tail 1, input.tail 2, input.tail 3, input.tail 4,
    input.tail 5, input.tail 6, input.tail 7, input.tail 8, input.tail 9]
def Signature.entry (input : Signature) : Value := source_value Extracted.«lowering::signature_index».Types.«Entry».mk
  [.signed .i32 input.id, functionKind, internalShape, .signed .i32 0, referenceValue input.result,
    input.starts 0, input.starts 1, input.starts 2]
def Signature.Read (input : Signature) (state : State) : Prop :=
  readRawSliceIndex extractedProgram state signatureType input.address input.length input.id = .ok input.entry

@[core_pure_rule] theorem actualSignatureRecord (input : Signature)
    (read : readRawSliceIndex extractedProgram before signatureType input.address input.length input.id = .ok input.entry)
    (formed : before.CellsWellFormed) : ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«lowering::signature_index».Functions.«record_at».core.id
        [.value input.value, .value (.signed .i32 input.id)]) (signatureRecord input.id input.result) after ∧ PureFrame before after := by
  core_call_pure Extracted.«lowering::signature_index».Functions.«record_at».core as callee
  core_pure
@[core_pure_rule] theorem actualSignatureContains (input : Signature)
    (read : readRawSliceIndex extractedProgram before signatureType input.address input.length input.id = .ok input.entry)
    (formed : before.CellsWellFormed) : ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«lowering::signature_index».Functions.«contains».core.id
        [.value input.value, .value (.signed .i32 input.id)]) (.boolean true) after ∧ PureFrame before after := by
  core_facts [input]
  core_call_pure Extracted.«lowering::signature_index».Functions.«contains».core as callee
  core_pure
@[core_pure_rule] theorem actualSignatureShape (input : Signature)
    (read : readRawSliceIndex extractedProgram before signatureType input.address input.length input.id = .ok input.entry)
    (formed : before.CellsWellFormed) : ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«lowering::signature_index».Functions.«has_shape».core.id
        [.value input.value, .value (.signed .i32 input.id), .value internalShape]) (.boolean true) after ∧ PureFrame before after := by
  have contained := actualSignatureContains input read formed
  core_call_pure Extracted.«lowering::signature_index».Functions.«has_shape».core as callee
  core_pure
@[core_pure_rule] theorem actualSignatureArity (id : Nat) (result : Reference) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«lowering::signatures».Functions.«record_arity».core.id [.value (signatureRecord id result)])
      (.signed .i32 0) after ∧ PureFrame before after := by
  core_call_pure Extracted.«lowering::signatures».Functions.«record_arity».core as callee
  core_pure
@[core_pure_rule] theorem actualSignatureResult (id : Nat) (result : Reference) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«lowering::signatures».Functions.«record_result_type».core.id [.value (signatureRecord id result)])
      (referenceValue result) after ∧ PureFrame before after := by
  core_call_pure Extracted.«lowering::signatures».Functions.«record_result_type».core as callee
  core_pure

#print axioms actualProduction
#print axioms actualChildCount
#print axioms actualChild
#print axioms actualFunctionBody
#print axioms actualBlockList
#print axioms actualListEnd
#print axioms actualListMore
#print axioms actualReturnVoid
#print axioms actualReturnValue
#print axioms actualSignatureRecord
#print axioms actualSignatureShape
#print axioms actualSignatureArity
#print axioms actualSignatureResult

end IRBodyProductionInputs
