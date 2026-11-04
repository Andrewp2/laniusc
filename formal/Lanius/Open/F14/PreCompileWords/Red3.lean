module

public import Lanius.Open.F14.PreCompileWords.Stmt
public import Lanius.Open.F14.PostFrontEndWords.Stmt
public import Lanius.Open.F14.FrontEndTypeSlots.Stmt
public import Lanius.Open.F14.FrontEndStmtDepth.Stmt
public import Lanius.Open.F14.PreCompileSourceV3.Stmt
public import Lanius.Open.F14.PreBinaryWordsV3.Stmt
import all Lanius.Mini.Frontend.P.grammarPart13
import all Lanius.Mini.Compiler.P.BinOp_folds
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.Expr_agrees
import all Lanius.Mini.Compiler.P.FArith_opcode
import all Lanius.Mini.Compiler.P.FloatTy_rex
import all Lanius.Mini.Compiler.P.Instr_pieces
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.SrcExpr_guard
import all Lanius.Mini.Compiler.P.SrcType_same
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
import all Lanius.Mini.Compiler.P.arrayCallSig
import all Lanius.Mini.Compiler.P.assignFrom
import all Lanius.Mini.Compiler.P.binaryConstant
import all Lanius.Mini.Compiler.P.bindingBytes
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
import all Lanius.Mini.Compiler.P.evalHost
import all Lanius.Mini.Compiler.P.evalNot
import all Lanius.Mini.Compiler.P.evalSame
import all Lanius.Mini.Compiler.P.evalSlotLimit
import all Lanius.Mini.Compiler.P.floatApply
import all Lanius.Mini.Compiler.P.funcNeeds
import all Lanius.Mini.Compiler.P.guardAnd
import all Lanius.Mini.Compiler.P.hostRandomCode
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
import all Lanius.Mini.Compiler.P.needCapped
import all Lanius.Mini.Compiler.P.needLimit
import all Lanius.Mini.Compiler.P.needsAfter
import all Lanius.Mini.Compiler.P.render
import all Lanius.Mini.Compiler.P.repeatType
import all Lanius.Mini.Compiler.P.roomFits
import all Lanius.Mini.Compiler.P.shortCircuit
import all Lanius.Mini.Compiler.P.sintToUint
import all Lanius.Mini.Compiler.P.storeArray
import all Lanius.Mini.Compiler.P.storeEvalWord
import all Lanius.Mini.Compiler.P.storeType
import all Lanius.Mini.Compiler.P.storeWordElement
import all Lanius.Mini.Compiler.P.strStores
import all Lanius.Mini.Compiler.P.structFields
import all Lanius.Mini.Compiler.P.usizeWidth
import all Lanius.Mini.Compiler.P.widthOf
import all Lanius.Mini.Compiler.P.withBudget
import all Lanius.Mini.Compiler.P.wordElement
import all Lanius.Mini.Compiler.P.wordStride
import all Lanius.Mini.Compiler.P.wordWidth
import all Lanius.Mini.Frontend.P.allWeighed
import all Lanius.Mini.Frontend.P.allocClosed
import all Lanius.Mini.Frontend.P.anyNested
import all Lanius.Mini.Frontend.P.argView
import all Lanius.Mini.Frontend.P.armsNaming
import all Lanius.Mini.Frontend.P.armsOf
import all Lanius.Mini.Frontend.P.assertClosed
import all Lanius.Mini.Frontend.P.basedDigits
import all Lanius.Mini.Frontend.P.basedLimit
import all Lanius.Mini.Frontend.P.bindsOfTys
import all Lanius.Mini.Frontend.P.blockArmsOf
import all Lanius.Mini.Frontend.P.callParts
import all Lanius.Mini.Frontend.P.checkedFunc
import all Lanius.Mini.Frontend.P.closeFuncs
import all Lanius.Mini.Frontend.P.collect
import all Lanius.Mini.Frontend.P.compoundEval
import all Lanius.Mini.Frontend.P.compoundOf
import all Lanius.Mini.Frontend.P.consBinder
import all Lanius.Mini.Frontend.P.consBound
import all Lanius.Mini.Frontend.P.consTreeTail
import all Lanius.Mini.Frontend.P.consTys
import all Lanius.Mini.Frontend.P.depthLimit
import all Lanius.Mini.Frontend.P.digitBelow
import all Lanius.Mini.Frontend.P.distinct
import all Lanius.Mini.Frontend.P.divergeArm
import all Lanius.Mini.Frontend.P.eDerefClosed
import all Lanius.Mini.Frontend.P.eDivideClosed
import all Lanius.Mini.Frontend.P.eStructClosed
import all Lanius.Mini.Frontend.P.effNamedTys
import all Lanius.Mini.Frontend.P.externBody
import all Lanius.Mini.Frontend.P.fieldValue
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
import all Lanius.Mini.Frontend.P.funcsBytes
import all Lanius.Mini.Frontend.P.funcsOnto
import all Lanius.Mini.Frontend.P.genericClose
import all Lanius.Mini.Frontend.P.genericOpen
import all Lanius.Mini.Frontend.P.grammarPart8
import all Lanius.Mini.Frontend.P.hasConst
import all Lanius.Mini.Frontend.P.hasKids
import all Lanius.Mini.Frontend.P.i32ArrayLength
import all Lanius.Mini.Frontend.P.ifEff
import all Lanius.Mini.Frontend.P.ifNotWrites
import all Lanius.Mini.Frontend.P.ifSome
import all Lanius.Mini.Frontend.P.isEmptyUsize
import all Lanius.Mini.Frontend.P.isFnPath
import all Lanius.Mini.Frontend.P.isMatchStmt
import all Lanius.Mini.Frontend.P.isPathCall
import all Lanius.Mini.Frontend.P.isTryEnum
import all Lanius.Mini.Frontend.P.isTypedSliceSegments
import all Lanius.Mini.Frontend.P.isUnderscore
import all Lanius.Mini.Frontend.P.itemOf
import all Lanius.Mini.Frontend.P.joinInsts
import all Lanius.Mini.Frontend.P.letClosed
import all Lanius.Mini.Frontend.P.letStructClosed
import all Lanius.Mini.Frontend.P.limExprs
import all Lanius.Mini.Frontend.P.limLeaf
import all Lanius.Mini.Frontend.P.litBound
import all Lanius.Mini.Frontend.P.litEffMatch
import all Lanius.Mini.Frontend.P.litIf
import all Lanius.Mini.Frontend.P.litWants
import all Lanius.Mini.Frontend.P.litWildValue
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
import all Lanius.Mini.Frontend.P.namesFieldBase
import all Lanius.Mini.Frontend.P.namesSome
import all Lanius.Mini.Frontend.P.negWideI32
import all Lanius.Mini.Frontend.P.nestedUsed
import all Lanius.Mini.Frontend.P.noBlock
import all Lanius.Mini.Frontend.P.noToken
import all Lanius.Mini.Frontend.P.noTrees
import all Lanius.Mini.Frontend.P.nullAt
import all Lanius.Mini.Frontend.P.nullConst
import all Lanius.Mini.Frontend.P.oneTreeNames
import all Lanius.Mini.Frontend.P.paramGoals
import all Lanius.Mini.Frontend.P.pathRef
import all Lanius.Mini.Frontend.P.pickTy
import all Lanius.Mini.Frontend.P.plainNaming
import all Lanius.Mini.Frontend.P.projection
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
import all Lanius.Mini.Frontend.P.setFieldOrEval
import all Lanius.Mini.Frontend.P.setIndexOrEval
import all Lanius.Mini.Frontend.P.setPlaceOf
import all Lanius.Mini.Frontend.P.shadowUse
import all Lanius.Mini.Frontend.P.shrFirst
import all Lanius.Mini.Frontend.P.sintAt
import all Lanius.Mini.Frontend.P.sliceHead
import all Lanius.Mini.Frontend.P.strBytes
import all Lanius.Mini.Frontend.P.stringCall
import all Lanius.Mini.Frontend.P.stringCons
import all Lanius.Mini.Frontend.P.stringLast
import all Lanius.Mini.Frontend.P.stringOpen
import all Lanius.Mini.Frontend.P.stringReturn
import all Lanius.Mini.Frontend.P.structHead
import all Lanius.Mini.Frontend.P.textSelf
import all Lanius.Mini.Frontend.P.textSliceLen
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
import all Lanius.Mini.Frontend.P.viewHead
import all Lanius.Mini.Frontend.P.weightAdd
import all Lanius.Mini.Frontend.P.whileEvalOf
import all Lanius.Mini.Frontend.P.wideLeftStmt
import all Lanius.Mini.Frontend.P.wideMarker
import all Lanius.Mini.Frontend.P.wideOf

@[expose] public section

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget
open Lanius.Faithful.SelfPre

theorem Lanius.Open.PreCompileWords.hb_words3 (l : List (BitVec 32)) : hb l = l.length := by
  induction l with
  | nil => rfl
  | cons a l ih => simp only [hb_cons, hb_bitvec, ih, List.length_cons]; omega

/-- The front end's output is lower than its inputs plus its cost
(`PostFrontEndWords`). Its types have at most `2 ^ 22` slots
(`FrontEndTypeSlots`), and its functions' lets need at most `2 ^ 55` slots
(`FrontEndStmtDepth`, words under `2 ^ 31`). So `compile_source`'s precondition
holds at that height (`PreCompileSourceV3`), and `binary_words`'s holds at any
budget (`PreBinaryWordsV3`). -/
theorem Lanius.Open.PreCompileWords.red3 (hpf : Lanius.Open.PostFrontEndWords)
    (hts : Lanius.Open.FrontEndTypeSlots) (hsd : Lanius.Open.FrontEndStmtDepth)
    (hcs : Lanius.Open.PreCompileSourceV3) (hbw : Lanius.Open.PreBinaryWordsV3) :
    Lanius.Open.PreCompileWords := by
  intro N W b hW hle
  rcases N with _ | n
  · trivial
  have hg : hb grammar ≤ 2 ^ 40 := by decide +kernel
  have hpost := hpf (n + 1) grammar W (2 ^ 40) hg (by rw [Lanius.Open.PreCompileWords.hb_words3]; omega) (by omega)
  rw [Pre_compile_words.eq_def]
  dsimp only
  cases hp : Lanius.Mini.frontEndWords grammar W with
  | none => trivial
  | some p =>
    rw [hp, hb_some] at hpost
    refine ⟨hcs p n b _ (hts W p hp) (fun f hf => ?_) hpost (by omega), fun b1 _ _ => hbw p n b1⟩
    have := hsd W p hp f hf
    have : 2 ^ 23 * (W.length + 1) ≤ 2 ^ 55 := by omega
    omega
