import Lanius.Extraction.VerifiedFrontend.Typing.Base
import Lanius.Extraction.VerifiedFrontend.Typing.Constants.Chunk0
import Lanius.Extraction.VerifiedFrontend.Typing.Constants.Chunk1
import Lanius.Extraction.VerifiedFrontend.Typing.Constants.Chunk2
import Lanius.Extraction.VerifiedFrontend.Typing.Constants.Chunk3
import Lanius.Extraction.VerifiedFrontend.Typing.Constants.Chunk4
import Lanius.Extraction.VerifiedFrontend.Typing.Constants.Chunk5
import Lanius.Extraction.VerifiedFrontend.Typing.Constants.Chunk6
import Lanius.Extraction.VerifiedFrontend.Typing.Constants.Chunk7
import Lanius.Extraction.VerifiedFrontend.Typing.Constants.Chunk8
import Lanius.Extraction.VerifiedFrontend.Typing.Constants.Chunk9
import Lanius.Extraction.VerifiedFrontend.Typing.Functions.Chunk0
import Lanius.Extraction.VerifiedFrontend.Typing.Functions.Chunk1
import Lanius.Extraction.VerifiedFrontend.Typing.Functions.Chunk2
import Lanius.Extraction.VerifiedFrontend.Typing.Functions.Chunk3
import Lanius.Extraction.VerifiedFrontend.Typing.Functions.Chunk4
import Lanius.Extraction.VerifiedFrontend.Typing.Functions.Chunk5
import Lanius.Extraction.VerifiedFrontend.Typing.Functions.Chunk6
import Lanius.Extraction.VerifiedFrontend.Typing.Functions.Chunk7
import Lanius.Extraction.VerifiedFrontend.Typing.Functions.Chunk8
import Lanius.Extraction.VerifiedFrontend.Typing.Functions.Chunk9
import Lanius.Extraction.VerifiedFrontend.Typing.Functions.Chunk10
import Lanius.Extraction.VerifiedFrontend.Typing.Functions.Chunk11
import Lanius.Extraction.VerifiedFrontend.Typing.Functions.Chunk12
import Lanius.Extraction.VerifiedFrontend.Typing.Functions.Chunk13
import Lanius.Extraction.VerifiedFrontend.Typing.Functions.Chunk14
import Lanius.Extraction.VerifiedFrontend.Typing.Functions.Chunk15
import Lanius.Extraction.VerifiedFrontend.Typing.Functions.Chunk16
import Lanius.Extraction.VerifiedFrontend.Typing.Functions.Chunk17
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
private theorem verifiedFrontendPack_constants_present_kernel :
    (CoreTyping.checkConstants verifiedFrontendPackProgramKernel
      verifiedFrontendPackProgramKernel.constants).isSome = true := by
  rw [verifiedFrontendPack_constants_chunks_kernel]
  simp only [CoreTyping.checkConstants_append_isSome,
    verifiedFrontendPack_constants_chunk0_present_kernel,
    verifiedFrontendPack_constants_chunk1_present_kernel,
    verifiedFrontendPack_constants_chunk2_present_kernel,
    verifiedFrontendPack_constants_chunk3_present_kernel,
    verifiedFrontendPack_constants_chunk4_present_kernel,
    verifiedFrontendPack_constants_chunk5_present_kernel,
    verifiedFrontendPack_constants_chunk6_present_kernel,
    verifiedFrontendPack_constants_chunk7_present_kernel,
    verifiedFrontendPack_constants_chunk8_present_kernel,
    verifiedFrontendPack_constants_chunk9_present_kernel, CoreTyping.checkConstants, Bool.true_and]
  rfl
private def verifiedFrontendPackConstantsTypedKernel :=
  (CoreTyping.checkConstants verifiedFrontendPackProgramKernel
    verifiedFrontendPackProgramKernel.constants).get
      verifiedFrontendPack_constants_present_kernel
private theorem verifiedFrontendPack_constants_found_kernel :
    CoreTyping.checkConstants verifiedFrontendPackProgramKernel
      verifiedFrontendPackProgramKernel.constants =
        some verifiedFrontendPackConstantsTypedKernel :=
  parseOptionEqSomeGet verifiedFrontendPack_constants_present_kernel
private theorem verifiedFrontendPack_functions_present_kernel :
    (CoreTyping.checkFunctions verifiedFrontendPackProgramKernel
      verifiedFrontendPackProgramKernel.functions).isSome = true := by
  rw [verifiedFrontendPack_functions_chunks_kernel]
  simp only [CoreTyping.checkFunctions_append_isSome,
    verifiedFrontendPack_functions_chunk0_present_kernel,
    verifiedFrontendPack_functions_chunk1_present_kernel,
    verifiedFrontendPack_functions_chunk2_present_kernel,
    verifiedFrontendPack_functions_chunk3_present_kernel,
    verifiedFrontendPack_functions_chunk4_present_kernel,
    verifiedFrontendPack_functions_chunk5_present_kernel,
    verifiedFrontendPack_functions_chunk6_present_kernel,
    verifiedFrontendPack_functions_chunk7_present_kernel,
    verifiedFrontendPack_functions_chunk8_present_kernel,
    verifiedFrontendPack_functions_chunk9_present_kernel,
    verifiedFrontendPack_functions_chunk10_present_kernel,
    verifiedFrontendPack_functions_chunk11_present_kernel,
    verifiedFrontendPack_functions_chunk12_present_kernel,
    verifiedFrontendPack_functions_chunk13_present_kernel,
    verifiedFrontendPack_functions_chunk14_present_kernel,
    verifiedFrontendPack_functions_chunk15_present_kernel,
    verifiedFrontendPack_functions_chunk16_present_kernel,
    verifiedFrontendPack_functions_chunk17_present_kernel, CoreTyping.checkFunctions, Bool.true_and]
  rfl
private def verifiedFrontendPackFunctionsTypedKernel :=
  (CoreTyping.checkFunctions verifiedFrontendPackProgramKernel
    verifiedFrontendPackProgramKernel.functions).get
      verifiedFrontendPack_functions_present_kernel
private theorem verifiedFrontendPack_functions_found_kernel :
    CoreTyping.checkFunctions verifiedFrontendPackProgramKernel
      verifiedFrontendPackProgramKernel.functions =
        some verifiedFrontendPackFunctionsTypedKernel :=
  parseOptionEqSomeGet verifiedFrontendPack_functions_present_kernel

theorem verifiedFrontendPack_typed_checked_kernel :
    (CoreTyping.checkProgram
      (CoreDecode.program verifiedFrontendPackWireKernel)).isSome = true := by
  change (CoreTyping.checkProgram verifiedFrontendPackProgramKernel).isSome = true
  unfold CoreTyping.checkProgram
  rw [verifiedFrontendPack_constants_found_kernel,
    verifiedFrontendPack_functions_found_kernel]
  rfl

def verifiedFrontendPackTypedKernel :=
  (CoreTyping.checkProgram
    (CoreDecode.program verifiedFrontendPackWireKernel)).get
      verifiedFrontendPack_typed_checked_kernel

theorem verifiedFrontendPackTypedKernel_eq :
    CoreTyping.checkProgram
        (CoreDecode.program verifiedFrontendPackWireKernel) =
      some verifiedFrontendPackTypedKernel :=
  parseOptionEqSomeGet verifiedFrontendPack_typed_checked_kernel

end Lanius.Extraction
