import Lanius.Extraction.CoreSynthesis.Program
import Lanius.Relational.CoreSuccess
import Lanius.Relational.CallInversion

namespace Lanius.Extraction.EntrypointAnalysis

open Lanius
open Lanius.Core
open Lanius.Extraction.CoreSynthesis.Program

def extractorReturnCodes : List Int :=
  [0, 1, 2, 3, 4, 5, 6, 20, 21, 22, 23, 25, 26, 27, 28]

/-- A syntax-directed invariant independent of the control-flow path: every
ordinary i32 return in the statement is one of `allowed`. -/
def ReturnCodesIn (allowed : List Int) : Core.Stmt → Prop
  | .skip | .expression _ | .breakLoop | .continueLoop => True
  | .sequence first second =>
      ReturnCodesIn allowed first ∧ ReturnCodesIn allowed second
  | .letLocal _ _ _ body | .letUninitialized _ _ body =>
      ReturnCodesIn allowed body
  | .ifThenElse _ thenBranch elseBranch =>
      ReturnCodesIn allowed thenBranch ∧ ReturnCodesIn allowed elseBranch
  | .whileLoop _ body | .forValues _ _ body | .forRange _ _ _ _ body =>
      ReturnCodesIn allowed body
  | .returnValue (some (.value (.signed .i32 code))) => code ∈ allowed
  | .returnValue _ => False

private def returnCodesIn? (allowed : List Int) :
    (statement : Core.Stmt) → Option (ArtifactPackChecker.Evidence
      (ReturnCodesIn allowed statement))
  | .skip | .expression _ | .breakLoop | .continueLoop => some ⟨trivial⟩
  | .sequence first second => do
      let firstSafe ← returnCodesIn? allowed first
      let secondSafe ← returnCodesIn? allowed second
      pure ⟨firstSafe.proof, secondSafe.proof⟩
  | .letLocal _ _ _ body | .letUninitialized _ _ body =>
      returnCodesIn? allowed body
  | .ifThenElse _ thenBranch elseBranch => do
      let thenSafe ← returnCodesIn? allowed thenBranch
      let elseSafe ← returnCodesIn? allowed elseBranch
      pure ⟨thenSafe.proof, elseSafe.proof⟩
  | .whileLoop _ body | .forValues _ _ body | .forRange _ _ _ _ body =>
      returnCodesIn? allowed body
  | .returnValue (some (.value (.signed .i32 code))) =>
      if member : code ∈ allowed then some ⟨member⟩ else none
  | .returnValue _ => none

structure AnalyzedEntrypoint {artifacts : List Artifact}
    (checked : CheckedProgram artifacts)
    {modulePath : Names.ModulePath} {name : Surface.Name}
    (entrypoint : CheckedEntrypoint checked modulePath name) where
  body : Core.Stmt
  bodyPresent : entrypoint.function.body = some body
  returnsI32 : entrypoint.function.returnType = .scalar (.signed .i32)
  relationallySupported : Lanius.Relational.CoreSuccess.Supported body = true
  classifiedReturns : ReturnCodesIn extractorReturnCodes body

def analyzeEntrypoint? {artifacts : List Artifact}
    (checked : CheckedProgram artifacts)
    {modulePath : Names.ModulePath} {name : Surface.Name}
    (entrypoint : CheckedEntrypoint checked modulePath name) :
    Option (AnalyzedEntrypoint checked entrypoint) :=
  match bodyPresent : entrypoint.function.body with
  | none => none
  | some body =>
      if returnsI32 : entrypoint.function.returnType =
          .scalar (.signed .i32) then
        if supported : Lanius.Relational.CoreSuccess.Supported body = true then
          match returnCodesIn? extractorReturnCodes body with
          | none => none
          | some classified =>
              some ⟨body, bodyPresent, returnsI32, supported, classified.proof⟩
        else none
      else none

structure CheckedExtractorCoreSourcePack
    (encoded : String) (expectedSources : List SourceFile) where
  checked : CheckedCompactCoreSourcePack encoded expectedSources
  entrypoint : CheckedEntrypoint checked.program ["app", "main"] "main"
  analysis : AnalyzedEntrypoint checked.program entrypoint

inductive ExtractorCoreSourcePackCheck
    (encoded : String) (expectedSources : List SourceFile) where
  | success (checked : CheckedExtractorCoreSourcePack encoded expectedSources)
  | failure (stage : String)

def checkExtractorCoreSourcePack
    (encoded : String) (expectedSources : List SourceFile) :
    ExtractorCoreSourcePackCheck encoded expectedSources :=
  match checkCompactCoreSourcePack encoded expectedSources with
  | .failure stage => .failure stage
  | .success checked =>
      match checkEntrypoint? checked.program ["app", "main"] "main" with
      | none => .failure "entrypoint"
      | some entrypoint =>
          match analyzeEntrypoint? checked.program entrypoint with
          | none => .failure "entrypoint-control-flow"
          | some analysis => .success ⟨checked, entrypoint, analysis⟩

def checkExtractorCoreSourcePack?
    (encoded : String) (expectedSources : List SourceFile) :
    Option (CheckedExtractorCoreSourcePack encoded expectedSources) :=
  match checkExtractorCoreSourcePack encoded expectedSources with
  | .success checked => some checked
  | .failure _ => none

private theorem returnValue_shape
    {allowed : List Int} {expression : Core.Expr}
    (classified : ReturnCodesIn allowed (.returnValue (some expression))) :
    ∃ code, expression = .value (.signed .i32 code) ∧ code ∈ allowed := by
  cases expression <;> try simp_all [ReturnCodesIn]
  rename_i value
  cases value <;> try simp_all [ReturnCodesIn]
  rename_i integerType integerValue
  cases integerType <;> simp_all [ReturnCodesIn]

/-- The syntax-directed return analysis is sound for every successful
structural execution, independently of which control-flow path was taken. -/
theorem returnCode_mem_of_stmtExecutes
    {allowed : List Int} {program : Core.Program}
    {before after : Lanius.Semantics.State} {statement : Core.Stmt}
    {completion : Lanius.Semantics.Completion} {code : Int}
    (classified : ReturnCodesIn allowed statement)
    (executed : Lanius.Relational.CoreSuccess.StmtExecutes program before
      statement completion after)
    (returned : completion = .returned (some (.signed .i32 code))) :
    code ∈ allowed := by
  induction executed generalizing code <;>
    simp_all [ReturnCodesIn, Lanius.Semantics.Evaluates,
      Lanius.Semantics.evalExpr]
  case returnSome =>
    rename_i expression value evaluated
    obtain ⟨literalCode, rfl, member⟩ := returnValue_shape classified
    rcases evaluated with ⟨fuel, evaluated⟩
    cases fuel with
    | zero => simp [Lanius.Semantics.evalExpr] at evaluated
    | succ fuel =>
        simp [Lanius.Semantics.evalExpr] at evaluated
        simpa [evaluated.1] using member

theorem returnCode_mem_of_executes
    {allowed : List Int} {program : Core.Program}
    {before after : Lanius.Semantics.State} {statement : Core.Stmt}
    {code : Int}
    (classified : ReturnCodesIn allowed statement)
    (supported : Lanius.Relational.CoreSuccess.Supported statement = true)
    (executed : Lanius.Semantics.Executes program before statement
      (.returned (some (.signed .i32 code))) after) :
    code ∈ allowed := by
  apply returnCode_mem_of_stmtExecutes classified
    (Lanius.Relational.CoreSuccess.ofExecutes supported executed)
  rfl

theorem analyzedCall_returnCode_mem
    {artifacts : List Artifact} {checked : CheckedProgram artifacts}
    {modulePath : Names.ModulePath} {name : Surface.Name}
    {entrypoint : CheckedEntrypoint checked modulePath name}
    (analysis : AnalyzedEntrypoint checked entrypoint)
    {before after : Lanius.Semantics.State} {code : Int}
    (evaluated : Lanius.Semantics.Evaluates checked.core before
      (.call entrypoint.source.id []) (.signed .i32 code) after) :
    code ∈ extractorReturnCodes := by
  have functionId : entrypoint.function.id = entrypoint.source.id := by
    have found : checked.core.functions.find?
        (fun function => function.id == entrypoint.source.id) =
        some entrypoint.function := by
      simpa [Core.Program.function?] using entrypoint.found
    exact beq_iff_eq.mp (List.find?_some
      (p := fun function : Core.Function =>
        function.id == entrypoint.source.id)
      (a := entrypoint.function) (l := checked.core.functions) found)
  have foundByFunctionId :
      checked.core.function? entrypoint.function.id = some entrypoint.function := by
    simpa [functionId] using entrypoint.found
  have returnsValue : entrypoint.function.returnType ≠ .unit := by
    rw [analysis.returnsI32]
    simp
  obtain ⟨values, afterArguments, bindings, completed,
      argumentsEvaluated, bindingsFound, bodyExecuted, restored⟩ :=
    Lanius.Relational.evaluatesCallReturned_invert foundByFunctionId
      analysis.bodyPresent returnsValue (by simpa [functionId] using evaluated)
  exact returnCode_mem_of_executes analysis.classifiedReturns
    analysis.relationallySupported bodyExecuted

private theorem runReturned_evaluates
    {program : Core.Program} {entrypoint : FunctionId} {fuel : Nat}
    {before after : Lanius.Semantics.State} {value : Core.Value}
    (returned : Lanius.Execution.run fuel
      ({ program, entrypoint } : Lanius.Execution.Executable) before =
        .returned value after) :
    Lanius.Semantics.Evaluates program before (.call entrypoint []) value after := by
  unfold Lanius.Execution.run at returned
  generalize evaluated : Lanius.Semantics.evalExpr fuel program before
    (.call entrypoint []) = outcome at returned
  cases outcome <;> simp_all
  exact ⟨fuel, evaluated⟩

theorem analyzedRun_returnCode_mem
    {artifacts : List Artifact} {checked : CheckedProgram artifacts}
    {modulePath : Names.ModulePath} {name : Surface.Name}
    {entrypoint : CheckedEntrypoint checked modulePath name}
    (analysis : AnalyzedEntrypoint checked entrypoint)
    {fuel : Nat} {before after : Lanius.Semantics.State} {code : Int}
    (returned : Lanius.Execution.run fuel entrypoint.executable before =
      .returned (.signed .i32 code) after) :
    code ∈ extractorReturnCodes := by
  have literalRun : Lanius.Execution.run fuel
      ({ program := checked.core, entrypoint := entrypoint.source.id } :
        Lanius.Execution.Executable) before =
      .returned (.signed .i32 code) after := by
    simpa [entrypoint.executableDefinition] using returned
  exact analyzedCall_returnCode_mem analysis
    (runReturned_evaluates literalRun)

end Lanius.Extraction.EntrypointAnalysis
