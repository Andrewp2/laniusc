import Lanius.Compiler.Lexer.ArtifactScanEnd
import Lanius.Compiler.Lexer.ScanEndValue
import Lanius.Semantics.AggregateCall

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics

private theorem scanEndField_pure (caller : State) (result : ScanEnd) (functionId : FunctionId)
    (returnType : Ty) (field : FieldId) (value : Value) (fieldFound : (scanEndFields result)[field]? = some value)
    (found : Artifact.lexerProgram.function? functionId = some (oneParameterFunction functionId 0 (.structure 0) returnType (.field (.local 0) field)))
    (formed : caller.CellsWellFormed) : PurelyEvaluates Artifact.lexerProgram caller (.call functionId [.value (scanEndValue result)]) value :=
  purelyEvaluatesOneParameterCallOfBuilder Artifact.lexerProgram caller functionId 0 (.structure 0) returnType
    (.field (.local 0) field) (scanEndValue result) value
    (fun _callee cf lf => ⟨2, ThresholdPure.localField cf 0 scanEndStructureId (scanEndFields result) field value lf fieldFound⟩) found formed

theorem scanSucceeded_pure (caller : State) (result : ScanEnd) (formed : caller.CellsWellFormed) :
    PurelyEvaluates Artifact.lexerProgram caller (.call Artifact.scanSucceededFunction.id [.value (scanEndValue result)]) (scanEndSuccessField result) := by
  exact scanEndField_pure caller result 8 (.scalar .bool) 0 (scanEndSuccessField result) (by cases result <;> rfl) (by rfl) formed

theorem scanEndOffset_pure (caller : State) (result : ScanEnd) (formed : caller.CellsWellFormed) :
    PurelyEvaluates Artifact.lexerProgram caller (.call Artifact.scanEndOffsetFunction.id [.value (scanEndValue result)]) (scanEndEndOffsetField result) := by
  exact scanEndField_pure caller result 9 (.scalar (.signed .i32)) 1 (scanEndEndOffsetField result) (by cases result <;> rfl) (by rfl) formed

theorem scanErrorOffset_pure (caller : State) (result : ScanEnd) (formed : caller.CellsWellFormed) :
    PurelyEvaluates Artifact.lexerProgram caller (.call Artifact.scanErrorOffsetFunction.id [.value (scanEndValue result)]) (scanEndErrorOffsetField result) := by
  exact scanEndField_pure caller result 10 (.scalar (.signed .i32)) 2 (scanEndErrorOffsetField result) (by cases result <;> rfl) (by rfl) formed
theorem successfulScan_of_argument (caller : State) (argument : Expr) (endOffset : Nat)
    {argumentFuel : Nat} {argumentAfter : State}
    (argumentContract : ThresholdPure argumentFuel Artifact.lexerProgram caller argument (.signed .i32 (Int.ofNat endOffset)) argumentAfter) :
    ∃ threshold after, ThresholdPure threshold Artifact.lexerProgram caller (.call Artifact.successfulScanFunction.id [argument]) (successfulScanValue endOffset) after := by
  exact thresholdOneParameterCallOfArgumentBuilder Artifact.lexerProgram caller 11 0
    (.scalar (.signed .i32)) (.structure 0)
    (.structValue 0 [.value (.boolean true), .local 0, .value (.signed .i32 0)]) argument
    (.signed .i32 (Int.ofNat endOffset)) (successfulScanValue endOffset) argumentContract
    (fun callee cf lf => ⟨_, ThresholdPure.structValue_triple (ThresholdPure.value cf)
      (ThresholdPure.localValue cf 0 (.signed .i32 (Int.ofNat endOffset)) lf) (ThresholdPure.value cf)⟩)
    (by rfl)

theorem successfulScan_threshold (caller : State) (endOffset : Nat) (formed : caller.CellsWellFormed) :
    ∃ threshold after, ThresholdPure threshold Artifact.lexerProgram caller
      (.call Artifact.successfulScanFunction.id [.value (.signed .i32 (Int.ofNat endOffset))]) (successfulScanValue endOffset) after := by
  simpa using successfulScan_of_argument caller
    (.value (.signed .i32 (Int.ofNat endOffset))) endOffset
    (ThresholdPure.value formed)

theorem successfulScan_pure (caller : State) (endOffset : Nat) (formed : caller.CellsWellFormed) : PurelyEvaluates Artifact.lexerProgram caller
      (.call Artifact.successfulScanFunction.id [.value (.signed .i32 (Int.ofNat endOffset))]) (successfulScanValue endOffset) := by
  exact (successfulScan_threshold caller endOffset formed).choose_spec.choose_spec.erase

theorem failedScan_of_argument (caller : State) (argument : Expr) (errorOffset : Nat)
    {argumentFuel : Nat} {argumentAfter : State}
    (argumentContract : ThresholdPure argumentFuel Artifact.lexerProgram caller argument (.signed .i32 (Int.ofNat errorOffset)) argumentAfter) :
    ∃ threshold after, ThresholdPure threshold Artifact.lexerProgram caller (.call Artifact.failedScanFunction.id [argument]) (failedScanValue errorOffset) after := by
  exact thresholdOneParameterCallOfArgumentBuilder Artifact.lexerProgram caller 12 0
    (.scalar (.signed .i32)) (.structure 0)
    (.structValue 0 [.value (.boolean false), .value (.signed .i32 0), .local 0]) argument
    (.signed .i32 (Int.ofNat errorOffset)) (failedScanValue errorOffset) argumentContract
    (fun callee cf lf => ⟨_, ThresholdPure.structValue_triple (ThresholdPure.value cf)
      (ThresholdPure.value cf) (ThresholdPure.localValue cf 0
        (.signed .i32 (Int.ofNat errorOffset)) lf)⟩)
    (by rfl)

theorem failedScan_threshold (caller : State) (errorOffset : Nat) (formed : caller.CellsWellFormed) :
    ∃ threshold after, ThresholdPure threshold Artifact.lexerProgram caller
      (.call Artifact.failedScanFunction.id [.value (.signed .i32 (Int.ofNat errorOffset))]) (failedScanValue errorOffset) after := by
  simpa using failedScan_of_argument caller
    (.value (.signed .i32 (Int.ofNat errorOffset))) errorOffset
    (ThresholdPure.value formed)

theorem failedScan_pure (caller : State) (errorOffset : Nat)
    (formed : caller.CellsWellFormed) : PurelyEvaluates Artifact.lexerProgram caller
      (.call Artifact.failedScanFunction.id
        [.value (.signed .i32 (Int.ofNat errorOffset))]) (failedScanValue errorOffset) := by
  exact (failedScan_threshold caller errorOffset formed).choose_spec.choose_spec.erase

end Lanius.Compiler.Lexer
