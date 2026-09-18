import Lanius.Extraction.Reconstruction.Plan
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Contexts
open Reconstruction.Contexts

private def literal : ParseTree := .node 0 ⟨185, 90, 0, 2, [.token 0]⟩ [none]
private def tail : ParseTree := .node 1 ⟨164, 89, 2, 2, []⟩ []
private def postfixTree : ParseTree := .node 2 ⟨160, 88, 0, 2, [.node 0, .node 1]⟩ [some literal, some tail]
private def unary : ParseTree := .node 3 ⟨159, 131, 0, 2, [.node 2]⟩ [some postfixTree]
private def input : Artifact := { Artifact.empty with
  sources := [⟨"literal.lani", [116, 114, 117, 101]⟩]
  tokens := [⟨90, ⟨0, 0, 4⟩⟩]
  semantic_token_kinds := [90]
  parse_nodes := [literal.value, tail.value, postfixTree.value, unary.value] ++ nodes levels unary
  parse_root := some 23 }

private def view : ParseArtifactView input := {
  artifactView := ArtifactCache.ofMatches (cache := ArtifactCache.ofArtifact input) (by kernel_rfl)
  leafCapacity := 8
  semanticKinds := .leaf [90]
  semanticKindsWellFormed := (by decide : 1 ≤ 8)
  semanticKindsRepresent := rfl }

-- The child is itself a valid, nonempty grammar derivation, not a dummy tree
-- whose reconstruction always fails. This also checks its terminal span.
private theorem allNodes : checkNodesFromParseView laniusGrammar input view 0 input.parse_nodes = true := by
  decide +kernel

private theorem sourceBound :
    checkNodesFromParseView laniusGrammar input view 4 (nodes levels unary) = true :=
  source_checked view unary
    (matchesSource_of_range view.artifactView unary (by kernel_rfl)) rfl (by decide) (by decide)

-- Exactly one boolean literal is constructed, preserving its original parse
-- identity and advancing an arbitrary nonzero Surface counter once.
private theorem actualResult :
    (reconstructBinaryLayer 32 input (precedence unary) .logical_or).run 33 =
      some ({ id := 33, parse_node := 0, value := .literal (.boolean true) }, 34) := by
  change reconstructBinaryLayer (21 + 11) input (precedence unary) .logical_or 33 = _
  rw [precedence_eq]
  kernel_rfl

private theorem exhausted :
    (reconstructBinaryLayer 10 input (precedence unary) .logical_or).run 33 = none := by kernel_rfl

private theorem mismatches :
    view.artifactView.cache.parseNodes.rangeEq 4 (unary.value :: nodes levels unary) = false ∧
    view.artifactView.cache.parseNodes.rangeEq 3
      ({ unary.value with nonterminal := 72 } :: nodes levels unary) = false ∧
    view.artifactView.cache.parseNodes.rangeEq 3
      (unary.value :: (nodes levels unary).reverse) = false ∧
    view.artifactView.cache.parseNodes.rangeEq 23 (unary.value :: nodes levels unary) = false := by
  decide +kernel

private theorem completePlan :
    Reconstruction.Plan.run view laniusGrammar.production? [.ordinary 4, .context levels]
      0 input.parse_nodes [] = some [precedence unary] := by kernel_rfl

private theorem ordinaryPlan :
    Reconstruction.Plan.run view laniusGrammar.production? [.ordinary 100]
      0 input.parse_nodes [] = some [precedence unary] := by kernel_rfl

private theorem badPlans :
    ([[], [.ordinary 0], [.ordinary 4], [.context levels],
      [.ordinary 4, .context [.logical_or, .multiplicative]],
      [.ordinary 4, .context [.multiplicative]],
      [.ordinary 4, .context levels, .context levels]] : List (List Reconstruction.Plan.Segment)).all
      (fun plan => (Reconstruction.Plan.run view laniusGrammar.production? plan
        0 input.parse_nodes []).isNone) = true := by kernel_rfl

-- Every source node remains an obligation, including the skipped context
-- pairs: corrupting any production must make the planned check fail.
private theorem damagedNodes :
    (List.range input.parse_nodes.length).all (fun index =>
      let node := input.parse_nodes[index]?.getD ⟨0, 0, 0, 0, []⟩
      let damaged := input.parse_nodes.set index
        { node with production := laniusGrammar.productions.length }
      (Reconstruction.Plan.run view laniusGrammar.production? [.ordinary 4, .context levels]
        0 damaged []).isNone) = true := by decide +kernel

run_elab do
  for name in #[``allNodes, ``sourceBound, ``actualResult, ``exhausted, ``mismatches,
      ``completePlan, ``ordinaryPlan, ``badPlans, ``damagedNodes,
      ``Reconstruction.Plan.run_sound, ``Reconstruction.Plan.checkedView_sound,
      ``Reconstruction.Contexts.precedence_eq, ``Reconstruction.Contexts.precedence_link,
      ``Reconstruction.Contexts.source_checked, ``Reconstruction.Contexts.matchesSource_of_range] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "unexpected axiom {assumption} in {name}"
end Lanius.Extraction.Tests.Contexts
