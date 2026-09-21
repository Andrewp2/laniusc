import Lanius.Extraction.SurfaceReconstruct

namespace Lanius.Extraction

/-! A successful check exposes only the Surface tree independently
    reconstructed by Lean from the syntax artifact.  Parse validity is a
    separate prerequisite supplied by `SyntaxCheck`; an untrusted proposed
    Surface tree is never accepted here. -/

structure CheckedSurface (artifact : Artifact) where
  surface : Lanius.Surface.File
  reconstructed : decodeReconstructedSurface artifact = some surface

def checkSurface (artifact : Artifact) : Option (CheckedSurface artifact) :=
  match reconstructed : decodeReconstructedSurface artifact with
  | none => none
  | some surface => some { surface, reconstructed }

theorem checkSurface_sound {artifact : Artifact}
    {checked : CheckedSurface artifact}
    (_accepted : checkSurface artifact = some checked) :
    decodeReconstructedSurface artifact = some checked.surface :=
  checked.reconstructed

end Lanius.Extraction
