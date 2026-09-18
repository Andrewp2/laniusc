import SelfLowering
import Lean.Util.CollectAxioms

open Lanius.Extraction.Self
#check Lowering.all_lowered
#check Core.wellTyped
#check Core.target

run_elab do
  for name in #[``Lowering.all_lowered, ``Core.wellTyped, ``Core.target] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "saved certificate {name} uses unexpected assumption {assumption}"
