import Lanius.Extraction.Entry.Host
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Process
open Lanius.Extraction.Entry

private def world (paths : List String) : Lanius.World.State := {
  arguments := "extractor" :: paths
  files := [⟨[97], [255]⟩, ⟨Lanius.World.utf8Bytes "empty", []⟩,
    ⟨Lanius.World.utf8Bytes "big", List.replicate 65537 255⟩]
  fileHandles := [⟨3, [98], 7, true, false⟩]
  nextFileHandle := 17
  standardOutput := [17, 18]
  standardError := [19]
  calls := [.close] }

private def admitted : List Lanius.World.State :=
  [{ world [] with arguments := [] }, world []] ++
  (["a", "empty", "missing", "", String.ofList (List.replicate 1025 'λ'), "big"].map fun path => world [path]) ++
  ([1, 2, 4].flatMap fun count => ["", "missing", "big"].map fun bad =>
    world (List.replicate count "a" ++ [bad, "unchecked-tail"])) ++
  [{ world ["big"] with nextFileHandle := 2147483647 },
   { world ["a", "big"] with nextFileHandle := 2147483646 }]

def check : IO Unit := do
  for world in admitted do
    unless (checkHostDomain? world).isSome do
      throw (IO.userError "host-only domain rejected ordinary missing, oversized, or arbitrary-syntax inputs")
  for world in [
      { world ["a"] with nextFileHandle := 2147483648 },
      { world ["a", "big"] with nextFileHandle := 2147483647 },
      { world ["a"] with fileHandles := [⟨17, [98], 7, true, false⟩] }] do
    if (checkHostDomain? world).isSome then
      throw (IO.userError "host domain accepted an unrepresentable or colliding open handle")
  IO.println "Host-only domain: 19 admitted worlds cover no inputs, arbitrary syntax, missing/oversized files at any tested position, UTF-8 paths, and exact handle limits; three invalid handle states rejected."

def checkExecutable (checked : CheckedExecution accepted) : IO Unit := do
  for world in admitted do
    let some domain := checkHostDomain? world
      | throw (IO.userError "host-only domain fixture rejected")
    have _actualMain := checked.hostSafe domain.down
    pure ()
  IO.println "Unified actual-main safety and finite-termination theorem instantiated on all 19 host-domain worlds."

#eval check

run_elab do
  for name in #[``checkHostDomain?, ``HostDomain.classify, ``ExecutionCorrect.safe,
      ``RejectedExecution.safe, ``CheckedExecution.hostSafe] do
    for assumption in ← Lean.collectAxioms name do
      unless assumption == ``propext || assumption == ``Classical.choice || assumption == ``Quot.sound do
        throwError "Host coverage theorem {name} adds unexpected axiom {assumption}"
  Lean.logInfo "Exhaustive host-input classification and unified public execution theorem use only standard axioms."

end Lanius.Extraction.Tests.Process
