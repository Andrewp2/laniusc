import Lanius.Extraction.Entry.Domain.Syntax
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Parser.Language
open Lanius.Compiler.Parser

-- S → A t t | S t; A → ε. Physical 9 can be consumed whole as
-- semantic 1 or split into two semantic 0 terminals (physical kind 7).
private def grammar : IndexedGrammar := {
  grammar := {
    n_kinds := 2, n_nonterminals := 2, start_nonterminal := 0
    split_token_kind := 9, split_component_kind := 7, canonical_kinds := [7, 9]
    productions := [⟨0, [3, 0, 0]⟩, ⟨1, []⟩, ⟨0, [2, 0]⟩] }
  productionsByLhs := [[0, 2], [1]] }

private def tokens : List Token := [⟨9, ⟨0, 0, 2⟩⟩, ⟨7, ⟨0, 2, 3⟩⟩]
private def kinds : List Nat := [packedFlag, 0]
private def nodes : List ParseNode := [
  ⟨1, 1, 0, 0, []⟩,
  ⟨0, 0, 0, 2, [.node 0, .token 0, .token 0]⟩,
  ⟨2, 0, 0, 4, [.node 1, .token 1]⟩]

-- Derive the language judgment from an actual accepted finite tree, not
-- from an assumed parser result or an assumed recognized-input premise.
example : RecognizesInput grammar (tokens.map Token.kind) :=
  RootMatches.recognizes (nodes := nodes) (rootId := 2) (kinds := kinds) (rootShapeValid_sound (by decide))
    (checkNodesFrom_sound (by decide)) (by decide) (by decide) (by decide)

example : scanTerminal grammar (tokens.map Token.kind) 0 0 = some 1 :=
  advanceTerminal.scanTerminal (kinds := kinds) (by decide) (by decide) (by decide)

example : scanTerminal grammar (tokens.map Token.kind) 1 0 = some 2 :=
  advanceTerminal.scanTerminal (kinds := kinds) (by decide) (by decide) (by decide)

example : scanTerminal grammar (tokens.map Token.kind) 2 0 = some 4 :=
  advanceTerminal.scanTerminal (kinds := kinds) (by decide) (by decide) (by decide)

-- A split-capable physical token can also be used whole; the certificate
-- must retain which semantic interpretation the validated tree selected.
example : scanTerminal grammar (([⟨9, ⟨0, 0, 2⟩⟩] : List Token).map Token.kind) 0 1 = some 2 :=
  advanceTerminal.scanTerminal (kinds := [1]) (by decide) (by decide) (by decide)

example : advanceTerminal [0] 1 0 = none := by decide
example : advanceTerminal kinds 4 0 = none := by decide
example : semanticKindsValid grammar.grammar [⟨7, ⟨0, 0, 1⟩⟩] [packedFlag] = false := by decide
example : semanticKindsValid grammar.grammar [⟨9, ⟨0, 0, 2⟩⟩] [packedFlag + 1] = false := by decide
example : semanticKindsValid grammar.grammar tokens [packedFlag] = false := by decide

-- Reject forward/self child references, missing split halves, wrong
-- nonterminals, and a root that does not cover all physical tokens.
example : checkNode grammar.grammar kinds nodes 0 ⟨0, 0, 0, 2, [.node 1, .token 0, .token 0]⟩ = false := by decide
example : checkNode grammar.grammar kinds nodes 1 ⟨0, 0, 0, 2, [.node 1, .token 0, .token 0]⟩ = false := by decide
example : checkNode grammar.grammar kinds nodes 1 ⟨0, 0, 0, 2, [.node 0, .token 0]⟩ = false := by decide
example : checkNode grammar.grammar kinds nodes 1 ⟨0, 1, 0, 2, [.node 0, .token 0, .token 0]⟩ = false := by decide
example : rootShapeValid grammar.grammar tokens.length nodes 1 = false := by decide

run_elab do
  let standard := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``semanticKindsValid.lookup, ``advanceTerminal.scanTerminal,
      ``ChildrenMatch.recognizes, ``NodesMatchFrom.recognizes, ``RootMatches.recognizes,
      ``decodeTokens.kinds, ``ParseArtifactValid.recognizes, ``ParseArtifactValid.sourceSyntax,
      ``ArtifactPackChecker.CheckedUnitSurfaces.sourceSyntax, ``Entry.CheckedExecution.syntaxDomain,
      ``Entry.File.Resources.recognizes, ``Entry.File.Resources.frontend_success_or_resource] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption do
        throwError "Artifact-to-language result {name} adds unexpected axiom {assumption}"
  Lean.logInfo "Accepted postorder trees imply declarative syntax with standard Lean axioms; nullable/recursive trees, whole/split terminals, malformed edges and incomplete roots covered."
  Lean.logInfo "The source-linked frontend on the certified syntax/token domain can only succeed, exhaust parser capacity, or exhaust tree resources."

end Lanius.Extraction.Tests.Parser.Language
