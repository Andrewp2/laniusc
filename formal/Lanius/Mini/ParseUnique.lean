module

public import Lanius.Mini.GrammarCert
public import Lanius.Mini.Frontend.P.genericOpen
public import Lanius.Mini.Frontend.P.genericPathAt
public import Lanius.Mini.Frontend.P.opensBlock
public import Lanius.Mini.Frontend.P.picks
import all Lanius.Mini.Compiler.P.BinOp_size
import all Lanius.Mini.Compiler.P.Lists_concat
import all Lanius.Mini.Compiler.P.Lists_cons
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.Lists_get
import all Lanius.Mini.Compiler.P.Lists_getOr
import all Lanius.Mini.Compiler.P.Lists_length
import all Lanius.Mini.Compiler.P.Lists_single
import all Lanius.Mini.Compiler.P.MemWidth_bytes
import all Lanius.Mini.Compiler.P.MemWidth_prefix
import all Lanius.Mini.Compiler.P.MemWidth_rex
import all Lanius.Mini.Compiler.P.Word_prefix
import all Lanius.Mini.Compiler.Types
import all Lanius.Mini.Frontend.P.litBound
import all Lanius.Mini.Frontend.P.litScrutChain
import all Lanius.Mini.Frontend.P.blockOf
import all Lanius.Mini.Frontend.P.consParam
import all Lanius.Mini.Frontend.P.contractThen
import all Lanius.Mini.Frontend.P.contractsOf
import all Lanius.Mini.Frontend.P.funcBody
import all Lanius.Mini.Frontend.P.funcParams
import all Lanius.Mini.Frontend.P.funcRet
import all Lanius.Mini.Frontend.P.litBind
import all Lanius.Mini.Frontend.P.litIf
import all Lanius.Mini.Frontend.P.paramToken
import all Lanius.Mini.Frontend.P.paramTyOf
import all Lanius.Mini.Frontend.P.paramsOf
import all Lanius.Mini.Frontend.P.refTy
import all Lanius.Mini.Frontend.P.resultOf
import all Lanius.Mini.Frontend.P.retExpected
import all Lanius.Mini.Frontend.P.retOfTy
import all Lanius.Mini.Frontend.P.litEffMatch
import all Lanius.Mini.Frontend.P.stringClose
import all Lanius.Mini.Frontend.P.effOf
import all Lanius.Mini.Frontend.P.isStrType
import all Lanius.Mini.Frontend.P.returnEff
import all Lanius.Mini.Frontend.P.stringInit
import all Lanius.Mini.Frontend.P.stringLiteral
import all Lanius.Mini.Frontend.P.stringOpen
import all Lanius.Mini.Frontend.P.stringPrimary
import all Lanius.Mini.Frontend.P.eqOn
import all Lanius.Mini.Frontend.P.litIfOf
import all Lanius.Mini.Frontend.P.litLastValue
import all Lanius.Mini.Frontend.P.litTest
import all Lanius.Mini.Frontend.P.litValueIf
import all Lanius.Mini.Frontend.P.litWants
import all Lanius.Mini.Frontend.P.litChain
import all Lanius.Mini.Frontend.P.litLink
import all Lanius.Mini.Frontend.P.litResult
import all Lanius.Mini.Frontend.P.litWildValue
import all Lanius.Mini.Frontend.P.frontEndWords
import all Lanius.Mini.Frontend.P.grammarPart0
import all Lanius.Mini.Frontend.P.grammarPart1
import all Lanius.Mini.Frontend.P.grammarPart2
import all Lanius.Mini.Frontend.P.grammarPart3
import all Lanius.Mini.Frontend.P.grammarPart4
import all Lanius.Mini.Frontend.P.grammarPart5
import all Lanius.Mini.Frontend.P.grammarPart6
import all Lanius.Mini.Frontend.P.grammarPart7
import all Lanius.Mini.Frontend.P.genericClose
import all Lanius.Mini.Frontend.P.genericOpen
import all Lanius.Mini.Frontend.P.genericPathAt
import all Lanius.Mini.Frontend.P.opensBlock
import all Lanius.Mini.Frontend.P.picks
import all Lanius.Mini.Frontend.P.Inline_attachAfter
import all Lanius.Mini.Frontend.P.Inline_attachTerm
import all Lanius.Mini.Frontend.P.Inline_genericCloseAt
import all Lanius.Mini.Frontend.P.grammar
import all Lanius.Mini.Frontend.P.grammarPart13
import all Lanius.Mini.Frontend.P.grammarPart14
import all Lanius.Mini.Frontend.P.grammarPart15
import all Lanius.Mini.Frontend.P.grammarPart16
import all Lanius.Mini.Frontend.P.grammarPart10
import all Lanius.Mini.Frontend.P.grammarPart11
import all Lanius.Mini.Frontend.P.grammarPart12
import all Lanius.Mini.Frontend.P.grammarPart8
import all Lanius.Mini.Frontend.P.grammarPart9
import all Lanius.Mini.Frontend.P.basedDigits
import all Lanius.Mini.Frontend.P.charBody
import all Lanius.Mini.Frontend.P.charClose
import all Lanius.Mini.Frontend.P.charCloseOpt
import all Lanius.Mini.Frontend.P.charLiteral
import all Lanius.Mini.Frontend.P.charTail
import all Lanius.Mini.Frontend.P.escapedByte
import all Lanius.Mini.Frontend.P.flAdd
import all Lanius.Mini.Frontend.P.flBorrowBit
import all Lanius.Mini.Frontend.P.flCarry
import all Lanius.Mini.Frontend.P.flCarryOut
import all Lanius.Mini.Frontend.P.flLess
import all Lanius.Mini.Frontend.P.flMul10
import all Lanius.Mini.Frontend.P.flShl
import all Lanius.Mini.Frontend.P.flSub
import all Lanius.Mini.Frontend.P.flTimes10
import all Lanius.Mini.Frontend.P.flXor
import all Lanius.Mini.Frontend.P.intLiteral
import all Lanius.Mini.Frontend.P.litBase
import all Lanius.Mini.Frontend.P.litPrefixed
import all Lanius.Mini.Frontend.P.litSized
import all Lanius.Mini.Frontend.P.litValue
import all Lanius.Mini.Frontend.P.isEmptyUsize
import all Lanius.Mini.Frontend.P.noTokens
import all Lanius.Mini.Frontend.P.nodeProd
import all Lanius.Mini.Frontend.P.usedUp
import all Lanius.Mini.Frontend.P.validateTree
import all Lanius.Mini.Frontend.P.whole
import all Lanius.Mini.Frontend.P.genericTail
import all Lanius.Mini.Frontend.P.kid
import all Lanius.Mini.Frontend.P.kidsOf
import all Lanius.Mini.Frontend.P.noToken
import all Lanius.Mini.Frontend.P.startsWithKind
import all Lanius.Mini.Frontend.P.withKid
import all Lanius.Mini.Frontend.P.attach
import all Lanius.Mini.Frontend.P.only
import all Lanius.Mini.Frontend.P.shrFirst
import all Lanius.Mini.Frontend.P.shrSecond
import all Lanius.Mini.Frontend.P.build
import all Lanius.Mini.Frontend.P.buildChecked
import all Lanius.Mini.Frontend.P.buildClosed
import all Lanius.Mini.Frontend.P.buildCollected
import all Lanius.Mini.Frontend.P.buildFiles
import all Lanius.Mini.Frontend.P.buildMono
import all Lanius.Mini.Frontend.P.consRoot
import all Lanius.Mini.Frontend.P.filesFuel
import all Lanius.Mini.Frontend.P.frontEnd
import all Lanius.Mini.Frontend.P.frontEndFiles
import all Lanius.Mini.Frontend.P.lxDigit
import all Lanius.Mini.Frontend.P.lxIdentContinue
import all Lanius.Mini.Frontend.P.lxIdentStart
import all Lanius.Mini.Frontend.P.lxSpace
import all Lanius.Mini.Frontend.P.untypedRejected
import all Lanius.Mini.Frontend.P.validateFiles
import all Lanius.Mini.Frontend.P.wideLeftFuncs
import all Lanius.Mini.Frontend.P.wideLeftStmt
import all Lanius.Mini.Frontend.Types
import all Lanius.Mini.Frontend.P.assertArg
import all Lanius.Mini.Frontend.P.assertOf
import all Lanius.Mini.Frontend.P.assignOpOf
import all Lanius.Mini.Frontend.P.assignTarget
import all Lanius.Mini.Frontend.P.callStmt
import all Lanius.Mini.Frontend.P.compoundEff
import all Lanius.Mini.Frontend.P.compoundFieldEval
import all Lanius.Mini.Frontend.P.compoundOp
import all Lanius.Mini.Frontend.P.discardOf
import all Lanius.Mini.Frontend.P.freeOf
import all Lanius.Mini.Frontend.P.freeShifted
import all Lanius.Mini.Frontend.P.setPlaceOf
import all Lanius.Mini.Frontend.P.setPlaceOpOf
import all Lanius.Mini.Frontend.P.setPlaceOpValue
import all Lanius.Mini.Frontend.P.refRooted
import all Lanius.Mini.Frontend.P.refTarget
import all Lanius.Mini.Frontend.P.setFieldOrEval
import all Lanius.Mini.Frontend.P.setPlaceValue
import all Lanius.Mini.Frontend.P.divergeFunc
import all Lanius.Mini.Frontend.P.namesFieldBase
import all Lanius.Mini.Frontend.P.paramEffs
import all Lanius.Mini.Frontend.P.projectionFunc
import all Lanius.Mini.Frontend.P.readFn
import all Lanius.Mini.Frontend.P.refKids
import all Lanius.Mini.Frontend.P.refUsesOk
import all Lanius.Mini.Frontend.P.refsChecked
import all Lanius.Mini.Frontend.P.refsUsedOk
import all Lanius.Mini.Frontend.P.isFnPath
import all Lanius.Mini.Frontend.P.isMethodForm
import all Lanius.Mini.Frontend.P.memberArgs
import all Lanius.Mini.Frontend.P.effSliceLocal
import all Lanius.Mini.Frontend.P.fieldOfTy
import all Lanius.Mini.Frontend.P.fieldValue
import all Lanius.Mini.Frontend.P.methodOfTy
import all Lanius.Mini.Frontend.P.stepExpected
import all Lanius.Mini.Frontend.P.eArraySliceClosed
import all Lanius.Mini.Frontend.P.eDerefClosed
import all Lanius.Mini.Frontend.P.eIndexClosed
import all Lanius.Mini.Frontend.P.ePlaceAtClosed
import all Lanius.Mini.Frontend.P.ePlaceFieldClosed
import all Lanius.Mini.Frontend.P.setPlaceClosed
import all Lanius.Mini.Frontend.P.setPlaceOpClosed
import all Lanius.Mini.Frontend.P.checkedFunc
public import Lanius.Mini.Frontend.P.Inline_attachAfter
public import Lanius.Mini.Frontend.P.Inline_attachTerm
public import Lanius.Mini.Frontend.P.Inline_genericCloseAt
public import Lanius.Mini.Frontend.P.grammar
public import Lanius.Mini.Frontend.P.grammarPart13
public import Lanius.Mini.Frontend.P.grammarPart14
public import Lanius.Mini.Frontend.P.grammarPart15
public import Lanius.Mini.Frontend.P.grammarPart16
public import Lanius.Mini.Frontend.P.isEmptyUsize
public import Lanius.Mini.Frontend.P.noTokens
public import Lanius.Mini.Frontend.P.nodeProd
public import Lanius.Mini.Frontend.P.usedUp
public import Lanius.Mini.Frontend.P.validateTree
public import Lanius.Mini.Frontend.P.whole
public import Lanius.Mini.Frontend.P.attach
public import Lanius.Mini.Frontend.P.only
public import Lanius.Mini.Frontend.P.shrFirst
public import Lanius.Mini.Frontend.P.shrSecond
public import Lanius.Mini.Frontend.P.build
public import Lanius.Mini.Frontend.P.buildChecked
public import Lanius.Mini.Frontend.P.buildClosed
public import Lanius.Mini.Frontend.P.buildCollected
public import Lanius.Mini.Frontend.P.buildFiles
public import Lanius.Mini.Frontend.P.buildMono
public import Lanius.Mini.Frontend.P.consRoot
public import Lanius.Mini.Frontend.P.filesFuel
public import Lanius.Mini.Frontend.P.frontEnd
public import Lanius.Mini.Frontend.P.frontEndFiles
public import Lanius.Mini.Frontend.P.lxDigit
public import Lanius.Mini.Frontend.P.lxIdentContinue
public import Lanius.Mini.Frontend.P.lxIdentStart
public import Lanius.Mini.Frontend.P.lxSpace
public import Lanius.Mini.Frontend.P.untypedRejected
public import Lanius.Mini.Frontend.P.validateFiles
public import Lanius.Mini.Frontend.P.wideLeftFuncs
public import Lanius.Mini.Frontend.P.wideLeftStmt

@[expose] public section
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
