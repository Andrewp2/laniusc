import Lanius.Mini.GrammarCert

/-! # The front end reads a source one way (roadmap step V4)

laniusc's grammar, with `picks` choosing between `x` and `x<...>` in an
expression and leaving out block statements and a method's type arguments,
has at most one parse tree for `file` that is `Picked` for given tokens
(`grammar_unique`, from the kernel-checked certificate `grammarCert_ok` and
`Cert.parse_unique`). So the tree the validator accepts from laniusc is the
only one (`validate_unique`), and the front end's program depends on the
source text alone, not on the tree laniusc hands it (`sourceProgram_determined`,
`sourceProgramFiles_determined`). -/

namespace Lanius.Mini

/-- At most one parse tree of the grammar for `file` is `Picked` for given
tokens. -/
theorem grammar_unique {t₁ t₂ : CTree} {tokens : List Token} (s₁ : Shape grammar 0 t₁)
    (p₁ : Picked t₁ tokens []) (s₂ : Shape grammar 0 t₂) (p₂ : Picked t₂ tokens []) : t₁ = t₂ :=
  Cert.parse_unique grammarCert_ok s₁ p₁ s₂ p₂

/-- The tree the validator accepts is the only parse tree for `file` that is
`Picked` for the tokens. -/
theorem validate_unique {tokens : List Token} {prods parents : List Nat} {root : CTree}
    (h : validateTree grammar tokens prods parents = some root) {t : CTree} (s : Shape grammar 0 t)
    (p : Picked t tokens []) : t = root :=
  grammar_unique s p (validate_sound h).1 (validate_sound h).2.1

/-- The front end's program from a source does not depend on the parse tree
laniusc gives with it. -/
theorem sourceProgram_determined {source : List Lanius.Compiler.Lexer.Byte} {prods₁ parents₁ prods₂ parents₂ : List Nat}
    {program₁ program₂ : SrcProgram} (h₁ : sourceProgram source prods₁ parents₁ = some program₁)
    (h₂ : sourceProgram source prods₂ parents₂ = some program₂) : program₁ = program₂ := by
  obtain ⟨tokens₁, root₁, lex₁, s₁, p₁, pre₁, -, b₁⟩ := sourceProgram_sound h₁
  obtain ⟨tokens₂, root₂, lex₂, s₂, p₂, pre₂, -, b₂⟩ := sourceProgram_sound h₂
  rw [lex₁, Option.some.injEq] at lex₂
  subst lex₂
  obtain rfl := grammar_unique s₁ p₁ s₂ p₂
  have : prods₁.length = prods₂.length := by rw [← pre₁, ← pre₂]
  rw [this, b₂, Option.some.injEq] at b₁
  exact b₁.symm

/-- Each file's tokens are the lexer's, and its productions laniusc's. -/
abbrev LexRel : List SourceFile → List FileInput → Prop :=
  ListRel (fun (f : SourceFile) (i : FileInput) => lexTokens f.source = some i.tokens ∧ i.prods = f.prods)

/-- Each file's tree is a `Picked` parse tree for its tokens, with its
productions. -/
abbrev TreeRel : List FileInput → List CTree → Prop :=
  ListRel (fun (i : FileInput) (root : CTree) => Shape grammar 0 root ∧ Picked root i.tokens [] ∧ root.preorder = i.prods)

/-- Two inputs with the same tokens and production counts, file by file. -/
abbrev SameSize : List FileInput → List FileInput → Prop :=
  ListRel (fun (i₁ i₂ : FileInput) => i₁.tokens = i₂.tokens ∧ i₁.prods.length = i₂.prods.length)

theorem filesFuel_eq : ∀ {inputs₁ inputs₂ : List FileInput}, SameSize inputs₁ inputs₂ →
    filesFuel inputs₁ = filesFuel inputs₂
  | [], [], .nil => rfl
  | _ :: _, _ :: _, .cons ⟨t, l⟩ rest => by
    simp only [filesFuel, t, l, filesFuel_eq rest]

theorem files_unique : ∀ {fs₁ : List SourceFile} {is₁ : List FileInput}, LexRel fs₁ is₁ →
    ∀ {fs₂ : List SourceFile} {is₂ : List FileInput} {rs₁ rs₂ : List CTree},
      fs₁.map SourceFile.source = fs₂.map SourceFile.source → LexRel fs₂ is₂ → TreeRel is₁ rs₁ → TreeRel is₂ rs₂ →
      rs₁ = rs₂ ∧ SameSize is₁ is₂
  | _, _, .nil, fs₂, _, _, _, same, l₂, v₁, v₂ => by
    cases fs₂ with
    | nil => cases l₂; cases v₁; cases v₂; exact ⟨rfl, .nil⟩
    | cons _ _ => simp at same
  | _, _, .cons ⟨lx₁, _⟩ l₁, fs₂, _, _, _, same, l₂, v₁, v₂ => by
    cases fs₂ with
    | nil => simp at same
    | cons f₂ more₂ =>
      simp only [List.map_cons, List.cons.injEq] at same
      cases l₂ with
      | cons lf₂ l₂ =>
        cases v₁ with
        | cons vf₁ v₁ =>
          cases v₂ with
          | cons vf₂ v₂ =>
            obtain ⟨lx₂, -⟩ := lf₂
            rw [← same.1, lx₁, Option.some.injEq] at lx₂
            obtain ⟨s₁, p₁, pre₁⟩ := vf₁
            obtain ⟨s₂, p₂, pre₂⟩ := vf₂
            rw [← lx₂] at p₂
            obtain rfl := grammar_unique s₁ p₁ s₂ p₂
            obtain ⟨rfl, rest⟩ := files_unique l₁ same.2 l₂ v₁ v₂
            exact ⟨rfl, .cons ⟨lx₂, by rw [← pre₁, ← pre₂]⟩ rest⟩

/-- The several-file front end's program does not depend on the parse trees
laniusc gives with the files' sources. -/
theorem sourceProgramFiles_determined {files₁ files₂ : List SourceFile} {program₁ program₂ : SrcProgram}
    (same : files₁.map SourceFile.source = files₂.map SourceFile.source)
    (h₁ : sourceProgramFiles files₁ = some program₁) (h₂ : sourceProgramFiles files₂ = some program₂) :
    program₁ = program₂ := by
  obtain ⟨inputs₁, roots₁, lex₁, val₁, b₁⟩ := sourceProgramFiles_sound h₁
  obtain ⟨inputs₂, roots₂, lex₂, val₂, b₂⟩ := sourceProgramFiles_sound h₂
  obtain ⟨rfl, size⟩ := files_unique lex₁ same lex₂ val₁ val₂
  rw [filesFuel_eq size, b₂, Option.some.injEq] at b₁
  exact b₁.symm

end Lanius.Mini
