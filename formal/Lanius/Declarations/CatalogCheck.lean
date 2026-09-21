import Lanius.Declarations.Occurrences

namespace Lanius.Declarations

open Lanius

open Lanius.Surface

def occurrencesCovered (headers : List DeclarationHeader) :
    List DeclarationOccurrence → Bool
  | [] => true
  | occurrence :: tail =>
      headers.any (fun header => decide (header.source = occurrence)) &&
        occurrencesCovered headers tail

theorem occurrencesCovered_sound {headers : List DeclarationHeader}
    {occurrences : List DeclarationOccurrence}
    (accepted : occurrencesCovered headers occurrences = true) :
    ∀ occurrence, occurrence ∈ occurrences →
      ∃ header, header ∈ headers ∧ header.source = occurrence := by
  induction occurrences with
  | nil => simp
  | cons head tail ih =>
      simp only [occurrencesCovered, Bool.and_eq_true] at accepted
      intro occurrence member
      rcases List.mem_cons.mp member with (rfl | member)
      · rcases List.any_eq_true.mp accepted.1 with ⟨header, member, equal⟩
        exact ⟨header, member, of_decide_eq_true equal⟩
      · exact ih accepted.2 occurrence member

abbrev DeclarationIdsCompatible : DeclarationHeader → DeclarationHeader → Prop :=
  fun left right => left.declaration ≠ right.declaration ∨ left.source = right.source

abbrev OccurrencesCompatible : DeclarationHeader → DeclarationHeader → Prop :=
  fun left right => left.source ≠ right.source ∨ left = right

def checkCatalogRows (headers : List DeclarationHeader) :
    Option (ProofOf (List.Pairwise DeclarationIdsCompatible headers ∧
      List.Pairwise OccurrencesCompatible headers)) :=
  if ids : List.Pairwise DeclarationIdsCompatible headers then
    if sources : List.Pairwise OccurrencesCompatible headers then
      some ⟨⟨ids, sources⟩⟩
    else none
  else none

theorem pairwiseIds_unique {headers : List DeclarationHeader}
    (accepted : List.Pairwise DeclarationIdsCompatible headers) :
    DeclarationIdsUnique ⟨headers⟩ := by
  induction headers with
  | nil => simp [DeclarationIdsUnique]
  | cons head tail ih =>
      intro left leftMember right rightMember equal
      simp only [List.mem_cons] at leftMember rightMember
      rcases leftMember with rfl | leftMember <;>
        rcases rightMember with rfl | rightMember
      · rfl
      · exact Or.elim ((List.pairwise_cons.mp accepted).1 right rightMember)
          (fun h => False.elim (h equal)) id
      · exact Or.elim ((List.pairwise_cons.mp accepted).1 left leftMember)
          (fun h => False.elim (h equal.symm)) Eq.symm
      · exact ih (List.pairwise_cons.mp accepted).2 left leftMember right rightMember equal

theorem pairwiseOccurrences_unique {headers : List DeclarationHeader}
    (accepted : List.Pairwise OccurrencesCompatible headers) :
    OccurrencesUnique ⟨headers⟩ := by
  have same : ∀ left, left ∈ headers → ∀ right, right ∈ headers →
      left.source = right.source → left = right := by
    induction headers with
    | nil => simp
    | cons head tail ih =>
        intro left leftMember right rightMember equal
        simp only [List.mem_cons] at leftMember rightMember
        rcases leftMember with rfl | leftMember <;>
          rcases rightMember with rfl | rightMember
        · rfl
        · exact Or.elim ((List.pairwise_cons.mp accepted).1 right rightMember)
            (fun h => False.elim (h equal)) id
        · exact Or.elim ((List.pairwise_cons.mp accepted).1 left leftMember)
            (fun h => False.elim (h equal.symm)) Eq.symm
        · exact ih (List.pairwise_cons.mp accepted).2 left leftMember right rightMember equal
  intro left leftMember right rightMember equal
  exact congrArg DeclarationHeader.declaration
    (same left leftMember right rightMember equal)

theorem pairwiseOccurrences_same {headers : List DeclarationHeader}
    (accepted : List.Pairwise OccurrencesCompatible headers) :
    ∀ left, left ∈ headers → ∀ right, right ∈ headers →
      left.source = right.source → left = right := by
  induction headers with
  | nil => simp
  | cons head tail ih =>
      intro left leftMember right rightMember equal
      simp only [List.mem_cons] at leftMember rightMember
      rcases leftMember with rfl | leftMember <;>
        rcases rightMember with rfl | rightMember
      · rfl
      · exact Or.elim ((List.pairwise_cons.mp accepted).1 right rightMember)
          (fun h => False.elim (h equal)) id
      · exact Or.elim ((List.pairwise_cons.mp accepted).1 left leftMember)
          (fun h => False.elim (h equal.symm)) Eq.symm
      · exact ih (List.pairwise_cons.mp accepted).2 left leftMember right rightMember equal

theorem catalogCovers_of {pack : SourcePack} {catalog : Catalog}
    (covered : ∀ occurrence, occurrence ∈ normalizedOccurrences pack →
      ∃ header, header ∈ catalog.headers ∧ header.source = occurrence)
    (headerMatches : ∀ header, header ∈ catalog.headers → HeaderMatches pack header)
    (unique : List.Pairwise OccurrencesCompatible catalog.headers) :
    CatalogCovers pack catalog := by
  constructor
  · intro occurrence occurrenceFound
    obtain ⟨selected, selectedMember, selectedSource⟩ :=
      covered occurrence (occurs_mem_normalized occurrenceFound)
    refine ⟨selected, selectedMember, selectedSource, headerMatches selected selectedMember, ?_⟩
    intro candidate candidateMember candidateSource candidateMatches
    exact pairwiseOccurrences_same unique candidate candidateMember selected selectedMember
      (candidateSource.trans selectedSource.symm)
  · exact headerMatches

def checkHeaderMatches (pack : SourcePack) (header : DeclarationHeader) :
    Option (ProofOf (HeaderMatches pack header)) :=
  match header.source with
  | .item address =>
      match hfile : pack.file? address.file with
      | none => none
      | some file =>
          match hitem : file.contents.items[address.index]? with
          | some (.function function) =>
              let expected : DeclarationHeader :=
                { source := .item address, moduleId := file.moduleInfo.id,
                  declaration := header.declaration, kind := .function,
                  lookupNamespace := some .value, name := some function.name,
                  visibility := visibility function.isPublic }
              if shape : header = expected then
                have itemFound : pack.item? address = some (.function function) := by
                  simp [SourcePack.item?, hfile, hitem]
                some ⟨by simpa [shape] using
                  (HeaderMatches.function hfile itemFound : HeaderMatches pack expected)⟩
              else none
          | some (.externFunction function) =>
              let expected : DeclarationHeader :=
                { source := .item address, moduleId := file.moduleInfo.id,
                  declaration := header.declaration, kind := .externalFunction,
                  lookupNamespace := some .value, name := some function.name,
                  visibility := visibility function.isPublic }
              if shape : header = expected then
                have itemFound : pack.item? address = some (.externFunction function) := by
                  simp [SourcePack.item?, hfile, hitem]
                some ⟨by simpa [shape] using
                  (HeaderMatches.externalFunction hfile itemFound : HeaderMatches pack expected)⟩
              else none
          | some (.constant name isPublic type value) =>
              let expected : DeclarationHeader :=
                { source := .item address, moduleId := file.moduleInfo.id,
                  declaration := header.declaration, kind := .constant,
                  lookupNamespace := some .value, name := some name,
                  visibility := visibility isPublic }
              if shape : header = expected then
                have itemFound : pack.item? address = some (.constant name isPublic type value) := by
                  simp [SourcePack.item?, hfile, hitem]
                some ⟨by simpa [shape] using
                  (HeaderMatches.constant hfile itemFound : HeaderMatches pack expected)⟩
              else none
          | some (.typeAlias name isPublic parameters predicates target) =>
              let expected : DeclarationHeader :=
                { source := .item address, moduleId := file.moduleInfo.id,
                  declaration := header.declaration, kind := .typeAlias,
                  lookupNamespace := some .type, name := some name,
                  visibility := visibility isPublic }
              if shape : header = expected then
                have itemFound : pack.item? address =
                    some (.typeAlias name isPublic parameters predicates target) := by
                  simp [SourcePack.item?, hfile, hitem]
                some ⟨by simpa [shape] using
                  (HeaderMatches.typeAlias hfile itemFound : HeaderMatches pack expected)⟩
              else none
          | some (.structure declaration) =>
              let expected : DeclarationHeader :=
                { source := .item address, moduleId := file.moduleInfo.id,
                  declaration := header.declaration, kind := .structureType,
                  lookupNamespace := some .type, name := some declaration.name,
                  visibility := visibility declaration.isPublic }
              if shape : header = expected then
                have itemFound : pack.item? address = some (.structure declaration) := by
                  simp [SourcePack.item?, hfile, hitem]
                some ⟨by simpa [shape] using
                  (HeaderMatches.structureType hfile itemFound : HeaderMatches pack expected)⟩
              else none
          | some (.enumeration declaration) =>
              let expected : DeclarationHeader :=
                { source := .item address, moduleId := file.moduleInfo.id,
                  declaration := header.declaration, kind := .enumeration,
                  lookupNamespace := some .type, name := some declaration.name,
                  visibility := visibility declaration.isPublic }
              if shape : header = expected then
                have itemFound : pack.item? address = some (.enumeration declaration) := by
                  simp [SourcePack.item?, hfile, hitem]
                some ⟨by simpa [shape] using
                  (HeaderMatches.enumeration hfile itemFound : HeaderMatches pack expected)⟩
              else none
          | some (.trait declaration) =>
              let expected : DeclarationHeader :=
                { source := .item address, moduleId := file.moduleInfo.id,
                  declaration := header.declaration, kind := .trait,
                  lookupNamespace := some .type, name := some declaration.name,
                  visibility := visibility declaration.isPublic }
              if shape : header = expected then
                have itemFound : pack.item? address = some (.trait declaration) := by
                  simp [SourcePack.item?, hfile, hitem]
                some ⟨by simpa [shape] using
                  (HeaderMatches.trait hfile itemFound : HeaderMatches pack expected)⟩
              else none
          | some (.implementation declaration) =>
              let expected : DeclarationHeader :=
                { source := .item address, moduleId := file.moduleInfo.id,
                  declaration := header.declaration, kind := .implementation,
                  visibility := visibility declaration.isPublic }
              if shape : header = expected then
                have itemFound : pack.item? address = some (.implementation declaration) := by
                  simp [SourcePack.item?, hfile, hitem]
                some ⟨by simpa [shape] using
                  (HeaderMatches.implementation hfile itemFound : HeaderMatches pack expected)⟩
              else none
          | _ => none
  | .enumVariant parent index =>
      match hfile : pack.file? parent.file with
      | none => none
      | some file =>
          match hitem : file.contents.items[parent.index]? with
          | some (.enumeration declaration) =>
              match hchild : declaration.variants[index]? with
              | none => none
              | some variant =>
                  let expected : DeclarationHeader :=
                    { source := .enumVariant parent index, moduleId := file.moduleInfo.id,
                      declaration := header.declaration, kind := .enumVariant,
                      lookupNamespace := some .value, name := some variant.name,
                      visibility := visibility declaration.isPublic }
                  if shape : header = expected then
                    have itemFound : pack.item? parent = some (.enumeration declaration) := by
                      simp [SourcePack.item?, hfile, hitem]
                    some ⟨by simpa [shape] using
                      (HeaderMatches.enumVariant hfile itemFound hchild : HeaderMatches pack expected)⟩
                  else none
          | _ => none
  | .traitMethod parent index =>
      match hfile : pack.file? parent.file with
      | none => none
      | some file =>
          match hitem : file.contents.items[parent.index]? with
          | some (.trait declaration) =>
              match hchild : declaration.methods[index]? with
              | none => none
              | some method =>
                  let expected : DeclarationHeader :=
                    { source := .traitMethod parent index, moduleId := file.moduleInfo.id,
                      declaration := header.declaration, kind := .traitMethod,
                      name := some method.signature.name,
                      visibility := visibility method.signature.isPublic }
                  if shape : header = expected then
                    have itemFound : pack.item? parent = some (.trait declaration) := by
                      simp [SourcePack.item?, hfile, hitem]
                    some ⟨by simpa [shape] using
                      (HeaderMatches.traitMethod hfile itemFound hchild : HeaderMatches pack expected)⟩
                  else none
          | _ => none
  | .implementationMethod parent index =>
      match hfile : pack.file? parent.file with
      | none => none
      | some file =>
          match hitem : file.contents.items[parent.index]? with
          | some (.implementation declaration) =>
              match hchild : declaration.methods[index]? with
              | none => none
              | some method =>
                  let expected : DeclarationHeader :=
                    { source := .implementationMethod parent index,
                      moduleId := file.moduleInfo.id, declaration := header.declaration,
                      kind := .implementationMethod, name := some method.name,
                      visibility := visibility method.isPublic }
                  if shape : header = expected then
                    have itemFound : pack.item? parent = some (.implementation declaration) := by
                      simp [SourcePack.item?, hfile, hitem]
                    some ⟨by simpa [shape] using
                      (HeaderMatches.implementationMethod hfile itemFound hchild :
                        HeaderMatches pack expected)⟩
                  else none
          | _ => none

def checkAllHeaderMatches (pack : SourcePack) :
    (headers : List DeclarationHeader) →
      Option (ProofOf (∀ header, header ∈ headers → HeaderMatches pack header))
  | [] => some ⟨by simp⟩
  | head :: tail => do
      let headProof ← checkHeaderMatches pack head
      let tailProof ← checkAllHeaderMatches pack tail
      pure ⟨by
        intro header member
        simp only [List.mem_cons] at member
        rcases member with rfl | member
        · exact headProof.down
        · exact tailProof.down header member⟩

def checkCatalogWellFormed (pack : SourcePack) (catalog : Catalog) :
    Option (ProofOf (CatalogWellFormed pack catalog)) := do
  let headerEvidence ← checkAllHeaderMatches pack catalog.headers
  let covered : ProofOf (∀ occurrence, occurrence ∈ normalizedOccurrences pack →
      ∃ header, header ∈ catalog.headers ∧ header.source = occurrence) ←
    if accepted : occurrencesCovered catalog.headers (normalizedOccurrences pack) = true
      then some ⟨occurrencesCovered_sound accepted⟩ else none
  let rows ← checkCatalogRows catalog.headers
  pure ⟨⟨catalogCovers_of covered.down headerEvidence.down rows.down.2,
    pairwiseIds_unique rows.down.1, pairwiseOccurrences_unique rows.down.2⟩⟩

theorem checkCatalogWellFormed_evidence {pack : SourcePack} {catalog : Catalog}
    {formed : ProofOf (CatalogWellFormed pack catalog)}
    (_accepted : checkCatalogWellFormed pack catalog = some formed) :
    CatalogWellFormed pack catalog := formed.down

end Lanius.Declarations
