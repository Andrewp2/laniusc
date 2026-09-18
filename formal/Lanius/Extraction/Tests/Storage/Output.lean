import Lanius.Extraction.Entry.Domain.Output
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Storage.Output
open Lanius.Compiler Lanius.Compiler.Lexer Lanius.Compiler.Parser
open Lanius.Extraction.Frontend Lanius.Extraction.SemanticTokens
open Lanius.Extraction.ParserTreeLayout Lanius.Extraction.CompactOutput

private def grammar : IndexedGrammar := ⟨{
  n_kinds := 1, n_nonterminals := 1, start_nonterminal := 0,
  split_token_kind := 44, split_component_kind := 13, canonical_kinds := [13],
  productions := [⟨0, [0,0]⟩] }, []⟩

-- Compare the size algebra to the real serializers across empty, wide,
-- nested, terminal and split-reference layouts, including UTF-8 paths.
#eval (do
  for width in [:9] do
    let leaf : Lanius.Compiler.Parser.ParseTree := .nonterminal 0 0 0 0 []
    let flat : Lanius.Compiler.Parser.ParseTree := .nonterminal 0 0 0 (2 * width)
      (List.replicate width (.terminal 0 0))
    let mixed : Lanius.Compiler.Parser.ParseTree := .nonterminal 0 0 0 (2 * width)
      [.terminal 0 0, leaf, flat, .terminal 0 0]
    for tree in [leaf, flat, mixed, .terminal 0 0] do
      let layout := treeFrom 0 0 tree
      let records := (treeVisits grammar [44] 0 0 0 tree).1
      unless (Nodes.encodeAll records).length == Size.treeBytes layout.words.length layout.offsets.length do
        throw (IO.userError "tree wire-size formula differs from the actual serializer")
      for path in ["", "unit.lani", "λ/δ.lani"] do
        let tokens : List RawToken := List.replicate width ⟨.identifier, 0, 1⟩
        let unit : CompactDecode.UnitData := {
          path, source := "x += 1;".toUTF8,
          raw := ⟨.whitespace, 0, 1⟩ :: tokens, tokens,
          assignments := List.replicate width ⟨0, some 0⟩, nodes := records }
        let bound := Size.unitBytes unit.path.toUTF8.size unit.source.size unit.raw.length unit.tokens.length
          layout.words.length layout.offsets.length
        unless unit.encoding.length == bound do
          throw (IO.userError "unit wire-size formula differs from the actual serializer")
  IO.println "Output-size algebra matches serializers across empty, wide, nested, split-reference and UTF-8 fixtures." : IO Unit)

/-- Reuse the existing accepted unit and its checked tree budget. Missing raw
evidence must fail closed, even though canonical-only syntax remains valid. -/
def checkRawEvidence : {artifacts : List Artifact} →
    ArtifactPackChecker.CheckedUnitSurfaces artifacts →
    CheckedParserTrees 4194304 1048576 65536 1024 artifacts → IO Unit
  | [], .nil, .nil => pure ()
  | [artifact], .cons head .nil, .cons stored .nil => do
      let missing := {artifact with raw_tokens := none}
      have missingValid : TokenArtifactValid missing := by
        obtain ⟨source, tokens, version, decoded, rows, lexical, _⟩ := head.valid.1.1
        refine ⟨source, tokens, version, decoded, rows, lexical, ?_⟩
        intro raw found
        cases found
      let missingStorage : CheckedParserTreeStorage missing 4194304 1048576 65536 1024 :=
        ⟨stored.words, stored.nodes, stored.depth, stored.fits, stored.parser, stored.trees⟩
      unless (checkArtifactOutputStorage? missing missingValid missingStorage).isNone do
        throw (IO.userError "output bound accepted without authenticated raw rows")
      unless (checkArtifactOutputStorage? artifact head.valid.1.1 stored).isSome do
        throw (IO.userError "output bound rejected existing authenticated raw rows")
      unless !checkTokenArtifact {artifact with raw_tokens := some [⟨999999, ⟨0, 0, 1⟩⟩]} do
        throw (IO.userError "forged raw-token evidence accepted")
  | _ :: _ :: _, .cons _ tail, .cons _ stored => checkRawEvidence tail stored

def checkCapacity (storage : CheckedOutputStorage sources) : IO Unit := do
  let required := Entry.moduleFramingBytes + storage.bounds.sum
  unless (Entry.checkOutputCapacity? storage required).isSome do
    throw (IO.userError "exact-fit output capacity rejected")
  unless (Entry.checkOutputCapacity? storage (required - 1)).isNone do
    throw (IO.userError "one-byte-short output capacity accepted")
  IO.println "Source-bound output checking accepts exact fits and rejects one-byte shortages, missing raw evidence, and forged raw tokens."

run_elab do
  let standard := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``Size.tree_encoding_size, ``Size.forest_encoding_size, ``Size.collection_encoding_size,
      ``Size.emission_encoding_size, ``Size.treeBytes_mono,
      ``checkArtifactOutputStorage?, ``checkUnitsOutputStorage?, ``Entry.checkOutputCapacity?,
      ``Entry.CheckedTreeDomain.checkOutputDomain?, ``Entry.File.Resources.encoding_bound,
      ``checkTokenArtifact_sound, ``CheckedParserTrees.domains] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption do
        throwError "Output resource proof {name} adds unexpected axiom {assumption}"
  Lean.logInfo "Output-size, ordered source budgets, and actual-emitter bounds use only standard Lean axioms."

end Lanius.Extraction.Tests.Storage.Output
