import Lanius.Extraction.Frontend.Storage.Tree
import Lanius.Extraction.Frontend.Storage.Artifact
import Lanius.Extraction.CompactOutput.Size

namespace Lanius.Extraction.Frontend
open Lanius.Compiler Lanius.Compiler.Lexer Lanius.Compiler.Parser
open Lanius.Extraction.ParserTreeLayout Lanius.Extraction.CompactOutput.Size

/-- An output bound stated only in terms of source bytes and their language
semantics. It covers every recognized tree, not a tree selected by an
untrusted executable, and assumes no successful extraction or output check. -/
def SourceOutputBound (file : SourceFile) (bound : Nat) : Prop :=
  ∀ source raw tokens, decodeBytes file.bytes = some source →
    lexRaw source = .success raw → lexCanonical source = .success tokens →
    ∀ grammar : IndexedGrammar, grammar.grammar = laniusGrammar →
      ∀ parse : MaterializedParse grammar (tokens.map (fun token => token.kind.gpuCode)),
        unitBytes file.path.toUTF8.size source.length raw.length tokens.length
          (treeFrom 0 0 parse.tree).words.length (treeFrom 0 0 parse.tree).offsets.length ≤ bound

inductive SourcesOutputBounds : List SourceFile → List Nat → Prop where
  | nil : SourcesOutputBounds [] []
  | cons (head : SourceOutputBound file bound) (tail : SourcesOutputBounds files bounds) :
      SourcesOutputBounds (file :: files) (bound :: bounds)

theorem SourcesOutputBounds.append (first : SourcesOutputBounds files bounds)
    (second : SourcesOutputBounds moreFiles moreBounds) :
    SourcesOutputBounds (files ++ moreFiles) (bounds ++ moreBounds) := by
  induction first with
  | nil => exact second
  | cons head tail ih => exact .cons head ih

structure CheckedOutputStorage (sources : List SourceFile) where
  bounds : List Nat
  valid : SourcesOutputBounds sources bounds

/-- Raw rows have already been checked by the token checker. Retain and use
that evidence; this resource pass only reads lengths and tight tree budgets. -/
def checkArtifactOutputStorage? (artifact : Artifact) (valid : TokenArtifactValid artifact)
    (storage : CheckedParserTreeStorage artifact workspaceWords recordWords nodeSlots depth) :
    Option (CheckedOutputStorage artifact.sources) :=
  match sources : artifact.sources, rawRowsFound : artifact.raw_tokens with
  | [file], some rawRows =>
      let bound := unitBytes file.path.toUTF8.size file.bytes.length rawRows.length artifact.tokens.length
        storage.words storage.nodes
      some ⟨[bound], by
        refine .cons ?_ .nil
        intro source raw tokens decoded rawLexical lexical grammar identity parse
        obtain ⟨checkedSource, checkedTokens, _, sourceDecoded, tokensDecoded, canonical, rawValid⟩ := valid
        have sourceSame : checkedSource = source := Option.some.inj
          ((by simpa only [sources, decodeSingleSource] using sourceDecoded : decodeBytes file.bytes = some checkedSource).symm.trans decoded)
        subst checkedSource
        have tokensSame := RawLexResult.success.inj (canonical.symm.trans lexical)
        subst checkedTokens
        obtain ⟨checkedRaw, rawDecoded, checkedLexical⟩ := rawValid rawRows rawRowsFound
        have rawSame := RawLexResult.success.inj (checkedLexical.symm.trans rawLexical)
        subst checkedRaw
        obtain ⟨treeSource, treeTokens, treeDecoded, treeLexical, treesFit⟩ :=
          storage.trees file (by simp only [sources, List.mem_singleton])
        have sameSource := Option.some.inj (treeDecoded.symm.trans decoded)
        subst treeSource
        have sameTokens := RawLexResult.success.inj (treeLexical.symm.trans lexical)
        subst treeTokens
        have fit := treesFit grammar identity parse
        have treeBound := treeBytes_mono fit.2.1 fit.2.2
        have sourceLength := decode_length decoded
        have rawLength := decode_length rawDecoded
        have tokenLength := decode_length tokensDecoded
        dsimp only [unitBytes, bound]
        omega⟩
  | _, _ => none

def checkUnitsOutputStorage? :
    {artifacts : List Artifact} → CheckedParserTrees workspaceWords recordWords nodeSlots depth artifacts →
      (∀ artifact ∈ artifacts, TokenArtifactValid artifact) →
      Option (CheckedOutputStorage (artifacts.flatMap (·.sources)))
  | [], .nil, _ => some ⟨[], .nil⟩
  | _ :: _, .cons head tail, valid => do
      let first ← checkArtifactOutputStorage? _ (valid _ (by simp)) head
      let rest ← checkUnitsOutputStorage? tail (fun artifact member => valid artifact (by simp [member]))
      pure ⟨first.bounds ++ rest.bounds, first.valid.append rest.valid⟩

end Lanius.Extraction.Frontend
