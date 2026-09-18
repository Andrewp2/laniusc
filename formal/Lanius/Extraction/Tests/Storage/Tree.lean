import Lanius.Extraction.Entry.Domain.Tree
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Storage.Tree
open Lanius.Compiler.Parser Lanius.Extraction.Frontend

/-- Exercise the source-bound checker on the last actual checked unit. Keep
the unit's accepted lexical evidence, and vary only untrusted resource inputs. -/
def check : {artifacts : List Artifact} → ArtifactPackChecker.CheckedUnitSurfaces artifacts →
    List Envelope.Candidate → IO Unit
  | [], .nil, [] => pure ()
  | [artifact], .cons head .nil, [candidate] => do
    for (label, workspace, records, offsets, depth, proposal, expected) in
        [("ordinary", 4194304, 1048576, 65536, 1024, candidate, true),
         ("wrong token count", 4194304, 1048576, 65536, 1024, {candidate with tokenCount := candidate.tokenCount + 1}, false),
         ("no workspace", 0, 1048576, 65536, 1024, candidate, false),
         ("no tree words", 4194304, 0, 65536, 1024, candidate, false),
         ("no node slots", 4194304, 1048576, 0, 1024, candidate, false),
         ("no recursion depth", 4194304, 1048576, 65536, 0, candidate, false),
         ("invalid production", 4194304, 1048576, 65536, 1024,
           {candidate with items := (0, 999999, 0, 0) :: candidate.items}, false)] do
      unless (checkArtifactParserTreeStorage? artifact head.valid.1.1 workspace records offsets depth proposal).isSome == expected do
        throw (IO.userError s!"source-bound tree resource boundary differs: {label}")
    unless (checkUnitsParserTreeStorage? 4194304 1048576 65536 1024 [artifact]
        (Entry.checkedUnits_tokensValid (.cons head .nil)) []).isNone do
      throw (IO.userError "missing resource candidate accepted")
    unless (checkUnitsParserTreeStorage? 4194304 1048576 65536 1024 []
        (by intro _ member; cases member) [candidate]).isNone do
      throw (IO.userError "surplus resource candidate accepted")
    IO.println "source-bound parser/tree resource checking rejects wrong token counts, insufficient buffers/depth, invalid productions, and missing/surplus candidates"
  | _ :: _ :: _, .cons _ tail, _ :: rest => check tail rest
  | _, _, _ => throw (IO.userError "resource test fixtures have mismatched unit counts")

run_elab do
  let standard := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``sourcesParserStorage_of_certificate, ``sourcesTreeStorage_of_certificate,
      ``checkArtifactParserTreeStorage?, ``checkUnitsParserTreeStorage?,
      ``Entry.CheckedExecution.checkParserTreeDomain?, ``syntaxPost.no_tree_failure,
      ``bodyPost.no_tree_failure, ``Entry.File.Resources.no_tree_failure,
      ``Entry.File.Resources.frontend_success, ``Lanius.Fuel.evaluates_deterministic] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption do
        throwError "Tree source boundary {name} adds unexpected axiom {assumption}"
  let baseline ← Lean.collectAxioms ``ParserTreeSource.CheckedMaterialize.call_bounded
  for assumption in ← Lean.collectAxioms ``CheckedAfterParse.accepted do
    unless standard.contains assumption || baseline.contains assumption do
      throwError "Successful materialization retention adds unexpected axiom {assumption}"
  Lean.logInfo "Tree resource domains and actual frontend success use only standard Lean axioms; source execution adds nothing beyond its existing materializer baseline."

end Lanius.Extraction.Tests.Storage.Tree
