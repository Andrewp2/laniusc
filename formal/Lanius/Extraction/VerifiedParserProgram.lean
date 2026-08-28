import Lanius.Extraction.ArtifactQuote
import Lanius.Extraction.VerifiedFrontendArtifacts
import Lanius.Extraction.VerifiedParserCertificate
import Lanius.ExecutionRules

namespace Lanius.Extraction

set_option maxRecDepth 1000000

open Lanius.Core
open Lanius.Semantics

theorem verifiedParserArtifact_tracks_source :
    verifiedParserArtifact.sources.map (fun source => source.path) =
        ["verified_compiler/src/verified/parser.lani"] ∧
      verifiedParserArtifact.sources.map (fun source => source.bytes) =
        [sourceBytes verifiedParserSourceText] := by
  native_decide

def extractedParserRangeValidWire : CoreFunction :=
  artifact_function%
    (include_str "Artifacts" / "parser.json"),
    "verified_compiler/src/verified/parser.lani",
    "range_valid"

def extractedParserChartWordWire : CoreFunction :=
  artifact_function%
    (include_str "Artifacts" / "parser.json"),
    "verified_compiler/src/verified/parser.lani",
    "chart_word"

def extractedParserStateWordWire : CoreFunction :=
  artifact_function%
    (include_str "Artifacts" / "parser.json"),
    "verified_compiler/src/verified/parser.lani",
    "state_word"

def extractedParserAppendStateWire : CoreFunction :=
  artifact_function%
    (include_str "Artifacts" / "parser.json"),
    "verified_compiler/src/verified/parser.lani",
    "append_state"

def extractedParserRecognizeWire : CoreFunction :=
  artifact_function%
    (include_str "Artifacts" / "parser.json"),
    "verified_compiler/src/verified/parser.lani",
    "recognize"

def extractedParserRangeValidFunction : Function :=
  CoreDecode.function extractedParserRangeValidWire

def extractedParserChartWordFunction : Function :=
  CoreDecode.function extractedParserChartWordWire

def extractedParserStateWordFunction : Function :=
  CoreDecode.function extractedParserStateWordWire

def extractedParserAppendStateFunction : Function :=
  CoreDecode.function extractedParserAppendStateWire

def extractedParserRecognizeFunction : Function :=
  CoreDecode.function extractedParserRecognizeWire

theorem extractedParser_workspace_function_ids :
    extractedParserRangeValidFunction.id = 7 ∧
      extractedParserChartWordFunction.id = 9 ∧
      extractedParserStateWordFunction.id = 10 ∧
      extractedParserAppendStateFunction.id = 13 ∧
      extractedParserRecognizeFunction.id = 19 := by
  decide

theorem verifiedParserArtifact_decodes_core :
    verifiedParserArtifact.core_program.map CoreDecode.program =
      some verifiedParserCore := by
  unfold verifiedParserArtifact verifiedParserCore verifiedParserCoreProgramWire
  rfl

theorem verifiedParserCore_finds_rangeValid :
    verifiedParserCore.function? extractedParserRangeValidFunction.id =
      some extractedParserRangeValidFunction := by
  unfold verifiedParserCore verifiedParserCoreProgramWire
    verifiedParserCoreProgram verifiedParserCoreFunctions
    extractedParserRangeValidFunction extractedParserRangeValidWire
  rfl

theorem verifiedParserCore_finds_chartWord :
    verifiedParserCore.function? extractedParserChartWordFunction.id =
      some extractedParserChartWordFunction := by
  unfold verifiedParserCore verifiedParserCoreProgramWire
    verifiedParserCoreProgram verifiedParserCoreFunctions
    extractedParserChartWordFunction extractedParserChartWordWire
  rfl

theorem verifiedParserCore_finds_stateWord :
    verifiedParserCore.function? extractedParserStateWordFunction.id =
      some extractedParserStateWordFunction := by
  unfold verifiedParserCore verifiedParserCoreProgramWire
    verifiedParserCoreProgram verifiedParserCoreFunctions
    extractedParserStateWordFunction extractedParserStateWordWire
  rfl

theorem verifiedParserCore_finds_appendState :
    verifiedParserCore.function? extractedParserAppendStateFunction.id =
      some extractedParserAppendStateFunction := by
  unfold verifiedParserCore verifiedParserCoreProgramWire
    verifiedParserCoreProgram verifiedParserCoreFunctions
    extractedParserAppendStateFunction extractedParserAppendStateWire
  rfl

theorem verifiedParserCore_finds_recognize :
    verifiedParserCore.function? extractedParserRecognizeFunction.id =
      some extractedParserRecognizeFunction := by
  unfold verifiedParserCore verifiedParserCoreProgramWire
    verifiedParserCoreProgram verifiedParserCoreFunctions
    extractedParserRecognizeFunction extractedParserRecognizeWire
  rfl

theorem extractedParser_named_selections_checked :
    (verifiedParserArtifact.core_program.map CoreDecode.program).bind
          (fun program => program.function?
            extractedParserRangeValidFunction.id) =
        some extractedParserRangeValidFunction ∧
      (verifiedParserArtifact.core_program.map CoreDecode.program).bind
          (fun program => program.function?
            extractedParserChartWordFunction.id) =
        some extractedParserChartWordFunction ∧
      (verifiedParserArtifact.core_program.map CoreDecode.program).bind
          (fun program => program.function?
            extractedParserStateWordFunction.id) =
        some extractedParserStateWordFunction ∧
      (verifiedParserArtifact.core_program.map CoreDecode.program).bind
          (fun program => program.function?
            extractedParserAppendStateFunction.id) =
        some extractedParserAppendStateFunction ∧
      (verifiedParserArtifact.core_program.map CoreDecode.program).bind
          (fun program => program.function?
            extractedParserRecognizeFunction.id) =
        some extractedParserRecognizeFunction := by
  rw [verifiedParserArtifact_decodes_core]
  exact ⟨verifiedParserCore_finds_rangeValid,
    verifiedParserCore_finds_chartWord,
    verifiedParserCore_finds_stateWord,
    verifiedParserCore_finds_appendState,
    verifiedParserCore_finds_recognize⟩

/-! ## Extracted workspace addressing

The recognizer stores two chart words per input position and nine words per
Earley state.  These definitions intentionally quote the extracted Core
expressions rather than restating the source functions only as mathematical
functions.  The execution theorems below are therefore the first semantic
link from the checked parser artifact to its workspace model.
-/

def parserI32Type : Ty :=
  .scalar (.signed .i32)

def parserChartWordExpr : Expr :=
  .binary .add
    (.binary .multiply (.local 0) (.constant 24))
    (.local 1)

def parserStateWordExpr : Expr :=
  .binary .add
    (.binary .add
      (.local 0)
      (.binary .multiply (.local 1) (.constant 27)))
    (.local 2)

def parserChartWordBody : Stmt :=
  .sequence (.returnValue (some parserChartWordExpr)) .skip

def parserStateWordBody : Stmt :=
  .sequence (.returnValue (some parserStateWordExpr)) .skip

def extractedParserChartWordBody : Stmt :=
  extractedParserChartWordFunction.body.getD .skip

def extractedParserStateWordBody : Stmt :=
  extractedParserStateWordFunction.body.getD .skip

theorem extractedParser_workspace_function_shapes :
    extractedParserChartWordFunction.parameters =
        [(0, parserI32Type), (1, parserI32Type)] ∧
      extractedParserChartWordFunction.returnType = parserI32Type ∧
      extractedParserChartWordFunction.body = some parserChartWordBody ∧
      extractedParserChartWordFunction.external = none ∧
      extractedParserStateWordFunction.parameters =
        [(0, parserI32Type), (1, parserI32Type), (2, parserI32Type)] ∧
      extractedParserStateWordFunction.returnType = parserI32Type ∧
      extractedParserStateWordFunction.body = some parserStateWordBody ∧
      extractedParserStateWordFunction.external = none := by
  exact ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

theorem extractedParserChartWordBody_eq :
    extractedParserChartWordBody = parserChartWordBody := by
  rfl

theorem extractedParserStateWordBody_eq :
    extractedParserStateWordBody = parserStateWordBody := by
  rfl

def signedI32ConstantValue? : Value → Option Int
  | .signed .i32 value => some value
  | _ => none

theorem constant_eq_of_signed_i32_evidence
    (program : Program) (id : ConstantId) (value : Int)
    (evidence : (program.constant? id).map (fun declaration =>
      (declaration.id, declaration.type,
        signedI32ConstantValue? declaration.value)) =
      some (id, parserI32Type, some value)) :
    program.constant? id = some {
      id := id
      type := parserI32Type
      value := .signed .i32 value
    } := by
  cases found : program.constant? id with
  | none => simp [found] at evidence
  | some declaration =>
      simp only [found, Option.map_some, Option.some.injEq,
        Prod.mk.injEq] at evidence
      rcases evidence with ⟨idEqual, typeEqual, valueEqual⟩
      cases declaration with
      | mk declarationId declarationType declarationValue =>
          simp only at idEqual typeEqual valueEqual found
          subst declarationId
          subst declarationType
          cases declarationValue <;>
            simp [signedI32ConstantValue?] at valueEqual
          case signed signedType actualValue =>
            cases signedType <;>
              simp at valueEqual
            case i32 =>
              subst actualValue
              rfl

theorem verifiedParser_workspace_constants :
    verifiedParserCore.constant? 24 = some {
        id := 24
        type := parserI32Type
        value := .signed .i32 2
      } ∧
      verifiedParserCore.constant? 27 = some {
        id := 27
        type := parserI32Type
        value := .signed .i32 9
      } := by
  have evidence :
      (verifiedParserCore.constant? 24).map (fun declaration =>
          (declaration.id, declaration.type,
            signedI32ConstantValue? declaration.value)) =
          some (24, parserI32Type, some 2) ∧
        (verifiedParserCore.constant? 27).map (fun declaration =>
          (declaration.id, declaration.type,
            signedI32ConstantValue? declaration.value)) =
          some (27, parserI32Type, some 9) := by
    native_decide
  exact ⟨constant_eq_of_signed_i32_evidence verifiedParserCore 24 2 evidence.1,
    constant_eq_of_signed_i32_evidence verifiedParserCore 27 9 evidence.2⟩

theorem verifiedParser_find_constants :
    verifiedParserCore.constant? 25 = some {
        id := 25
        type := parserI32Type
        value := .signed .i32 0
      } ∧
      verifiedParserCore.constant? 28 = some {
        id := 28
        type := parserI32Type
        value := .signed .i32 0
      } ∧
      verifiedParserCore.constant? 29 = some {
        id := 29
        type := parserI32Type
        value := .signed .i32 1
      } ∧
      verifiedParserCore.constant? 30 = some {
        id := 30
        type := parserI32Type
        value := .signed .i32 2
      } ∧
      verifiedParserCore.constant? 32 = some {
        id := 32
        type := parserI32Type
        value := .signed .i32 4
      } := by
  have evidence :
      (verifiedParserCore.constant? 25).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (25, parserI32Type, some 0) ∧
      (verifiedParserCore.constant? 28).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (28, parserI32Type, some 0) ∧
      (verifiedParserCore.constant? 29).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (29, parserI32Type, some 1) ∧
      (verifiedParserCore.constant? 30).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (30, parserI32Type, some 2) ∧
      (verifiedParserCore.constant? 32).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (32, parserI32Type, some 4) := by
    native_decide
  exact ⟨
    constant_eq_of_signed_i32_evidence verifiedParserCore 25 0 evidence.1,
    constant_eq_of_signed_i32_evidence verifiedParserCore 28 0 evidence.2.1,
    constant_eq_of_signed_i32_evidence verifiedParserCore 29 1 evidence.2.2.1,
    constant_eq_of_signed_i32_evidence verifiedParserCore 30 2
      evidence.2.2.2.1,
    constant_eq_of_signed_i32_evidence verifiedParserCore 32 4
      evidence.2.2.2.2⟩

def parserChartWordValue
    (target : Target) (position field : Int) : Int :=
  wrapSigned target .i32
    (wrapSigned target .i32 (position * 2) + field)

def parserStateWordValue
    (target : Target) (base stateId field : Int) : Int :=
  wrapSigned target .i32
    (wrapSigned target .i32
      (base + wrapSigned target .i32 (stateId * 9)) + field)

theorem parserChartWordExpr_evaluates
    (program : Program) (state : State) (position field : Int)
    (positionLocal : state.local? 0 = some (.signed .i32 position))
    (fieldLocal : state.local? 1 = some (.signed .i32 field))
    (wordsPerChart : program.constant? 24 = some {
      id := 24
      type := parserI32Type
      value := .signed .i32 2
    }) :
    Evaluates program state parserChartWordExpr
      (.signed .i32 (parserChartWordValue program.target position field)) state := by
  have positionResult := evalLocal_of_local 1 program state 0
    (.signed .i32 position) positionLocal
  have wordsResult : evalExpr 2 program state (.constant 24) =
      .done (.signed .i32 2) state := by
    simp [evalExpr, wordsPerChart]
  have multiplied : evalExpr 3 program state
      (.binary .multiply (.local 0) (.constant 24)) =
      .done (.signed .i32
        (wrapSigned program.target .i32 (position * 2))) state := by
    rw [Lanius.Semantics.evalExpr.eq_def]
    simp only
    rw [positionResult]
    simp only
    rw [wordsResult]
    simp [evalBinaryValue, evalSignedBinary]
  have fieldResult := evalLocal_of_local 2 program state 1
    (.signed .i32 field) fieldLocal
  refine ⟨4, ?_⟩
  simp only [parserChartWordExpr]
  rw [Lanius.Semantics.evalExpr.eq_def]
  simp only
  rw [multiplied]
  simp only
  rw [fieldResult]
  simp [parserChartWordValue, evalBinaryValue, evalSignedBinary]

theorem parserStateWordExpr_evaluates
    (program : Program) (state : State) (base stateId field : Int)
    (baseLocal : state.local? 0 = some (.signed .i32 base))
    (stateIdLocal : state.local? 1 = some (.signed .i32 stateId))
    (fieldLocal : state.local? 2 = some (.signed .i32 field))
    (wordsPerState : program.constant? 27 = some {
      id := 27
      type := parserI32Type
      value := .signed .i32 9
    }) :
    Evaluates program state parserStateWordExpr
      (.signed .i32
        (parserStateWordValue program.target base stateId field)) state := by
  have stateIdResult := evalLocal_of_local 1 program state 1
    (.signed .i32 stateId) stateIdLocal
  have wordsResult : evalExpr 2 program state (.constant 27) =
      .done (.signed .i32 9) state := by
    simp [evalExpr, wordsPerState]
  have multiplied : evalExpr 3 program state
      (.binary .multiply (.local 1) (.constant 27)) =
      .done (.signed .i32
        (wrapSigned program.target .i32 (stateId * 9))) state := by
    rw [Lanius.Semantics.evalExpr.eq_def]
    simp only
    rw [stateIdResult]
    simp only
    rw [wordsResult]
    simp [evalBinaryValue, evalSignedBinary]
  have baseResult := evalLocal_of_local 2 program state 0
    (.signed .i32 base) baseLocal
  have basePlusState : evalExpr 4 program state
      (.binary .add
        (.local 0)
        (.binary .multiply (.local 1) (.constant 27))) =
      .done (.signed .i32
        (wrapSigned program.target .i32
          (base + wrapSigned program.target .i32 (stateId * 9)))) state := by
    rw [Lanius.Semantics.evalExpr.eq_def]
    simp only
    rw [baseResult]
    simp only
    rw [multiplied]
    simp [evalBinaryValue, evalSignedBinary]
  have fieldResult := evalLocal_of_local 3 program state 2
    (.signed .i32 field) fieldLocal
  refine ⟨5, ?_⟩
  simp only [parserStateWordExpr]
  rw [Lanius.Semantics.evalExpr.eq_def]
  simp only
  rw [basePlusState]
  simp only
  rw [fieldResult]
  simp [parserStateWordValue, evalBinaryValue, evalSignedBinary]

theorem parserChartWordBody_executes
    (program : Program) (state : State) (position field : Int)
    (positionLocal : state.local? 0 = some (.signed .i32 position))
    (fieldLocal : state.local? 1 = some (.signed .i32 field))
    (wordsPerChart : program.constant? 24 = some {
      id := 24
      type := parserI32Type
      value := .signed .i32 2
    }) :
    Executes program state parserChartWordBody
      (.returned (some (.signed .i32
        (parserChartWordValue program.target position field)))) state := by
  apply executesSequenceReturned
  apply executesReturnValue
  exact parserChartWordExpr_evaluates program state position field
    positionLocal fieldLocal wordsPerChart

theorem parserStateWordBody_executes
    (program : Program) (state : State) (base stateId field : Int)
    (baseLocal : state.local? 0 = some (.signed .i32 base))
    (stateIdLocal : state.local? 1 = some (.signed .i32 stateId))
    (fieldLocal : state.local? 2 = some (.signed .i32 field))
    (wordsPerState : program.constant? 27 = some {
      id := 27
      type := parserI32Type
      value := .signed .i32 9
    }) :
    Executes program state parserStateWordBody
      (.returned (some (.signed .i32
        (parserStateWordValue program.target base stateId field)))) state := by
  apply executesSequenceReturned
  apply executesReturnValue
  exact parserStateWordExpr_evaluates program state base stateId field
    baseLocal stateIdLocal fieldLocal wordsPerState

theorem extractedParserChartWordBody_executes
    (state : State) (position field : Int)
    (positionLocal : state.local? 0 = some (.signed .i32 position))
    (fieldLocal : state.local? 1 = some (.signed .i32 field)) :
    Executes verifiedParserCore state extractedParserChartWordBody
      (.returned (some (.signed .i32
        (parserChartWordValue verifiedParserCore.target position field)))) state := by
  rw [extractedParserChartWordBody_eq]
  exact parserChartWordBody_executes verifiedParserCore state position field
    positionLocal fieldLocal verifiedParser_workspace_constants.1

theorem extractedParserStateWordBody_executes
    (state : State) (base stateId field : Int)
    (baseLocal : state.local? 0 = some (.signed .i32 base))
    (stateIdLocal : state.local? 1 = some (.signed .i32 stateId))
    (fieldLocal : state.local? 2 = some (.signed .i32 field)) :
    Executes verifiedParserCore state extractedParserStateWordBody
      (.returned (some (.signed .i32
        (parserStateWordValue verifiedParserCore.target base stateId field)))) state := by
  rw [extractedParserStateWordBody_eq]
  exact parserStateWordBody_executes verifiedParserCore state base stateId field
    baseLocal stateIdLocal fieldLocal verifiedParser_workspace_constants.2

end Lanius.Extraction
