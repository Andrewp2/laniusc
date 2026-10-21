import verified_compiler.tests.direct_ir_body_production_main_domain
import verified_compiler.tests.direct_ir_catalog_append_post

namespace IRBodyProductionProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRTypeRefProof
open IRCatalogAppendProof IRChildrenProof

/-- Restricted native/Core correspondence, independently stated using the
    semantic event constructors and their actual payloads and subtree ends. -/
inductive TerminalRepresentation (events ends : Nat → Except Trap Value) : Nat → Stmt → Prop where
  | void
      (header : events 0 = .ok (source_value Extracted.«ir::body_events».Types.«Event».«StatementReturnVoid» []))
      (endpoint : ends 0 = .ok (.signed .i32 1)) :
      TerminalRepresentation events ends 1 (.returnValue none)
  | boolean (value : Bool)
      (header : events 0 = .ok (source_value Extracted.«ir::body_events».Types.«Event».«StatementReturnValue» []))
      (literal : events 1 = .ok (source_value Extracted.«ir::body_events».Types.«Event».«ExpressionBoolean» [.boolean value]))
      (endpoints : ∀ index, index < 2 → ends index = .ok (.signed .i32 2)) :
      TerminalRepresentation events ends 2 (.returnValue (some (.value (.boolean value))))
  | integer (value : Int32)
      (header : events 0 = .ok (source_value Extracted.«ir::body_events».Types.«Event».«StatementReturnValue» []))
      (literal : events 1 = .ok (source_value Extracted.«ir::body_events».Types.«Event».«ExpressionInteger» [.signed .i32 value.toInt]))
      (endpoints : ∀ index, index < 2 → ends index = .ok (.signed .i32 2)) :
      TerminalRepresentation events ends 2 (.returnValue (some (.value (.signed .i32 value.toInt))))
  | negative (value : Int32)
      (header : events 0 = .ok (source_value Extracted.«ir::body_events».Types.«Event».«StatementReturnValue» []))
      (operator : events 1 = .ok (source_value Extracted.«ir::body_events».Types.«Event».«ExpressionUnaryNegate» []))
      (literal : events 2 = .ok (source_value Extracted.«ir::body_events».Types.«Event».«ExpressionInteger» [.signed .i32 value.toInt]))
      (endpoints : ∀ index, index < 3 → ends index = .ok (.signed .i32 3)) :
      TerminalRepresentation events ends 3
        (.returnValue (some (.unary .negate (.value (.signed .i32 value.toInt)))))

def terminalResult : Stmt → Reference
  | .returnValue none => .Void
  | .returnValue (some (.value (.boolean _))) => .Bool
  | .returnValue (some (.value (.signed .i32 _)))
  | .returnValue (some (.unary .negate (.value (.signed .i32 _)))) => .I32
  | _ => .Invalid

private theorem ReturnBody.terminalResult (body : ReturnBody) :
    terminalResult body.coreStatement = body.result := by cases body <;> rfl

/-- The stored row names this very native tree and zero-parameter Core body.
    This relation does not assert execution of a backend reader or emitter. -/
structure StoredTerminalRepresentation (heap : Heap) (row : Nat) (id : Int32)
    (events types ends count : Nat) (annotations : Bool) (statement : Stmt) : Prop where
  rowSnapshot : NativeSnapshot 64 extractedProgram heap IRCatalogStoreProof.bodyType row
    (IRCatalogStoreProof.body (IRCatalogStoreProof.signature id 0 (terminalResult statement))
      (IRValidatorProof.treeValue (.rawSlice IREventStoreProof.eventType events count)
        (.rawSlice IREventStoreProof.referenceType types count) true
        (.rawSlice (.scalar (.signed .i32)) ends count) count)) 96
  payloads : TerminalRepresentation
    (readRawSliceIndex extractedProgram { heap := heap } IREventStoreProof.eventType events count)
    (readRawSliceIndex extractedProgram { heap := heap } (.scalar (.signed .i32)) ends count)
    count statement
  resultTypes : ∀ index, index < count → readRawSliceIndex extractedProgram { heap := heap }
    IREventStoreProof.referenceType types count index = .ok
      (referenceValue (if annotations then if index = 0 then .Invalid else terminalResult statement else .Invalid))

private theorem ReturnBody.nativeEndpoints {arguments : Arguments} {annotations : Nat → Reference} (body : ReturnBody)
    (nodes : ∀ index, index < body.count → (body.request arguments annotations).Node ends index)
    (root : ends 0 = (body.count : Int)) : ∀ index, index < body.count → ends index = body.count := by
  intro index inside
  cases body with
  | void =>
      have zero : index = 0 := by change index < 1 at inside; omega
      subst index; exact root
  | boolean value | integer value =>
      have choices : index = 0 ∨ index = 1 := by change index < 2 at inside; omega
      rcases choices with rfl | rfl
      · exact root
      · obtain ⟨_, _, _, endpoint, equal, chain⟩ := nodes 1 (by change 1 < 2; decide)
        change ChildChain 2 _ _ _ ends 0 0 2 endpoint at chain
        cases chain
        exact equal
  | negative value =>
      have leaf : ends 2 = 3 := by
        obtain ⟨_, _, _, endpoint, equal, chain⟩ := nodes 2 (by change 2 < 3; decide)
        change ChildChain 3 _ _ _ ends 0 0 3 endpoint at chain
        cases chain
        exact equal
      have choices : index = 0 ∨ index = 1 ∨ index = 2 := by change index < 3 at inside; omega
      rcases choices with rfl | rfl | rfl
      · exact root
      · obtain ⟨_, _, _, endpoint, equal, chain⟩ := nodes 1 (by change 1 < 3; decide)
        change ChildChain 3 _ _ _ ends 1 0 2 endpoint at chain
        cases chain with
        | cons _ _ _ _ tail =>
          cases tail
          rw [leaf] at equal
          change ends 1 = 3 at equal
          exact equal
      · exact leaf

/-- Copy and store already retain all required native payloads. Interpret
    those facts directly, without rebuilding a typing tree or decoding proof data. -/
theorem ReturnBody.storedRepresentation (body : ReturnBody)
    (arguments : Arguments) (parameters : arguments.parameters = 0) (result : arguments.result = body.result)
    (annotations : Nat → Reference)
    (typedAnnotations : ∀ index, index < body.count → annotations index = if index = 0 then .Invalid else body.result)
    {previous : Nat → PreviousRow}
    (post : Post { body.request arguments annotations with previous } caller answer heap world views)
    (success : ({ body.request arguments annotations with previous } : Model).Success caller.heap) :
    StoredTerminalRepresentation heap (arguments.rowBase arguments.occupied) arguments.id
      (caller.heap.allocationAddress 8 + body.count * 40 - 8)
      (caller.heap.allocationAddress 8 + body.count * 56 - 8)
      (caller.heap.allocationAddress 8 + body.count * 56) body.count arguments.hasResultTypes body.coreStatement := by
  have active : ({ body.request arguments annotations with previous } : Model).CopyNeeded caller.heap :=
    ⟨success.1, success.2.1, success.2.2.1, by
      obtain ⟨first, second, available, _⟩ := success.2.2.2.1
      exact ⟨first, available⟩⟩
  obtain ⟨eventReads, typeReads⟩ := post.copied active
  obtain ⟨row, _, ends, nodes, root, endReads⟩ := post.stored success
  have eventTypeEq : IRCatalogAppendProof.eventType = IREventStoreProof.eventType := by rfl
  have referenceTypeEq : IRCatalogAppendProof.referenceType = IREventStoreProof.referenceType := by rfl
  have bodyTypeEq : IRCatalogAppendProof.bodyType = IRCatalogStoreProof.bodyType := by rfl
  have count := body.requestCount (arguments := arguments) (annotations := annotations)
  have endpoints := body.nativeEndpoints (arguments := arguments) (annotations := annotations)
    (by simpa only [Model.Node, count] using nodes) (by simpa only [count] using root)
  have nativeEvents : ∀ index, index < body.count → readRawSliceIndex extractedProgram { heap := heap }
      IREventStoreProof.eventType (caller.heap.allocationAddress 8 + body.count * 40 - 8) body.count index =
        .ok (body.event index) := by
    intro index inside
    have event : (body.request arguments annotations).events index = body.event index := rfl
    simpa only [count, eventTypeEq, event] using
      eventReads index (by simpa only [count] using inside)
  have nativeTypes : ∀ index, index < body.count → readRawSliceIndex extractedProgram { heap := heap }
      IREventStoreProof.referenceType (caller.heap.allocationAddress 8 + body.count * 56 - 8) body.count index =
        .ok ((body.request arguments annotations).annotation index) := by
    intro index inside
    simpa only [Model.annotation, count, referenceTypeEq] using
      typeReads index (by simpa only [count] using inside)
  have observed : ∀ index, index < body.count → readRawSliceIndex extractedProgram { heap := heap }
      (.scalar (.signed .i32)) (caller.heap.allocationAddress 8 + body.count * 56) body.count index =
        .ok (.signed .i32 body.count) := by
    intro index inside
    simpa only [count, endpoints index inside] using endReads index (by simpa only [count] using inside)
  refine ⟨?_, ?_, ?_⟩
  · simp only [Arguments.copiedTree, count] at row
    simpa only [Arguments.signature, IRCatalogStoreProof.signature, Arguments.rowBase,
      Arguments.occupied, ReturnBody.request, parameters, result, body.terminalResult,
      Int32.toInt_zero, eventTypeEq, referenceTypeEq, bodyTypeEq] using row
  · cases body with
    | void => exact .void (nativeEvents 0 (by decide)) (observed 0 (by decide))
    | boolean value =>
      exact .boolean value
        (nativeEvents 0 (by change 0 < 2; decide)) (nativeEvents 1 (by change 1 < 2; decide)) observed
    | integer value =>
      exact .integer value
        (nativeEvents 0 (by change 0 < 2; decide)) (nativeEvents 1 (by change 1 < 2; decide)) observed
    | negative value =>
      exact .negative value (nativeEvents 0 (by change 0 < 3; decide))
        (nativeEvents 1 (by change 1 < 3; decide)) (nativeEvents 2 (by change 2 < 3; decide)) observed
  · intro index inside
    cases enabled : arguments.hasResultTypes <;>
      simpa only [Model.annotation, ReturnBody.request, typedAnnotations index inside,
        body.terminalResult, enabled, Bool.false_eq_true, ↓reduceIte, IREventStoreProof.invalid,
        referenceValue] using
          nativeTypes index inside

#print axioms ReturnBody.storedRepresentation

end IRBodyProductionProof
