import Lanius.Extraction.SurfaceReconstruct

namespace Lanius.Extraction.Reconstruction

private theorem lift_map_bind {α β γ : Type} (f : α → β) (xs : Option α)
    (next : β → SurfaceBuild γ) :
    (do let x ← xs.map f; next x : SurfaceBuild γ) =
      (do let x ← xs; next (f x) : SurfaceBuild γ) := by
  funext state
  cases xs <;> rfl

variable [ArtifactAccess] {Ref : Type} [ParseReference Ref] {artifact : Artifact}
  (agrees : ParseReference.Agrees (Ref := Ref) artifact)

include agrees

theorem node_eq (ref : Ref) :
    artifactNode? artifact (ParseReference.id ref) = artifactNode? artifact ref :=
  agrees.node_eq ref

theorem production_eq (ref : Ref) :
    artifactProduction? artifact (ParseReference.id ref) = artifactProduction? artifact ref := by
  unfold artifactProduction?
  rw [node_eq agrees]

theorem child_eq (ref : Ref) (index : Nat) :
    artifactChildNode? artifact (ParseReference.id ref) index =
      (artifactChildNode? artifact ref index).map ParseReference.id :=
  agrees.child_eq ref index

theorem token_eq (ref : Ref) (index : Nat) :
    artifactChildToken? artifact (ParseReference.id ref) index =
      artifactChildToken? artifact ref index := by
  unfold artifactChildToken?
  rw [node_eq agrees]

theorem expect_eq (ref : Ref) (production : Nat) :
    artifactExpectProduction artifact (ParseReference.id ref) production =
      artifactExpectProduction artifact ref production := by
  unfold artifactExpectProduction
  rw [production_eq agrees]

theorem name_eq (ref : Ref) (index : Nat) :
    reconstructName artifact (ParseReference.id ref) index = reconstructName artifact ref index := by
  unfold reconstructName
  rw [token_eq agrees]

theorem arrayLength_eq (ref : Ref) :
    reconstructArrayLength artifact (ParseReference.id ref) = reconstructArrayLength artifact ref := by
  unfold reconstructArrayLength
  simp only [production_eq agrees, token_eq agrees, name_eq agrees]

theorem literal_eq (ref : Ref) (production : Nat) :
    reconstructTokenLiteral artifact (ParseReference.id ref) production =
      reconstructTokenLiteral artifact ref production := by
  unfold reconstructTokenLiteral
  rw [token_eq agrees]

set_option linter.unusedSimpArgs false in
theorem paths_eq (fuel : Nat) :
    (∀ (ref : Ref), reconstructPathSegment fuel artifact (ParseReference.id ref) =
      reconstructPathSegment fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructPath fuel artifact (ParseReference.id ref) =
      reconstructPath fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructPathTail fuel artifact (ParseReference.id ref) =
      reconstructPathTail fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructPathTypeArgTail fuel artifact (ParseReference.id ref) =
      reconstructPathTypeArgTail fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructPathTypeArgTailAfterComma fuel artifact (ParseReference.id ref) =
      reconstructPathTypeArgTailAfterComma fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructTypeExpr fuel artifact (ParseReference.id ref) =
      reconstructTypeExpr fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructTypePath fuel artifact (ParseReference.id ref) =
      reconstructTypePath fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructTypePathTail fuel artifact (ParseReference.id ref) =
      reconstructTypePathTail fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructTypeArgsOpt fuel artifact (ParseReference.id ref) =
      reconstructTypeArgsOpt fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructTypeArgTail fuel artifact (ParseReference.id ref) =
      reconstructTypeArgTail fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructTypeArgTailAfterComma fuel artifact (ParseReference.id ref) =
      reconstructTypeArgTailAfterComma fuel artifact ref) := by
  induction fuel with
  | zero => exact ⟨(fun _ => rfl), (fun _ => rfl), (fun _ => rfl), (fun _ => rfl), (fun _ => rfl), (fun _ => rfl), (fun _ => rfl), (fun _ => rfl), (fun _ => rfl), (fun _ => rfl), (fun _ => rfl)⟩
  | succ fuel ih =>
    refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
    all_goals
      intros
      first
      | rw [reconstructPathSegment, reconstructPathSegment]
      | rw [reconstructPath, reconstructPath]
      | rw [reconstructPathTail, reconstructPathTail]
      | rw [reconstructPathTypeArgTail, reconstructPathTypeArgTail]
      | rw [reconstructPathTypeArgTailAfterComma, reconstructPathTypeArgTailAfterComma]
      | rw [reconstructTypeExpr, reconstructTypeExpr]
      | rw [reconstructTypePath, reconstructTypePath]
      | rw [reconstructTypePathTail, reconstructTypePathTail]
      | rw [reconstructTypeArgsOpt, reconstructTypeArgsOpt]
      | rw [reconstructTypeArgTail, reconstructTypeArgTail]
      | rw [reconstructTypeArgTailAfterComma, reconstructTypeArgTailAfterComma]
    all_goals
      simp only [production_eq agrees, child_eq agrees, token_eq agrees, expect_eq agrees,
        name_eq agrees, arrayLength_eq agrees, literal_eq agrees,
        ParseReference.indexed_id, lift_map_bind, ih]

set_option linter.unusedSimpArgs false in
theorem expressions_eq (fuel : Nat) :
    (∀ (ref : Ref), reconstructExpr fuel artifact (ParseReference.id ref) =
      reconstructExpr fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructAssign fuel artifact (ParseReference.id ref) =
      reconstructAssign fuel artifact ref) ∧
    (∀ (ref : Ref) (layer : ReconstructBinaryLayer), reconstructBinaryLayer fuel artifact (ParseReference.id ref) layer =
      reconstructBinaryLayer fuel artifact ref layer) ∧
    (∀ (layer : ReconstructBinaryLayer) (ref : Ref) (left : SurfaceExpr), reconstructBinaryTail fuel artifact layer (ParseReference.id ref) left =
      reconstructBinaryTail fuel artifact layer ref left) ∧
    (∀ (ref : Ref), reconstructUnary fuel artifact (ParseReference.id ref) =
      reconstructUnary fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructPostfix fuel artifact (ParseReference.id ref) =
      reconstructPostfix fuel artifact ref) ∧
    (∀ (ref : Ref) (left : SurfaceExpr), reconstructPostfixTail fuel artifact (ParseReference.id ref) left =
      reconstructPostfixTail fuel artifact ref left) ∧
    (∀ (ref : Ref), reconstructArguments fuel artifact (ParseReference.id ref) =
      reconstructArguments fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructArgumentTail fuel artifact (ParseReference.id ref) =
      reconstructArgumentTail fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructArgumentTailAfterComma fuel artifact (ParseReference.id ref) =
      reconstructArgumentTailAfterComma fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructPrimary fuel artifact (ParseReference.id ref) =
      reconstructPrimary fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructArrayElements fuel artifact (ParseReference.id ref) =
      reconstructArrayElements fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructArrayElementTail fuel artifact (ParseReference.id ref) =
      reconstructArrayElementTail fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructArrayElementTailAfterComma fuel artifact (ParseReference.id ref) =
      reconstructArrayElementTailAfterComma fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructStructLiteralFields fuel artifact (ParseReference.id ref) =
      reconstructStructLiteralFields fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructStructLiteralField fuel artifact (ParseReference.id ref) =
      reconstructStructLiteralField fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructStructLiteralFieldTail fuel artifact (ParseReference.id ref) =
      reconstructStructLiteralFieldTail fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructStructLiteralFieldTailAfterComma fuel artifact (ParseReference.id ref) =
      reconstructStructLiteralFieldTailAfterComma fuel artifact ref) := by
  induction fuel with
  | zero => exact ⟨(fun _ => rfl), (fun _ => rfl), (fun _ _ => rfl), (fun _ _ _ => rfl), (fun _ => rfl), (fun _ => rfl), (fun _ _ => rfl), (fun _ => rfl), (fun _ => rfl), (fun _ => rfl), (fun _ => rfl), (fun _ => rfl), (fun _ => rfl), (fun _ => rfl), (fun _ => rfl), (fun _ => rfl), (fun _ => rfl), (fun _ => rfl)⟩
  | succ fuel ih =>
    refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
    all_goals
      intros
      first
      | rw [reconstructExpr, reconstructExpr]
      | rw [reconstructAssign, reconstructAssign]
      | rw [reconstructBinaryLayer, reconstructBinaryLayer]
      | rw [reconstructBinaryTail, reconstructBinaryTail]
      | rw [reconstructUnary, reconstructUnary]
      | rw [reconstructPostfix, reconstructPostfix]
      | rw [reconstructPostfixTail, reconstructPostfixTail]
      | rw [reconstructArguments, reconstructArguments]
      | rw [reconstructArgumentTail, reconstructArgumentTail]
      | rw [reconstructArgumentTailAfterComma, reconstructArgumentTailAfterComma]
      | rw [reconstructPrimary, reconstructPrimary]
      | rw [reconstructArrayElements, reconstructArrayElements]
      | rw [reconstructArrayElementTail, reconstructArrayElementTail]
      | rw [reconstructArrayElementTailAfterComma, reconstructArrayElementTailAfterComma]
      | rw [reconstructStructLiteralFields, reconstructStructLiteralFields]
      | rw [reconstructStructLiteralField, reconstructStructLiteralField]
      | rw [reconstructStructLiteralFieldTail, reconstructStructLiteralFieldTail]
      | rw [reconstructStructLiteralFieldTailAfterComma, reconstructStructLiteralFieldTailAfterComma]
    all_goals
      simp only [production_eq agrees, child_eq agrees, token_eq agrees, expect_eq agrees,
        name_eq agrees, arrayLength_eq agrees, literal_eq agrees,
        ParseReference.indexed_id, lift_map_bind, ih, paths_eq agrees fuel]

set_option linter.unusedSimpArgs false in
theorem statements_eq (fuel : Nat) :
    (∀ (ref : Ref), reconstructStatements fuel artifact (ParseReference.id ref) =
      reconstructStatements fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructStatement fuel artifact (ParseReference.id ref) =
      reconstructStatement fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructOptionalType fuel artifact (ParseReference.id ref) =
      reconstructOptionalType fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructOptionalInitializer fuel artifact (ParseReference.id ref) =
      reconstructOptionalInitializer fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructOptionalReturn fuel artifact (ParseReference.id ref) =
      reconstructOptionalReturn fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructElseTail fuel artifact (ParseReference.id ref) =
      reconstructElseTail fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructBlock fuel artifact (ParseReference.id ref) =
      reconstructBlock fuel artifact ref) := by
  induction fuel with
  | zero => exact ⟨(fun _ => rfl), (fun _ => rfl), (fun _ => rfl), (fun _ => rfl), (fun _ => rfl), (fun _ => rfl), (fun _ => rfl)⟩
  | succ fuel ih =>
    refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
    all_goals
      intros
      first
      | rw [reconstructStatements, reconstructStatements]
      | rw [reconstructStatement, reconstructStatement]
      | rw [reconstructOptionalType, reconstructOptionalType]
      | rw [reconstructOptionalInitializer, reconstructOptionalInitializer]
      | rw [reconstructOptionalReturn, reconstructOptionalReturn]
      | rw [reconstructElseTail, reconstructElseTail]
      | rw [reconstructBlock, reconstructBlock]
    all_goals
      simp only [production_eq agrees, child_eq agrees, token_eq agrees, expect_eq agrees,
        name_eq agrees, arrayLength_eq agrees, literal_eq agrees,
        ParseReference.indexed_id, lift_map_bind, ih, paths_eq agrees fuel, expressions_eq agrees fuel]

set_option linter.unusedSimpArgs false in
theorem parameters_eq (fuel : Nat) :
    (∀ (ref : Ref), reconstructParameters fuel artifact (ParseReference.id ref) =
      reconstructParameters fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructParameter fuel artifact (ParseReference.id ref) =
      reconstructParameter fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructParameterTail fuel artifact (ParseReference.id ref) =
      reconstructParameterTail fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructParameterTailAfterComma fuel artifact (ParseReference.id ref) =
      reconstructParameterTailAfterComma fuel artifact ref) := by
  induction fuel with
  | zero => exact ⟨(fun _ => rfl), (fun _ => rfl), (fun _ => rfl), (fun _ => rfl)⟩
  | succ fuel ih =>
    refine ⟨?_, ?_, ?_, ?_⟩
    all_goals
      intros
      first
      | rw [reconstructParameters, reconstructParameters]
      | rw [reconstructParameter, reconstructParameter]
      | rw [reconstructParameterTail, reconstructParameterTail]
      | rw [reconstructParameterTailAfterComma, reconstructParameterTailAfterComma]
    all_goals
      simp only [production_eq agrees, child_eq agrees, token_eq agrees, expect_eq agrees,
        name_eq agrees, arrayLength_eq agrees, literal_eq agrees,
        ParseReference.indexed_id, lift_map_bind, ih, paths_eq agrees fuel]

set_option linter.unusedSimpArgs false in
theorem fields_eq (fuel : Nat) :
    (∀ (ref : Ref), reconstructStructFields fuel artifact (ParseReference.id ref) =
      reconstructStructFields fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructStructField fuel artifact (ParseReference.id ref) =
      reconstructStructField fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructStructFieldTail fuel artifact (ParseReference.id ref) =
      reconstructStructFieldTail fuel artifact ref) ∧
    (∀ (ref : Ref), reconstructStructFieldTailAfterComma fuel artifact (ParseReference.id ref) =
      reconstructStructFieldTailAfterComma fuel artifact ref) := by
  induction fuel with
  | zero => exact ⟨(fun _ => rfl), (fun _ => rfl), (fun _ => rfl), (fun _ => rfl)⟩
  | succ fuel ih =>
    refine ⟨?_, ?_, ?_, ?_⟩
    all_goals
      intros
      first
      | rw [reconstructStructFields, reconstructStructFields]
      | rw [reconstructStructField, reconstructStructField]
      | rw [reconstructStructFieldTail, reconstructStructFieldTail]
      | rw [reconstructStructFieldTailAfterComma, reconstructStructFieldTailAfterComma]
    all_goals
      simp only [production_eq agrees, child_eq agrees, token_eq agrees, expect_eq agrees,
        name_eq agrees, arrayLength_eq agrees, literal_eq agrees,
        ParseReference.indexed_id, lift_map_bind, ih, paths_eq agrees fuel]

set_option linter.unusedSimpArgs false in
theorem function_eq (fuel : Nat) (ref : Ref) (isPublic : Bool) :
    reconstructFunction fuel artifact (ParseReference.id ref) isPublic =
      reconstructFunction fuel artifact ref isPublic := by
  unfold reconstructFunction
  simp only [production_eq agrees, child_eq agrees, token_eq agrees, expect_eq agrees,
    name_eq agrees, ParseReference.indexed_id, lift_map_bind,
    paths_eq agrees fuel, parameters_eq agrees fuel, statements_eq agrees fuel]

set_option linter.unusedSimpArgs false in
theorem struct_eq (fuel : Nat) (ref : Ref) (isPublic : Bool) :
    reconstructStruct fuel artifact (ParseReference.id ref) isPublic =
      reconstructStruct fuel artifact ref isPublic := by
  unfold reconstructStruct
  simp only [production_eq agrees, child_eq agrees, token_eq agrees, expect_eq agrees,
    name_eq agrees, ParseReference.indexed_id, lift_map_bind, fields_eq agrees fuel]

set_option linter.unusedSimpArgs false in
theorem items_eq (fuel : Nat) :
    (∀ ref : Ref, reconstructItem fuel artifact (ParseReference.id ref) =
      reconstructItem fuel artifact ref) ∧
    (∀ ref : Ref, reconstructItems fuel artifact (ParseReference.id ref) =
      reconstructItems fuel artifact ref) := by
  induction fuel with
  | zero => exact ⟨(fun _ => rfl), (fun _ => rfl)⟩
  | succ fuel ih =>
    refine ⟨?_, ?_⟩
    all_goals
      intro ref
      first
      | rw [reconstructItem, reconstructItem]
      | rw [reconstructItems, reconstructItems]
    all_goals
      simp only [production_eq agrees, child_eq agrees, token_eq agrees, expect_eq agrees,
        name_eq agrees, ParseReference.indexed_id, lift_map_bind,
        paths_eq agrees fuel, expressions_eq agrees fuel, function_eq agrees fuel,
        struct_eq agrees fuel, ih, pure_bind]

theorem file_eq (fuel : Nat) (ref : Ref) :
    reconstructFile fuel artifact (ParseReference.id ref) =
      reconstructFile fuel artifact ref := by
  unfold reconstructFile
  simp only [expect_eq agrees, child_eq agrees, ParseReference.indexed_id,
    lift_map_bind, items_eq agrees fuel]

end Lanius.Extraction.Reconstruction
