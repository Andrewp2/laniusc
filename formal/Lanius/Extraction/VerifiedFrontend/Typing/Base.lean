import Lanius.Extraction.VerifiedFrontend.Assembly.Wire
import Lanius.Extraction.CoreTypingChunks
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 100000
def verifiedFrontendPackProgramKernel : Lanius.Core.Program :=
  CoreDecode.program verifiedFrontendPackWireKernel
def verifiedFrontendPackConstantsChunk0Kernel : List Lanius.Core.Constant :=
  (verifiedFrontendPackProgramKernel.constants.drop 0).take 10
def verifiedFrontendPackConstantsChunk1Kernel : List Lanius.Core.Constant :=
  (verifiedFrontendPackProgramKernel.constants.drop 10).take 10
def verifiedFrontendPackConstantsChunk2Kernel : List Lanius.Core.Constant :=
  (verifiedFrontendPackProgramKernel.constants.drop 20).take 10
def verifiedFrontendPackConstantsChunk3Kernel : List Lanius.Core.Constant :=
  (verifiedFrontendPackProgramKernel.constants.drop 30).take 10
def verifiedFrontendPackConstantsChunk4Kernel : List Lanius.Core.Constant :=
  (verifiedFrontendPackProgramKernel.constants.drop 40).take 10
def verifiedFrontendPackConstantsChunk5Kernel : List Lanius.Core.Constant :=
  (verifiedFrontendPackProgramKernel.constants.drop 50).take 10
def verifiedFrontendPackConstantsChunk6Kernel : List Lanius.Core.Constant :=
  (verifiedFrontendPackProgramKernel.constants.drop 60).take 10
def verifiedFrontendPackConstantsChunk7Kernel : List Lanius.Core.Constant :=
  (verifiedFrontendPackProgramKernel.constants.drop 70).take 10
def verifiedFrontendPackConstantsChunk8Kernel : List Lanius.Core.Constant :=
  (verifiedFrontendPackProgramKernel.constants.drop 80).take 10
def verifiedFrontendPackConstantsChunk9Kernel : List Lanius.Core.Constant :=
  (verifiedFrontendPackProgramKernel.constants.drop 90).take 2
def verifiedFrontendPackFunctionsChunk0Kernel : List Lanius.Core.Function :=
  (verifiedFrontendPackProgramKernel.functions.drop 0).take 3
def verifiedFrontendPackFunctionsChunk1Kernel : List Lanius.Core.Function :=
  (verifiedFrontendPackProgramKernel.functions.drop 3).take 3
def verifiedFrontendPackFunctionsChunk2Kernel : List Lanius.Core.Function :=
  (verifiedFrontendPackProgramKernel.functions.drop 6).take 3
def verifiedFrontendPackFunctionsChunk3Kernel : List Lanius.Core.Function :=
  (verifiedFrontendPackProgramKernel.functions.drop 9).take 3
def verifiedFrontendPackFunctionsChunk4Kernel : List Lanius.Core.Function :=
  (verifiedFrontendPackProgramKernel.functions.drop 12).take 3
def verifiedFrontendPackFunctionsChunk5Kernel : List Lanius.Core.Function :=
  (verifiedFrontendPackProgramKernel.functions.drop 15).take 3
def verifiedFrontendPackFunctionsChunk6Kernel : List Lanius.Core.Function :=
  (verifiedFrontendPackProgramKernel.functions.drop 18).take 3
def verifiedFrontendPackFunctionsChunk7Kernel : List Lanius.Core.Function :=
  (verifiedFrontendPackProgramKernel.functions.drop 21).take 3
def verifiedFrontendPackFunctionsChunk8Kernel : List Lanius.Core.Function :=
  (verifiedFrontendPackProgramKernel.functions.drop 24).take 3
def verifiedFrontendPackFunctionsChunk9Kernel : List Lanius.Core.Function :=
  (verifiedFrontendPackProgramKernel.functions.drop 27).take 3
def verifiedFrontendPackFunctionsChunk10Kernel : List Lanius.Core.Function :=
  (verifiedFrontendPackProgramKernel.functions.drop 30).take 3
def verifiedFrontendPackFunctionsChunk11Kernel : List Lanius.Core.Function :=
  (verifiedFrontendPackProgramKernel.functions.drop 33).take 3
def verifiedFrontendPackFunctionsChunk12Kernel : List Lanius.Core.Function :=
  (verifiedFrontendPackProgramKernel.functions.drop 36).take 3
def verifiedFrontendPackFunctionsChunk13Kernel : List Lanius.Core.Function :=
  (verifiedFrontendPackProgramKernel.functions.drop 39).take 3
def verifiedFrontendPackFunctionsChunk14Kernel : List Lanius.Core.Function :=
  (verifiedFrontendPackProgramKernel.functions.drop 42).take 3
def verifiedFrontendPackFunctionsChunk15Kernel : List Lanius.Core.Function :=
  (verifiedFrontendPackProgramKernel.functions.drop 45).take 3
def verifiedFrontendPackFunctionsChunk16Kernel : List Lanius.Core.Function :=
  (verifiedFrontendPackProgramKernel.functions.drop 48).take 3
def verifiedFrontendPackFunctionsChunk17Kernel : List Lanius.Core.Function :=
  (verifiedFrontendPackProgramKernel.functions.drop 51).take 3
def verifiedFrontendPackFunction45Kernel : Lanius.Core.Function :=
  verifiedFrontendPackProgramKernel.functions.get ⟨45, by with_unfolding_all decide⟩
def verifiedFrontendPackFunction46Kernel : Lanius.Core.Function :=
  verifiedFrontendPackProgramKernel.functions.get ⟨46, by with_unfolding_all decide⟩
def verifiedFrontendPackFunction47Kernel : Lanius.Core.Function :=
  verifiedFrontendPackProgramKernel.functions.get ⟨47, by with_unfolding_all decide⟩
theorem verifiedFrontendPack_constants_chunks_kernel :
    verifiedFrontendPackProgramKernel.constants = verifiedFrontendPackConstantsChunk0Kernel ++ (verifiedFrontendPackConstantsChunk1Kernel ++ (verifiedFrontendPackConstantsChunk2Kernel ++ (verifiedFrontendPackConstantsChunk3Kernel ++ (verifiedFrontendPackConstantsChunk4Kernel ++ (verifiedFrontendPackConstantsChunk5Kernel ++ (verifiedFrontendPackConstantsChunk6Kernel ++ (verifiedFrontendPackConstantsChunk7Kernel ++ (verifiedFrontendPackConstantsChunk8Kernel ++ (verifiedFrontendPackConstantsChunk9Kernel ++ ([])))))))))) := by
  with_unfolding_all rfl
theorem verifiedFrontendPack_functions_chunks_kernel :
    verifiedFrontendPackProgramKernel.functions = verifiedFrontendPackFunctionsChunk0Kernel ++ (verifiedFrontendPackFunctionsChunk1Kernel ++ (verifiedFrontendPackFunctionsChunk2Kernel ++ (verifiedFrontendPackFunctionsChunk3Kernel ++ (verifiedFrontendPackFunctionsChunk4Kernel ++ (verifiedFrontendPackFunctionsChunk5Kernel ++ (verifiedFrontendPackFunctionsChunk6Kernel ++ (verifiedFrontendPackFunctionsChunk7Kernel ++ (verifiedFrontendPackFunctionsChunk8Kernel ++ (verifiedFrontendPackFunctionsChunk9Kernel ++ (verifiedFrontendPackFunctionsChunk10Kernel ++ (verifiedFrontendPackFunctionsChunk11Kernel ++ (verifiedFrontendPackFunctionsChunk12Kernel ++ (verifiedFrontendPackFunctionsChunk13Kernel ++ (verifiedFrontendPackFunctionsChunk14Kernel ++ (verifiedFrontendPackFunctionsChunk15Kernel ++ (verifiedFrontendPackFunctionsChunk16Kernel ++ (verifiedFrontendPackFunctionsChunk17Kernel ++ ([])))))))))))))))))) := by
  with_unfolding_all rfl
end Lanius.Extraction
