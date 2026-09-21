import Lanius.Compiler.FrontendArtifact
import Lanius.Compiler.FrontendTypingCertificate
import Lanius.Typing.Check

namespace Lanius.Compiler.FrontendArtifactCheck

open Lanius Lanius.Core Lanius.Extraction

def isTrivia : Function :=
  CoreDecode.function (artifact_pack_function%
    (include_str "../Extraction/Artifacts/frontend_pack.json"),
    "verified_compiler/src/verified/canonical_tokens.lani", "is_trivia")

def matchesAscii : Function :=
  CoreDecode.function (artifact_pack_function%
    (include_str "../Extraction/Artifacts/frontend_pack.json"),
    "verified_compiler/src/verified/canonical_tokens.lani", "matches_ascii")

def keywordKind : Function :=
  CoreDecode.function (artifact_pack_function%
    (include_str "../Extraction/Artifacts/frontend_pack.json"),
    "verified_compiler/src/verified/canonical_tokens.lani", "keyword_kind")

def canonicalKind : Function :=
  CoreDecode.function (artifact_pack_function%
    (include_str "../Extraction/Artifacts/frontend_pack.json"),
    "verified_compiler/src/verified/canonical_tokens.lani", "canonical_kind")

def canonicalizeInPlace : Function :=
  CoreDecode.function
    (artifact_pack_function% (include_str "../Extraction/Artifacts/frontend_pack.json"),
      "verified_compiler/src/verified/canonical_tokens.lani", "canonicalize_in_place")

theorem isTrivia_found :
    FrontendArtifact.frontendProgram.function? isTrivia.id = some isTrivia := by
  rfl

theorem matchesAscii_found :
    FrontendArtifact.frontendProgram.function? matchesAscii.id = some matchesAscii := by
  rfl

theorem keywordKind_found :
    FrontendArtifact.frontendProgram.function? keywordKind.id = some keywordKind := by
  rfl

theorem canonicalKind_found :
    FrontendArtifact.frontendProgram.function? canonicalKind.id = some canonicalKind := by
  rfl

theorem canonicalizeInPlace_found :
    FrontendArtifact.frontendProgram.function? canonicalizeInPlace.id = some canonicalizeInPlace := by
  rfl

/- Keep the checker as the proof-producing computation.  The companion
   certificate stages its list reduction, so this acceptance theorem does not
   require a recursion-depth override or an untrusted evaluator. -/
def frontendProgramCheck :
    Option (Typing.Check.ProofOf (Typing.ProgramWellTyped FrontendArtifact.frontendProgram)) :=
  Typing.Check.checkProgramWellTyped FrontendArtifact.frontendProgram

theorem frontendProgramCheck_accepted : frontendProgramCheck.isSome = true := by
  simpa [frontendProgramCheck] using
    FrontendTypingCertificate.frontendProgramCheck_accepted

theorem frontendProgramCheck_sound {checked}
    (accepted : frontendProgramCheck = some checked) :
    Typing.ProgramWellTyped FrontendArtifact.frontendProgram :=
  Typing.Check.checkProgramWellTyped_evidence accepted

theorem frontendProgram_wellTyped :
    Typing.ProgramWellTyped FrontendArtifact.frontendProgram := by
  obtain ⟨checked, accepted⟩ := Option.isSome_iff_exists.mp frontendProgramCheck_accepted
  exact frontendProgramCheck_sound accepted

end Lanius.Compiler.FrontendArtifactCheck
