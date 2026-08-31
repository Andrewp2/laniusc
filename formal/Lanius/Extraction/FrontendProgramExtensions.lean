import Lanius.ProgramSemanticsAgreement
import Lanius.Extraction.VerifiedLexerProgram

namespace Lanius.Extraction

open Lanius.Core

set_option maxRecDepth 100000
set_option maxHeartbeats 2000000

theorem verifiedFrontendCore_extends_verifiedFrontendLexerCore :
    verifiedFrontendLexerCore.RuntimeExtends verifiedFrontendCore := by
  constructor
  · native_decide
  · intro id declaration found
    change List.find? (fun row => row.id == id)
      verifiedFrontendLexerCore.constants = some declaration at found
    change List.find? (fun row => row.id == id)
      (verifiedFrontendLexerCore.constants ++ _) = some declaration
    rw [List.find?_append, found]
    rfl
  · intro id declaration found
    change List.find? (fun row => row.id == id)
      verifiedFrontendLexerCore.functions = some declaration at found
    change List.find? (fun row => row.id == id)
      (verifiedFrontendLexerCore.functions ++ _) = some declaration
    rw [List.find?_append, found]
    rfl

theorem verifiedFrontendCore_extends_verifiedFrontendDigitsCore :
    verifiedFrontendDigitsCore.RuntimeExtends verifiedFrontendCore := by
  constructor
  · native_decide
  · intro id declaration found
    change List.find? (fun row => row.id == id)
      verifiedFrontendDigitsCore.constants = some declaration at found
    simp [verifiedFrontendDigitsCore, verifiedFrontendDigitsArtifact,
      CoreDecode.program] at found
  · intro id declaration found
    change List.find? (fun row => row.id == id)
      verifiedFrontendDigitsCore.functions = some declaration at found
    have selected := List.find?_eq_some_iff_append.mp found
    have predicate := selected.1
    obtain ⟨before, after, decomposition, _⟩ := selected.2
    have member : declaration ∈ verifiedFrontendDigitsCore.functions := by
      rw [decomposition]
      simp
    simp [verifiedFrontendDigitsCore, verifiedFrontendDigitsArtifact,
      CoreDecode.program] at member
    rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
      simp at predicate <;> subst id <;> rfl

end Lanius.Extraction
