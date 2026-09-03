import Lanius.Extraction.Parser.ResultAccessors
import Lanius.Extraction.Parser.Constructors
import Lanius.Extraction.VerifiedFrontend.Parser.FunctionalView.Range
import Lanius.Extraction.VerifiedFrontend.Parser.FunctionalView.Validation
import Lanius.Extraction.VerifiedFrontend.Parser.FunctionalView.Reads
import Lanius.Extraction.VerifiedFrontend.Parser.FunctionalView.Find
import Lanius.Extraction.Parser.Append
import Lanius.Extraction.VerifiedFrontend.Parser.FunctionalView.Accessors
import Lanius.Extraction.VerifiedFrontend.Parser.FunctionalView.Scan
import Lanius.Extraction.VerifiedFrontend.Parser.FunctionalView.Recognize
import Lanius.Extraction.VerifiedFrontend.Parser.Soundness

namespace Lanius.Extraction.Parser.FunctionalViewCoverage

/-! # Parser FunctionalView completeness gate

This module intentionally names every function in the checked
`verified_compiler/src/verified/parser.lani` artifact. Adding a source
function without adding its exact-to-Core theorem here, or removing/renaming
one of the referenced theorems, makes this module fail to elaborate.

The checked artifact currently contains twenty functions. The source-derived
function-name certificate below is part of the gate, so that count cannot
silently drift.
-/

/-- A proof term used as a type index. This makes each coverage field depend
    on the named theorem itself, not merely on another proof of the same
    proposition. -/
structure TheoremReference {proposition : Prop} (proof : proposition) where
  checked : proposition

private theorem reference {proposition : Prop} (proof : proposition) :
    TheoremReference proof :=
  ⟨proof⟩

/-- Compile-time coverage certificate for all parser source functions and the
    end-to-end soundness theorem of the real `recognize` entry point. -/
structure Coverage where
  sourceFunctionNames : TheoremReference
    Lanius.Extraction.verifiedParser_symbolic_function_names
  parseStatus : TheoremReference
    Lanius.Extraction.Parser.ResultAccessors.parseStatusView_toCore_exactly
  parseStateCount : TheoremReference
    Lanius.Extraction.Parser.ResultAccessors.parseStateCountView_toCore_exactly
  parseRootState : TheoremReference
    Lanius.Extraction.Parser.ResultAccessors.parseRootStateView_toCore_exactly
  parseErrorPosition : TheoremReference
    Lanius.Extraction.Parser.ResultAccessors.parseErrorPositionView_toCore_exactly
  parseResult : TheoremReference
    Lanius.Extraction.Parser.Constructors.parseResultView_toCore_exactly
  stateSeed : TheoremReference
    Lanius.Extraction.Parser.Constructors.stateSeedView_toCore_exactly
  appendResult : TheoremReference
    Lanius.Extraction.Parser.Constructors.appendResultView_toCore_exactly
  rangeValid : TheoremReference
    Lanius.Extraction.ParserRange.FunctionalView.view_toCore_exactly
  grammarIsValid : TheoremReference
    Lanius.Extraction.ParserValidation.FunctionalView.view_toCore_exactly
  chartWord : TheoremReference
    Lanius.Extraction.ParserReads.Functional.ChartWord.view_toCore_exactly
  stateWord : TheoremReference
    Lanius.Extraction.ParserReads.Functional.StateWord.view_toCore_exactly
  stateValue : TheoremReference
    Lanius.Extraction.ParserReads.Functional.StateValue.view_toCore_exactly
  findState : TheoremReference
    Lanius.Extraction.ParserFind.Functional.view_toCore_exactly
  appendState : TheoremReference
    Lanius.Extraction.Parser.Append.view_toCore_exactly
  productionRhsLength : TheoremReference
    Lanius.Extraction.ParserAccessors.FunctionalView.RhsLength.view_toCore_exactly
  productionRhsSymbol : TheoremReference
    Lanius.Extraction.ParserAccessors.FunctionalView.RhsSymbol.view_toCore_exactly
  productionLhs : TheoremReference
    Lanius.Extraction.ParserAccessors.FunctionalView.Lhs.view_toCore_exactly
  scanTerminal : TheoremReference
    Lanius.Extraction.ParserScan.Proof.scanTerminalView_toCore_exactly
  appendOrFull : TheoremReference
    Lanius.Extraction.Parser.Constructors.appendOrFullView_toCore_exactly
  recognize : TheoremReference
    Lanius.Extraction.ParserRecognize.parserRecognizeView_toCore_exactly
  recognizeSoundness : TheoremReference
    (@Lanius.Extraction.ParserRecognize.RecognizerCallExecution.success_recognizesInput)

/-- The parser coverage gate is inhabited only by the named, checked proof
    terms above. -/
theorem complete : Nonempty Coverage := by
  exact ⟨{
  sourceFunctionNames := reference
    Lanius.Extraction.verifiedParser_symbolic_function_names
  parseStatus := reference
    Lanius.Extraction.Parser.ResultAccessors.parseStatusView_toCore_exactly
  parseStateCount := reference
    Lanius.Extraction.Parser.ResultAccessors.parseStateCountView_toCore_exactly
  parseRootState := reference
    Lanius.Extraction.Parser.ResultAccessors.parseRootStateView_toCore_exactly
  parseErrorPosition := reference
    Lanius.Extraction.Parser.ResultAccessors.parseErrorPositionView_toCore_exactly
  parseResult := reference
    Lanius.Extraction.Parser.Constructors.parseResultView_toCore_exactly
  stateSeed := reference
    Lanius.Extraction.Parser.Constructors.stateSeedView_toCore_exactly
  appendResult := reference
    Lanius.Extraction.Parser.Constructors.appendResultView_toCore_exactly
  rangeValid := reference
    Lanius.Extraction.ParserRange.FunctionalView.view_toCore_exactly
  grammarIsValid := reference
    Lanius.Extraction.ParserValidation.FunctionalView.view_toCore_exactly
  chartWord := reference
    Lanius.Extraction.ParserReads.Functional.ChartWord.view_toCore_exactly
  stateWord := reference
    Lanius.Extraction.ParserReads.Functional.StateWord.view_toCore_exactly
  stateValue := reference
    Lanius.Extraction.ParserReads.Functional.StateValue.view_toCore_exactly
  findState := reference
    Lanius.Extraction.ParserFind.Functional.view_toCore_exactly
  appendState := reference
    Lanius.Extraction.Parser.Append.view_toCore_exactly
  productionRhsLength := reference
    Lanius.Extraction.ParserAccessors.FunctionalView.RhsLength.view_toCore_exactly
  productionRhsSymbol := reference
    Lanius.Extraction.ParserAccessors.FunctionalView.RhsSymbol.view_toCore_exactly
  productionLhs := reference
    Lanius.Extraction.ParserAccessors.FunctionalView.Lhs.view_toCore_exactly
  scanTerminal := reference
    Lanius.Extraction.ParserScan.Proof.scanTerminalView_toCore_exactly
  appendOrFull := reference
    Lanius.Extraction.Parser.Constructors.appendOrFullView_toCore_exactly
  recognize := reference
    Lanius.Extraction.ParserRecognize.parserRecognizeView_toCore_exactly
  recognizeSoundness := reference
    (@Lanius.Extraction.ParserRecognize.RecognizerCallExecution.success_recognizesInput)
  }⟩

/-! `Coverage` prevents the proof-facing parser syntax from drifting from the
checked source. `SemanticCoverage` additionally indexes the real
`verifiedParserCore` execution or semantic-soundness contract for every
covered source function. -/

structure SemanticCoverage where
  exact : Coverage
  parseStatus : TheoremReference
    Lanius.Extraction.Parser.ResultAccessors.parseStatusCall_soundness
  parseStateCount : TheoremReference
    Lanius.Extraction.Parser.ResultAccessors.parseStateCountCall_soundness
  parseRootState : TheoremReference
    Lanius.Extraction.Parser.ResultAccessors.parseRootStateCall_soundness
  parseErrorPosition : TheoremReference
    Lanius.Extraction.Parser.ResultAccessors.parseErrorPositionCall_soundness
  parseResult : TheoremReference
    Lanius.Extraction.ParserResult.extractedParserParseResultCall_contract
  stateSeed : TheoremReference
    Lanius.Extraction.ParserAppend.extractedParserStateSeedCall_contract
  appendResult : TheoremReference
    Lanius.Extraction.ParserAppend.extractedParserAppendResultCall_contract
  rangeValid : TheoremReference
    Lanius.Extraction.ParserRange.FunctionalView.call_soundness
  grammarIsValid : TheoremReference
    (@Lanius.Extraction.ParserValidation.FunctionalView.call_soundness)
  chartWord : TheoremReference
    Lanius.Extraction.ParserReads.Functional.ChartWord.call_soundness
  stateWord : TheoremReference
    Lanius.Extraction.ParserReads.Functional.StateWord.call_soundness
  stateValue : TheoremReference
    Lanius.Extraction.ParserReads.Functional.StateValue.genericCall_soundness
  findState : TheoremReference
    (@Lanius.Extraction.ParserFind.Functional.Call.soundness)
  appendState : TheoremReference
    Lanius.Extraction.ParserAppend.extractedParserAppendStateCall_evaluates
  productionRhsLength : TheoremReference
    (@Lanius.Extraction.ParserAccessors.extractedParserRhsLengthCall_reads_encoded)
  productionRhsSymbol : TheoremReference
    (@Lanius.Extraction.ParserAccessors.extractedParserRhsSymbolCall_reads_encoded)
  productionLhs : TheoremReference
    (@Lanius.Extraction.ParserAccessors.extractedParserLhsCall_reads_encoded)
  scanTerminal : TheoremReference
    (@Lanius.Extraction.ParserScan.extractedParserScanTerminalCall_implements_model)
  appendOrFull : TheoremReference
    Lanius.Extraction.ParserResult.extractedParserAppendOrFullCall_contract
  recognizeSoundness : TheoremReference
    (@Lanius.Extraction.ParserRecognize.RecognizerCallExecution.success_recognizesInput)

private theorem exactCoverage : Coverage :=
  Classical.choice complete

theorem semantics_complete : Nonempty SemanticCoverage := by
  exact ⟨{
    exact := exactCoverage
    parseStatus := reference
      Lanius.Extraction.Parser.ResultAccessors.parseStatusCall_soundness
    parseStateCount := reference
      Lanius.Extraction.Parser.ResultAccessors.parseStateCountCall_soundness
    parseRootState := reference
      Lanius.Extraction.Parser.ResultAccessors.parseRootStateCall_soundness
    parseErrorPosition := reference
      Lanius.Extraction.Parser.ResultAccessors.parseErrorPositionCall_soundness
    parseResult := reference
      Lanius.Extraction.ParserResult.extractedParserParseResultCall_contract
    stateSeed := reference
      Lanius.Extraction.ParserAppend.extractedParserStateSeedCall_contract
    appendResult := reference
      Lanius.Extraction.ParserAppend.extractedParserAppendResultCall_contract
    rangeValid := reference
      Lanius.Extraction.ParserRange.FunctionalView.call_soundness
    grammarIsValid := reference
      (@Lanius.Extraction.ParserValidation.FunctionalView.call_soundness)
    chartWord := reference
      Lanius.Extraction.ParserReads.Functional.ChartWord.call_soundness
    stateWord := reference
      Lanius.Extraction.ParserReads.Functional.StateWord.call_soundness
    stateValue := reference
      Lanius.Extraction.ParserReads.Functional.StateValue.genericCall_soundness
    findState := reference
      (@Lanius.Extraction.ParserFind.Functional.Call.soundness)
    appendState := reference
      Lanius.Extraction.ParserAppend.extractedParserAppendStateCall_evaluates
    productionRhsLength := reference
      (@Lanius.Extraction.ParserAccessors.extractedParserRhsLengthCall_reads_encoded)
    productionRhsSymbol := reference
      (@Lanius.Extraction.ParserAccessors.extractedParserRhsSymbolCall_reads_encoded)
    productionLhs := reference
      (@Lanius.Extraction.ParserAccessors.extractedParserLhsCall_reads_encoded)
    scanTerminal := reference
      (@Lanius.Extraction.ParserScan.extractedParserScanTerminalCall_implements_model)
    appendOrFull := reference
      Lanius.Extraction.ParserResult.extractedParserAppendOrFullCall_contract
    recognizeSoundness := reference
      (@Lanius.Extraction.ParserRecognize.RecognizerCallExecution.success_recognizesInput)
  }⟩

end Lanius.Extraction.Parser.FunctionalViewCoverage
