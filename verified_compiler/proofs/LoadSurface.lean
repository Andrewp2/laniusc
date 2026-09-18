import SelfSurface
import Lean.Util.CollectAxioms

open Lean Lanius.Extraction Lanius.Extraction.Self.Surface

-- Loading is reuse of a frozen certificate, not a fresh source check.
example : (checkSurfaceArtifact? Host.unit.artifact).isSome = true := Host.original_accepted
example : (checkSurfaceArtifact? TokenScan.unit.artifact).isSome = true := TokenScan.original_accepted
example : (checkSurfaceArtifact? ByteIO.unit.artifact).isSome = true := ByteIO.original_accepted

run_elab do
  for name in #[``Lanius.Extraction.Self.Encoding.encodable,
      ``Lanius.Extraction.Self.Encoding.decoded, ``Lanius.Extraction.Self.Encoding.source_bound,
      ``Host.source_path, ``Host.reference_accepted, ``Host.original_accepted,
      ``TokenScan.source_path, ``TokenScan.reference_accepted, ``TokenScan.original_accepted,
      ``ByteIO.source_path, ``ByteIO.reference_accepted, ``ByteIO.original_accepted] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "saved Surface certificate {name} uses unexpected assumption {assumption}"
