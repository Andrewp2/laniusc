import Lanius.Extraction.ExtractorContract
import Lanius.Extraction.CoreDecode
import Lanius.Core.Relocation.Permutation
import Lanius.Core.Relocation.Program
import Lanius.Semantics.Relocation.Execution
import Lanius.Semantics.Relocation.Link
import Lanius.Extraction.RawLexer.LexInto.Functions
import Lanius.Extraction.ArtifactPackChecker
import Lanius.Semantics.CellRenaming.Execution.Check
import Lanius.Extraction.BufferCopy.CanonicalizeSource
import Lanius.Extraction.BufferCopy.RecognizeSource
import Lanius.Extraction.Parser.Derivation.Source
import Lanius.Extraction.Parser.Derivation.Transport
import Lanius.Extraction.Parser.Tree.Source
import Lanius.Extraction.Parser.Tree.MaterializeSource
import Lanius.Extraction.Parser.Tree.Root
import Lanius.Extraction.Frontend.Source
import Lanius.Extraction.Frontend.Lexer
import Lanius.Extraction.Frontend.Canonicalize
import Lanius.Extraction.Frontend.Pipeline
import Lanius.Extraction.Frontend.Tree
import Lanius.Extraction.Frontend.Syntax
import Lanius.Extraction.Frontend.Call
import Lanius.Extraction.Tests.SemanticTokens
import Lanius.Extraction.SemanticTokens.Pipeline
import Lanius.Extraction.Tests.CompactOutput
import Lanius.Extraction.Tests.CompactOutput.Word

/-! Check exact frontend relocation and the assumptions of the generic
execution-transport theorem against the actual self-embedding. This is not
the whole extractor's correctness proof. -/

open Lanius Lanius.Core Lanius.Extraction Lanius.Extraction.ExtractorContract
open Lanius.Extraction.EntrypointAnalysis

private structure Offsets where
  function : Nat
  constant : Nat
  typeId : Nat
  typeCount : Nat

private def Offsets.symbols (offsets : Offsets) : Relocation.Symbols :=
  ⟨Relocation.rotateTypes offsets.typeId offsets.typeCount,
    (offsets.function + ·), (offsets.constant + ·)⟩

def main (arguments : List String) : IO UInt32 := do
  let modulePath :: oldDirectory :: paths := arguments
    | throw (IO.userError "expected self-module, old artifact directory, then ordered source paths")
  let emitted ← IO.FS.readFile modulePath
  unless emitted.startsWith modulePrefix && emitted.endsWith moduleSuffix do
    throw (IO.userError "self-module framing differs from the extraction contract")
  let encoded := ((emitted.drop modulePrefix.length).dropEnd moduleSuffix.length).toString
  let sources ← paths.mapM fun (path : String) => do
    let bytes ← IO.FS.readBinFile path
    pure ({ path, bytes := bytes.toList.map UInt8.toNat } : SourceFile)
  let .success checked := checkExtractorCoreSourcePack encoded sources
    | throw (IO.userError "self-embedding rejected")
  let some collector := SemanticTokens.Collect.checkCollect? checked.checked.program
    | throw (IO.userError "current collector failed its complete body/signature/tag check")
  Tests.SemanticTokens.checkCollectExecution checked.checked.program.core collector.source.function.id
  IO.println "Whole semantic collector checked: ten parameters, all guards, initialization, record/child loops, final validation, and both tag constants."
  IO.println "Current Lanius semantic collector passed split-postorder, capacity, malformed-kind, and caller-frame executions."
  let some byte := CompactOutput.checkByte? checked.checked.program
    | throw (IO.userError "output.byte differs from its proved complete function")
  let some digit := CompactOutput.checkDigit? checked.checked.program
    | throw (IO.userError "compact hex_digit differs from its proved complete function")
  let some hexByte := CompactOutput.checkHexByte? checked.checked.program byte digit
    | throw (IO.userError "compact hex_byte differs from its proved complete function or calls different helpers")
  have _hexByteCall := fun {caller before : Semantics.State} {arguments : List Expr}
      {outputCell : CellId} {original : List Int} =>
    CompactOutput.CheckedHexByte.write (caller := caller) (before := before)
      (arguments := arguments) (outputCell := outputCell) (original := original) hexByte
  Tests.CompactOutput.checkExecution checked.checked.program.core byte.source.function.id digit.source.function.id hexByte.source.function.id
  IO.println "Current output.byte, hex_digit, and hex_byte match complete proved functions. All 256 bytes, capacity/partial-output errors, invalid values, and caller frames checked; public hex_byte theorem instantiated."
  let some word := CompactOutput.Word.check? checked.checked.program byte digit
    | throw (IO.userError "compact hex_u32 differs from its complete proved function or helper identities")
  have _wordCall := fun {caller before : Semantics.State} {arguments : List Expr}
      {outputCell : CellId} {original : List Int} =>
    CompactOutput.Word.Checked.write (caller := caller) (before := before)
      (arguments := arguments) (outputCell := outputCell) (original := original) word
  let wordCalls ← Tests.CompactOutput.Word.checkExecution checked.checked.program.core word.source.function.id
  IO.println s!"Current hex_u32 complete source and public-call theorem checked: {wordCalls} executions cover fixed width, byte order, all output cutoffs, invalid inputs, and caller frames."
  let some extraction := CoreSynthesis.Program.checkSourceFunction? checked.checked.program
      ["verified", "extraction"] "extract_syntax"
    | throw (IO.userError "checked extract_syntax function was not found")
  let some syntaxBody := extraction.function.body
    | throw (IO.userError "checked extract_syntax has no body")
  let some region := BufferCopy.findCanonicalization? syntaxBody
    | throw (IO.userError "checked extract_syntax lacks the copy/canonicalizer scope and call arguments")
  let some canonicalizer := CoreSynthesis.Program.checkSourceFunction? checked.checked.program
      ["verified", "canonical_tokens"] "canonicalize_in_place"
    | throw (IO.userError "checked canonicalizer was not found")
  unless region.locals.functionId == canonicalizer.function.id do
    throw (IO.userError "copy scope calls a different function, not canonicalize_in_place")
  IO.println s!"Copy/canonicalizer scope checked: function {region.locals.functionId}, result local {region.locals.resultId}."
  let some recognition := BufferCopy.findRecognition? syntaxBody
    | throw (IO.userError "checked extract_syntax lacks the kind-copy/recognizer scope and arguments")
  let some recognizer := CoreSynthesis.Program.checkSourceFunction? checked.checked.program
      ["verified", "parser"] "recognize"
    | throw (IO.userError "checked recognizer was not found")
  unless recognition.locals.functionId == recognizer.function.id do
    throw (IO.userError "kind-copy scope calls a different function, not recognize")
  unless recognition.locals.locals.count == region.locals.resultId &&
      recognition.locals.locals.source == region.locals.locals.destination do
    throw (IO.userError "kind-copy input/count do not come from the canonicalizer")
  IO.println s!"Kind-copy/recognizer scope checked: function {recognition.locals.functionId}, canonicalizer result supplies logical token count."
  let some reader := ParserDerivation.checkReader? checked.checked.program
    | throw (IO.userError "current derivation reader failed source/body/arity reification checks")
  IO.println s!"Current derivation reader {reader.source.function.id}: complete body reified with exact Core lowering evidence."
  let some tree := ParserTreeSource.checkVisit? checked.checked.program reader
    | throw (IO.userError "current tree materializer failed complete visit/constructor/source checks")
  IO.println s!"Current tree visit {tree.source.function.id}: full body, recursive call, reader call, statuses, and result constructor match checked source."
  let some materializer := ParserTreeSource.checkMaterialize? tree
    | throw (IO.userError "current materialize wrapper or parser-result accessors failed source checks")
  IO.println s!"Current materialize {materializer.source.function.id}: full body and parser status/count/root accessor calls match checked source."
  for (name, field) in [("tree_status", 0), ("tree_node_count", 1), ("tree_words_used", 2)] do
    let some _projection := Source.checkProjection? checked.checked.program
        ["verified", "parse_tree"] name tree.symbols.resultType field
      | throw (IO.userError s!"current {name} result projection failed source checks")
  IO.println "Tree result status/count/word projections match checked source."
  let some _rootAccessor := ParserTreeSource.checkRoot? tree
    | throw (IO.userError "current tree_root success/subtraction/sentinel body failed source checks")
  IO.println "Tree root accessor: success subtraction and failure sentinel match checked source."
  for (label, readScale, countScale) in
      [("raw words", BufferCopy.Scale.plain, BufferCopy.Scale.triple),
       ("token kinds", BufferCopy.Scale.triple, BufferCopy.Scale.plain)] do
    let some copied := Source.findStatement? BufferCopy.Locals.loop (fun statement => do
        let checked ← BufferCopy.checkLoop? statement
        if checked.locals.readScale = readScale ∧ checked.locals.countScale = countScale then
          some checked
        else none) syntaxBody
      | throw (IO.userError s!"checked extract_syntax lacks the exact {label} copy loop")
    IO.println s!"Checked {label} loop: source local {copied.locals.source}, destination local {copied.locals.destination}, cursor {copied.locals.cursor}."
  let mut mismatches := 0
  for name in ["lexer", "token_scan", "parser"] do
    let some allocation := checked.checked.program.prepared.allocations.find?
        (fun allocation => allocation.unit.modulePath == ["verified", name])
      | throw (IO.userError s!"{name} module not found")
    let oldPath := System.FilePath.mk oldDirectory / (name ++ ".json")
    let oldJson ← IO.ofExcept (Lean.Json.parse (← IO.FS.readFile oldPath))
    let oldCore ← IO.ofExcept (oldJson.getObjValAs? CoreProgram "core_program")
    unless CoreDecode.target oldCore.target == checked.checked.program.core.target do
      throw (IO.userError s!"{name} target differs")
    let offsets : Offsets := ⟨allocation.functionIdStart, allocation.constantIdStart,
      allocation.structureTypeStart, oldCore.structures.length⟩
    let some matching := Relocation.checkProgram? offsets.symbols (CoreDecode.program oldCore)
        checked.checked.program.core
      | throw (IO.userError s!"{name} proof-producing lookup check rejected relocation")
    let some ⟨internal⟩ := Semantics.Relocation.Execution.checkInternal? (CoreDecode.program oldCore)
      | throw (IO.userError s!"{name} requires an external-call transport contract")
    if name == "parser" then
      let some _readerLink := ParserDerivation.checkLinkedReader? reader (fun _ => true) offsets.symbols
          (Relocation.rotateTypes_injective offsets.typeId offsets.typeCount)
        | throw (IO.userError "complete derivation reader execution link rejected")
      IO.println "Complete derivation reader: standalone execution transports to the exact current source body."
    have _preserved : ∀ {before expr value after},
        Semantics.Evaluates (CoreDecode.program oldCore) before expr value after →
        Semantics.Evaluates checked.checked.program.core
          (Semantics.Relocation.state offsets.symbols before) (Relocation.expression offsets.symbols expr)
          (Relocation.value offsets.symbols value) (Semantics.Relocation.state offsets.symbols after) :=
      Semantics.Relocation.Execution.evaluates matching
        (Relocation.rotateTypes_injective offsets.typeId offsets.typeCount) internal
    IO.println s!"{name} relocation offsets: functions={offsets.function}, constants={offsets.constant}, structures={offsets.typeId}"
    let mut matched := 0
    for oldWire in oldCore.functions do
      let old := CoreDecode.function oldWire
      let some current := checked.checked.program.core.function? (offsets.function + old.id)
        | throw (IO.userError s!"missing relocated {name} function {old.id}")
      if Relocation.function offsets.symbols old == current then
        matched := matched + 1
      else
        IO.println s!"{name} function {old.id}: differs after relocation"
        mismatches := mismatches + 1
    IO.println s!"{matched}/{oldCore.functions.length} old {name} functions match"
    for oldWire in oldCore.constants do
      let old := CoreDecode.constant oldWire
      let some current := checked.checked.program.core.constant? (offsets.constant + old.id)
        | throw (IO.userError s!"missing relocated {name} constant {old.id}")
      unless Relocation.constant offsets.symbols old == current do
        throw (IO.userError s!"{name} constant {old.id} differs after relocation")
    for oldWire in oldCore.structures do
      let old := CoreDecode.structDecl oldWire
      let some current := checked.checked.program.core.structure? (offsets.typeId + old.id)
        | throw (IO.userError s!"missing relocated {name} structure {old.id}")
      unless old.fields.map (Relocation.ty offsets.symbols) == current.fields do
        throw (IO.userError s!"{name} structure {old.id} differs after relocation")
    IO.println s!"{name}: {oldCore.constants.length} constants and {oldCore.structures.length} structure layouts match"
  IO.println "Execution-transport assumptions checked for all three internal frontend modules."
  let packJson ← IO.ofExcept (Lean.Json.parse (← IO.FS.readFile
    (System.FilePath.mk oldDirectory / "frontend_pack.json")))
  let oldUnits ← IO.ofExcept (packJson.getObjValAs? (List Lean.Json) "units")
  let mut wire : Option CoreProgram := none
  let mut functions : List (Nat × Nat) := []
  let mut constants : List (Nat × Nat) := []
  let mut types : List (Nat × Nat) := []
  let mut replaced : List Nat := []
  for unitJson in oldUnits do
    let sources ← IO.ofExcept (unitJson.getObjValAs? (List SourceFile) "sources")
    let some source := sources.head? | throw (IO.userError "old frontend unit has no source")
    let name := (((source.path.splitOn "/").getLast!).dropEnd 5).toString
    let some allocation := checked.checked.program.prepared.allocations.find?
        (fun allocation => allocation.unit.modulePath == ["verified", name])
      | throw (IO.userError s!"merged frontend module {name} not found")
    let fragment ← IO.ofExcept (unitJson.getObjValAs? CoreProgram "core_program")
    if name == "canonical_tokens" then
      replaced := replaced ++ fragment.functions.map (·.id)
    wire ← match wire with
      | none => pure (some fragment)
      | some previous =>
          let some merged := ArtifactPackChecker.appendCorePrograms? previous fragment
            | throw (IO.userError "old merged frontend targets disagree")
          pure (some merged)
    let surface ← IO.ofExcept (unitJson.getObjValAs? SurfaceFile "surface")
    let sourceFunctions := ScopedSurface.collectFunctions surface.value.items
    unless sourceFunctions.length == fragment.functions.length do
      throw (IO.userError s!"{name} old source/Core function counts disagree")
    for (declaration, (_, sourceFunction)) in fragment.functions.zip sourceFunctions do
      let some current := CoreSynthesis.Program.checkSourceFunction? checked.checked.program
          ["verified", name] sourceFunction.name.text
        | throw (IO.userError s!"{name}::{sourceFunction.name.text} was not found in the checked source")
      functions := functions ++ [(declaration.id, current.source.id)]
    constants := constants ++ fragment.constants.zipIdx.map
      (fun (declaration, index) => (declaration.id, allocation.constantIdStart + index))
    types := types ++ fragment.structures.zipIdx.map
      (fun (declaration, index) => (declaration.id, allocation.structureTypeStart + index))
    unless fragment.enumerations.isEmpty do
      throw (IO.userError "merged frontend enumeration mapping needs an explicit allocation")
  let some mergedWire := wire | throw (IO.userError "old merged frontend is empty")
  let lookup := fun (entries : List (Nat × Nat)) (id : Nat) =>
    ((entries.find? fun pair => pair.1 == id).map Prod.snd).getD id
  let symbols : Relocation.Symbols := ⟨Relocation.permuteTypes types, lookup functions, lookup constants⟩
  let some tokenization := Frontend.findTokenization? syntaxBody
    | throw (IO.userError "checked extract_syntax lacks the complete lexer/guards/copy/canonicalizer source sequence")
  let some recognitionStage := Frontend.checkRecognitionStage? tokenization.locals.rest
    | throw (IO.userError "canonicalization is not followed immediately by the proved kind guard/copy/recognizer source sequence")
  unless recognitionStage.locals.functionId == recognizer.function.id &&
      Ty.structure recognitionStage.locals.resultType == recognizer.function.returnType do
    throw (IO.userError "recognition continuation calls a different parser or binds a different result type")
  let some ⟨afterParse, tailExact⟩ := Frontend.checkAfterParse? materializer recognitionStage.locals.rest
    | throw (IO.userError "parse guard/materializer/result tail differs from the complete checked source")
  have _joinedSource := Frontend.syntax_source_sequence tokenization recognitionStage afterParse tailExact.equal
  let some early := Frontend.checkEarly? afterParse.finish.constructor tokenization.locals recognitionStage.locals
    | throw (IO.userError "early lexer/canonical/kind failure returns differ from the checked result fields")
  have _allSource := Frontend.syntax_source_all tokenization recognitionStage afterParse tailExact.equal early
  let some publicSyntax := Frontend.checkSyntax? materializer
    | throw (IO.userError "the whole extract_syntax signature/body does not match the proved public function")
  unless publicSyntax.parserId == recognizer.function.id && publicSyntax.parserType == recognitionStage.locals.resultType do
    throw (IO.userError "public extract_syntax uses a different parser or parsed-result type")
  let syntaxRest := Frontend.tokenizationBody publicSyntax.symbols publicSyntax.early.lexicalBody publicSyntax.early.canonicalBody
    (Frontend.recognitionBody publicSyntax.parserId publicSyntax.parserType publicSyntax.early.kindsBody publicSyntax.tail.body)
  let reordered := Frontend.inputGuards publicSyntax.tail.finish.constructor.source.function.id publicSyntax.inputs.badInput
    (Frontend.inputLengths.reverse) syntaxRest
  let inserted := Stmt.sequence .skip (publicSyntax.inputs.body syntaxRest)
  unless (Frontend.checkInput? publicSyntax.tail.finish.constructor reordered syntaxRest).isNone &&
      (Frontend.checkInput? publicSyntax.tail.finish.constructor inserted syntaxRest).isNone do
    throw (IO.userError "whole-body checker accepted reordered input guards or an extra leading statement")
  IO.println "Whole extract_syntax checked: 17-parameter signature, eight ordered input guards, and every lexer-to-return branch."
  let swappedTokenization := { tokenization.locals with storageFailure := early.checked.kindsBody }
  let swappedRecognition := { recognitionStage.locals with storageFailure := early.checked.canonicalBody }
  unless (Frontend.checkEarly? afterParse.finish.constructor swappedTokenization recognitionStage.locals).isNone &&
      (Frontend.checkEarly? afterParse.finish.constructor tokenization.locals swappedRecognition).isNone do
    throw (IO.userError "early-return checker accepted interchanged canonical/kind storage result fields")
  IO.println "All early failure fields checked against the final result constructor; interchanged storage branches rejected."
  IO.println "Joined lexer-to-return statement occurs in current extract_syntax with checked adjacent source equality."
  IO.println "Complete parse tail checked: parser failure fields, nine materializer arguments, stage assignment, result constructor, and seven returned fields."
  let wrongArguments := Frontend.materializeArguments.set 3 (.local 18)
  let wrongCount : Stmt := .sequence (.ifThenElse afterParse.condition afterParse.rejected .skip)
    (.letLocal 23 (.structure tree.symbols.resultType) (.call materializer.source.function.id wrongArguments)
      (Frontend.finishBody afterParse.finish.symbols))
  let wrongStage := Frontend.finishBody { afterParse.finish.symbols with failure := afterParse.finish.successId }
  unless (Frontend.checkAfterParse? materializer wrongCount).isNone &&
      (Frontend.checkFinish? tree wrongStage).isNone do
    throw (IO.userError "source matcher accepted a raw-count materializer argument or success-tagged tree failure")
  IO.println "Contiguous lexer-to-recognizer source checked: canonical count, kind capacity guard, copy stride, six arguments, and parsed-result binding."
  let some countAccessor := Source.checkProjection? checked.checked.program
      ["verified", "raw_lexer"] "lex_token_count" (symbols.typeId 4) 1
    | throw (IO.userError "current lex_token_count accessor failed exact source checks")
  let some statusAccessor := Source.checkProjection? checked.checked.program
      ["verified", "raw_lexer"] "lex_status" (symbols.typeId 4) 0
    | throw (IO.userError "current lex_status accessor failed exact source checks")
  let some _success := ParserTreeSource.checkConstantValue? checked.checked.program.core
      tokenization.locals.symbols.success 0
    | throw (IO.userError "lexer success guard does not compare with the zero success constant")
  unless tokenization.locals.symbols.lexer == symbols.functionId RawLexer.LexInto.Functions.lexIntoFunction.id &&
      tokenization.locals.symbols.count == countAccessor.source.function.id &&
      tokenization.locals.symbols.status == statusAccessor.source.function.id &&
      tokenization.locals.symbols.resultType == symbols.typeId 4 &&
      tokenization.locals.symbols.canonicalize == canonicalizer.function.id do
    throw (IO.userError "tokenization source sequence calls different functions or uses a different result type")
  let some matcher := CoreSynthesis.Program.checkSourceFunction? checked.checked.program
      ["verified", "canonical_tokens"] "matches_ascii"
    | throw (IO.userError "canonical ASCII matcher was not found")
  let some keywords := CoreSynthesis.Program.checkSourceFunction? checked.checked.program
      ["verified", "canonical_tokens"] "keyword_kind"
    | throw (IO.userError "canonical keyword dispatcher was not found")
  let some keywordProof := CanonicalTokens.Dispatch.checkFunction? checked.checked.program.core
      keywords.function.id matcher.function.id
    | throw (IO.userError "canonical keyword dispatch/reference proof check rejected")
  let some kind := CoreSynthesis.Program.checkSourceFunction? checked.checked.program
      ["verified", "canonical_tokens"] "canonical_kind"
    | throw (IO.userError "canonical_kind was not found")
  let some kindProof := CanonicalTokens.Kind.check? checked.checked.program.core kind.function.id keywordProof
    | throw (IO.userError "canonical_kind differs from its proved source")
  let some trivia := CoreSynthesis.Program.checkSourceFunction? checked.checked.program
      ["verified", "canonical_tokens"] "is_trivia"
    | throw (IO.userError "canonical trivia classifier was not found")
  let some triviaProof := CanonicalTokens.Trivia.check? checked.checked.program.core trivia.function.id
    | throw (IO.userError "canonical trivia classifier differs from its proved source")
  let some canonicalizerProof := CanonicalTokens.Compaction.checkSource? checked.checked.program.core
      canonicalizer.function.id triviaProof kindProof
    | throw (IO.userError "canonicalizer differs from the complete proved source")
  IO.println "Complete tokenization prefix checked: lexer/count, status and capacity guards, raw copying, and canonicalization share exact source scopes and bindings."
  IO.println "Status/count accessors, zero success constant, and complete canonicalizer/helper proofs match current source."
  -- Link the exact program used by the public correctness theorem, not just
  -- a separately decoded JSON value with a similar inventory.
  let oldProgram := verifiedFrontendCore
  let some ⟨cellInvariant⟩ := Semantics.CellRenaming.Execution.checkSourceProgram? oldProgram
    | throw (IO.userError "frontend contains a runtime-cell literal or a missing function body")
  have _allCellLayouts := cellInvariant
  IO.println "Frontend source invariance checked for every cell renaming."
  let allowed := fun id => !replaced.contains id
  let retained := Dependencies.restrict oldProgram allowed
  unless allowed RawLexer.LexInto.Functions.lexIntoFunction.id do
    throw (IO.userError "raw-lexer entrypoint was excluded from proof transport")
  let some link := Semantics.Relocation.checkLink? allowed symbols oldProgram checked.checked.program.core
    | do
      for function in retained.functions do
        let current := checked.checked.program.core.function? (symbols.functionId function.id)
        unless current == some (Relocation.function symbols function) do
          IO.println s!"merged frontend function {function.id} differs at destination {symbols.functionId function.id}"
      throw (IO.userError "merged frontend proof-producing relocation check rejected")
  have _preserved : ∀ {before expr value after}, Semantics.Evaluates oldProgram before expr value after →
      Dependencies.expression allowed expr = true →
      Semantics.Evaluates checked.checked.program.core (Semantics.Relocation.state symbols before)
        (Relocation.expression symbols expr) (Relocation.value symbols value)
        (Semantics.Relocation.state symbols after) :=
    link.evaluates (Relocation.permuteTypes_injective types)
  have _inverse : Function.RightInverse (Relocation.permuteTypes types.reverse) symbols.typeId := by
    intro id
    simpa only [List.reverse_reverse] using Relocation.permuteTypes_inverse types.reverse id
  let some parserAllocation := checked.checked.program.prepared.allocations.find?
      (fun allocation => allocation.unit.modulePath == ["verified", "parser"])
    | throw (IO.userError "current parser allocation is absent")
  let parserOffsets : Offsets := ⟨parserAllocation.functionIdStart, parserAllocation.constantIdStart,
    parserAllocation.structureTypeStart, verifiedParserCore.structures.length⟩
  let some readerLink := ParserDerivation.checkLinkedReader? tree.reader (fun _ => true) parserOffsets.symbols
      (Relocation.rotateTypes_injective parserOffsets.typeId parserOffsets.typeCount)
    | throw (IO.userError "public call's complete reader link rejected")
  if identities : allowed RawLexer.LexInto.Functions.lexIntoFunction.id = true ∧
      publicSyntax.symbols.lexer = symbols.functionId RawLexer.LexInto.Functions.lexIntoFunction.id ∧
      publicSyntax.symbols.count = countAccessor.source.function.id ∧
      publicSyntax.symbols.resultType = symbols.typeId 4 ∧
      publicSyntax.symbols.canonicalize = canonicalizer.function.id ∧
      materializer.parsedType = parserOffsets.symbols.typeId 0 ∧
      publicSyntax.parserId = parserOffsets.symbols.functionId extractedParserRecognizeFunction.id ∧
      publicSyntax.parserType = parserOffsets.symbols.typeId 0 then
    let ⟨retained, lexerId, countId, resultType, canonicalId, parsedType, parserId, parserType⟩ := identities
    let linked : Frontend.LinkedSyntax publicSyntax := {
      invariant := cellInvariant
      lexerAllowed := allowed
      lexerSymbols := symbols
      lexerLink := link
      lexerInjective := Relocation.permuteTypes_injective types
      lexerInverseType := Relocation.permuteTypes types.reverse
      lexerInverse := _inverse
      lexerRetained := retained
      countAccessor, lexerId, countId, resultType
      triviaId := trivia.function.id
      kindId := kind.function.id
      keywordId := keywords.function.id
      matcher := matcher.function.id
      canonicalizer := by rw [canonicalId]; exact canonicalizerProof
      parserAllowed := fun _ => true
      parserSymbols := parserOffsets.symbols
      reader := readerLink
      parsedType, parserId, parserType
      parserInverseType := Relocation.rotateTypes parserOffsets.typeCount parserOffsets.typeId
      parserInverse := Relocation.rotateTypes_inverse parserOffsets.typeCount parserOffsets.typeId
      parserRetained := rfl
    }
    have _publicCall := fun {caller before : Semantics.State} {arguments : List Expr} =>
      publicSyntax.call_evaluates (caller := caller) (before := before) (arguments := arguments) linked
    IO.println "Public call theorem instantiated with the current whole-function source, lexer/canonicalizer/parser links, and type inverses."
    have _frontendCollector := fun {caller before : Semantics.State} {arguments : List Expr}
        {outputCell : CellId} {original : List Int} =>
      SemanticTokens.frontend_then_collect (caller := caller) (before := before)
        (arguments := arguments) (outputCell := outputCell) (original := original)
        publicSyntax linked collector
    IO.println "Frontend-to-collector call theorem instantiated with both complete current functions: returned counts/tree determine collector inputs; output capacity determines success or unchanged-output rejection."
  else
    throw (IO.userError "public call's component identities differ from the checked links")
  IO.println s!"Merged frontend: {retained.functions.length}/{oldProgram.functions.length} dependency-closed functions and {oldProgram.constants.length} constants have checked execution transport; {replaced.length} canonicalization helpers are excluded."
  IO.println "Whole frontend function source linkage is checked; compact emission, main, and the final extractor contracts remain separate obligations."
  return if mismatches == 0 then 0 else 1
