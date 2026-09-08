import Lanius.Compiler.ParserTree
import Lanius.Extraction.ParseChecker

namespace Lanius.Extraction.SemanticTokens

open Lanius.Compiler.Parser

/-- A leaf occurrence keeps its lattice position as well as its physical token
and semantic kind. The collector's assignment address is this position. -/
structure Use where
  position : Nat
  finish : Nat
  token : Nat
  kind : Nat
deriving DecidableEq, Repr

def Use.slot (use : Use) := use.token * 2 + use.position % 2

structure Use.Valid (grammar : IndexedGrammar) (tokens : List Nat) (use : Use) : Prop where
  tokenEq : use.token = use.position / 2
  kindBound : use.kind < grammar.grammar.n_kinds
  scanned : scanTerminal grammar tokens use.position use.kind = some use.finish

theorem Use.Valid.slot {use : Use} (valid : use.Valid grammar tokens) : use.slot = use.position := by
  simp only [Use.slot, valid.tokenEq]
  omega

theorem Use.Valid.advances {use : Use} (valid : use.Valid grammar tokens) : use.position < use.finish :=
  scanTerminal_some_gt valid.scanned

theorem Use.Valid.tokenBound {use : Use} (valid : use.Valid grammar tokens) : use.token < tokens.length := by
  have scanned := valid.scanned
  unfold scanTerminal at scanned
  split at scanned <;> try contradiction
  rename_i raw canonical found kind
  rw [valid.tokenEq]
  exact (List.getElem?_eq_some_iff.mp found).1

/-- The same three cases as the parser's declarative scan: a whole token,
the first half of a split token, or its second half. -/
def Use.Shape (grammar : IndexedGrammar) (tokens : List Nat) (use : Use) : Prop :=
  (use.position = 2 * use.token ∧ use.finish = use.position + 2 ∧
    ∃ raw, tokens[use.token]? = some raw ∧ grammar.grammar.canonical_kinds[use.kind]? = some raw) ∨
  (use.position = 2 * use.token ∧ use.finish = use.position + 1 ∧
    tokens[use.token]? = some grammar.grammar.split_token_kind ∧
    grammar.grammar.canonical_kinds[use.kind]? = some grammar.grammar.split_component_kind ∧
    grammar.grammar.split_token_kind ≠ grammar.grammar.split_component_kind) ∨
  (use.position = 2 * use.token + 1 ∧ use.finish = use.position + 1 ∧
    tokens[use.token]? = some grammar.grammar.split_token_kind ∧
    grammar.grammar.canonical_kinds[use.kind]? = some grammar.grammar.split_component_kind)

theorem Use.Valid.shape {use : Use} (valid : use.Valid grammar tokens) : use.Shape grammar tokens := by
  have scanned := valid.scanned
  have tokenEq := valid.tokenEq
  unfold scanTerminal at scanned
  split at scanned <;> try contradiction
  rename_i raw canonical found kind
  rw [← tokenEq] at found
  unfold scanTerminalStep at scanned
  split at scanned
  · rename_i odd
    split at scanned
    · rename_i splitKinds
      obtain ⟨rfl, rfl⟩ := splitKinds
      simp only [Option.some.injEq] at scanned
      exact Or.inr (Or.inr ⟨by omega, scanned.symm, found, kind⟩)
    · contradiction
  · rename_i even
    split at scanned
    · rename_i same
      subst canonical
      simp only [Option.some.injEq] at scanned
      exact Or.inl ⟨by omega, scanned.symm, raw, found, kind⟩
    · rename_i different
      split at scanned
      · rename_i splitKinds
        obtain ⟨rfl, rfl⟩ := splitKinds
        simp only [Option.some.injEq] at scanned
        exact Or.inr (Or.inl ⟨by omega, scanned.symm, found, kind, different⟩)
      · contradiction

/-- A source-order path through terminal occurrences. Nonterminal boundaries
may be empty, but every terminal strictly advances the token lattice. -/
inductive ScanPath (grammar : IndexedGrammar) (tokens : List Nat) : List Use → Nat → Nat → Prop
  | nil : ScanPath grammar tokens [] position position
  | cons (valid : use.Valid grammar tokens) (tail : ScanPath grammar tokens uses use.finish finish) :
      ScanPath grammar tokens (use :: uses) use.position finish

theorem ScanPath.append (left : ScanPath grammar tokens uses start middle)
    (right : ScanPath grammar tokens more middle finish) : ScanPath grammar tokens (uses ++ more) start finish := by
  induction left with
  | nil => exact right
  | cons valid tail ih => exact .cons valid (ih right)

theorem ScanPath.monotone (path : ScanPath grammar tokens uses start finish) : start ≤ finish := by
  induction path with
  | nil => exact Nat.le_refl _
  | cons valid tail ih => exact Nat.le_trans (Nat.le_of_lt valid.advances) ih

theorem ScanPath.member (path : ScanPath grammar tokens uses start finish) (member : use ∈ uses) :
    use.Valid grammar tokens ∧ start ≤ use.position ∧ use.finish ≤ finish := by
  induction path with
  | nil => simp at member
  | cons valid tail ih =>
      rcases List.mem_cons.mp member with rfl | later
      · exact ⟨valid, Nat.le_refl _, tail.monotone⟩
      · obtain ⟨validUse, lower, upper⟩ := ih later
        exact ⟨validUse, Nat.le_trans (Nat.le_of_lt valid.advances) lower, upper⟩

theorem ScanPath.covers (path : ScanPath grammar tokens uses start finish)
    (lower : start ≤ position) (upper : position < finish) :
    ∃ use ∈ uses, use.position ≤ position ∧ position < use.finish := by
  induction path with
  | nil => omega
  | @cons uses finish use valid tail ih =>
      by_cases inside : position < use.finish
      · exact ⟨use, by simp, lower, inside⟩
      · obtain ⟨found, member, low, high⟩ := ih (by omega) upper
        exact ⟨found, List.mem_cons_of_mem _ member, low, high⟩

/-- No other terminal begins inside a consumed span. This is stronger than
distinct addresses and also excludes a spurious second half of a whole token. -/
theorem ScanPath.no_inside (path : ScanPath grammar tokens uses start finish)
    (left : first ∈ uses) (right : second ∈ uses)
    (later : first.position < second.position) (inside : second.position < first.finish) : False := by
  induction path with
  | nil => simp at left
  | cons valid tail ih =>
      rcases List.mem_cons.mp left with rfl | leftTail
      · rcases List.mem_cons.mp right with rfl | rightTail
        · omega
        · have bounds := tail.member rightTail
          omega
      · rcases List.mem_cons.mp right with rfl | rightTail
        · have bounds := tail.member leftTail
          have advances := valid.advances
          omega
        · exact ih leftTail rightTail

theorem ScanPath.positions_unique (path : ScanPath grammar tokens uses start finish) :
    (uses.map Use.position).Nodup := by
  induction path with
  | nil => simp
  | cons valid tail ih =>
      rw [List.map_cons, List.nodup_cons]
      refine ⟨?_, ih⟩
      intro member
      obtain ⟨use, member, positionEq⟩ := List.mem_map.mp member
      have bound := (tail.member member).2.1
      have advances := valid.advances
      omega

theorem ScanPath.first_use (path : ScanPath grammar tokens uses start finish) (nonempty : start < finish) :
    ∃ use ∈ uses, use.position = start := by
  cases path with
  | nil => omega
  | cons valid tail => exact ⟨_, by simp, rfl⟩

theorem ScanPath.next_use (path : ScanPath grammar tokens uses start finish)
    (member : use ∈ uses) (beforeEnd : use.finish < finish) :
    ∃ next ∈ uses, next.position = use.finish := by
  induction path with
  | nil => simp at member
  | cons valid tail ih =>
      rcases List.mem_cons.mp member with rfl | later
      · obtain ⟨next, member, position⟩ := tail.first_use beforeEnd
        exact ⟨next, List.mem_cons_of_mem _ member, position⟩
      · obtain ⟨next, member, position⟩ := ih later beforeEnd
        exact ⟨next, List.mem_cons_of_mem _ member, position⟩

theorem ScanPath.slots_unique (path : ScanPath grammar tokens uses start finish) :
    (uses.map Use.slot).Nodup := by
  have same : uses.map Use.slot = uses.map Use.position :=
    List.map_congr_left (fun use member => (path.member member).1.slot)
  rw [same]
  exact path.positions_unique

/-- Complete paths assign every physical token's first slot. No guessed token
count, successful collector result, or semantic-validator premise is used. -/
theorem ScanPath.first_slot (path : ScanPath grammar tokens uses 0 (finalPosition tokens.length))
    (bound : token < tokens.length) : ∃ use ∈ uses, use.position = 2 * token := by
  obtain ⟨use, member, lower, upper⟩ := path.covers (position := 2 * token) (by omega) (by simp [finalPosition]; omega)
  have valid := (path.member member).1
  refine ⟨use, member, ?_⟩
  rcases valid.shape with whole | first | second
  · obtain ⟨even, finish, _⟩ := whole
    omega
  · obtain ⟨even, finish, _⟩ := first
    omega
  · obtain ⟨odd, finish, _⟩ := second
    omega

end Lanius.Extraction.SemanticTokens
