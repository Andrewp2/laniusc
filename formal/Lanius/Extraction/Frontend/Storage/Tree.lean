import Lanius.Extraction.Frontend.Storage.Parser
import Lanius.Extraction.Parser.Tree.Bounds.Propose

namespace Lanius.Extraction.Frontend
open Lanius.Compiler Lanius.Compiler.Lexer Lanius.Compiler.Parser
open Lanius.Extraction.ParserTreeBounds

/-- Source-only tree resources: every declarative full-input tree fits the
actual materializer layout and depth limit. No successful execution, selected
backpointer, or accepted output is part of the condition. -/
def SourceTreeStorage (file : SourceFile) (recordWords nodeSlots depth : Nat) : Prop :=
  ∃ source tokens, decodeBytes file.bytes = some source ∧ lexCanonical source = .success tokens ∧
    ∀ grammar : IndexedGrammar, grammar.grammar = laniusGrammar →
      ∀ parse : MaterializedParse grammar (tokens.map (fun token => token.kind.gpuCode)),
        Fits parse.tree recordWords nodeSlots depth

def SourcesTreeStorage (sources : List SourceFile) (recordWords nodeSlots depth : Nat) : Prop :=
  ∀ file ∈ sources, SourceTreeStorage file recordWords nodeSlots depth

theorem SourcesTreeStorage.mono (stored : SourcesTreeStorage sources words nodes depth)
    (wordRoom : words ≤ largerWords) (nodeRoom : nodes ≤ largerNodes) (depthRoom : depth ≤ largerDepth) :
    SourcesTreeStorage sources largerWords largerNodes largerDepth := by
  intro file member
  obtain ⟨source, tokens, decoded, lexical, fits⟩ := stored file member
  refine ⟨source, tokens, decoded, lexical, ?_⟩
  intro grammar identity parse
  have bounded := fits grammar identity parse
  exact ⟨Nat.le_trans bounded.1 depthRoom, Nat.le_trans bounded.2.1 wordRoom,
    Nat.le_trans bounded.2.2 nodeRoom⟩

/-- Keep the checked tight bounds, not just the fact that the physical buffers
are large enough. Output sizing consumes these numbers without rebuilding the
chart or traversing a proposed parse tree. -/
structure CheckedParserTreeStorage (artifact : Artifact)
    (workspaceWords recordWords nodeSlots limit : Nat) where
  words : Nat
  nodes : Nat
  depth : Nat
  fits : words ≤ recordWords ∧ nodes ≤ nodeSlots ∧ depth ≤ limit
  parser : SourcesParserStorage artifact.sources workspaceWords
  trees : SourcesTreeStorage artifact.sources words nodes depth

theorem CheckedParserTreeStorage.physical
    (checked : CheckedParserTreeStorage artifact workspaceWords recordWords nodeSlots limit) :
    SourcesTreeStorage artifact.sources recordWords nodeSlots limit :=
  checked.trees.mono checked.fits.1 checked.fits.2.1 checked.fits.2.2

inductive CheckedParserTrees (workspaceWords recordWords nodeSlots depth : Nat) : List Artifact → Type where
  | nil : CheckedParserTrees workspaceWords recordWords nodeSlots depth []
  | cons (head : CheckedParserTreeStorage artifact workspaceWords recordWords nodeSlots depth)
      (tail : CheckedParserTrees workspaceWords recordWords nodeSlots depth artifacts) :
      CheckedParserTrees workspaceWords recordWords nodeSlots depth (artifact :: artifacts)

theorem CheckedParserTrees.domains :
    {artifacts : List Artifact} → CheckedParserTrees workspaceWords recordWords nodeSlots depth artifacts →
      SourcesParserStorage (artifacts.flatMap (·.sources)) workspaceWords ∧
        SourcesTreeStorage (artifacts.flatMap (·.sources)) recordWords nodeSlots depth
  | [], .nil => by
      constructor
      · intro _ member; cases member
      · intro _ member; cases member
  | _ :: _, .cons head tail => by
      constructor
      · intro file member
        rcases List.mem_append.mp member with here | later
        · exact head.parser file here
        · exact tail.domains.1 file later
      · intro file member
        rcases List.mem_append.mp member with here | later
        · exact head.physical file here
        · exact tail.domains.2 file later

/-- A numerical proposal only. `checkRoots` still independently authenticates
the chosen bound against every possible start production. -/
def proposeRootCost (grammar : IndexedGrammar) (tokens : List Nat) (costs : Costs) : Cost :=
  grammar.grammar.productions.zipIdx.foldl (fun upper (production, id) =>
    if production.lhs = grammar.grammar.start_nonterminal then
      upper.maximum (potential costs (finalPosition tokens.length) ⟨id, production.rhs.length, 0⟩).node
    else upper) Cost.zero

theorem sourcesTreeStorage_of_certificate (valid : TokenArtifactValid artifact)
    (certificate : Envelope.Checked Entry.Grammar.indexedLanius (artifact.tokens.map Token.kind) capacity)
    (bounded : checkCosts Entry.Grammar.indexedLanius (artifact.tokens.map Token.kind) certificate.items costs = true)
    (roots : checkRoots Entry.Grammar.indexedLanius (artifact.tokens.map Token.kind) costs recordWords nodeSlots depth = true) :
    SourcesTreeStorage artifact.sources recordWords nodeSlots depth := by
  intro file member
  obtain ⟨source, tokens, _, sourceDecoded, tokensDecoded, lexical, _⟩ := valid
  have codes := decodeTokens.kinds tokensDecoded
  have fits (grammar : IndexedGrammar) (identity : grammar.grammar = laniusGrammar)
      (parse : MaterializedParse grammar (tokens.map (fun token => token.kind.gpuCode))) :
      Fits parse.tree recordWords nodeSlots depth := by
    have closed : ChartClosed grammar (artifact.tokens.map Token.kind) (Envelope.workspace certificate.items) := by
      apply Envelope.check_closed
      rw [Envelope.check_grammar_congr (right := Entry.Grammar.indexedLanius) identity]
      exact certificate.closed
    have budgets : checkCosts grammar (artifact.tokens.map Token.kind) certificate.items costs = true := by
      rw [checkCosts_grammar_congr (right := Entry.Grammar.indexedLanius) identity]
      exact bounded
    have rootBounds : checkRoots grammar (artifact.tokens.map Token.kind) costs recordWords nodeSlots depth = true := by
      rw [checkRoots_grammar_congr (right := Entry.Grammar.indexedLanius) identity]
      exact roots
    apply checkRoots_fits (costs := costs) (workspace := Envelope.workspace certificate.items) (parse := parse)
    · simpa only [codes] using checkCosts_bounded closed budgets
    · simpa only [codes] using rootBounds
  cases sources : artifact.sources with
  | nil => simp [sources] at member
  | cons head tail =>
    cases tail with
    | cons _ _ => simp [sources, decodeSingleSource] at sourceDecoded
    | nil =>
      have same : file = head := by simpa only [sources, List.mem_singleton] using member
      subst file
      exact ⟨source, tokens, by simpa only [sources, decodeSingleSource] using sourceDecoded, lexical, fits⟩

/-- Validate chart closure once, then independently validate proposed tree
potentials. Reuse the same source/token evidence for both resource domains. -/
def checkArtifactParserTreeStorage? (artifact : Artifact) (valid : TokenArtifactValid artifact)
    (workspaceWords recordWords nodeSlots depth : Nat) (candidate : Envelope.Candidate) :
    Option (CheckedParserTreeStorage artifact workspaceWords recordWords nodeSlots depth) := do
  if candidate.tokenCount != artifact.tokens.length then none else do
  let certificate ← Envelope.check? Entry.Grammar.indexedLanius (artifact.tokens.map Token.kind)
    (stateCapacity artifact.tokens.length workspaceWords) candidate.items
  let costs ← (proposeCosts Entry.Grammar.indexedLanius (artifact.tokens.map Token.kind) certificate.items).toOption
  if bounded : checkCosts Entry.Grammar.indexedLanius (artifact.tokens.map Token.kind) certificate.items costs = true then
    let bound := proposeRootCost Entry.Grammar.indexedLanius (artifact.tokens.map Token.kind) costs
    if fits : bound.words - 3 ≤ recordWords ∧ bound.nodes ≤ nodeSlots ∧ bound.depth ≤ depth then
      if roots : checkRoots Entry.Grammar.indexedLanius (artifact.tokens.map Token.kind) costs
          (bound.words - 3) bound.nodes bound.depth = true then
        pure ⟨bound.words - 3, bound.nodes, bound.depth, fits,
          sourcesParserStorage_of_certificate valid certificate,
          sourcesTreeStorage_of_certificate valid certificate bounded roots⟩
      else none
    else none
  else none

def checkUnitsParserTreeStorage? (workspaceWords recordWords nodeSlots depth : Nat) :
    (artifacts : List Artifact) → (∀ artifact ∈ artifacts, TokenArtifactValid artifact) →
      List Envelope.Candidate →
      Option (CheckedParserTrees workspaceWords recordWords nodeSlots depth artifacts)
  | [], _, [] => some .nil
  | head :: tail, valid, first :: rest => do
    let headStorage ← checkArtifactParserTreeStorage? head (valid head (by simp)) workspaceWords recordWords nodeSlots depth first
    let tailStorage ← checkUnitsParserTreeStorage? workspaceWords recordWords nodeSlots depth tail
      (fun artifact member => valid artifact (by simp [member])) rest
    pure (.cons headStorage tailStorage)
  | _, _, _ => none

end Lanius.Extraction.Frontend
