import Lanius.Extraction.ArtifactQuote
import Lanius.Semantics.AggregateCall
import Lanius.Semantics.MutableLocal

namespace Lanius.Compiler.FrontendArtifact

open Lanius Lanius.Core Lanius.Extraction Lanius.Semantics

def frontendProgram : Program :=
  artifact_pack_core_program_flat% (include_str "../Extraction/Artifacts/frontend_pack.json")

def currentSources : List String := [
  include_str "../../../verified_compiler/src/verified/lexer.lani",
  include_str "../../../verified_compiler/src/verified/token_scan.lani",
  include_str "../../../verified_compiler/src/verified/digits.lani",
  include_str "../../../verified_compiler/src/verified/token.lani",
  include_str "../../../verified_compiler/src/verified/canonical_tokens.lani",
  include_str "../../../verified_compiler/src/verified/decimal.lani",
  include_str "../../../verified_compiler/src/verified/number.lani",
  include_str "../../../verified_compiler/src/verified/symbol.lani",
  include_str "../../../verified_compiler/src/verified/raw_lexer.lani"
]

/- The regenerated pack contains the current canonical-token source and its
   five current Core functions, including the private matching helper. -/
def canonicalCoreExportAvailable : Bool := true

theorem canonicalCoreExport_available : canonicalCoreExportAvailable = true := by
  rfl

def lexInto : Function :=
  CoreDecode.function (artifact_pack_function%
    (include_str "../Extraction/Artifacts/frontend_pack.json"),
    "verified_compiler/src/verified/raw_lexer.lani",
    "lex_into")

def lexStatus : Function := CoreDecode.function (artifact_pack_function% (include_str "../Extraction/Artifacts/frontend_pack.json"), "verified_compiler/src/verified/raw_lexer.lani", "lex_status")
def lexTokenCount : Function := CoreDecode.function (artifact_pack_function% (include_str "../Extraction/Artifacts/frontend_pack.json"), "verified_compiler/src/verified/raw_lexer.lani", "lex_token_count")
def lexErrorOffset : Function := CoreDecode.function (artifact_pack_function% (include_str "../Extraction/Artifacts/frontend_pack.json"), "verified_compiler/src/verified/raw_lexer.lani", "lex_error_offset")
def completed : Function := CoreDecode.function (artifact_pack_function% (include_str "../Extraction/Artifacts/frontend_pack.json"), "verified_compiler/src/verified/raw_lexer.lani", "completed")
def lexicalFailure : Function := CoreDecode.function (artifact_pack_function% (include_str "../Extraction/Artifacts/frontend_pack.json"), "verified_compiler/src/verified/raw_lexer.lani", "lexical_failure")
def outputFull : Function := CoreDecode.function (artifact_pack_function% (include_str "../Extraction/Artifacts/frontend_pack.json"), "verified_compiler/src/verified/raw_lexer.lani", "output_full")

theorem lexInto_found :
    frontendProgram.function? lexInto.id = some lexInto := by
  rfl

theorem lexStatus_found : frontendProgram.function? lexStatus.id = some lexStatus := by rfl
theorem lexTokenCount_found : frontendProgram.function? lexTokenCount.id = some lexTokenCount := by rfl
theorem lexErrorOffset_found : frontendProgram.function? lexErrorOffset.id = some lexErrorOffset := by rfl
theorem completed_found : frontendProgram.function? completed.id = some completed := by rfl
theorem lexicalFailure_found : frontendProgram.function? lexicalFailure.id = some lexicalFailure := by rfl
theorem outputFull_found : frontendProgram.function? outputFull.id = some outputFull := by rfl

private def lexResultType : Ty := .structure 4
private def i32Type : Ty := .scalar (.signed .i32)
def lexResultValue (status tokenCount errorOffset : Int) : Value :=
  .structure 4 [.signed .i32 status, .signed .i32 tokenCount, .signed .i32 errorOffset]
private def lexResultFieldBody (field : FieldId) : Expr := .field (.local 0) field

private theorem lexResultConstant (state : State) (constant : ConstantId) (value : Int)
    (declaration : Constant) (found : frontendProgram.constant? constant = some declaration)
    (same : declaration.value = .signed .i32 value) (formed : state.CellsWellFormed) : ThresholdPure 1
      frontendProgram state (.constant constant) (.signed .i32 value) state := by
  refine ⟨?_, PureFrame.refl formed⟩
  intro fuel enough
  rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def]
  simp [found, same]

private theorem lexResultField_pure (caller : State) (fields : List Value) (field : FieldId)
    (value : Value) (functionId : FunctionId) (returnType : Ty)
    (found : frontendProgram.function? functionId = some (oneParameterFunction functionId 0
      lexResultType returnType (lexResultFieldBody field))) (fieldFound : fields[field]? = some value)
    (formed : caller.CellsWellFormed) : PurelyEvaluates frontendProgram caller
      (.call functionId [.value (.structure 4 fields)]) value := by
  apply purelyEvaluatesOneParameterCall frontendProgram caller functionId 0
    lexResultType returnType (lexResultFieldBody field) (.structure 4 fields)
    found formed
  exact ThresholdPure.localField (program := frontendProgram)
    (state := ({ caller with locals := [] }).bindLocal 0 (.structure 4 fields))
    (by exact (show ({ caller with locals := [] } : State).CellsWellFormed from formed).bindLocal 0 _)
    0 4 fields field value (by exact (show (({ caller with locals := [] }).bindLocal 0 (.structure 4 fields)).local? 0 = some (.structure 4 fields) from (show ({ caller with locals := [] } : State).CellsWellFormed from formed).bindLocal_local 0 _)) fieldFound

private def lexResultPairBody (statusConstant : ConstantId) : Expr := .structValue 4 [.constant statusConstant, .local 0, .local 1]
private def lexResultPairFunction (functionId : FunctionId) (statusConstant : ConstantId) : Function :=
  { id := functionId, parameters := [(0, i32Type), (1, i32Type)], returnType := lexResultType,
    body := some (.sequence (.returnValue (some (lexResultPairBody statusConstant))) .skip) }

private theorem lexResultPair_pure (caller : State) (functionId : FunctionId)
    (statusConstant : ConstantId) (status first second : Int)
    (found : frontendProgram.function? functionId = some (lexResultPairFunction functionId statusConstant))
    (constantFound : frontendProgram.constant? statusConstant = some
      { id := statusConstant, type := i32Type, value := .signed .i32 status })
    (formed : caller.CellsWellFormed) : PurelyEvaluates frontendProgram caller
      (.call functionId [.value (.signed .i32 first), .value (.signed .i32 second)]) (lexResultValue status first second) := by
  let firstValue : Value := .signed .i32 first
  let secondValue : Value := .signed .i32 second
  let callee : State := ({ caller with locals := [] }).bindLocals
    [(0, firstValue), (1, secondValue)]
  have clearedFormed : ({ caller with locals := [] } : State).CellsWellFormed := formed
  have calleeFrame : CallerFrame caller callee := by
    have base : CallerFrame caller ({ caller with locals := [] }) := ⟨formed, ⟨[], by simp, Nat.le_refl _, by simp⟩, rfl, rfl, rfl⟩
    simpa [callee, State.bindLocals] using
      (base.bindLocal 0 firstValue).bindLocal 1 secondValue
  have calleeFormed := calleeFrame.currentFormed
  have firstFound : callee.local? 0 = some firstValue := by
    have firstBase := clearedFormed.bindLocal_local 0 firstValue
    have firstAfter := State.bindLocal_local?_of_ne (({ caller with locals := [] }).bindLocal 0 firstValue)
      (clearedFormed.bindLocal 0 firstValue) 0 1 firstValue secondValue (by decide) firstBase
    simpa [callee, State.bindLocals, firstValue] using firstAfter
  have secondFound : callee.local? 1 = some secondValue := by
    simpa [callee, State.bindLocals, secondValue] using ((clearedFormed.bindLocal 0 firstValue).bindLocal_local 1 secondValue)
  have firstConstant := lexResultConstant callee statusConstant status
    { id := statusConstant, type := i32Type, value := .signed .i32 status } constantFound (by rfl) calleeFormed
  have bodyContract : ThresholdPure 5 frontendProgram callee
      (lexResultPairBody statusConstant) (lexResultValue status first second) callee := by
    have bodyBase := ThresholdPure.structValue_triple (program := frontendProgram) (id := 4)
      (first := .constant statusConstant) (second := .local 0) (third := .local 1)
      (firstValue := .signed .i32 status) (secondValue := firstValue)
      (thirdValue := secondValue)
      firstConstant
      (ThresholdPure.localValue (program := frontendProgram) calleeFormed 0 firstValue firstFound)
      (ThresholdPure.localValue (program := frontendProgram) calleeFormed 1 secondValue secondFound)
    simpa [lexResultPairBody, lexResultValue, firstValue, secondValue] using bodyBase.weaken (by omega)
  have bodyRun := StableStmt.returnValueSequence frontendProgram callee
    (lexResultPairBody statusConstant) (lexResultValue status first second) bodyContract.run
  have arguments : ThresholdPureList 3 frontendProgram caller
      [.value firstValue, .value secondValue] [firstValue, secondValue] caller :=
    ThresholdPureList.pair (ThresholdPure.value formed) (ThresholdPure.value formed)
  have call := thresholdInternalCall frontendProgram caller (lexResultPairFunction functionId statusConstant)
    [.value firstValue, .value secondValue]
    (.sequence (.returnValue (some (lexResultPairBody statusConstant))) .skip)
    [firstValue, secondValue] [(0, firstValue), (1, secondValue)] caller callee callee
    (lexResultValue status first second) found rfl arguments
    (by simp [lexResultPairFunction, bindParameters])
    (by simp [callee, State.bindLocals]) bodyRun calleeFrame
    (PureFrame.refl calleeFormed)
  exact call.erase

private def lexResultSingleBody (statusConstant : ConstantId) (errorOffset : Int) : Expr :=
  .structValue 4 [.constant statusConstant, .local 0, .value (.signed .i32 errorOffset)]

private theorem lexResultSingle_pure (caller : State) (functionId : FunctionId)
    (statusConstant : ConstantId) (status tokenCount errorOffset : Int)
    (found : frontendProgram.function? functionId = some
      (oneParameterFunction functionId 0 i32Type lexResultType (lexResultSingleBody statusConstant errorOffset)))
    (constantFound : frontendProgram.constant? statusConstant = some
      { id := statusConstant, type := i32Type, value := .signed .i32 status })
    (formed : caller.CellsWellFormed) : PurelyEvaluates frontendProgram caller
      (.call functionId [.value (.signed .i32 tokenCount)]) (lexResultValue status tokenCount errorOffset) := by
  let tokenValue : Value := .signed .i32 tokenCount
  let callee : State := ({ caller with locals := [] }).bindLocal 0 tokenValue
  have calleeFormed : callee.CellsWellFormed := by
    simpa [callee] using (show ({ caller with locals := [] } : State).CellsWellFormed from formed).bindLocal 0 tokenValue
  have localFound : callee.local? 0 = some tokenValue := by
    simpa [callee] using
      (show ({ caller with locals := [] } : State).CellsWellFormed from formed).bindLocal_local 0 tokenValue
  have firstConstant := lexResultConstant callee statusConstant status
    { id := statusConstant, type := i32Type, value := .signed .i32 status } constantFound (by rfl) calleeFormed
  have bodyBase := ThresholdPure.structValue_triple (program := frontendProgram) (id := 4)
    (first := .constant statusConstant) (second := .local 0)
    (third := .value (.signed .i32 errorOffset))
    (firstValue := .signed .i32 status) (secondValue := tokenValue)
    (thirdValue := .signed .i32 errorOffset)
    firstConstant
    (ThresholdPure.localValue (program := frontendProgram) calleeFormed 0 tokenValue localFound)
    (ThresholdPure.value calleeFormed)
  apply purelyEvaluatesOneParameterCall frontendProgram caller functionId 0
    i32Type lexResultType (lexResultSingleBody statusConstant errorOffset) tokenValue found formed
  simpa [lexResultSingleBody, lexResultValue, tokenValue] using bodyBase

theorem lexStatus_pure (caller : State) (status tokenCount errorOffset : Int) (formed : caller.CellsWellFormed) :
    PurelyEvaluates frontendProgram caller (.call lexStatus.id [.value (lexResultValue status tokenCount errorOffset)]) (.signed .i32 status) :=
  lexResultField_pure caller [.signed .i32 status, .signed .i32 tokenCount, .signed .i32 errorOffset] 0 (.signed .i32 status) lexStatus.id i32Type (by rfl) (by simp) formed
theorem lexTokenCount_pure (caller : State) (status tokenCount errorOffset : Int) (formed : caller.CellsWellFormed) :
    PurelyEvaluates frontendProgram caller (.call lexTokenCount.id [.value (lexResultValue status tokenCount errorOffset)]) (.signed .i32 tokenCount) :=
  lexResultField_pure caller [.signed .i32 status, .signed .i32 tokenCount, .signed .i32 errorOffset] 1 (.signed .i32 tokenCount) lexTokenCount.id i32Type (by rfl) (by simp) formed
theorem lexErrorOffset_pure (caller : State) (status tokenCount errorOffset : Int) (formed : caller.CellsWellFormed) :
    PurelyEvaluates frontendProgram caller (.call lexErrorOffset.id [.value (lexResultValue status tokenCount errorOffset)]) (.signed .i32 errorOffset) :=
  lexResultField_pure caller [.signed .i32 status, .signed .i32 tokenCount, .signed .i32 errorOffset] 2 (.signed .i32 errorOffset) lexErrorOffset.id i32Type (by rfl) (by simp) formed
theorem completed_pure (caller : State) (tokenCount : Int) (formed : caller.CellsWellFormed) :
    PurelyEvaluates frontendProgram caller (.call completed.id [.value (.signed .i32 tokenCount)]) (lexResultValue 0 tokenCount 0) :=
  lexResultSingle_pure caller completed.id 89 0 tokenCount 0 (by rfl) (by rfl) formed
theorem lexicalFailure_pure (caller : State) (tokenCount errorOffset : Int) (formed : caller.CellsWellFormed) :
    PurelyEvaluates frontendProgram caller (.call lexicalFailure.id [.value (.signed .i32 tokenCount), .value (.signed .i32 errorOffset)]) (lexResultValue 1 tokenCount errorOffset) :=
  lexResultPair_pure caller lexicalFailure.id 90 1 tokenCount errorOffset (by rfl) (by rfl) formed
theorem outputFull_pure (caller : State) (tokenCount sourceOffset : Int) (formed : caller.CellsWellFormed) :
    PurelyEvaluates frontendProgram caller (.call outputFull.id [.value (.signed .i32 tokenCount), .value (.signed .i32 sourceOffset)]) (lexResultValue 2 tokenCount sourceOffset) :=
  lexResultPair_pure caller outputFull.id 91 2 tokenCount sourceOffset (by rfl) (by rfl) formed

end Lanius.Compiler.FrontendArtifact
