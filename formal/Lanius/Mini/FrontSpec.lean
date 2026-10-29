import Lanius.Mini.FrontLex

/-! # The front end by translation validation (roadmap step 8)

What `validateTree` (extracted from `formal/lani/mini/frontend.lani`) establishes
about the parse tree laniusc hands it. These definitions are part of the
statement:

- `CTree.leaves`: the tokens a concrete tree prints, left to right.
- `CTree.preorder`: its production ids in preorder, laniusc's `node_kind`.
- `Shape g nt c`: `c` is a parse tree of the grammar `g` for nonterminal `nt`:
  every node is a production of `g` with `nt`'s left side, and its children
  are, in order, one per symbol on the production's right side, a token of
  the terminal's kind or a tree for the nonterminal.
- `Derives g syms kinds`: the usual derivation relation of a context-free
  grammar, written without trees.

- `Reads leaves tokens rest`: the leaves read the tokens in order, up to the
  tokens `rest` left over, except that a `>>` token may be read as its two
  halves, two `>`; laniusc's parser reads the `>>` that closes two type
  argument lists (`Vec<Option<T>>`) that way.
- `Picked c tokens rest`: `c`'s leaves read the tokens up to `rest`, and
  `picks` allows each node's production at the tokens from that node on: it
  rules out two productions the subset does not use and chooses between the
  two readings of `x<` in an expression (`Unique.lean`).

`validate_sound`: an accepted tree is a parse tree for `file` that is `Picked`
for exactly the tokens and whose preorder is exactly laniusc's production list, so
the leaves' token kinds are a sentence of the grammar (`validate_derives`).
`sourceProgram_sound` ties the front end's program to such a tree. -/

namespace Lanius.Mini

mutual
/-- The tokens a concrete tree prints. -/
def CTree.leaves : CTree → List Token
  | .leaf token => [token]
  | .node _prod kids => CTree.leavesOf kids

def CTree.leavesOf : List CTree → List Token
  | [] => []
  | c :: rest => c.leaves ++ CTree.leavesOf rest
end

mutual
/-- The production ids of a concrete tree in preorder. -/
def CTree.preorder : CTree → List Nat
  | .leaf _token => []
  | .node prod kids => prod :: CTree.preorderOf kids

def CTree.preorderOf : List CTree → List Nat
  | [] => []
  | c :: rest => c.preorder ++ CTree.preorderOf rest
end

mutual
/-- `c` is a parse tree of `g` for the nonterminal `nt`. -/
inductive Shape (g : List Rule) : Nat → CTree → Prop
  | node {prodId nt : Nat} {prod : Rule} {kids : List CTree} :
      g[prodId]? = some prod → prod.lhs = nt → KidsShape g prod.rhs kids →
      Shape g nt (.node prodId kids)

/-- `kids` are the children for the right side `rhs`. -/
inductive KidsShape (g : List Rule) : List Sym → List CTree → Prop
  | nil : KidsShape g [] []
  | term {kind : Nat} {token : Token} {rhs : List Sym} {kids : List CTree} :
      token.kind = kind → KidsShape g rhs kids →
      KidsShape g (.term kind :: rhs) (.leaf token :: kids)
  | nonterm {nt : Nat} {c : CTree} {rhs : List Sym} {kids : List CTree} :
      Shape g nt c → KidsShape g rhs kids →
      KidsShape g (.nonterm nt :: rhs) (c :: kids)
end

/-- The symbols `syms` derive the token kinds `kinds` in the grammar `g`. -/
inductive Derives (g : List Rule) : List Sym → List Nat → Prop
  | nil : Derives g [] []
  | term {kind : Nat} {rhs : List Sym} {kinds : List Nat} :
      Derives g rhs kinds → Derives g (.term kind :: rhs) (kind :: kinds)
  | nonterm {prodId nt : Nat} {prod : Rule} {rhs : List Sym} {first rest : List Nat} :
      g[prodId]? = some prod → prod.lhs = nt → Derives g prod.rhs first →
      Derives g rhs rest → Derives g (.nonterm nt :: rhs) (first ++ rest)

mutual
theorem Shape.derives {g : List Rule} {nt : Nat} {c : CTree} :
    Shape g nt c → Derives g [.nonterm nt] (c.leaves.map Token.kind)
  | .node (prodId := prodId) found lhs kids => by
      have h := KidsShape.derives kids
      have d := Derives.nonterm (rhs := []) found lhs h Derives.nil
      simpa [CTree.leaves] using d

theorem KidsShape.derives {g : List Rule} {rhs : List Sym} {kids : List CTree} :
    KidsShape g rhs kids → Derives g rhs ((CTree.leavesOf kids).map Token.kind)
  | .nil => by simpa [CTree.leavesOf] using Derives.nil
  | .term (token := token) kind rest => by
      have h := Derives.term (kind := token.kind) (KidsShape.derives rest)
      subst kind
      simpa [CTree.leavesOf, CTree.leaves] using h
  | .nonterm (.node found lhs kids) rest => by
      have d := Derives.nonterm found lhs (KidsShape.derives kids) (KidsShape.derives rest)
      simpa [CTree.leavesOf, CTree.leaves] using d
end

/-- `leaves` read `tokens`, leaving `rest`: token by token, except that a
`>>` (token kind 44) may be read as two `>` (kind 13), its halves. -/
inductive Reads : List Token → List Token → List Token → Prop
  | done {rest : List Token} : Reads [] rest rest
  | token {t : Token} {leaves tokens rest : List Token} :
      Reads leaves tokens rest → Reads (t :: leaves) (t :: tokens) rest
  | halves {t : Token} {leaves tokens rest : List Token} :
      t.kind = 44 → Reads leaves (shrSecond t :: tokens) rest →
      Reads (shrFirst t :: leaves) (t :: tokens) rest

theorem Reads.append {l₁ l₂ tokens mid rest : List Token} :
    Reads l₁ tokens mid → Reads l₂ mid rest → Reads (l₁ ++ l₂) tokens rest
  | .done, h => h
  | .token r, h => .token (r.append h)
  | .halves k r, h => .halves k (r.append h)

mutual
/-- `c` reads `tokens`, leaving `rest`, and `picks` allows each node's
production at the tokens from the node on. -/
inductive Picked : CTree → List Token → List Token → Prop
  | leaf {t : Token} {tokens rest : List Token} : Reads [t] tokens rest → Picked (.leaf t) tokens rest
  | node {prod : Nat} {kids : List CTree} {tokens rest : List Token} :
      picks prod tokens = true → PickedKids kids tokens rest → Picked (.node prod kids) tokens rest

/-- `kids` read `tokens` one after another, leaving `rest`, each `Picked`. -/
inductive PickedKids : List CTree → List Token → List Token → Prop
  | nil {tokens : List Token} : PickedKids [] tokens tokens
  | cons {c : CTree} {cs : List CTree} {tokens mid rest : List Token} :
      Picked c tokens mid → PickedKids cs mid rest → PickedKids (c :: cs) tokens rest
end

mutual
theorem Picked.reads {c : CTree} {tokens rest : List Token} : Picked c tokens rest → Reads c.leaves tokens rest
  | .leaf r => by simpa [CTree.leaves] using r
  | .node _ kids => by simpa [CTree.leaves] using kids.reads

theorem PickedKids.reads {kids : List CTree} {tokens rest : List Token} :
    PickedKids kids tokens rest → Reads (CTree.leavesOf kids) tokens rest
  | .nil => by simpa [CTree.leavesOf] using Reads.done
  | .cons c cs => by simpa [CTree.leavesOf] using c.reads.append cs.reads
end

/-- What `attach` returns: children for `rhs` of the grammar's shape, whose
leaves read the tokens it consumed and whose preorder is the productions it
consumed. -/
theorem attach_sound (g : List Rule) :
    ∀ (fuel : Nat) (rhs : List Sym) (parent : Nat) (cur : Cursor) (a : Attached),
      attach g fuel rhs parent cur = some a →
      KidsShape g rhs a.kids ∧
      PickedKids a.kids cur.tokens a.rest.tokens ∧
      cur.prods = CTree.preorderOf a.kids ++ a.rest.prods := by
  intro fuel
  induction fuel with
  | zero => intro rhs parent cur a h; rw [attach.eq_def] at h; simp at h
  | succ fuel ih =>
    intro rhs parent cur a h
    rw [attach.eq_def] at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    cases rhs with
    | nil =>
        simp at h
        subst h
        exact ⟨.nil, .nil, by simp [CTree.preorderOf]⟩
    | cons sym more =>
      cases sym with
      | term kind =>
        cases htok : cur.tokens with
        | nil => simp [htok] at h
        | cons tok toks =>
          simp only [htok] at h
          by_cases hk : tok.kind = kind
          · simp only [hk, if_true] at h
            cases hrest : attach g fuel more parent
                { prods := cur.prods, parents := cur.parents, tokens := toks, index := cur.index } with
            | none => simp [hrest, withKid] at h
            | some r =>
              simp only [hrest, withKid, Option.some.injEq] at h
              subst h
              obtain ⟨shape, toksEq, prodsEq⟩ := ih _ _ _ _ hrest
              refine ⟨.term hk shape, ?_, ?_⟩
              · exact .cons (.leaf (.token .done)) toksEq
              · simpa [CTree.preorderOf, CTree.preorder] using prodsEq
          · simp only [hk, if_false] at h
            by_cases hs : tok.kind = 44 ∧ kind = 13
            · obtain ⟨hs₁, hs₂⟩ := hs
              simp only [hs₁, hs₂, decide_true, Bool.and_self, if_true] at h
              cases hrest : attach g fuel more parent
                  { prods := cur.prods, parents := cur.parents, tokens := shrSecond tok :: toks,
                    index := cur.index } with
              | none => simp [hrest, withKid] at h
              | some r =>
                simp only [hrest, withKid, Option.some.injEq] at h
                subst h
                obtain ⟨shape, toksEq, prodsEq⟩ := ih _ _ _ _ hrest
                refine ⟨.term (by simp [shrFirst, hs₂]) shape, ?_, ?_⟩
                · exact .cons (.leaf (.halves hs₁ .done)) toksEq
                · simpa [CTree.preorderOf, CTree.preorder] using prodsEq
            · have : ¬(decide (tok.kind = 44) && decide (kind = 13)) = true := by
                simpa [Bool.and_eq_true, decide_eq_true_eq] using hs
              simp [this] at h
      | nonterm nt =>
        cases hprods : cur.prods with
        | nil => simp [hprods] at h
        | cons p ps =>
          cases hparents : cur.parents with
          | nil => simp [hprods, hparents] at h
          | cons q qs =>
            simp only [hprods, hparents] at h
            by_cases hq : q = parent ∧ picks p cur.tokens = true
            · obtain ⟨hq, hp⟩ := hq
              simp only [hq, hp, ne_eq, not_true_eq_false, decide_false, Bool.not_true, Bool.or_self,
                Bool.false_eq_true, if_false] at h
              cases hg : g[p]? with
              | none => simp [hg] at h
              | some prod =>
                simp only [hg] at h
                by_cases hl : prod.lhs = nt
                · simp only [hl, not_true_eq_false, if_false] at h
                  cases hin : attach g fuel prod.rhs cur.index
                      { prods := ps, parents := qs, tokens := cur.tokens, index := cur.index + 1 } with
                  | none => simp [hin] at h
                  | some inner =>
                    simp only [hin] at h
                    cases hrest : attach g fuel more parent inner.rest with
                    | none => simp [hrest, withKid] at h
                    | some r =>
                      simp only [hrest, withKid, Option.some.injEq] at h
                      subst h
                      obtain ⟨shape₁, toks₁, prods₁⟩ := ih _ _ _ _ hin
                      obtain ⟨shape₂, toks₂, prods₂⟩ := ih _ _ _ _ hrest
                      refine ⟨.nonterm (.node hg hl shape₁) shape₂, ?_, ?_⟩
                      · exact .cons (.node hp toks₁) toks₂
                      · simp only [CTree.preorderOf, CTree.preorder, List.cons_append,
                          List.append_assoc]
                        simp only at prods₁
                        rw [prods₁, prods₂]
                · simp [hl] at h
            · have : (decide (q ≠ parent) || !picks p cur.tokens) = true := by
                by_cases hq' : q = parent
                · have : ¬picks p cur.tokens = true := fun hp => hq ⟨hq', hp⟩
                  simp [hq', this]
                · simp [hq']
              simp only [this, if_true] at h
              exact absurd h (by simp)

/-- An accepted parse: a tree for `file` (nonterminal 0) whose leaves read
exactly the tokens and whose preorder is exactly laniusc's production list. -/
theorem validate_sound {g : List Rule} {tokens : List Token} {prods parents : List Nat}
    {root : CTree} (h : validateTree g tokens prods parents = some root) :
    Shape g 0 root ∧ Picked root tokens [] ∧ root.preorder = prods := by
  unfold validateTree at h
  cases ha : attach g (2 * (prods.length + tokens.length) + 2) [Sym.nonterm 0] 4294967295
      { prods := prods, parents := parents, tokens := tokens, index := 0 } with
  | none => simp [ha] at h
  | some a =>
    simp only [ha] at h
    obtain ⟨shape, toksEq, prodsEq⟩ := attach_sound g _ _ _ _ _ ha
    unfold whole at h
    by_cases hu : usedUp a.rest = true
    · simp only [hu, if_true] at h
      unfold usedUp at hu
      simp only [Bool.and_eq_true] at hu
      obtain ⟨⟨hp, -⟩, ht⟩ := hu
      have restProds : a.rest.prods = [] := by
        cases hr : a.rest.prods with
        | nil => rfl
        | cons x xs => simp [hr, isEmptyUsize] at hp
      have restTokens : a.rest.tokens = [] := by
        cases hr : a.rest.tokens with
        | nil => rfl
        | cons x xs => simp [hr, noTokens] at ht
      cases hk : a.kids with
      | nil => simp [hk] at h
      | cons c more =>
        simp only [hk] at h
        cases more with
        | cons d rest => simp [only] at h
        | nil =>
          simp only [only, Option.some.injEq] at h
          subst h
          rw [hk] at shape toksEq prodsEq
          cases shape with
          | nonterm s tail =>
            cases tail
            refine ⟨s, ?_, ?_⟩
            · cases toksEq with
              | cons pc pn =>
                cases pn
                rw [restTokens] at pc
                exact pc
            · simpa [CTree.preorderOf, restProds] using prodsEq.symm
    · simp [hu] at h

/-- The token kinds of an accepted parse's leaves are a sentence of the
grammar. -/
theorem validate_derives {g : List Rule} {tokens : List Token} {prods parents : List Nat}
    {root : CTree} (h : validateTree g tokens prods parents = some root) :
    Derives g [.nonterm 0] (root.leaves.map Token.kind) :=
  (validate_sound h).1.derives

/-- The front end's program is `build` of a tree for `file` in laniusc's
grammar whose leaves read exactly the source's tokens (as the Lean lexer reads
them) and whose preorder is laniusc's production list. -/
theorem sourceProgram_sound {source : List Lanius.Compiler.Lexer.Byte} {prods parents : List Nat}
    {program : SrcProgram} (h : sourceProgram source prods parents = some program) :
    ∃ tokens root, lexTokens source = some tokens ∧
      Shape grammar 0 root ∧ Picked root tokens [] ∧ root.preorder = prods ∧
      Derives grammar [.nonterm 0] (root.leaves.map Token.kind) ∧
      build (4 * (prods.length + tokens.length) + 16) root = some program := by
  unfold sourceProgram at h
  cases hl : lexTokens source with
  | none => simp [hl] at h
  | some tokens =>
    simp only [hl] at h
    unfold frontEnd at h
    cases hv : validateTree grammar tokens prods parents with
    | none => simp [hv] at h
    | some root =>
      simp only [hv] at h
      obtain ⟨shape, leaves, pre⟩ := validate_sound hv
      exact ⟨tokens, root, rfl, shape, leaves, pre, validate_derives hv, h⟩

/-- `R` relates the two lists element by element (so they have one length). -/
inductive ListRel {α β : Type} (R : α → β → Prop) : List α → List β → Prop
  | nil : ListRel R [] []
  | cons {a : α} {b : β} {as : List α} {bs : List β} : R a b → ListRel R as bs → ListRel R (a :: as) (b :: bs)

/-- Each accepted file's tree is a parse tree for `file` whose leaves read
exactly its tokens and whose preorder is laniusc's production list. -/
theorem validateFiles_sound {g : List Rule} :
    ∀ {files : List FileInput} {roots : List CTree}, validateFiles g files = some roots →
      ListRel (fun (f : FileInput) (root : CTree) =>
        Shape g 0 root ∧ Picked root f.tokens [] ∧ root.preorder = f.prods) files roots
  | [], roots, h => by
    simp only [validateFiles, Option.some.injEq] at h
    subst h
    exact .nil
  | f :: rest, roots, h => by
    unfold validateFiles consRoot at h
    cases hv : validateTree g f.tokens f.prods f.parents with
    | none => simp [hv] at h
    | some root =>
      cases hr : validateFiles g rest with
      | none => simp [hv, hr] at h
      | some more =>
        simp only [hv, hr, Option.some.injEq] at h
        subst h
        exact .cons (validate_sound hv) (validateFiles_sound hr)

theorem lexFiles_tokens :
    ∀ {files : List SourceFile} {inputs : List FileInput}, lexFiles files = some inputs →
      ListRel (fun (f : SourceFile) (i : FileInput) =>
        lexTokens f.source = some i.tokens ∧ i.prods = f.prods) files inputs
  | [], inputs, h => by
    simp only [lexFiles, Option.some.injEq] at h
    subst h
    exact .nil
  | f :: rest, inputs, h => by
    unfold lexFiles at h
    cases hl : lexTokens f.source with
    | none => simp [hl] at h
    | some tokens =>
      cases hr : lexFiles rest with
      | none => simp [hl, hr] at h
      | some more =>
        simp only [hl, hr, Option.some.injEq] at h
        subst h
        exact .cons ⟨hl, rfl⟩ (lexFiles_tokens hr)

/-- The several-file front end's program is `buildFiles` of one tree per
file, each a parse tree for `file` in laniusc's grammar whose leaves read
exactly that file's tokens (as the Lean lexer reads them) and whose preorder is
laniusc's production list for it. -/
theorem sourceProgramFiles_sound {files : List SourceFile} {program : SrcProgram}
    (h : sourceProgramFiles files = some program) :
    ∃ inputs roots,
      ListRel (fun (f : SourceFile) (i : FileInput) =>
        lexTokens f.source = some i.tokens ∧ i.prods = f.prods) files inputs ∧
      ListRel (fun (i : FileInput) (root : CTree) =>
        Shape grammar 0 root ∧ Picked root i.tokens [] ∧ root.preorder = i.prods) inputs roots ∧
      buildFiles (filesFuel inputs) roots = some program := by
  unfold sourceProgramFiles at h
  cases hl : lexFiles files with
  | none => simp [hl] at h
  | some inputs =>
    simp only [hl] at h
    unfold frontEndFiles at h
    cases hv : validateFiles grammar inputs with
    | none => simp [hv] at h
    | some roots =>
      simp only [hv] at h
      exact ⟨inputs, roots, lexFiles_tokens hl, validateFiles_sound hv, h⟩

end Lanius.Mini
