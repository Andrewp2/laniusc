import Lanius.Compiler.FrontendArtifact
import Lanius.Typing.Check

namespace Lanius.Compiler.FrontendTypingCertificate

open Lanius Lanius.Core

private theorem functionsAppendIsSome (program : Program) (first second : List Function)
    (firstAccepted : (Typing.Check.checkFunctionsWellTyped program first).isSome = true)
    (secondAccepted : (Typing.Check.checkFunctionsWellTyped program second).isSome = true) :
    (Typing.Check.checkFunctionsWellTyped program (first ++ second)).isSome = true := by
  induction first with
  | nil => simpa using secondAccepted
  | cons head tail inductionTail =>
      cases checked : Typing.Check.checkFunctionWellTyped program head with
      | none => simp [Typing.Check.checkFunctionsWellTyped, checked] at firstAccepted
      | some checked =>
          have tailAccepted :
              (Typing.Check.checkFunctionsWellTyped program tail).isSome = true := by
            cases tailChecked : Typing.Check.checkFunctionsWellTyped program tail with
            | none =>
                simp [Typing.Check.checkFunctionsWellTyped, checked, tailChecked] at firstAccepted
            | some _ => simp
          have appendTail := inductionTail tailAccepted
          cases appendChecked :
              Typing.Check.checkFunctionsWellTyped program (tail ++ second) with
          | none => simp [appendChecked] at appendTail
          | some appendChecked =>
              simp [Typing.Check.checkFunctionsWellTyped, checked, appendChecked]

private theorem constantsAppendIsSome (program : Program) (first second : List Constant)
    (firstAccepted : (Typing.Check.checkConstantsWellTyped program first).isSome = true)
    (secondAccepted : (Typing.Check.checkConstantsWellTyped program second).isSome = true) :
    (Typing.Check.checkConstantsWellTyped program (first ++ second)).isSome = true := by
  induction first with
  | nil => simpa using secondAccepted
  | cons head tail inductionTail =>
      cases checked : Typing.Check.checkConstantWellTyped program head with
      | none => simp [Typing.Check.checkConstantsWellTyped, checked] at firstAccepted
      | some checked =>
          have tailAccepted :
              (Typing.Check.checkConstantsWellTyped program tail).isSome = true := by
            cases tailChecked : Typing.Check.checkConstantsWellTyped program tail with
            | none =>
                simp [Typing.Check.checkConstantsWellTyped, checked, tailChecked] at firstAccepted
            | some _ => simp
          have appendTail := inductionTail tailAccepted
          cases appendChecked :
              Typing.Check.checkConstantsWellTyped program (tail ++ second) with
          | none => simp [appendChecked] at appendTail
          | some appendChecked =>
              simp [Typing.Check.checkConstantsWellTyped, checked, appendChecked]

private theorem functionsChunksIsSome (program : Program) :
    ∀ chunks : List (List Function),
      (∀ chunk ∈ chunks,
        (Typing.Check.checkFunctionsWellTyped program chunk).isSome = true) →
      (Typing.Check.checkFunctionsWellTyped program chunks.flatten).isSome = true
  | [], _ => rfl
  | chunk :: chunks, each => by
      have head := each chunk (by simp)
      have tail := functionsChunksIsSome program chunks
        (by intro chunk member; exact each chunk (by simp [member]))
      simpa using functionsAppendIsSome program chunk chunks.flatten head tail

private theorem constantsChunksIsSome (program : Program) :
    ∀ chunks : List (List Constant),
      (∀ chunk ∈ chunks,
        (Typing.Check.checkConstantsWellTyped program chunk).isSome = true) →
      (Typing.Check.checkConstantsWellTyped program chunks.flatten).isSome = true
  | [], _ => rfl
  | chunk :: chunks, each => by
      have head := each chunk (by simp)
      have tail := constantsChunksIsSome program chunks
        (by intro chunk member; exact each chunk (by simp [member]))
      simpa using constantsAppendIsSome program chunk chunks.flatten head tail

private theorem dropTakeAppend {α : Type} (items : List α) (offset : Nat) :
    (items.drop offset).take 20 ++ items.drop (offset + 20) = items.drop offset := by
  simpa [List.drop_drop] using List.take_append_drop 20 (items.drop offset)

private def functionChunks : List (List Function) := [
  FrontendArtifact.frontendProgram.functions.take 20,
  FrontendArtifact.frontendProgram.functions.drop 20 |>.take 20,
  FrontendArtifact.frontendProgram.functions.drop 40 |>.take 20,
  FrontendArtifact.frontendProgram.functions.drop 60]

private def constantChunks : List (List Constant) := [
  FrontendArtifact.frontendProgram.constants.take 20,
  FrontendArtifact.frontendProgram.constants.drop 20 |>.take 20,
  FrontendArtifact.frontendProgram.constants.drop 40 |>.take 20,
  FrontendArtifact.frontendProgram.constants.drop 60 |>.take 20,
  FrontendArtifact.frontendProgram.constants.drop 80 |>.take 20,
  FrontendArtifact.frontendProgram.constants.drop 100]

private theorem functionChunks_flatten :
    functionChunks.flatten = FrontendArtifact.frontendProgram.functions := by
  simp only [functionChunks, List.flatten_cons, List.flatten_nil, List.append_nil]
  rw [dropTakeAppend _ 40, dropTakeAppend _ 20]
  simpa only [List.drop_zero, Nat.zero_add] using
    (dropTakeAppend FrontendArtifact.frontendProgram.functions 0)

private theorem constantChunks_flatten :
    constantChunks.flatten = FrontendArtifact.frontendProgram.constants := by
  simp only [constantChunks, List.flatten_cons, List.flatten_nil, List.append_nil]
  rw [dropTakeAppend _ 80, dropTakeAppend _ 60, dropTakeAppend _ 40,
    dropTakeAppend _ 20]
  simpa only [List.drop_zero, Nat.zero_add] using
    (dropTakeAppend FrontendArtifact.frontendProgram.constants 0)

private theorem functionsFull :
    (Typing.Check.checkFunctionsWellTyped FrontendArtifact.frontendProgram
      FrontendArtifact.frontendProgram.functions).isSome = true := by
  have each : ∀ chunk ∈ functionChunks,
      (Typing.Check.checkFunctionsWellTyped FrontendArtifact.frontendProgram chunk).isSome = true := by
    intro chunk member
    simp only [functionChunks, List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with h | h | h | h
    all_goals subst chunk <;> rfl
  have result := functionsChunksIsSome FrontendArtifact.frontendProgram functionChunks each
  rw [functionChunks_flatten] at result
  exact result

private theorem constantsFull :
    (Typing.Check.checkConstantsWellTyped FrontendArtifact.frontendProgram
      FrontendArtifact.frontendProgram.constants).isSome = true := by
  have each : ∀ chunk ∈ constantChunks,
      (Typing.Check.checkConstantsWellTyped FrontendArtifact.frontendProgram chunk).isSome = true := by
    intro chunk member
    simp only [constantChunks, List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with h | h | h | h | h | h
    all_goals subst chunk <;> rfl
  have result := constantsChunksIsSome FrontendArtifact.frontendProgram constantChunks each
  rw [constantChunks_flatten] at result
  exact result

theorem frontendProgramCheck_accepted :
    (Typing.Check.checkProgramWellTyped FrontendArtifact.frontendProgram).isSome = true := by
  have constantsAccepted := constantsFull
  have functionsAccepted := functionsFull
  cases constantsChecked : Typing.Check.checkConstantsWellTyped
      FrontendArtifact.frontendProgram FrontendArtifact.frontendProgram.constants with
  | none => simp [constantsChecked] at constantsAccepted
  | some constantsChecked =>
      cases functionsChecked : Typing.Check.checkFunctionsWellTyped
          FrontendArtifact.frontendProgram FrontendArtifact.frontendProgram.functions with
      | none => simp [functionsChecked] at functionsAccepted
      | some functionsChecked =>
          simp [Typing.Check.checkProgramWellTyped, constantsChecked, functionsChecked]

end Lanius.Compiler.FrontendTypingCertificate
