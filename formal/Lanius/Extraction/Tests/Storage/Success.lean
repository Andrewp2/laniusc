import Lanius.Extraction.Entry.Domain.Output
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Storage.Success
open Lanius.Extraction.Entry

/-- The self-source fixture contains distinct paths in source order. Exercise
the public admission boundary with changed process inputs, without repeating
the expensive syntax or resource checks. -/
def checkInputs (output : CheckedOutputDomain sources 16777216)
    (tokens : TokenDomain sources) (syntaxValid : SyntaxDomain sources)
    (parser : ParserDomain sources) (tree : TreeDomain sources)
    (world : Lanius.World.State) : IO Unit := do
  let first :: second :: rest := sources.map (·.path)
    | throw (IO.userError "success-domain fixture needs at least two source paths")
  unless (sources.map (·.path)).eraseDups.length == sources.length do
    throw (IO.userError "success-domain fixture needs distinct source paths")
  let some original := world.file? (Lanius.World.utf8Bytes first)
    | throw (IO.userError "success-domain fixture is missing its first source")
  let changed := { original with bytes := original.bytes ++ [0] }
  let cases : List (String × Lanius.World.State × Bool) := [
    ("exact inputs", world, true),
    ("different executable name", { world with arguments := "renamed" :: first :: second :: rest }, true),
    ("unrelated host state", { world with standardOutput := [65], standardError := [66], unixTimeSeconds := 9 }, true),
    ("reordered file storage", { world with files := world.files.reverse }, true),
    ("later shadowed file", { world with files := world.files ++ [changed] }, true),
    ("no requested sources", { world with arguments := ["extractor"] }, false),
    ("missing requested source", { world with arguments := "extractor" :: second :: rest }, false),
    ("reordered requests", { world with arguments := "extractor" :: second :: first :: rest }, false),
    ("repeated request", { world with arguments := "extractor" :: first :: first :: rest }, false),
    ("missing file", { world with files := world.files.filter (fun file => file.path != original.path) }, false),
    ("changed source bytes", { world with files := changed :: world.files }, false)]
  for (name, candidate, expected) in cases do
    unless (output.checkSuccessDomain? tokens syntaxValid parser tree candidate).isSome == expected do
      throw (IO.userError s!"successful-input admission differs: {name}")
  IO.println s!"{cases.length} successful-input admission cases passed: exact order and bytes, missing/repeated requests, host lookup and irrelevant state"

run_elab do
  let standard := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``SourceDomain.of_domains, ``SourceDomain.singleton,
      ``SourceDomains.of_bounds, ``SourceDomains.of_domains,
      ``CheckedOutputDomain.checkSuccessDomain?, ``File.append_position_bounds,
      ``CheckedExecution.run_complete, ``CheckedExecution.succeeds] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption do
        throwError "Successful-input theorem {name} adds unexpected axiom {assumption}"
  Lean.logInfo "Source-only successful-input admission and public RunComplete use only standard Lean axioms."

end Lanius.Extraction.Tests.Storage.Success
