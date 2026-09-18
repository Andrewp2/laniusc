import Lanius.Extraction.Entry.Domain
import Lanius.Extraction.Entry.Failure
import Lanius.Extraction.Entry.Startup.Reject
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Later
open Lanius.Core Lanius.Semantics Lanius.Extraction.Entry

private def world (count : Nat) (bad : String) : Lanius.World.State := {
  arguments := "extractor" :: List.replicate count "a" ++ [bad, "unchecked-later"]
  files := [⟨[97], [255]⟩]
  fileHandles := [⟨3, [98], 7, true, false⟩]
  nextFileHandle := 17
  standardOutput := [17, 18]
  standardError := [19]
  calls := [.close] }

private def oversized (count size : Nat) : Lanius.World.State := {
  world count "λ.lani" with
  files := [⟨[97], [255]⟩, ⟨Lanius.World.utf8Bytes "λ.lani", List.replicate size 255⟩] }

/-- The domain accepts arbitrary prefix syntax, repeated files, and an
unrestricted tail. It rejects missing prerequisites instead of trusting an
expected error code or an alleged successful prefix run. -/
private def admitted : List (Lanius.World.State × Nat) :=
  ([1, 2, 4].flatMap fun count =>
    ["", String.ofList (List.replicate 1025 'a'), "λ-missing"].map fun bad => (world count bad, count + 1)) ++
  [({ world 1 "missing" with nextFileHandle := 2147483647 }, 2),
   ({ world 2 "missing" with files := [⟨[97], []⟩] }, 3)] ++
  ([1, 2, 4].flatMap fun count =>
    [65537, 131073].map fun size => (oversized count size, count + 1)) ++
  [({ oversized 1 65537 with nextFileHandle := 2147483646 }, 2),
   ({ oversized 4 65537 with nextFileHandle := 2147483643 }, 5)]

def check : IO Unit := do
  for (world, index) in admitted do
    unless (checkLaterFailureDomain? world index).isSome do
      throw (IO.userError s!"loadable prefix followed by rejection was not admitted at argument {index}")
  let base := world 2 "missing"
  for (world, index) in [
      (base, 0), (base, 1), (base, 2), (base, 99),
      ({ base with files := [] }, 3),
      ({ base with arguments := ["extractor", "", "a", "missing"] }, 3),
      ({ base with files := [⟨[97], List.replicate 65537 0⟩] }, 3),
      ({ base with fileHandles := [⟨17, [97], 0, true, false⟩] }, 3),
      ({ base with nextFileHandle := 2147483647 }, 3),
      ({ base with files := base.files ++ [⟨Lanius.World.utf8Bytes "missing", []⟩] }, 3)] do
    if (checkLaterFailureDomain? world index).isSome then
      throw (IO.userError s!"later-failure domain accepted a missing or false prerequisite at argument {index}")
  for count in [1, 2, 4] do
    for changed in [oversized count 65535, oversized count 65536,
        { oversized count 65537 with nextFileHandle := 2147483648 - count }] do
      if (checkLaterFailureDomain? changed (count + 1)).isSome then
        throw (IO.userError "later overflow accepted a fitting file or omitted the extra open-handle requirement")
  IO.println "Later-failure domain: 19 accepted cases and 19 rejected mutations cover invalid/missing paths, oversized files, arbitrary prefix syntax, repeated paths, and exact handle limits."

def checkExecutable (checked : CheckedExecution accepted) : IO Unit := do
  for (world, index) in admitted do
    let some domain := checkLaterFailureDomain? world index
      | throw (IO.userError "later-failure domain fixture was rejected")
    have _actualMain := checked.laterFailure domain.down
    pure ()
  IO.println "Actual-main later-failure theorem instantiated on 19 worlds, including oversized files after 1, 2, and 4 preceding files; preceding syntax need not succeed and later arguments are unrestricted."

#eval check

run_elab do
  let standard := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``Path.checkRejection?, ``Path.Rejection.transport, ``Path.Rejection.index_lt,
      ``Path.Rejection.classified, ``Path.Rejection.nonzero, ``Path.Rejection.executes,
      ``File.checkRejection?, ``File.Rejection.transport, ``File.Rejection.index_lt, ``File.Rejection.afterFile,
      ``File.Next.pathBuffers, ``checkLaterFailureDomain?, ``CheckedExecution.laterFailure] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption do
        throwError "Later-rejection domain/resource theorem {name} adds unexpected axiom {assumption}"
  let baseline ← Lean.collectAxioms ``Frontend.CheckedSyntax.call_evaluates
  for name in #[``Files.rejectsAfter, ``Startup.rejectsAfter] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption || baseline.contains assumption do
        throwError "Later-file loop theorem {name} adds unexpected axiom {assumption}"
  Lean.logInfo "Later-file rejection loop and main composition add no assumptions beyond the existing frontend baseline."

end Lanius.Extraction.Tests.Later
