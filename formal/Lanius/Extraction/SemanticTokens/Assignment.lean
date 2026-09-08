import Lanius.Extraction.SemanticTokens.Tree

namespace Lanius.Extraction.SemanticTokens

open Lanius.Compiler.Parser

/-- The two signed words actually emitted by collect. Packing belongs only to
the compact decoder/checker boundary, never to signed-i32 storage. -/
structure Assignment where
  first : Nat
  second : Option Nat
deriving DecidableEq, Repr

def Assignment.words (assignment : Assignment) : List Int :=
  [assignment.first, match assignment.second with | none => -1 | some kind => kind]

def Assignment.code (assignment : Assignment) : Nat :=
  match assignment.second with
  | none => assignment.first
  | some second => packedFlag + assignment.first + second * packedKindBase

def Assignment.Valid (grammar : Grammar) (raw : Nat) (assignment : Assignment) : Prop :=
  assignment.first < grammar.n_kinds ∧
    match assignment.second with
    | none => grammar.canonical_kinds[assignment.first]? = some raw
    | some second => second < grammar.n_kinds ∧ raw = grammar.split_token_kind ∧
        grammar.canonical_kinds[assignment.first]? = some grammar.split_component_kind ∧
        grammar.canonical_kinds[second]? = some grammar.split_component_kind

theorem packed_parts (firstBound : first < 32768) (secondBound : second < 32768) :
    isPackedSemanticKind (packedFlag + first + second * packedKindBase) = true ∧
    packedInnerKind (packedFlag + first + second * packedKindBase) = first ∧
    packedOuterKind (packedFlag + first + second * packedKindBase) = second := by
  refine ⟨?_, ?_, ?_⟩
  · have lower : 2147483648 ≤ 2147483648 + first + second * 32768 := by omega
    have upper : 2147483648 + first + second * 32768 < 4294967296 := by omega
    simp [isPackedSemanticKind, packedFlag, packedLimit, packedKindBase, lower, upper]
  · simp only [packedInnerKind, packedFlag, packedKindBase]
    omega
  · simp only [packedOuterKind, packedFlag, packedKindBase]
    omega

theorem Assignment.Valid.matches {assignment : Assignment} {token : Token}
    (valid : assignment.Valid grammar token.kind) (kindsBound : grammar.n_kinds ≤ 32768) :
    semanticKindMatchesToken grammar token assignment.code = true := by
  obtain ⟨first, second⟩ := assignment
  cases second with
  | none =>
      simp only [Assignment.Valid] at valid
      obtain ⟨bound, canonical⟩ := valid
      have small : first < packedFlag := by simp only [packedFlag]; omega
      have notPacked : isPackedSemanticKind first = false := by
        simp [isPackedSemanticKind, show ¬ packedFlag ≤ first from by omega]
      simp [semanticKindMatchesToken, Assignment.code, notPacked, Grammar.canonicalKind?, bound, canonical]
  | some second =>
      simp only [Assignment.Valid] at valid
      obtain ⟨firstBound, secondBound, raw, inner, outer⟩ := valid
      obtain ⟨packed, firstEq, secondEq⟩ := packed_parts (by omega : first < 32768) (by omega : second < 32768)
      simp [semanticKindMatchesToken, Assignment.code, packed, firstEq, secondEq, Grammar.canonicalKind?, raw, inner, outer]

def findUse? (uses : List Use) (position : Nat) : Option Use :=
  uses.find? (fun use => use.position == position)

def assignmentAt? (uses : List Use) (token : Nat) : Option Assignment := do
  let first ← findUse? uses (2 * token)
  pure ⟨first.kind, (findUse? uses (2 * token + 1)).map Use.kind⟩

private theorem findUse_member (found : findUse? uses position = some use) : use ∈ uses ∧ use.position = position :=
  ⟨List.mem_of_find?_eq_some found, by simpa using List.find?_some found⟩

private theorem findUse_exists (member : use ∈ uses) (atPosition : use.position = position) :
    ∃ found, findUse? uses position = some found := by
  cases found : findUse? uses position with
  | some use => exact ⟨use, rfl⟩
  | none =>
      have absent := List.find?_eq_none.mp found use member
      simp [atPosition] at absent

/-- Reading the two assignment slots from the selected complete terminal path
always succeeds and satisfies the existing semantic-token checker's meaning. -/
theorem ScanPath.assignment (path : ScanPath grammar tokens uses 0 (finalPosition tokens.length))
    (bound : token < tokens.length) (rawFound : tokens[token]? = some raw) :
    ∃ assignment, assignmentAt? uses token = some assignment ∧ assignment.Valid grammar.grammar raw := by
  obtain ⟨use, member, atPosition⟩ := path.first_slot bound
  obtain ⟨first, found⟩ := findUse_exists member atPosition
  obtain ⟨firstMember, firstPosition⟩ := findUse_member found
  have firstValid := (path.member firstMember).1
  have firstToken : first.token = token := by have index := firstValid.tokenEq; omega
  rcases firstValid.shape with whole | splitFirst | splitSecond
  · obtain ⟨_, finish, physical, physicalFound, canonical⟩ := whole
    have noSecond : findUse? uses (2 * token + 1) = none := by
      apply List.find?_eq_none.mpr
      intro other otherMember otherPosition
      have position : other.position = 2 * token + 1 := by simpa using otherPosition
      exact path.no_inside firstMember otherMember (by omega) (by omega)
    have same : physical = raw := by rw [firstToken, rawFound] at physicalFound; exact Option.some.inj physicalFound.symm
    refine ⟨⟨first.kind, none⟩, ?_, firstValid.kindBound, ?_⟩
    · simp [assignmentAt?, found, noSecond]
    · simpa only [same] using canonical
  · obtain ⟨_, finish, physical, canonical, _⟩ := splitFirst
    obtain ⟨next, member, position⟩ := path.next_use firstMember (by simp only [finalPosition]; omega)
    obtain ⟨second, secondFound⟩ := findUse_exists member (by omega : next.position = 2 * token + 1)
    obtain ⟨secondMember, secondPosition⟩ := findUse_member secondFound
    have secondValid := (path.member secondMember).1
    have secondCanonical : grammar.grammar.canonical_kinds[second.kind]? = some grammar.grammar.split_component_kind := by
      rcases secondValid.shape with whole | inner | outer
      · have position := whole.1; omega
      · have position := inner.1; omega
      · exact outer.2.2.2
    have rawKind : raw = grammar.grammar.split_token_kind := by
      rw [firstToken, rawFound] at physical
      exact Option.some.inj physical
    exact ⟨⟨first.kind, some second.kind⟩, by simp [assignmentAt?, found, secondFound],
      firstValid.kindBound, secondValid.kindBound, rawKind, canonical, secondCanonical⟩
  · have position := splitSecond.1
    omega

def assignmentsFrom? (uses : List Use) : Nat → Nat → Option (List Assignment)
  | _, 0 => some []
  | start, count + 1 => do
      let first ← assignmentAt? uses start
      let rest ← assignmentsFrom? uses (start + 1) count
      pure (first :: rest)

end Lanius.Extraction.SemanticTokens
