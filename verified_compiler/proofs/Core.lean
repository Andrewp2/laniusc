import Lanius.Core.Quote
import Lanius.Extraction.CoreSynthesis.Provenance
import Lanius.Extraction.ArtifactQuote
import Lanius.Extraction.ArtifactCacheQuote
import Lanius.Extraction.KernelReduction
import Lean.Util.CollectAxioms

/-! Freeze the full Core candidate proposed from the existing self-extraction.
The kernel certifies its typing and target, not the native proposal's derivation
from Lanius source. The missing source-to-Core equation remains a separate
obligation: this is not an extractor execution or x86 preservation certificate.
Re-run for changed inputs; loading the saved result certifies frozen data only. -/

open Lean Elab Term Lanius.Extraction
namespace Lanius.Extraction.Self.Core

set_option maxRecDepth 4096
set_option maxHeartbeats 2000000
set_option compiler.extract_closed false

private def phase (message : String) : IO Unit :=
  IO.FS.withFile "target/verified-compiler/self-core-phases.log" .append fun handle => do
    handle.putStrLn s!"[{← IO.monoMsNow}] {message}"
    handle.flush

elab "self_core%" : term => do
  IO.FS.writeFile "target/verified-compiler/self-core-phases.log" ""
  phase "proposing full Core program"
  let emitted ← IO.FS.readFile "target/verified-compiler/SelfCompactRequirements.lean"
  let some first := (emitted.splitOn "def encodedPack : String := \"")[1]?
    | throwError "missing compact literal"
  let some encoded := (first.splitOn "\"").head? | throwError "missing literal end"
  let paths ← IO.FS.lines "verified_compiler/source-closure.txt"
  let sources ← paths.toList.mapM fun (path : String) => do
    let bytes ← IO.FS.readBinFile path
    return ({path, bytes := bytes.toList.map UInt8.toNat} : SourceFile)
  let some checked := checkCompactSurfaceArtifactPackSources? encoded sources
    | throwError "Surface proposal failed"
  phase "source bytes checked; proposing indexed Surface data"
  let data := checked.surfaceData
  phase "Surface proposed; synthesizing Core"
  let some checked := CoreSynthesis.Program.synthesize? data | throwError "Core proposal failed"
  phase s!"quoting {checked.core.functions.length} functions"
  quoteBounded checked.core (compile := false)

noncomputable def program : Lanius.Core.Program := self_core%

theorem target : program.target = .x86_64 := by kernel_rfl

theorem function_count : program.functions.length = 125 := by kernel_rfl

run_elab phase "Core quoted; checking full typing"

set_option Elab.async false in
theorem typed : (CoreTyping.checkProgram program).isSome = true := by kernel_rfl

theorem wellTyped : Lanius.Typing.ProgramWellTyped program :=
  ((CoreTyping.checkProgram program).get typed).proof

run_elab do
  for name in #[``target, ``function_count, ``wellTyped] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "Core certificate {name} uses unexpected assumption {assumption}"
  phase "complete Core typing and strict audit checked"

end Lanius.Extraction.Self.Core
