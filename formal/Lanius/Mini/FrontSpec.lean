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

`validate_sound`: an accepted tree is a parse tree for `file` whose leaves are
exactly the tokens and whose preorder is exactly laniusc's production list, so
the token kinds are a sentence of the grammar (`validate_derives`).
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

/-- What `attach` returns: children for `rhs` of the grammar's shape, which
print the tokens it consumed and whose preorder is the productions it
consumed. -/
theorem attach_sound (g : List Rule) :
    ∀ (fuel : Nat) (rhs : List Sym) (parent : Nat) (cur : Cursor) (a : Attached),
      attach g fuel rhs parent cur = some a →
      KidsShape g rhs a.kids ∧
      cur.tokens = CTree.leavesOf a.kids ++ a.rest.tokens ∧
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
        exact ⟨.nil, by simp [CTree.leavesOf], by simp [CTree.preorderOf]⟩
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
              · simp [CTree.leavesOf, CTree.leaves, ← toksEq]
              · simpa [CTree.preorderOf, CTree.preorder] using prodsEq
          · simp [hk] at h
      | nonterm nt =>
        cases hprods : cur.prods with
        | nil => simp [hprods] at h
        | cons p ps =>
          cases hparents : cur.parents with
          | nil => simp [hprods, hparents] at h
          | cons q qs =>
            simp only [hprods, hparents] at h
            by_cases hq : q = parent
            · simp only [hq, ne_eq, not_true_eq_false, if_false] at h
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
                      · simp only [CTree.leavesOf, CTree.leaves, List.append_assoc]
                        rw [toks₁, toks₂]
                      · simp only [CTree.preorderOf, CTree.preorder, List.cons_append,
                          List.append_assoc]
                        simp only at prods₁
                        rw [prods₁, prods₂]
                · simp [hl] at h
            · simp [hq] at h

/-- An accepted parse: a tree for `file` (nonterminal 0) that prints exactly
the tokens and whose preorder is exactly laniusc's production list. -/
theorem validate_sound {g : List Rule} {tokens : List Token} {prods parents : List Nat}
    {root : CTree} (h : validateTree g tokens prods parents = some root) :
    Shape g 0 root ∧ root.leaves = tokens ∧ root.preorder = prods := by
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
            · simpa [CTree.leavesOf, restTokens] using toksEq.symm
            · simpa [CTree.preorderOf, restProds] using prodsEq.symm
    · simp [hu] at h

/-- The token kinds of an accepted parse are a sentence of the grammar. -/
theorem validate_derives {g : List Rule} {tokens : List Token} {prods parents : List Nat}
    {root : CTree} (h : validateTree g tokens prods parents = some root) :
    Derives g [.nonterm 0] (tokens.map Token.kind) := by
  obtain ⟨shape, leaves, -⟩ := validate_sound h
  simpa [leaves] using shape.derives

/-- The front end's program is `build` of a tree for `file` in laniusc's
grammar that prints exactly the source's tokens (as the Lean lexer reads
them) and whose preorder is laniusc's production list. -/
theorem sourceProgram_sound {source : List Lanius.Compiler.Lexer.Byte} {prods parents : List Nat}
    {program : SrcProgram} (h : sourceProgram source prods parents = some program) :
    ∃ tokens root, lexTokens source = some tokens ∧
      Shape grammar 0 root ∧ root.leaves = tokens ∧ root.preorder = prods ∧
      Derives grammar [.nonterm 0] (tokens.map Token.kind) ∧
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

end Lanius.Mini
