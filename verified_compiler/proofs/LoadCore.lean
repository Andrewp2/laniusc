import SelfCore
import Lean.Util.CollectAxioms

open Lean Lanius.Extraction.Self.Core

-- Loading reuses a frozen typing certificate, not a fresh source check.
example : Lanius.Typing.ProgramWellTyped program := wellTyped
example : program.target = .x86_64 := target
example : program.functions.length = 125 := function_count

run_elab do
  for name in #[``wellTyped, ``target, ``function_count] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "saved Core certificate {name} uses unexpected assumption {assumption}"
