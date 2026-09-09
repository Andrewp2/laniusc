import Lanius.Extraction.CompactOutput.PackHeader
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.CompactOutput.PackHeader

run_elab do
  let standard : Array Lean.Name := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``Lanius.Extraction.CompactOutput.PackHeader.execute,
      ``Lanius.Extraction.CompactOutput.PackHeader.Checked.write] do
    unless (← Lean.getEnv).contains name do throwError "Missing pack-header theorem {name}"
    for axiomName in ← Lean.collectAxioms name do
      unless standard.contains axiomName do throwError "Pack-header theorem {name} depends on {axiomName}"
  Lean.logInfo "Pack header public-call proof uses standard axioms only."

end Lanius.Extraction.Tests.CompactOutput.PackHeader
