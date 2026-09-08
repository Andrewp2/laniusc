import Lanius.Compiler.ParserDerivation
import Lanius.Extraction.ParserTreeArtifact

namespace Lanius.Extraction.ParserTreeLayout

open Lanius.Compiler.Parser

/-- Record words are in preorder; offsets are indexed by postorder node ID.
    A terminal root contributes only a child triple, not a node record. -/
structure Layout (α : Type) where
  words : List Int
  offsets : List Nat
  roots : α
deriving Repr

def recordHeader (production start finish count : Nat) : List Int :=
  [Int.ofNat production, Int.ofNat start, Int.ofNat finish, Int.ofNat count]

mutual
  /-- Model the storage order of `parse_tree.visit`: reserve the parent record,
      expand children left-to-right, then allocate the parent's postorder ID. -/
  def treeFrom (nodeBase wordBase : Nat) : Lanius.Compiler.Parser.ParseTree → Layout Child
    | .terminal token kind => ⟨[], [], .token token kind⟩
    | .nonterminal production _ start finish children =>
      let nested := forestFrom nodeBase (wordBase + 4 + children.length * 3) children
      ⟨recordHeader production start finish children.length ++
          nested.roots.flatMap derivationChildWords ++ nested.words,
        nested.offsets ++ [wordBase], .state (nodeBase + nested.offsets.length)⟩

  def forestFrom (nodeBase wordBase : Nat) : List Lanius.Compiler.Parser.ParseTree → Layout (List Child)
    | [] => ⟨[], [], []⟩
    | tree :: trees =>
      let first := treeFrom nodeBase wordBase tree
      let rest := forestFrom (nodeBase + first.offsets.length) (wordBase + first.words.length) trees
      ⟨first.words ++ rest.words, first.offsets ++ rest.offsets, first.roots :: rest.roots⟩
end

/-- Forget semantic token kinds only at the existing `ParseChild` boundary.
    A sentinel is not a valid materialized child reference. -/
def parseChild? : Child → Option ParseChild
  | .none => none
  | .token token _ => some (.token token)
  | .state node => some (.node node)

theorem forest_roots_length (trees : List Lanius.Compiler.Parser.ParseTree) :
    (forestFrom nodeBase wordBase trees).roots.length = trees.length := by
  induction trees generalizing nodeBase wordBase with
  | nil => rfl
  | cons tree trees ih => simp only [forestFrom, List.length_cons, ih]

mutual
  /-- The materializer's node count and root reference agree with the existing
      canonical postorder serializer, despite its different physical word order. -/
  theorem tree_references (tree : Lanius.Compiler.Parser.ParseTree) (nodeBase wordBase : Nat) :
      (treeFrom nodeBase wordBase tree).offsets.length = (serializeParseTreeFrom nodeBase tree).1.length ∧
      parseChild? (treeFrom nodeBase wordBase tree).roots = some (serializeParseTreeFrom nodeBase tree).2 := by
    cases tree with
    | terminal token kind => exact ⟨rfl, rfl⟩
    | nonterminal production nonterminal start finish children =>
      obtain ⟨count, references⟩ := forest_references children nodeBase (wordBase + 4 + children.length * 3)
      simp [treeFrom, serializeParseTreeFrom, parseChild?, count]
  termination_by sizeOf tree

  theorem forest_references (trees : List Lanius.Compiler.Parser.ParseTree) (nodeBase wordBase : Nat) :
      (forestFrom nodeBase wordBase trees).offsets.length = (serializeParseTreesFrom nodeBase trees).1.length ∧
      (forestFrom nodeBase wordBase trees).roots.map parseChild? =
        (serializeParseTreesFrom nodeBase trees).2.map some := by
    cases trees with
    | nil => exact ⟨rfl, rfl⟩
    | cons tree trees =>
      obtain ⟨headCount, headRef⟩ := tree_references tree nodeBase wordBase
      obtain ⟨tailCount, tailRefs⟩ := forest_references trees
        (nodeBase + (treeFrom nodeBase wordBase tree).offsets.length)
        (wordBase + (treeFrom nodeBase wordBase tree).words.length)
      simp only [headCount] at tailCount tailRefs
      simp only [forestFrom, serializeParseTreesFrom, List.length_append, List.map_cons, headCount, headRef]
      exact ⟨tailCount ▸ rfl, tailRefs ▸ rfl⟩
  termination_by sizeOf trees
end

theorem nonterminal_root_last :
    (treeFrom nodeBase wordBase (.nonterminal production nonterminal start finish children)).roots =
      .state (nodeBase + (treeFrom nodeBase wordBase
        (.nonterminal production nonterminal start finish children)).offsets.length - 1) := by
  simp [treeFrom]

theorem nonterminal_offset_last :
    (treeFrom nodeBase wordBase (.nonterminal production nonterminal start finish children)).offsets.getLast? =
      some wordBase := by
  simp [treeFrom]

mutual
  def treeWords : Lanius.Compiler.Parser.ParseTree → Nat
    | .terminal _ _ => 0
    | .nonterminal _ _ _ _ children => 4 + children.length * 3 + forestWords children

  def forestWords : List Lanius.Compiler.Parser.ParseTree → Nat
    | [] => 0
    | tree :: trees => treeWords tree + forestWords trees
end

theorem child_words_length (children : List Child) :
    (children.flatMap derivationChildWords).length = children.length * 3 := by
  induction children with
  | nil => rfl
  | cons child children ih => simp [derivationChildWords, ih, Nat.add_mul]

mutual
  /-- Exact record capacity, independent of starting IDs and word offsets. -/
  theorem tree_words_length (tree : Lanius.Compiler.Parser.ParseTree) (nodeBase wordBase : Nat) :
      (treeFrom nodeBase wordBase tree).words.length = treeWords tree := by
    cases tree with
    | terminal token kind => rfl
    | nonterminal production nonterminal start finish children =>
      have nested := forest_words_length children nodeBase (wordBase + 4 + children.length * 3)
      simp only [treeFrom, treeWords, List.length_append, child_words_length,
        forest_roots_length, nested, recordHeader, List.length_cons, List.length_nil]
  termination_by sizeOf tree

  theorem forest_words_length (trees : List Lanius.Compiler.Parser.ParseTree) (nodeBase wordBase : Nat) :
      (forestFrom nodeBase wordBase trees).words.length = forestWords trees := by
    cases trees with
    | nil => rfl
    | cons tree trees =>
      have first := tree_words_length tree nodeBase wordBase
      have rest := forest_words_length trees
        (nodeBase + (treeFrom nodeBase wordBase tree).offsets.length)
        (wordBase + (treeFrom nodeBase wordBase tree).words.length)
      simp only [forestFrom, forestWords, List.length_append]
      rw [rest, first]
  termination_by sizeOf trees
end

mutual
  /-- Every stored node offset points to room for a complete four-word header. -/
  theorem tree_offsets_bounded (tree : Lanius.Compiler.Parser.ParseTree) (nodeBase wordBase : Nat) :
      ∀ offset ∈ (treeFrom nodeBase wordBase tree).offsets,
        wordBase ≤ offset ∧ offset + 4 ≤ wordBase + treeWords tree := by
    cases tree with
    | terminal token kind => simp [treeFrom]
    | nonterminal production nonterminal start finish children =>
      intro offset member
      change offset ∈ (forestFrom nodeBase (wordBase + 4 + children.length * 3) children).offsets ++ [wordBase] at member
      rcases List.mem_append.mp member with nested | root
      · have bound := forest_offsets_bounded children nodeBase (wordBase + 4 + children.length * 3) offset nested
        simp only [treeWords]
        constructor <;> omega
      · have equal := List.mem_singleton.mp root
        subst offset
        simp [treeWords, Nat.add_assoc]
  termination_by sizeOf tree

  theorem forest_offsets_bounded (trees : List Lanius.Compiler.Parser.ParseTree) (nodeBase wordBase : Nat) :
      ∀ offset ∈ (forestFrom nodeBase wordBase trees).offsets,
        wordBase ≤ offset ∧ offset + 4 ≤ wordBase + forestWords trees := by
    cases trees with
    | nil => simp [forestFrom]
    | cons tree trees =>
      intro offset member
      change offset ∈ (treeFrom nodeBase wordBase tree).offsets ++
        (forestFrom (nodeBase + (treeFrom nodeBase wordBase tree).offsets.length)
          (wordBase + (treeFrom nodeBase wordBase tree).words.length) trees).offsets at member
      rcases List.mem_append.mp member with first | rest
      · have bound := tree_offsets_bounded tree nodeBase wordBase offset first
        simp only [forestWords]
        constructor <;> omega
      · have bound := forest_offsets_bounded trees
          (nodeBase + (treeFrom nodeBase wordBase tree).offsets.length)
          (wordBase + (treeFrom nodeBase wordBase tree).words.length) offset rest
        rw [tree_words_length] at bound
        simp only [forestWords]
        constructor <;> omega
  termination_by sizeOf trees
end

/-- A node's offset locates its complete record, including the exact child
    references. The grammar supplies nonterminal names; records store production
    IDs. Token kinds remain in the words but are erased by `ParseChild`. -/
def RecordAt (wordBase : Nat) (words : List Int) (offset : Nat) (node : ParseNode) : Prop :=
  ∃ (before : List Int) (children : List Child) (after : List Int),
    words = before ++ recordHeader node.production node.position_start node.position_end
      children.length ++ children.flatMap derivationChildWords ++ after ∧
    offset = wordBase + before.length ∧
    children.map parseChild? = node.children.map some

/-- Offsets and canonical nodes correspond one-for-one in postorder. -/
inductive RecordsAt (wordBase : Nat) (words : List Int) : List Nat → List ParseNode → Prop where
  | nil : RecordsAt wordBase words [] []
  | cons : RecordAt wordBase words offset node → RecordsAt wordBase words offsets nodes →
      RecordsAt wordBase words (offset :: offsets) (node :: nodes)

theorem RecordAt.frame (stored : RecordAt (wordBase + before.length) words offset node)
    (after : List Int) : RecordAt wordBase (before ++ words ++ after) offset node := by
  obtain ⟨leading, children, trailing, rfl, position, references⟩ := stored
  refine ⟨before ++ leading, children, trailing ++ after, ?_, ?_, references⟩
  · simp only [List.append_assoc]
  · simpa [List.length_append, Nat.add_assoc] using position

theorem RecordsAt.frame
    (stored : RecordsAt (wordBase + before.length) words offsets nodes)
    (after : List Int) : RecordsAt wordBase (before ++ words ++ after) offsets nodes := by
  induction stored with
  | nil => exact .nil
  | cons head tail ih => exact .cons (head.frame after) ih

theorem RecordsAt.append (left : RecordsAt wordBase words offsets nodes)
    (right : RecordsAt wordBase words moreOffsets moreNodes) :
    RecordsAt wordBase words (offsets ++ moreOffsets) (nodes ++ moreNodes) := by
  induction left with
  | nil => exact right
  | cons head tail ih => exact .cons head ih

theorem RecordsAt.lookup {index : Nat} (stored : RecordsAt wordBase words offsets nodes)
    (found : nodes[index]? = some node) :
    ∃ offset, offsets[index]? = some offset ∧ RecordAt wordBase words offset node := by
  induction stored generalizing index with
  | nil => simp at found
  | @cons offset current offsets nodes head tail ih =>
    cases index with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at found
      subst current
      exact ⟨offset, rfl, head⟩
    | succ index => exact ih found

/-- Capacity for an offset includes the entire child array, not only its header. -/
theorem RecordAt.bounds (stored : RecordAt wordBase words offset node) :
    wordBase ≤ offset ∧ offset + 4 + node.children.length * 3 ≤ wordBase + words.length := by
  obtain ⟨before, children, after, rfl, rfl, references⟩ := stored
  have lengthEq := congrArg List.length references
  simp only [List.length_map] at lengthEq
  simp only [List.length_append, child_words_length, recordHeader, List.length_cons, List.length_nil]
  constructor <;> omega

mutual
  /-- Every emitted offset locates the matching canonical node's full record.
      This relates physical storage, not just counts or root references. -/
  theorem tree_records (tree : Lanius.Compiler.Parser.ParseTree) (nodeBase wordBase : Nat) :
      RecordsAt wordBase (treeFrom nodeBase wordBase tree).words
        (treeFrom nodeBase wordBase tree).offsets (serializeParseTreeFrom nodeBase tree).1 := by
    cases tree with
    | terminal token kind => exact .nil
    | nonterminal production nonterminal start finish children =>
      let nested := forestFrom nodeBase (wordBase + 4 + children.length * 3) children
      let canonical := serializeParseTreesFrom nodeBase children
      let header := recordHeader production start finish children.length ++
        nested.roots.flatMap derivationChildWords
      have headerLength : header.length = 4 + children.length * 3 := by
        simp only [header, List.length_append, child_words_length, nested,
          forest_roots_length, recordHeader, List.length_cons, List.length_nil]
      have nestedRecords := forest_records children nodeBase (wordBase + 4 + children.length * 3)
      have framed : RecordsAt wordBase (header ++ nested.words) nested.offsets canonical.1 := by
        have baseEq : wordBase + header.length = wordBase + 4 + children.length * 3 := by omega
        have inner : RecordsAt (wordBase + header.length) nested.words nested.offsets canonical.1 := by
          rw [baseEq]
          exact nestedRecords
        simpa only [List.append_nil] using inner.frame (before := header) []
      have root : RecordAt wordBase (header ++ nested.words) wordBase
          { production := production, nonterminal := nonterminal,
            position_start := start, position_end := finish, children := canonical.2 } := by
        refine ⟨[], nested.roots, nested.words, ?_, by simp, ?_⟩
        · simp only [List.nil_append, header, nested, forest_roots_length, List.append_assoc]
        · exact (forest_references children nodeBase (wordBase + 4 + children.length * 3)).2
      exact framed.append (.cons root .nil)
  termination_by sizeOf tree

  theorem forest_records (trees : List Lanius.Compiler.Parser.ParseTree) (nodeBase wordBase : Nat) :
      RecordsAt wordBase (forestFrom nodeBase wordBase trees).words
        (forestFrom nodeBase wordBase trees).offsets (serializeParseTreesFrom nodeBase trees).1 := by
    cases trees with
    | nil => exact .nil
    | cons tree trees =>
      let first := treeFrom nodeBase wordBase tree
      let rest := forestFrom (nodeBase + first.offsets.length) (wordBase + first.words.length) trees
      have head := tree_records tree nodeBase wordBase
      have tail := forest_records trees (nodeBase + first.offsets.length) (wordBase + first.words.length)
      have headFramed : RecordsAt wordBase (first.words ++ rest.words)
          first.offsets (serializeParseTreeFrom nodeBase tree).1 := by
        simpa only [List.length_nil, Nat.add_zero, List.nil_append] using
          head.frame (before := []) rest.words
      have tailFramed : RecordsAt wordBase (first.words ++ rest.words)
          rest.offsets (serializeParseTreesFrom (nodeBase + first.offsets.length) trees).1 := by
        simpa only [List.append_nil] using tail.frame (before := first.words) []
      have combined := headFramed.append tailFramed
      have count := (tree_references tree nodeBase wordBase).1
      change RecordsAt wordBase (first.words ++ rest.words) (first.offsets ++ rest.offsets)
        ((serializeParseTreeFrom nodeBase tree).1 ++
          (serializeParseTreesFrom (nodeBase + (serializeParseTreeFrom nodeBase tree).1.length) trees).1)
      simpa only [first, count] using combined
  termination_by sizeOf trees
end

mutual
  /-- Nonterminal call depth needed by `visit`; terminals make no recursive call. -/
  def treeDepth : Lanius.Compiler.Parser.ParseTree → Nat
    | .terminal _ _ => 0
    | .nonterminal _ _ _ _ children => forestDepth children + 1

  def forestDepth : List Lanius.Compiler.Parser.ParseTree → Nat
    | [] => 0
    | tree :: trees => max (treeDepth tree) (forestDepth trees)
end

theorem forest_depth_member (member : tree ∈ trees) : treeDepth tree ≤ forestDepth trees := by
  induction trees with
  | nil => simp at member
  | cons first rest ih =>
    rcases List.mem_cons.mp member with rfl | later
    · exact Nat.le_max_left _ _
    · exact Nat.le_trans (ih later) (Nat.le_max_right _ _)

mutual
  /-- The exact allocated-node count is also a sufficient recursive depth bound. -/
  theorem tree_depth_le_nodes (tree : Lanius.Compiler.Parser.ParseTree) (nodeBase wordBase : Nat) :
      treeDepth tree ≤ (treeFrom nodeBase wordBase tree).offsets.length := by
    cases tree with
    | terminal token kind => exact Nat.le_refl 0
    | nonterminal production nonterminal start finish children =>
      have bound := forest_depth_le_nodes children nodeBase (wordBase + 4 + children.length * 3)
      simpa only [treeDepth, treeFrom, List.length_append, List.length_singleton] using Nat.succ_le_succ bound
  termination_by sizeOf tree

  theorem forest_depth_le_nodes (trees : List Lanius.Compiler.Parser.ParseTree) (nodeBase wordBase : Nat) :
      forestDepth trees ≤ (forestFrom nodeBase wordBase trees).offsets.length := by
    cases trees with
    | nil => exact Nat.le_refl 0
    | cons tree trees =>
      have head := tree_depth_le_nodes tree nodeBase wordBase
      have tail := forest_depth_le_nodes trees
        (nodeBase + (treeFrom nodeBase wordBase tree).offsets.length)
        (wordBase + (treeFrom nodeBase wordBase tree).words.length)
      simp only [forestDepth, forestFrom, List.length_append]
      omega
  termination_by sizeOf trees
end

/-- Public indexed storage contract used by consumers of the materialized tree. -/
theorem tree_node_lookup {index : Nat} (tree : Lanius.Compiler.Parser.ParseTree) (nodeBase wordBase : Nat)
    (found : (serializeParseTreeFrom nodeBase tree).1[index]? = some node) :
    ∃ offset, (treeFrom nodeBase wordBase tree).offsets[index]? = some offset ∧
      RecordAt wordBase (treeFrom nodeBase wordBase tree).words offset node ∧
      wordBase ≤ offset ∧ offset + 4 + node.children.length * 3 ≤ wordBase + treeWords tree := by
  obtain ⟨offset, indexed, stored⟩ := (tree_records tree nodeBase wordBase).lookup found
  obtain ⟨lower, upper⟩ := stored.bounds
  rw [tree_words_length] at upper
  exact ⟨offset, indexed, stored, lower, upper⟩

end Lanius.Extraction.ParserTreeLayout
