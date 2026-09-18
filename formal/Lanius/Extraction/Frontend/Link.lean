import Lanius.Extraction.Frontend.Call
import Lanius.Core.Relocation.Permutation
import Lanius.Semantics.CellRenaming.Execution.Check

namespace Lanius.Extraction.Frontend
open Lanius Lanius.Core Lanius.Semantics
open Lanius.Extraction.CoreSynthesis.Program
open Lanius.Extraction.ParserTreeSource Lanius.Extraction.ParserDerivation

private structure LexerMapping where
  functions : List (Nat × Nat) := []
  constants : List (Nat × Nat) := []
  types : List (Nat × Nat) := []
  replaced : List Nat := []

private def LexerMapping.symbols (mapping : LexerMapping) : Core.Relocation.Symbols :=
  let lookup := fun (entries : List (Nat × Nat)) (id : Nat) =>
    ((entries.find? fun pair => pair.1 == id).map Prod.snd).getD id
  ⟨Core.Relocation.permuteTypes mapping.types, lookup mapping.functions, lookup mapping.constants⟩

/-- Propose source-name mappings from the very pack used by the old lexer
theorems. These are only candidates: the complete dependency and relocation
check below authenticates them against both actual Core programs. No external
JSON file, old executable, or assumed symbol correspondence is needed. -/
private def lexerMapping? (program : CheckedProgram artifacts) : Option LexerMapping := do
  let mut mapping : LexerMapping := {}
  for unit in verifiedFrontendPack.units do
    let source ← unit.sources.head?
    let name := (((source.path.splitOn "/").getLast!).dropEnd 5).toString
    let allocation ← program.prepared.allocations.find?
      (fun allocation => allocation.unit.modulePath == ["verified", name])
    let fragment ← unit.core_program
    let surface ← unit.surface
    let declarations := ScopedSurface.collectFunctions surface.value.items
    if declarations.length != fragment.functions.length || !fragment.enumerations.isEmpty then
      failure
    if name == "canonical_tokens" then
      mapping := { mapping with replaced := mapping.replaced ++ fragment.functions.map (·.id) }
    for (declaration, (_, sourceFunction)) in fragment.functions.zip declarations do
      let current ← checkSourceFunction? program ["verified", name] sourceFunction.name.text
      mapping := { mapping with functions := mapping.functions ++ [(declaration.id, current.source.id)] }
    mapping := { mapping with
      constants := mapping.constants ++ fragment.constants.zipIdx.map
        (fun (declaration, index) => (declaration.id, allocation.constantIdStart + index))
      types := mapping.types ++ fragment.structures.zipIdx.map
        (fun (declaration, index) => (declaration.id, allocation.structureTypeStart + index)) }
  pure mapping

/-- Construct the public frontend's proof links from its checked source.
The old lexer and parser bodies must match under dependency-closed relocation;
the changed canonicalizer must match its separate, complete execution proof.
Every helper identity is checked against the actual `extract_syntax` body. -/
def checkLinkedSyntax? {program : CheckedProgram artifacts}
    {visit : CheckedVisit program} {materializer : CheckedMaterialize visit}
    (checked : CheckedSyntax materializer) : Option (LinkedSyntax checked) := do
  let mapping ← lexerMapping? program
  let symbols := mapping.symbols
  let allowed := fun id => !mapping.replaced.contains id
  let ⟨invariant⟩ ← Semantics.CellRenaming.Execution.checkSourceProgram? verifiedFrontendCore
  let link ← Semantics.Relocation.checkLink? allowed symbols verifiedFrontendCore program.core
  let countAccessor ← Source.checkProjection? program
    ["verified", "raw_lexer"] "lex_token_count" (symbols.typeId 4) 1
  let matcher ← checkSourceFunction? program ["verified", "canonical_tokens"] "matches_ascii"
  let keywords ← checkSourceFunction? program ["verified", "canonical_tokens"] "keyword_kind"
  let keywordProof ← CanonicalTokens.Dispatch.checkFunction? program.core
    keywords.function.id matcher.function.id
  let kind ← checkSourceFunction? program ["verified", "canonical_tokens"] "canonical_kind"
  let kindProof ← CanonicalTokens.Kind.check? program.core kind.function.id keywordProof
  let trivia ← checkSourceFunction? program ["verified", "canonical_tokens"] "is_trivia"
  let triviaProof ← CanonicalTokens.Trivia.check? program.core trivia.function.id
  let canonicalizer ← checkSourceFunction? program ["verified", "canonical_tokens"] "canonicalize_in_place"
  let canonicalizerProof ← CanonicalTokens.Compaction.checkSource? program.core
    canonicalizer.function.id triviaProof kindProof
  let parserAllocation ← program.prepared.allocations.find?
    (fun allocation => allocation.unit.modulePath == ["verified", "parser"])
  let parserOffset := parserAllocation.structureTypeStart
  let parserCount := verifiedParserCore.structures.length
  let parserSymbols : Core.Relocation.Symbols := {
    typeId := Core.Relocation.rotateTypes parserOffset parserCount
    functionId := (parserAllocation.functionIdStart + ·)
    constantId := (parserAllocation.constantIdStart + ·) }
  let reader ← ParserDerivation.checkLinkedReader? visit.reader (fun _ => true) parserSymbols
    (Core.Relocation.rotateTypes_injective parserOffset parserCount)
  if identities : allowed RawLexer.LexInto.Functions.lexIntoFunction.id = true ∧
      checked.symbols.lexer = symbols.functionId RawLexer.LexInto.Functions.lexIntoFunction.id ∧
      checked.symbols.count = countAccessor.source.function.id ∧
      checked.symbols.resultType = symbols.typeId 4 ∧
      checked.symbols.canonicalize = canonicalizer.function.id ∧
      materializer.parsedType = parserSymbols.typeId 0 ∧
      checked.parserId = parserSymbols.functionId extractedParserRecognizeFunction.id ∧
      checked.parserType = parserSymbols.typeId 0 then
    let ⟨lexerRetained, lexerId, countId, resultType, canonicalId, parsedType, parserId, parserType⟩ := identities
    pure {
      invariant
      lexerAllowed := allowed
      lexerSymbols := symbols
      lexerLink := link
      lexerInjective := Core.Relocation.permuteTypes_injective mapping.types
      lexerInverseType := Core.Relocation.permuteTypes mapping.types.reverse
      lexerInverse := by
        intro id
        change Core.Relocation.permuteTypes mapping.types
          (Core.Relocation.permuteTypes mapping.types.reverse id) = id
        simpa only [List.reverse_reverse] using Core.Relocation.permuteTypes_inverse mapping.types.reverse id
      lexerRetained, countAccessor, lexerId, countId, resultType
      triviaId := trivia.function.id
      kindId := kind.function.id
      keywordId := keywords.function.id
      matcher := matcher.function.id
      canonicalizer := by rw [canonicalId]; exact canonicalizerProof
      parserAllowed := fun _ => true
      parserSymbols, reader, parsedType, parserId, parserType
      parserInverseType := Core.Relocation.rotateTypes parserCount parserOffset
      parserInverse := Core.Relocation.rotateTypes_inverse parserCount parserOffset
      parserRetained := rfl }
  else none

end Lanius.Extraction.Frontend
