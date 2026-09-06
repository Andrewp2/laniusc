import Lanius.Extraction.TokenChecker
import Lanius.Extraction.KernelReduction
import Lanius.Extraction.ParseChecker

namespace Lanius.Extraction.LaniusEmitterTests

-- These terms are the exact UTF-8 expectations exercised by the GPU-compiled
-- tests in verified_compiler/tests/extraction_syntax.lani. This checks their
-- meaning against the existing validator, not just their Lean syntax.
private def sourceBytes : List Nat := [97,32]
private def raw : List Token := [⟨1,⟨0,0,1⟩⟩,⟨3,⟨0,1,2⟩⟩]
private def canonical : List Token := [⟨1,⟨0,0,1⟩⟩]
private def artifact : Artifact := { Artifact.empty with
  sources := [⟨"input.lani", sourceBytes⟩]
  raw_tokens := some raw
  tokens := canonical
}

theorem tokensAccepted : checkTokenArtifact artifact = true := by kernel_rfl
theorem tokensValid : TokenArtifactValid artifact := checkTokenArtifact_sound tokensAccepted

-- Well-typed terms alone do not authorize substituting a different source.
example : checkTokenArtifact { artifact with sources := [⟨"input.lani", [49,32]⟩] } = false := by
  kernel_rfl
example : checkTokenArtifact { artifact with tokens := [⟨1,⟨0,0,2⟩⟩] } = false := by
  kernel_rfl

#print axioms tokensValid

private def emittedSyntax : Artifact := { Lanius.Extraction.Artifact.empty with sources := [{ path := String.fromUTF8! (ByteArray.mk (([120]: List Nat).toArray.map UInt8.ofNat)), bytes := [97,32] }], raw_tokens := some [⟨1,⟨0,0,1⟩⟩,⟨3,⟨0,1,2⟩⟩], tokens := [⟨1,⟨0,0,1⟩⟩], semantic_token_kinds := [0], parse_nodes := [⟨0,0,0,2,[.token 0]⟩], parse_root := some 0 }
example : checkTokenArtifact emittedSyntax = true := by kernel_rfl
example : emittedSyntax.sources.map SourceFile.path = ["x"] := by kernel_rfl
example : emittedSyntax.parse_root = some 0 := by kernel_rfl

-- Exact packed expression emitted by the Lanius split-token fixture.
private def splitCode : Nat := (2147483648+0+1*32768)
example : isPackedSemanticKind splitCode = true := by kernel_rfl
example : packedInnerKind splitCode = 0 := by kernel_rfl
example : packedOuterKind splitCode = 1 := by kernel_rfl
end Lanius.Extraction.LaniusEmitterTests
