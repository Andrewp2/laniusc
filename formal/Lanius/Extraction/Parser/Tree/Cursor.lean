import Lanius.Extraction.Parser.Tree.Layout

namespace Lanius.Extraction.ParserTreeLayout

open Lanius.Compiler.Parser

/-- Append one expanded occurrence to the completed sibling prefix. -/
def appendTree (done : Layout (List Child)) (last : Layout Child) : Layout (List Child) :=
  ⟨done.words ++ last.words, done.offsets ++ last.offsets, done.roots ++ [last.roots]⟩

theorem forest_snoc (trees : List Lanius.Compiler.Parser.ParseTree)
    (tree : Lanius.Compiler.Parser.ParseTree) (nodeBase wordBase : Nat) :
    forestFrom nodeBase wordBase (trees ++ [tree]) =
      appendTree (forestFrom nodeBase wordBase trees)
        (treeFrom (nodeBase + (forestFrom nodeBase wordBase trees).offsets.length)
          (wordBase + (forestFrom nodeBase wordBase trees).words.length) tree) := by
  induction trees generalizing nodeBase wordBase with
  | nil => simp [forestFrom, appendTree]
  | cons first rest ih =>
    simp [forestFrom, ih, appendTree, List.length_append, List.append_assoc, Nat.add_assoc]

/-- A completed sibling prefix never requires more storage than the whole
    selected sibling sequence, for either record words or node offsets. -/
theorem forest_prefix_lengths (trees more : List Lanius.Compiler.Parser.ParseTree) (nodeBase wordBase : Nat) :
    (forestFrom nodeBase wordBase trees).words.length ≤ (forestFrom nodeBase wordBase (trees ++ more)).words.length ∧
    (forestFrom nodeBase wordBase trees).offsets.length ≤ (forestFrom nodeBase wordBase (trees ++ more)).offsets.length := by
  induction trees generalizing nodeBase wordBase with
  | nil => simp [forestFrom]
  | cons tree trees ih =>
    have tail := ih (nodeBase + (treeFrom nodeBase wordBase tree).offsets.length)
      (wordBase + (treeFrom nodeBase wordBase tree).words.length)
    simp only [List.cons_append, forestFrom, List.length_append]
    exact ⟨Nat.add_le_add_left tail.1 _, Nat.add_le_add_left tail.2 _⟩

/-- The parent is reserved before its descendants. Completed child references
    have dense output IDs; pending children still contain workspace state IDs.
    This describes only meaningful words, leaving caller prefix/suffix framing
    to the runtime resource invariant. -/
def partialWords (parent : EarleyState) (done : Layout (List Child)) (pending : List Child) : List Int :=
  recordHeader parent.production parent.origin parent.position parent.dot ++
    (done.roots ++ pending).flatMap derivationChildWords ++ done.words

theorem partialWords_length (parent : EarleyState) (done : Layout (List Child)) (pending : List Child)
    (count : done.roots.length + pending.length = parent.dot) :
    (partialWords parent done pending).length = 4 + parent.dot * 3 + done.words.length := by
  simp only [partialWords, List.length_append, child_words_length, count,
    recordHeader, List.length_cons, List.length_nil]

theorem partialWords_initial (parent : EarleyState) (children : List Child)
    (count : children.length = parent.dot) :
    partialWords parent ⟨[], [], []⟩ children = derivationRecordWords parent children := by
  simp [partialWords, recordHeader, derivationRecordWords, count]

theorem partialWords_complete (parent : EarleyState) (trees : List Lanius.Compiler.Parser.ParseTree)
    (nodeBase wordBase nonterminal : Nat) (count : trees.length = parent.dot) :
    partialWords parent (forestFrom nodeBase (wordBase + 4 + parent.dot * 3) trees) [] =
      (treeFrom nodeBase wordBase
        (.nonterminal parent.production nonterminal parent.origin parent.position trees)).words := by
  simp only [partialWords, treeFrom, List.append_nil, count]

/-- Consuming a token changes the cursor but no record or offset words. -/
theorem partialWords_token (parent : EarleyState) (done : Layout (List Child)) (pending : List Child) :
    partialWords parent (appendTree done (treeFrom nodeBase wordBase (.terminal token kind))) pending =
      partialWords parent done (.token token kind :: pending) := by
  simp [partialWords, appendTree, treeFrom, List.append_assoc]

/-- The next unread triple retains the workspace reference, including after
    earlier siblings have appended descendant records. -/
theorem partialWords_head (before after : List Int) (parent : EarleyState)
    (done : Layout (List Child)) (child : Child) (pending : List Child) :
    let values := before ++ partialWords parent done (child :: pending) ++ after
    let slot := before.length + 4 + done.roots.length * 3
    values[slot]? = some (childTag child) ∧
      values[slot + 1]? = some (childPayload child) ∧
      values[slot + 2]? = some (childKind child) := by
  let leading := before ++ recordHeader parent.production parent.origin parent.position parent.dot ++
    done.roots.flatMap derivationChildWords
  have length : leading.length = before.length + 4 + done.roots.length * 3 := by
    simp only [leading, List.length_append, child_words_length, recordHeader,
      List.length_cons, List.length_nil]
  have select (leading trailing : List Int) :
      (leading ++ derivationChildWords child ++ trailing)[leading.length]? = some (childTag child) ∧
      (leading ++ derivationChildWords child ++ trailing)[leading.length + 1]? = some (childPayload child) ∧
      (leading ++ derivationChildWords child ++ trailing)[leading.length + 2]? = some (childKind child) := by
    induction leading with
    | nil => simp [derivationChildWords]
    | cons word leading ih => simpa [Nat.add_assoc] using ih
  have selected := select leading (pending.flatMap derivationChildWords ++ done.words ++ after)
  rw [length] at selected
  simpa only [partialWords, List.flatMap_append, List.flatMap_cons, List.append_assoc, leading] using selected

private theorem rewrite_state_payload (before after : List Int) (oldId newId : Nat) :
    (before ++ derivationChildWords (.state oldId) ++ after).set (before.length + 1) (Int.ofNat newId) =
      before ++ derivationChildWords (.state newId) ++ after := by
  induction before with
  | nil => simp [derivationChildWords, childTag, childPayload, childKind]
  | cons word before ih => simpa [Nat.add_assoc] using congrArg (List.cons word) ih

/-- After the recursive child appends its records, the parent changes only
    that child's payload word. Its tag/kind, siblings, and descendants are kept. -/
theorem partialWords_state (before after : List Int)
    (parent : EarleyState) (done : Layout (List Child)) (pending : List Child)
    (child : Layout Child) (root : child.roots = .state newId) :
    (before ++ partialWords parent done (.state oldId :: pending) ++ child.words ++ after).set
        (before.length + 4 + done.roots.length * 3 + 1) (Int.ofNat newId) =
      before ++ partialWords parent (appendTree done child) pending ++ after := by
  let leading := before ++ recordHeader parent.production parent.origin parent.position parent.dot ++
    done.roots.flatMap derivationChildWords
  have leadingLength : leading.length = before.length + 4 + done.roots.length * 3 := by
    simp only [leading, List.length_append, child_words_length, recordHeader,
      List.length_cons, List.length_nil]
  have rewritten := rewrite_state_payload leading
    (pending.flatMap derivationChildWords ++ done.words ++ child.words ++ after) oldId newId
  rw [leadingLength] at rewritten
  simpa only [partialWords, appendTree, root, List.flatMap_append, List.flatMap_cons,
    List.flatMap_nil, List.append_nil, List.append_assoc, leading] using rewritten

/-- Appending a nonterminal makes the rewritten parent payload equal exactly
    to the recursive call's returned node count minus one. -/
theorem appended_root (done : Layout (List Child))
    (tree : Lanius.Compiler.Parser.ParseTree)
    (nonterminal : ∃ production nt start finish children,
      tree = .nonterminal production nt start finish children) :
    (treeFrom (nodeBase + done.offsets.length) wordBase tree).roots =
      .state (nodeBase + (appendTree done (treeFrom (nodeBase + done.offsets.length) wordBase tree)).offsets.length - 1) := by
  obtain ⟨production, nt, start, finish, children, rfl⟩ := nonterminal
  rw [nonterminal_root_last]
  simp only [appendTree, List.length_append, Nat.add_assoc]

end Lanius.Extraction.ParserTreeLayout
