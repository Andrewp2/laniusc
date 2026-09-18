import SelfSurface
open Lean Lanius.Extraction Lanius.Extraction.Self.Surface.ByteIO

/-! Phase diagnostics on the frozen byte-I/O fixture. Each equality is checked
afresh, but input quotation and cache authentication are NOT included. The phases
overlap; do not add them or present their timings as a full source check. -/

set_option maxRecDepth 4096
set_option maxHeartbeats 2000000

run_elab IO.println s!"[{← IO.monoMsNow}] link only"
set_option Elab.async false in
example : (ParseTree.link artifact.parse_nodes).isSome = true := by decide +kernel
run_elab IO.println s!"[{← IO.monoMsNow}] validated link"
set_option Elab.async false in
example : (Reconstruction.Validated.linkFrom laniusGrammar parseView Parse.productions.lookup
    0 artifact.parse_nodes []).isSome = true := by decide +kernel
run_elab IO.println s!"[{← IO.monoMsNow}] reconstruction only"
set_option Elab.async false in
example : Reconstruction.checkedView artifact indexed = some tree := by kernel_rfl
run_elab IO.println s!"[{← IO.monoMsNow}] fused acceptance"
set_option Elab.async false in
example : (Reconstruction.Validated.checkedView laniusGrammar parseView Parse.productions.lookup).isSome = true := by decide +kernel
run_elab IO.println s!"[{← IO.monoMsNow}] fused exact output"
set_option Elab.async false in
example : Reconstruction.Validated.checkedView laniusGrammar parseView Parse.productions.lookup = some tree := by kernel_rfl
run_elab IO.println s!"[{← IO.monoMsNow}] done"
