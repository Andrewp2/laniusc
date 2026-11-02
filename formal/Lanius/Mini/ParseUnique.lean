module

public import Lanius.Mini.GrammarCert
public import Lanius.Mini.Frontend.P.genericOpen
import all Lanius.Mini.Compiler.P.BinOp_folds
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.Expr_agrees
import all Lanius.Mini.Compiler.P.FArith_opcode
import all Lanius.Mini.Compiler.P.FloatTy_rex
import all Lanius.Mini.Compiler.P.Instr_pieces
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.SrcExpr_guard
import all Lanius.Mini.Compiler.P.SrcType_size
import all Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.UintTy_isWide
import all Lanius.Mini.Compiler.P.UintTy_mask
import all Lanius.Mini.Compiler.P.Word_compute
import all Lanius.Mini.Compiler.P.Word_narrows
import all Lanius.Mini.Compiler.P.applyGuard
import all Lanius.Mini.Compiler.P.arithShiftRight
import all Lanius.Mini.Compiler.P.arithUint
import all Lanius.Mini.Compiler.P.arities
import all Lanius.Mini.Compiler.P.armBodyScope
import all Lanius.Mini.Compiler.P.armPayload
import all Lanius.Mini.Compiler.P.armScope
import all Lanius.Mini.Compiler.P.assignFrom
import all Lanius.Mini.Compiler.P.binaryConstant
import all Lanius.Mini.Compiler.P.callAgrees
import all Lanius.Mini.Compiler.P.codeSize
import all Lanius.Mini.Compiler.P.compileArgs
import all Lanius.Mini.Compiler.P.compileModules
import all Lanius.Mini.Compiler.P.conjunction
import all Lanius.Mini.Compiler.P.consArgs
import all Lanius.Mini.Compiler.P.declareFuncs
import all Lanius.Mini.Compiler.P.declareProgram
import all Lanius.Mini.Compiler.P.elementAddress
import all Lanius.Mini.Compiler.P.elementBase
import all Lanius.Mini.Compiler.P.enumVariants
import all Lanius.Mini.Compiler.P.equality
import all Lanius.Mini.Compiler.P.evalDivide
import all Lanius.Mini.Compiler.P.evalDivideSint
import all Lanius.Mini.Compiler.P.evalNot
import all Lanius.Mini.Compiler.P.evalSame
import all Lanius.Mini.Compiler.P.floatApply
import all Lanius.Mini.Compiler.P.guardAnd
import all Lanius.Mini.Compiler.P.hostRandomCode
import all Lanius.Mini.Compiler.P.imageLimit
import all Lanius.Mini.Compiler.P.importOk
import all Lanius.Mini.Compiler.P.importsOk
import all Lanius.Mini.Compiler.P.indexOf
import all Lanius.Mini.Compiler.P.iteThen
import all Lanius.Mini.Compiler.P.leftTrue
import all Lanius.Mini.Compiler.P.loadAtBytes
import all Lanius.Mini.Compiler.P.lowerAddress
import all Lanius.Mini.Compiler.P.lowerApply
import all Lanius.Mini.Compiler.P.lowerBody
import all Lanius.Mini.Compiler.P.lowerCallSig
import all Lanius.Mini.Compiler.P.lowerLoadType
import all Lanius.Mini.Compiler.P.lowerLocal
import all Lanius.Mini.Compiler.P.lowerReturn
import all Lanius.Mini.Compiler.P.lowerSetCallArgs
import all Lanius.Mini.Compiler.P.lowerSetValues
import all Lanius.Mini.Compiler.P.lowerShift
import all Lanius.Mini.Compiler.P.lowerSlice
import all Lanius.Mini.Compiler.P.lowerTagged
import all Lanius.Mini.Compiler.P.matchDst
import all Lanius.Mini.Compiler.P.matchVariants
import all Lanius.Mini.Compiler.P.moduleExports
import all Lanius.Mini.Compiler.P.moduleFirsts
import all Lanius.Mini.Compiler.P.modulesOk
import all Lanius.Mini.Compiler.P.render
import all Lanius.Mini.Compiler.P.repeatType
import all Lanius.Mini.Compiler.P.shortCircuit
import all Lanius.Mini.Compiler.P.withBudget
import all Lanius.Mini.Compiler.P.funcNeeds
import all Lanius.Mini.Compiler.P.sintToUint
import all Lanius.Mini.Compiler.P.storeArray
import all Lanius.Mini.Compiler.P.arrayCallSig
import all Lanius.Mini.Compiler.P.bindingBytes
import all Lanius.Mini.Compiler.P.needRound
import all Lanius.Mini.Compiler.P.needsAfter
import all Lanius.Mini.Compiler.P.storeEvalWord
import all Lanius.Mini.Compiler.P.storeType
import all Lanius.Mini.Compiler.P.storeWordElement
import all Lanius.Mini.Compiler.P.structFields
import all Lanius.Mini.Compiler.P.usizeWidth
import all Lanius.Mini.Compiler.P.widthOf
import all Lanius.Mini.Compiler.P.wordElement
import all Lanius.Mini.Compiler.P.wordStride
import all Lanius.Mini.Compiler.P.wordWidth
import all Lanius.Mini.Compiler.Types
import all Lanius.Mini.Frontend.P.allocClosed
import all Lanius.Mini.Frontend.P.anyNested
import all Lanius.Mini.Frontend.P.armsNaming
import all Lanius.Mini.Frontend.P.armsOf
import all Lanius.Mini.Frontend.P.assertClosed
import all Lanius.Mini.Frontend.P.blockArmsOf
import all Lanius.Mini.Frontend.P.callParts
import all Lanius.Mini.Frontend.P.projection
import all Lanius.Mini.Frontend.P.closeFuncs
import all Lanius.Mini.Frontend.P.collect
import all Lanius.Mini.Frontend.P.compoundEval
import all Lanius.Mini.Frontend.P.compoundOf
import all Lanius.Mini.Frontend.P.consBinder
import all Lanius.Mini.Frontend.P.consBound
import all Lanius.Mini.Frontend.P.consTreeTail
import all Lanius.Mini.Frontend.P.consTys
import all Lanius.Mini.Frontend.P.distinct
import all Lanius.Mini.Frontend.P.divergeArm
import all Lanius.Mini.Frontend.P.bindsOfTys
import all Lanius.Mini.Frontend.P.eDivideClosed
import all Lanius.Mini.Frontend.P.eIndexClosed
import all Lanius.Mini.Frontend.P.eStructClosed
import all Lanius.Mini.Frontend.P.effNamedTys
import all Lanius.Mini.Frontend.P.externBody
import all Lanius.Mini.Frontend.P.fieldTyAt
import all Lanius.Mini.Frontend.P.findConst
import all Lanius.Mini.Frontend.P.firstSrc
import all Lanius.Mini.Frontend.P.flDecimal
import all Lanius.Mini.Frontend.P.flExpFirst
import all Lanius.Mini.Frontend.P.flLog2Or0
import all Lanius.Mini.Frontend.P.flNatHalf
import all Lanius.Mini.Frontend.P.flRoundUp
import all Lanius.Mini.Frontend.P.flattenTys
import all Lanius.Mini.Frontend.P.floatTyped
import all Lanius.Mini.Frontend.P.fnInstRet
import all Lanius.Mini.Frontend.P.forRange
import all Lanius.Mini.Frontend.P.freshId
import all Lanius.Mini.Frontend.P.frontEndRead
import all Lanius.Mini.Frontend.P.frontEndWords
import all Lanius.Mini.Frontend.P.funcsOnto
import all Lanius.Mini.Frontend.P.genericClose
import all Lanius.Mini.Frontend.P.genericOpen
import all Lanius.Mini.Frontend.P.grammarPart13
import all Lanius.Mini.Frontend.P.grammarPart8
import all Lanius.Mini.Frontend.P.hasConst
import all Lanius.Mini.Frontend.P.hasKids
import all Lanius.Mini.Frontend.P.ifEff
import all Lanius.Mini.Frontend.P.ifNotWrites
import all Lanius.Mini.Frontend.P.intLiteral
import all Lanius.Mini.Frontend.P.isEmptyUsize
import all Lanius.Mini.Frontend.P.isMatchStmt
import all Lanius.Mini.Frontend.P.isPathCall
import all Lanius.Mini.Frontend.P.isTryEnum
import all Lanius.Mini.Frontend.P.isUnderscore
import all Lanius.Mini.Frontend.P.itemOf
import all Lanius.Mini.Frontend.P.joinInsts
import all Lanius.Mini.Frontend.P.letClosed
import all Lanius.Mini.Frontend.P.letStructClosed
import all Lanius.Mini.Frontend.P.lowerTy
import all Lanius.Mini.Frontend.P.lxBlockEnd
import all Lanius.Mini.Frontend.P.lxCanonicalKind
import all Lanius.Mini.Frontend.P.lxDotAt
import all Lanius.Mini.Frontend.P.lxExponent
import all Lanius.Mini.Frontend.P.lxFixed
import all Lanius.Mini.Frontend.P.lxLeadingDot
import all Lanius.Mini.Frontend.P.lxSpaceEnd
import all Lanius.Mini.Frontend.P.lxSymbolStart
import all Lanius.Mini.Frontend.P.matchLetHead
import all Lanius.Mini.Frontend.P.matchStmtIf
import all Lanius.Mini.Frontend.P.matchTysOrNone
import all Lanius.Mini.Frontend.P.methodDecl
import all Lanius.Mini.Frontend.P.moduleOr
import all Lanius.Mini.Frontend.P.namesSome
import all Lanius.Mini.Frontend.P.negWideI32
import all Lanius.Mini.Frontend.P.nestedUsed
import all Lanius.Mini.Frontend.P.noBlock
import all Lanius.Mini.Frontend.P.noToken
import all Lanius.Mini.Frontend.P.noTrees
import all Lanius.Mini.Frontend.P.nullAt
import all Lanius.Mini.Frontend.P.nullConst
import all Lanius.Mini.Frontend.P.paramGoals
import all Lanius.Mini.Frontend.P.pathRef
import all Lanius.Mini.Frontend.P.pickTy
import all Lanius.Mini.Frontend.P.plainNaming
import all Lanius.Mini.Frontend.P.projectionRet
import all Lanius.Mini.Frontend.P.purePart
import all Lanius.Mini.Frontend.P.readCountedBytes
import all Lanius.Mini.Frontend.P.readDeclInst
import all Lanius.Mini.Frontend.P.readInst
import all Lanius.Mini.Frontend.P.repeatEff
import all Lanius.Mini.Frontend.P.retBinds
import all Lanius.Mini.Frontend.P.rootInsts
import all Lanius.Mini.Frontend.P.scalarOf
import all Lanius.Mini.Frontend.P.selfRefOf
import all Lanius.Mini.Frontend.P.setEvalClosed
import all Lanius.Mini.Frontend.P.setIndexOrEval
import all Lanius.Mini.Frontend.P.shadowUse
import all Lanius.Mini.Frontend.P.shrFirst
import all Lanius.Mini.Frontend.P.sintAt
import all Lanius.Mini.Frontend.P.sliceHead
import all Lanius.Mini.Frontend.P.structHead
import all Lanius.Mini.Frontend.P.textSelf
import all Lanius.Mini.Frontend.P.treeTokens
import all Lanius.Mini.Frontend.P.triedErr
import all Lanius.Mini.Frontend.P.triedIf
import all Lanius.Mini.Frontend.P.tryLet
import all Lanius.Mini.Frontend.P.tryLetHead
import all Lanius.Mini.Frontend.P.tryLocalOf
import all Lanius.Mini.Frontend.P.typeDeclAt
import all Lanius.Mini.Frontend.P.typePathSpellings
import all Lanius.Mini.Frontend.P.typedLiteral
import all Lanius.Mini.Frontend.P.unitTy
import all Lanius.Mini.Frontend.P.variantArm
import all Lanius.Mini.Frontend.P.variantIn
import all Lanius.Mini.Frontend.P.variantLetHead
import all Lanius.Mini.Frontend.P.variantOfDecl
import all Lanius.Mini.Frontend.P.whileEvalOf
import all Lanius.Mini.Frontend.P.wideLeftStmt
import all Lanius.Mini.Frontend.P.wideMarker
import all Lanius.Mini.Frontend.P.wideOf
import all Lanius.Mini.Frontend.Types
public import Lanius.Mini.Frontend.P.grammarPart13
public import Lanius.Mini.Frontend.P.isEmptyUsize
public import Lanius.Mini.Frontend.P.shrFirst
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
