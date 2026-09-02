import Lanius.Extraction.VerifiedFrontendPackKernelDecoded
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
def verifiedFrontendPackDecodedUnitsKernel :
    List ArtifactPackContextChecker.ProgramUnit :=
  verifiedFrontendPackDecodedKernel.units
def verifiedFrontendPackAllocationsKernel :=
  ArtifactPackContextChecker.allocateUnits verifiedFrontendPackDecodedUnitsKernel
end Lanius.Extraction
