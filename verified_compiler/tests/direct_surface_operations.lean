import verified_compiler.tests.direct_surface_dispatch
import verified_compiler.tests.direct_ir_pair_navigation

namespace SurfaceOperationsProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction
open SurfaceBooleanProof SurfaceDispatchProof IRBuilderNavigationProof

def emptyName : Value := source_value Extracted.«verified::lean_operations».Types.«Name».mk
  [.string "", .signed .i32 0]
private def named := Extracted.«verified::lean_operations».Functions.«named».core
private def unknown := Extracted.«verified::lean_operations».Functions.«unknown».core
def binarySymbol := Extracted.«verified::lean_operations».Functions.«binary_symbol».core
private def pointerSupported := Extracted.«verified::lean_body_shape».Functions.«pointer_binary_supported».core

theorem actualNamed (spelling : String) (length : Int) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call named.id [.value (.string spelling), .value (.signed .i32 length)])
      (source_value Extracted.«verified::lean_operations».Types.«Name».mk [.string spelling, .signed .i32 length]) after ∧
      PureFrame state after := by
  core_call_pure named as callee
  core_pure

theorem actualUnknown (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call unknown.id []) emptyName after ∧ PureFrame state after := by
  core_call_pure unknown as callee
  have writer := actualNamed "" 0 (state := callee) (by core_formed)
  core_pure

inductive Binary where
  | andThen | orElse | equal | notEqual | less | lessEqual | greater | greaterEqual
  | add | subtract | multiply | divide | remainder | bitAnd | bitOr | bitXor | shiftLeft | shiftRight
def Binary.event : Binary → Value
  | .andThen => source_value Extracted.«ir::body_events».Types.«Event».«ExpressionBinaryAndThen» []
  | .orElse => source_value Extracted.«ir::body_events».Types.«Event».«ExpressionBinaryOrElse» []
  | .equal => source_value Extracted.«ir::body_events».Types.«Event».«ExpressionBinaryEqual» []
  | .notEqual => source_value Extracted.«ir::body_events».Types.«Event».«ExpressionBinaryNotEqual» []
  | .less => source_value Extracted.«ir::body_events».Types.«Event».«ExpressionBinaryLess» []
  | .lessEqual => source_value Extracted.«ir::body_events».Types.«Event».«ExpressionBinaryLessEqual» []
  | .greater => source_value Extracted.«ir::body_events».Types.«Event».«ExpressionBinaryGreater» []
  | .greaterEqual => source_value Extracted.«ir::body_events».Types.«Event».«ExpressionBinaryGreaterEqual» []
  | .add => source_value Extracted.«ir::body_events».Types.«Event».«ExpressionBinaryAdd» []
  | .subtract => source_value Extracted.«ir::body_events».Types.«Event».«ExpressionBinarySubtract» []
  | .multiply => source_value Extracted.«ir::body_events».Types.«Event».«ExpressionBinaryMultiply» []
  | .divide => source_value Extracted.«ir::body_events».Types.«Event».«ExpressionBinaryDivide» []
  | .remainder => source_value Extracted.«ir::body_events».Types.«Event».«ExpressionBinaryRemainder» []
  | .bitAnd => source_value Extracted.«ir::body_events».Types.«Event».«ExpressionBinaryBitAnd» []
  | .bitOr => source_value Extracted.«ir::body_events».Types.«Event».«ExpressionBinaryBitOr» []
  | .bitXor => source_value Extracted.«ir::body_events».Types.«Event».«ExpressionBinaryBitXor» []
  | .shiftLeft => source_value Extracted.«ir::body_events».Types.«Event».«ExpressionBinaryShiftLeft» []
  | .shiftRight => source_value Extracted.«ir::body_events».Types.«Event».«ExpressionBinaryShiftRight» []
def Binary.spelling : Binary → String
  | .andThen => "&&" | .orElse => "||" | .equal => "==" | .notEqual => "!="
  | .less => "<" | .lessEqual => "<=" | .greater => ">" | .greaterEqual => ">="
  | .add => "+" | .subtract => "-" | .multiply => "*" | .divide => "/" | .remainder => "%"
  | .bitAnd => "&&&" | .bitOr => "|||" | .bitXor => "^^^" | .shiftLeft => "<<<" | .shiftRight => ">>>"
def Binary.length (operation : Binary) : Nat := (World.utf8Bytes operation.spelling).length
def Binary.name (operation : Binary) : Value :=
  source_value Extracted.«verified::lean_operations».Types.«Name».mk
    [.string operation.spelling, .signed .i32 operation.length]
def Binary.pointerArithmetic : Binary → Bool | .add | .subtract => true | _ => false
theorem Binary.lengthBounds (operation : Binary) : 1 ≤ operation.length ∧ operation.length ≤ 3 := by
  cases operation <;> decide

theorem actualSymbol (operation : Binary) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call binarySymbol.id [.value operation.event])
      operation.name after ∧ PureFrame state after := by
  core_call_pure binarySymbol as callee
  apply RunsStmt.returnPure
  apply RunsExpr.matchPure (value := operation.event) (bindings := [])
    (body := .call named.id [.value (.string operation.spelling), .value (.signed .i32 operation.length)])
  · core_run
  · cases operation <;> rfl
  · core_formed
  · exact actualNamed operation.spelling operation.length (by core_formed)

theorem binaryArity (operation : Binary) (classified : IRShapeProof.Classifies operation.event
    (IRShapeProof.shapeValue (IRShapeProof.kindValue kind) arity (IRShapeProof.ruleValue rule))) : arity = 2 := by
  cases operation <;> cases classified with
  | fixed listed => simp [IRShapeProof.fixedShapes, Binary.event, IRShapeProof.shapeValue] at listed; simp_all
  | payload listed => simp [IRShapeProof.payloadShapes, Binary.event] at listed
  | counted listed => simp [IRShapeProof.countedShapes, Binary.event] at listed

def nonAtomArms : List (Pattern × Expr) := match classifier.body with
  | some (.sequence _ (.letLocal _ _ _ (.returnValue (some (.matchValue _ arms))))) => arms
  | _ => []

/-- The shared non-atom route reads once and proves the actual selected arm. -/
theorem actualNonAtom (value : Value) (tree : Ready region referenceState)
    (inside : index < region.count)
    (read : readRawSliceIndex extractedProgram state eventType region.eventsAddress region.eventsLength index =
      .ok value) (selection : selectedArm value nonAtomArms = some ([], .value (.boolean false)))
    (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call classifier.id [.value tree.value, .value (.signed .i32 index)]) (.boolean false) after ∧
      PureFrame state after := by
  core_call_pure classifier as callee
  have eventRead : readRawSliceIndex extractedProgram callee eventType
      region.eventsAddress region.eventsLength index = .ok value := read
  apply RunsStmt.guardPureFalse
  · core_run
  · apply RunsStmt.letPure (value := .rawSlice eventType region.eventsAddress region.eventsLength)
    · core_run
    · core_formed
    · apply RunsStmt.returnPure
      apply RunsExpr.matchPure (value := value) (bindings := []) (body := .value (.boolean false))
      · core_run
      · exact selection
      · core_formed
      · core_pure_expr

theorem actualBinaryClassifier (operation : Binary) (tree : Ready region referenceState)
    (inside : index < region.count)
    (read : readRawSliceIndex extractedProgram state eventType region.eventsAddress region.eventsLength index =
      .ok operation.event) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call classifier.id [.value tree.value, .value (.signed .i32 index)]) (.boolean false) after ∧
      PureFrame state after :=
  actualNonAtom operation.event tree inside read (by cases operation <;> rfl) formed

inductive ScalarKind where | i32 | boolean | usize
def ScalarKind.reference : ScalarKind → IRTypeRefProof.Reference
  | .i32 => .I32 | .boolean => .Bool | .usize => .Usize
def ScalarAnnotation (_tree : Ready region state) (index : Nat) : Prop :=
  region.hasResultTypes = true ∧ ∃ kind : ScalarKind,
    readRawSliceIndex extractedProgram state referenceType region.resultAddress region.resultLength index =
      .ok (IRTypeRefProof.referenceValue kind.reference)
def NonPointerInput (operation : Binary) (tree : Ready region state) (index : Nat) : Prop :=
  operation.pointerArithmetic = true → ScalarAnnotation tree (index + 1)

@[core_pure_rule] theorem actualScalarNotPointer (kind : ScalarKind) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call Extracted.«ir::type_ref».Functions.«same».core.id
        [.value (IRTypeRefProof.referenceValue kind.reference), .value (IRTypeRefProof.referenceValue .Pointer)])
      (.boolean false) after ∧ PureFrame state after := by
  have different : IRTypeRefProof.sameType kind.reference .Pointer = false := by cases kind <;> rfl
  have run := IRTypeRefProof.actualSame kind.reference .Pointer formed
  rw [different] at run
  exact run

/-- The pointer guard navigates both children. Its false operation flag or
    the left child's existing scalar annotation rules out pointer arithmetic. -/
theorem actualNonPointer (operation : Binary) (tree : Ready region state) (inside : index < region.count)
    (scalar : NonPointerInput operation tree index)
    (parent : region.events index = operation.event) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call pointerSupported.id [.value tree.value, .value (.signed .i32 index)]) (.boolean false) after ∧
      PureFrame state after := by
  have arity := binaryArity operation (show IRShapeProof.Classifies operation.event
    (IRShapeProof.shapeValue (IRShapeProof.kindValue (region.kinds index)) (region.arities index)
      (IRShapeProof.ruleValue (region.rules index))) from by rw [← parent]; exact region.classified index inside)
  core_call_pure pointerSupported as callee
  let events := callee.bindLocal (pointerSupported.bindingId 0)
    (.rawSlice ((Extracted.«ir::body_tree».Functions.«shape».core.parameters[0]?).getD (0, .unit)).2
      region.eventsAddress region.eventsLength)
  let flags := events.bindLocal (pointerSupported.bindingId 1) (.boolean operation.pointerArithmetic)
  have eventRead := (tree.reheap (after := callee) rfl).eventReads index inside
  rw [parent] at eventRead
  have first := (tree.reheap (after := flags) rfl).firstChild inside (by core_formed)
  simp only [Ready.firstIndex, arity, show ¬(2 : Int) ≤ 0 by decide, ↓reduceIte] at first
  apply RunsStmt.letPure
  · core_run
  · core_formed
  · apply RunsStmt.letPure (value := .boolean operation.pointerArithmetic)
    · apply RunsExpr.matchValue (value := operation.event) (bindings := [])
        (body := .value (.boolean operation.pointerArithmetic)) (before := events)
        (middle := events) (after := events)
      · core_run
      · cases operation <;> rfl
      · core_run
    · core_formed
    · apply RunsStmt.letFramedPure (value := .signed .i32 (index + 1 : Nat))
      · apply RunsExpr.callPureArguments (values := [tree.value, .signed .i32 index])
        · core_arguments
        · have canonical := first
          rw [show (index : Int) + 1 = ((index + 1 : Nat) : Int) by omega] at canonical
          exact canonical
      · intro walked frame
        let left := walked.bindLocal (pointerSupported.bindingId 2) (.signed .i32 (index + 1 : Nat))
        have children := tree.childrenStart inside
        have next := (tree.reheap (after := left) frame.heap).nextChild (parent := index) (current := index + 1)
          (remaining := 1) (ordinal := 0) (by omega)
          (by simpa [Ready.Children, arity, Ready.reheap] using children) (by core_formed)
        simp only [show ¬(1 : Nat) = 0 by decide, ↓reduceIte] at next
        apply RunsStmt.letFramedPure (value := .signed .i32 (tree.ends (index + 1)))
        · apply RunsExpr.callPureArguments (values := [tree.value, .signed .i32 index, .signed .i32 (index + 1 : Nat)])
          · core_arguments
          · exact next
        · intro rightReady rightFrame
          let ready := rightReady.bindLocal (pointerSupported.bindingId 3) (.signed .i32 (tree.ends (index + 1)))
          have flagRead : ready.local? (pointerSupported.bindingId 1) = some (.boolean operation.pointerArithmetic) := by core_local
          cases flag : operation.pointerArithmetic
          · rw [flag] at flagRead
            core_pure
          · rw [flag] at flagRead
            obtain ⟨annotations, kind, annotation⟩ := scalar flag
            have heap : ready.heap = state.heap := rightFrame.heap.trans frame.heap
            have read : readRawSliceIndex extractedProgram ready referenceType
                region.resultAddress region.resultLength (index + 1) = .ok (IRTypeRefProof.referenceValue kind.reference) := by
              simpa only [readRawSliceIndex, heap] using annotation
            have lookup := actualResultType (tree.reheap (after := ready) heap) kind.reference
              annotations (IRPairNavigationProof.coordinates tree inside arity).1 read (by core_formed)
            core_pure

#print axioms actualSymbol
#print axioms actualNonAtom
#print axioms actualBinaryClassifier
#print axioms actualScalarNotPointer
#print axioms actualNonPointer

end SurfaceOperationsProof
