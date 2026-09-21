import Lanius.Compiler.FrontendArtifact

namespace Lanius.Compiler.FrontendCorrect

def canonicalCoreProofsAvailable : Bool :=
  FrontendArtifact.canonicalCoreExportAvailable

theorem canonicalCoreProofs_available : canonicalCoreProofsAvailable = true := by
  exact FrontendArtifact.canonicalCoreExport_available

end Lanius.Compiler.FrontendCorrect
