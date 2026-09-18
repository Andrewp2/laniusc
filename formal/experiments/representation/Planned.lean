import SelfSurface
import Lanius.Extraction.Reconstruction.Plan
import Lean.Util.CollectAxioms

open Lean Elab Lanius.Extraction Lanius.Extraction.Reconstruction
open Lanius.Extraction.Self.Surface.ByteIO
namespace PlannedProfile
set_option maxRecDepth 4096
set_option maxHeartbeats 2000000
set_option compiler.extract_closed false

private def phase (message : String) : TermElabM Unit := do
  let messages ← Lean.Core.getMessageLog
  if messages.hasErrors then
    for error in messages.toList do
      if error.severity == .error then IO.eprintln (← error.toString)
    IO.Process.exit 1
  IO.FS.withFile "target/verified-compiler/planned-profile-phases.log" .append fun handle => do
    handle.putStrLn s!"[{← IO.monoMsNow} ms] {message}"
    handle.flush

elab "plan% " minimum:num : term => do
  let emitted ← IO.FS.readFile "target/verified-compiler/SelfCompactRequirements.lean"
  let some first := (emitted.splitOn "def encodedPack : String := \"")[1]?
    | throwError "missing compact literal"
  let some encoded := (first.splitOn "\"").head? | throwError "missing literal end"
  let some pack := decodeCompactArtifactPack? encoded | throwError "invalid compact input"
  let some unit := pack.units[2]? | throwError "missing byte-I/O unit"
  let proposed := Plan.propose unit.parse_nodes minimum.getNat
  let (ordinary, contexts, contextual) := proposed.foldl (fun (ordinary, contexts, contextual) segment =>
    match segment with
    | .ordinary count => (ordinary + count, contexts, contextual)
    | .context layers => (ordinary, contexts + 1, contextual + 2 * layers.length)) (0, 0, 0)
  phase s!"proposed {proposed.length} segments: {ordinary} ordinary nodes, {contexts} contexts, {contextual} contextual nodes"
  quoteBounded proposed (compile := false)

run_elab do
  IO.FS.writeFile "target/verified-compiler/planned-profile-phases.log" ""
  phase "start proposal"
private noncomputable def plan : List Plan.Segment := plan% 2
run_elab phase "quoted; start planned complete reconstruction"

set_option Elab.async false in
theorem planned : Plan.checkedView parseView Parse.productions.lookup Parse.lookup_eq plan = some tree := by
  kernel_rfl
run_elab phase "planned result checked; retain original checker equation"

set_option Elab.async false in
theorem connected : Validated.checkedView laniusGrammar parseView Parse.productions.lookup = some tree :=
  Plan.checkedView_sound parseView Parse.productions.lookup Parse.lookup_eq plan tree planned
run_elab phase "original equation retained; run baseline"

set_option Elab.async false in
theorem recomputed : Validated.checkedView laniusGrammar parseView Parse.productions.lookup = some tree := by
  kernel_rfl
run_elab phase "baseline checked; audit"

run_elab do
  for name in #[``planned, ``connected, ``recomputed, ``Plan.run_sound, ``Plan.checkedView_sound] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "unexpected axiom {assumption} in {name}"
  phase "audit passed"
end PlannedProfile
