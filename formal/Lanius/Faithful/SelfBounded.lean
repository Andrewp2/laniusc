module

public import Lanius.Faithful.GenB.SelfBudget
public import Lanius.Faithful.SelfTotal
public import Lanius.Faithful.BudgetMono
import all Lanius.Faithful.Gen.Self
import all Lanius.Faithful.Gen.SelfPrimTab
import all Lanius.Faithful.Gen.SelfPrims
import all Lanius.Faithful.Gen.SelfProg
import all Lanius.Faithful.Gen.SelfPure
import all Lanius.Faithful.Gen.SelfPureBase
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrc0
import all Lanius.Faithful.Gen.SelfSrc1
import all Lanius.Faithful.Gen.SelfSrc2
import all Lanius.Faithful.Gen.SelfSrc3
import all Lanius.Faithful.Gen.SelfSrc4
import all Lanius.Faithful.Gen.SelfSrc5
import all Lanius.Faithful.Gen.SelfSrc6
import all Lanius.Faithful.Gen.SelfSrc7
import all Lanius.Faithful.Gen.SelfSrcC_BinOp_folds
import all Lanius.Faithful.Gen.SelfSrcC_DivOp_size
import all Lanius.Faithful.Gen.SelfSrcC_Expr_agrees
import all Lanius.Faithful.Gen.SelfSrcC_FArith_opcode
import all Lanius.Faithful.Gen.SelfSrcC_FloatTy_rex
import all Lanius.Faithful.Gen.SelfSrcC_Inline_arithOf
import all Lanius.Faithful.Gen.SelfSrcC_Inline_blockLeft
import all Lanius.Faithful.Gen.SelfSrcC_Inline_factOr
import all Lanius.Faithful.Gen.SelfSrcC_Inline_lowerSetScalar
import all Lanius.Faithful.Gen.SelfSrcC_Lists_empty
import all Lanius.Faithful.Gen.SelfSrcC_SrcExpr_guard
import all Lanius.Faithful.Gen.SelfSrcC_SrcType_same
import all Lanius.Faithful.Gen.SelfSrcC_Stmt_kills
import all Lanius.Faithful.Gen.SelfSrcC_UintTy_half
import all Lanius.Faithful.Gen.SelfSrcC_UintTy_isWide
import all Lanius.Faithful.Gen.SelfSrcC_UintTy_mask
import all Lanius.Faithful.Gen.SelfSrcC_Word_compute
import all Lanius.Faithful.Gen.SelfSrcC_Word_narrows
import all Lanius.Faithful.Gen.SelfSrcC_applyGuard
import all Lanius.Faithful.Gen.SelfSrcC_arithShiftRight
import all Lanius.Faithful.Gen.SelfSrcC_arithUint
import all Lanius.Faithful.Gen.SelfSrcC_arities
import all Lanius.Faithful.Gen.SelfSrcC_armBodyScope
import all Lanius.Faithful.Gen.SelfSrcC_armPayload
import all Lanius.Faithful.Gen.SelfSrcC_armScope
import all Lanius.Faithful.Gen.SelfSrcC_arrayCallSig
import all Lanius.Faithful.Gen.SelfSrcC_assignAgrees
import all Lanius.Faithful.Gen.SelfSrcC_assignFrom
import all Lanius.Faithful.Gen.SelfSrcC_binaryConstant
import all Lanius.Faithful.Gen.SelfSrcC_bindingBytes
import all Lanius.Faithful.Gen.SelfSrcC_callAgrees
import all Lanius.Faithful.Gen.SelfSrcC_codeSize
import all Lanius.Faithful.Gen.SelfSrcC_compileArgs
import all Lanius.Faithful.Gen.SelfSrcC_compileOr
import all Lanius.Faithful.Gen.SelfSrcC_compileSource
import all Lanius.Faithful.Gen.SelfSrcC_conjunction
import all Lanius.Faithful.Gen.SelfSrcC_consArgs
import all Lanius.Faithful.Gen.SelfSrcC_declareFuncs
import all Lanius.Faithful.Gen.SelfSrcC_declareProgram
import all Lanius.Faithful.Gen.SelfSrcC_elementAddress
import all Lanius.Faithful.Gen.SelfSrcC_elementBase
import all Lanius.Faithful.Gen.SelfSrcC_enumVariants
import all Lanius.Faithful.Gen.SelfSrcC_equality
import all Lanius.Faithful.Gen.SelfSrcC_evalDivide
import all Lanius.Faithful.Gen.SelfSrcC_evalDivideSint
import all Lanius.Faithful.Gen.SelfSrcC_evalHost
import all Lanius.Faithful.Gen.SelfSrcC_evalNot
import all Lanius.Faithful.Gen.SelfSrcC_evalSame
import all Lanius.Faithful.Gen.SelfSrcC_evalSlotLimit
import all Lanius.Faithful.Gen.SelfSrcC_extentAfter
import all Lanius.Faithful.Gen.SelfSrcC_floatApply
import all Lanius.Faithful.Gen.SelfSrcC_funcNeeds
import all Lanius.Faithful.Gen.SelfSrcC_guardAnd
import all Lanius.Faithful.Gen.SelfSrcC_hostRandomCode
import all Lanius.Faithful.Gen.SelfSrcC_indexOf
import all Lanius.Faithful.Gen.SelfSrcC_iteThen
import all Lanius.Faithful.Gen.SelfSrcC_killShared
import all Lanius.Faithful.Gen.SelfSrcC_larger
import all Lanius.Faithful.Gen.SelfSrcC_leftTrue
import all Lanius.Faithful.Gen.SelfSrcC_linkedSize
import all Lanius.Faithful.Gen.SelfSrcC_loadAtBytes
import all Lanius.Faithful.Gen.SelfSrcC_longer
import all Lanius.Faithful.Gen.SelfSrcC_lowerAddress
import all Lanius.Faithful.Gen.SelfSrcC_lowerApply
import all Lanius.Faithful.Gen.SelfSrcC_lowerBody
import all Lanius.Faithful.Gen.SelfSrcC_lowerCallSig
import all Lanius.Faithful.Gen.SelfSrcC_lowerLoadType
import all Lanius.Faithful.Gen.SelfSrcC_lowerLocal
import all Lanius.Faithful.Gen.SelfSrcC_lowerReturn
import all Lanius.Faithful.Gen.SelfSrcC_lowerSetCallArgs
import all Lanius.Faithful.Gen.SelfSrcC_lowerSetValues
import all Lanius.Faithful.Gen.SelfSrcC_lowerShift
import all Lanius.Faithful.Gen.SelfSrcC_lowerSlice
import all Lanius.Faithful.Gen.SelfSrcC_lowerTagged
import all Lanius.Faithful.Gen.SelfSrcC_matchDst
import all Lanius.Faithful.Gen.SelfSrcC_matchVariants
import all Lanius.Faithful.Gen.SelfSrcC_needCapped
import all Lanius.Faithful.Gen.SelfSrcC_needLimit
import all Lanius.Faithful.Gen.SelfSrcC_needsAfter
import all Lanius.Faithful.Gen.SelfSrcC_optimizeIte
import all Lanius.Faithful.Gen.SelfSrcC_optimizeLeft
import all Lanius.Faithful.Gen.SelfSrcC_optimizeNeg
import all Lanius.Faithful.Gen.SelfSrcC_packRound
import all Lanius.Faithful.Gen.SelfSrcC_render
import all Lanius.Faithful.Gen.SelfSrcC_repeatType
import all Lanius.Faithful.Gen.SelfSrcC_roomFits
import all Lanius.Faithful.Gen.SelfSrcC_shortCircuit
import all Lanius.Faithful.Gen.SelfSrcC_sintToUint
import all Lanius.Faithful.Gen.SelfSrcC_storeArray
import all Lanius.Faithful.Gen.SelfSrcC_storeEvalWord
import all Lanius.Faithful.Gen.SelfSrcC_storeType
import all Lanius.Faithful.Gen.SelfSrcC_storeWordElement
import all Lanius.Faithful.Gen.SelfSrcC_strStores
import all Lanius.Faithful.Gen.SelfSrcC_structFields
import all Lanius.Faithful.Gen.SelfSrcC_substAll
import all Lanius.Faithful.Gen.SelfSrcC_usizeWidth
import all Lanius.Faithful.Gen.SelfSrcC_widthOf
import all Lanius.Faithful.Gen.SelfSrcC_withBudget
import all Lanius.Faithful.Gen.SelfSrcC_wordElement
import all Lanius.Faithful.Gen.SelfSrcC_wordStride
import all Lanius.Faithful.Gen.SelfSrcC_wordWidth
import all Lanius.Faithful.Gen.SelfSrcF_Inline_attachNode
import all Lanius.Faithful.Gen.SelfSrcF_Inline_attachParent
import all Lanius.Faithful.Gen.SelfSrcF_Inline_charEnd
import all Lanius.Faithful.Gen.SelfSrcF_Inline_charOpen
import all Lanius.Faithful.Gen.SelfSrcF_Inline_findMethodAt
import all Lanius.Faithful.Gen.SelfSrcF_Inline_litValueAt
import all Lanius.Faithful.Gen.SelfSrcF_Inline_lxAfterFractionAt
import all Lanius.Faithful.Gen.SelfSrcF_Inline_lxFilterAt
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pAddTail
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pAndTail
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pArgsMore
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pArrayAfterCommaTrailing
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pArrayMore
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pBitAnd
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pBoundTypeArgsAfterCommaMore
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pContractsNone
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pElseStmt
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pEnumTypeParam
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pExpr
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pIdentPlain
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pImplMethodsSome
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pLeTail
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pModTail
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pPathMore
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pRangeStartInt
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pRetVoid
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pSelfParamPlain
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pSelfParamTyped
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pSelfValue
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pStmtsMore
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pStructFieldsAfterCommaMore
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pStructFieldsMore
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pTypeArgsNone
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pTypePathIdent
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pTypeSliceTail
import all Lanius.Faithful.Gen.SelfSrcF_Inline_positionAt
import all Lanius.Faithful.Gen.SelfSrcF_Inline_tLparen
import all Lanius.Faithful.Gen.SelfSrcF_Inline_tRparen
import all Lanius.Faithful.Gen.SelfSrcF_Inline_variantsNamedAt
import all Lanius.Faithful.Gen.SelfSrcF_allWeighed
import all Lanius.Faithful.Gen.SelfSrcF_allocClosed
import all Lanius.Faithful.Gen.SelfSrcF_anyNested
import all Lanius.Faithful.Gen.SelfSrcF_argView
import all Lanius.Faithful.Gen.SelfSrcF_armsNaming
import all Lanius.Faithful.Gen.SelfSrcF_armsOf
import all Lanius.Faithful.Gen.SelfSrcF_assertClosed
import all Lanius.Faithful.Gen.SelfSrcF_basedDigits
import all Lanius.Faithful.Gen.SelfSrcF_basedLimit
import all Lanius.Faithful.Gen.SelfSrcF_bindsOfTys
import all Lanius.Faithful.Gen.SelfSrcF_blockArmsOf
import all Lanius.Faithful.Gen.SelfSrcF_callParts
import all Lanius.Faithful.Gen.SelfSrcF_checkedFunc
import all Lanius.Faithful.Gen.SelfSrcF_closeFuncs
import all Lanius.Faithful.Gen.SelfSrcF_collect
import all Lanius.Faithful.Gen.SelfSrcF_compoundEval
import all Lanius.Faithful.Gen.SelfSrcF_compoundOf
import all Lanius.Faithful.Gen.SelfSrcF_consBinder
import all Lanius.Faithful.Gen.SelfSrcF_consBound
import all Lanius.Faithful.Gen.SelfSrcF_consTreeTail
import all Lanius.Faithful.Gen.SelfSrcF_consTys
import all Lanius.Faithful.Gen.SelfSrcF_depthLimit
import all Lanius.Faithful.Gen.SelfSrcF_digitBelow
import all Lanius.Faithful.Gen.SelfSrcF_distinct
import all Lanius.Faithful.Gen.SelfSrcF_divergeArm
import all Lanius.Faithful.Gen.SelfSrcF_eDerefClosed
import all Lanius.Faithful.Gen.SelfSrcF_eDivideClosed
import all Lanius.Faithful.Gen.SelfSrcF_eStructClosed
import all Lanius.Faithful.Gen.SelfSrcF_effNamedTys
import all Lanius.Faithful.Gen.SelfSrcF_externBody
import all Lanius.Faithful.Gen.SelfSrcF_fieldValue
import all Lanius.Faithful.Gen.SelfSrcF_findConst
import all Lanius.Faithful.Gen.SelfSrcF_firstSrc
import all Lanius.Faithful.Gen.SelfSrcF_flDecimal
import all Lanius.Faithful.Gen.SelfSrcF_flExpFirst
import all Lanius.Faithful.Gen.SelfSrcF_flLog2Or0
import all Lanius.Faithful.Gen.SelfSrcF_flNatHalf
import all Lanius.Faithful.Gen.SelfSrcF_flRoundUp
import all Lanius.Faithful.Gen.SelfSrcF_flattenTys
import all Lanius.Faithful.Gen.SelfSrcF_floatTyped
import all Lanius.Faithful.Gen.SelfSrcF_fnInstRet
import all Lanius.Faithful.Gen.SelfSrcF_forRange
import all Lanius.Faithful.Gen.SelfSrcF_freshId
import all Lanius.Faithful.Gen.SelfSrcF_frontEndRead
import all Lanius.Faithful.Gen.SelfSrcF_frontEndWords
import all Lanius.Faithful.Gen.SelfSrcF_funcsBytes
import all Lanius.Faithful.Gen.SelfSrcF_funcsOnto
import all Lanius.Faithful.Gen.SelfSrcF_genericClose
import all Lanius.Faithful.Gen.SelfSrcF_genericOpen
import all Lanius.Faithful.Gen.SelfSrcF_grammarPart13
import all Lanius.Faithful.Gen.SelfSrcF_grammarPart8
import all Lanius.Faithful.Gen.SelfSrcF_hasConst
import all Lanius.Faithful.Gen.SelfSrcF_hasKids
import all Lanius.Faithful.Gen.SelfSrcF_i32ArrayLength
import all Lanius.Faithful.Gen.SelfSrcF_ifEff
import all Lanius.Faithful.Gen.SelfSrcF_ifNotWrites
import all Lanius.Faithful.Gen.SelfSrcF_ifSome
import all Lanius.Faithful.Gen.SelfSrcF_isEmptyUsize
import all Lanius.Faithful.Gen.SelfSrcF_isFnPath
import all Lanius.Faithful.Gen.SelfSrcF_isMatchStmt
import all Lanius.Faithful.Gen.SelfSrcF_isPathCall
import all Lanius.Faithful.Gen.SelfSrcF_isTryEnum
import all Lanius.Faithful.Gen.SelfSrcF_isTypedSliceSegments
import all Lanius.Faithful.Gen.SelfSrcF_isUnderscore
import all Lanius.Faithful.Gen.SelfSrcF_itemOf
import all Lanius.Faithful.Gen.SelfSrcF_joinInsts
import all Lanius.Faithful.Gen.SelfSrcF_letClosed
import all Lanius.Faithful.Gen.SelfSrcF_letStructClosed
import all Lanius.Faithful.Gen.SelfSrcF_limExprs
import all Lanius.Faithful.Gen.SelfSrcF_limLeaf
import all Lanius.Faithful.Gen.SelfSrcF_litBound
import all Lanius.Faithful.Gen.SelfSrcF_litEffMatch
import all Lanius.Faithful.Gen.SelfSrcF_litIf
import all Lanius.Faithful.Gen.SelfSrcF_litWants
import all Lanius.Faithful.Gen.SelfSrcF_litWildValue
import all Lanius.Faithful.Gen.SelfSrcF_lowerTy
import all Lanius.Faithful.Gen.SelfSrcF_lxBlockEnd
import all Lanius.Faithful.Gen.SelfSrcF_lxCanonicalKind
import all Lanius.Faithful.Gen.SelfSrcF_lxDotAt
import all Lanius.Faithful.Gen.SelfSrcF_lxExponent
import all Lanius.Faithful.Gen.SelfSrcF_lxFixed
import all Lanius.Faithful.Gen.SelfSrcF_lxLeadingDot
import all Lanius.Faithful.Gen.SelfSrcF_lxSpaceEnd
import all Lanius.Faithful.Gen.SelfSrcF_lxSymbolStart
import all Lanius.Faithful.Gen.SelfSrcF_matchLetHead
import all Lanius.Faithful.Gen.SelfSrcF_matchStmtIf
import all Lanius.Faithful.Gen.SelfSrcF_matchTysOrNone
import all Lanius.Faithful.Gen.SelfSrcF_methodDecl
import all Lanius.Faithful.Gen.SelfSrcF_moduleOr
import all Lanius.Faithful.Gen.SelfSrcF_namesFieldBase
import all Lanius.Faithful.Gen.SelfSrcF_namesSome
import all Lanius.Faithful.Gen.SelfSrcF_negWideI32
import all Lanius.Faithful.Gen.SelfSrcF_nestedUsed
import all Lanius.Faithful.Gen.SelfSrcF_noBlock
import all Lanius.Faithful.Gen.SelfSrcF_noToken
import all Lanius.Faithful.Gen.SelfSrcF_noTrees
import all Lanius.Faithful.Gen.SelfSrcF_nullAt
import all Lanius.Faithful.Gen.SelfSrcF_nullConst
import all Lanius.Faithful.Gen.SelfSrcF_oneTreeNames
import all Lanius.Faithful.Gen.SelfSrcF_paramGoals
import all Lanius.Faithful.Gen.SelfSrcF_pathRef
import all Lanius.Faithful.Gen.SelfSrcF_pickTy
import all Lanius.Faithful.Gen.SelfSrcF_plainNaming
import all Lanius.Faithful.Gen.SelfSrcF_projection
import all Lanius.Faithful.Gen.SelfSrcF_projectionRet
import all Lanius.Faithful.Gen.SelfSrcF_purePart
import all Lanius.Faithful.Gen.SelfSrcF_readCountedBytes
import all Lanius.Faithful.Gen.SelfSrcF_readDeclInst
import all Lanius.Faithful.Gen.SelfSrcF_readInst
import all Lanius.Faithful.Gen.SelfSrcF_repeatEff
import all Lanius.Faithful.Gen.SelfSrcF_retBinds
import all Lanius.Faithful.Gen.SelfSrcF_rootInsts
import all Lanius.Faithful.Gen.SelfSrcF_scalarOf
import all Lanius.Faithful.Gen.SelfSrcF_selfRefOf
import all Lanius.Faithful.Gen.SelfSrcF_setEvalClosed
import all Lanius.Faithful.Gen.SelfSrcF_setFieldOrEval
import all Lanius.Faithful.Gen.SelfSrcF_setIndexOrEval
import all Lanius.Faithful.Gen.SelfSrcF_setPlaceOf
import all Lanius.Faithful.Gen.SelfSrcF_shadowUse
import all Lanius.Faithful.Gen.SelfSrcF_shrFirst
import all Lanius.Faithful.Gen.SelfSrcF_sintAt
import all Lanius.Faithful.Gen.SelfSrcF_sliceHead
import all Lanius.Faithful.Gen.SelfSrcF_strBytes
import all Lanius.Faithful.Gen.SelfSrcF_stringCall
import all Lanius.Faithful.Gen.SelfSrcF_stringCons
import all Lanius.Faithful.Gen.SelfSrcF_stringLast
import all Lanius.Faithful.Gen.SelfSrcF_stringOpen
import all Lanius.Faithful.Gen.SelfSrcF_stringReturn
import all Lanius.Faithful.Gen.SelfSrcF_structHead
import all Lanius.Faithful.Gen.SelfSrcF_textSelf
import all Lanius.Faithful.Gen.SelfSrcF_textSliceLen
import all Lanius.Faithful.Gen.SelfSrcF_treeTokens
import all Lanius.Faithful.Gen.SelfSrcF_triedErr
import all Lanius.Faithful.Gen.SelfSrcF_triedIf
import all Lanius.Faithful.Gen.SelfSrcF_tryLet
import all Lanius.Faithful.Gen.SelfSrcF_tryLetHead
import all Lanius.Faithful.Gen.SelfSrcF_tryLocalOf
import all Lanius.Faithful.Gen.SelfSrcF_typeDeclAt
import all Lanius.Faithful.Gen.SelfSrcF_typePathSpellings
import all Lanius.Faithful.Gen.SelfSrcF_typedLiteral
import all Lanius.Faithful.Gen.SelfSrcF_unitTy
import all Lanius.Faithful.Gen.SelfSrcF_variantArm
import all Lanius.Faithful.Gen.SelfSrcF_variantIn
import all Lanius.Faithful.Gen.SelfSrcF_variantLetHead
import all Lanius.Faithful.Gen.SelfSrcF_variantOfDecl
import all Lanius.Faithful.Gen.SelfSrcF_viewHead
import all Lanius.Faithful.Gen.SelfSrcF_weightAdd
import all Lanius.Faithful.Gen.SelfSrcF_whileEvalOf
import all Lanius.Faithful.Gen.SelfSrcF_wideLeftStmt
import all Lanius.Faithful.Gen.SelfSrcF_wideMarker
import all Lanius.Faithful.Gen.SelfSrcF_wideOf
import all Lanius.Faithful.Gen.SelfSrcRest
import all Lanius.Faithful.Gen.SelfTypes

@[expose] public section

/-! # The compile's bounds from the roots' preconditions (F14)

`SelfTotal`'s open premise asks that a wrapped compile (`costW`) under a
threshold `T` gives the self program's compile a value and a cost. The
budget certificates (`GenB.SelfBudget`) give that for the three roots,
`grammar` (8), `front_end_words` (7) and `compile_words` (6), each under its
precondition `Pre_F` at a budget above the run's block count (`uc`). The
certificates count blocks, the heap counts bytes (`boxCost prog`, at least 8
a block), so a run's block count is at most its heap cost
(`BudgetMono.qcall_cle`).

- `selfCost_of_pre`: a wrapped compile that costs `k < T`, with
  `front_end_words`'s precondition at `T` less `grammar`'s blocks, and
  `compile_words`'s at `T` less both, gives the self program's compile a cost.

What is left of `CompileBounded T` is those two preconditions. -/

namespace Lanius.Faithful.SelfBounded

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Faithful
open Lanius.Faithful.Self
open Lanius.Faithful.SelfRep
open Lanius.Faithful.SelfLive
open Lanius.Faithful.SelfPanics
open Lanius.Faithful.SelfTotal
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget

/-- Every `boxed` prim of the self program has one parameter. -/
theorem boxed_params :
    prims.boxed.all (fun c => (prog.funcs[c]?.map fun f => f.params.length) == some 1) = true := by
  decide +kernel

/-- A block costs at least one byte. -/
theorem uc_le_boxCost (c : Nat) (bx : prims.boxed.contains c = true) : uc c ≤ boxCost prog c := by
  have h := List.all_eq_true.mp boxed_params c (List.elem_iff.mp bx)
  unfold boxCost uc
  cases hf : prog.funcs[c]? with
  | none => rw [hf] at h; cases h
  | some f =>
    rw [hf] at h
    simp only [Option.map_some, beq_iff_eq, Option.some.injEq] at h
    simp only
    match hp : f.params with
    | [] => rw [hp] at h; cases h
    | [_] => simp only; omega
    | _ :: _ :: _ => rw [hp] at h; simp at h

/-- A run with a heap cost has a block count at most it, with the same value. -/
theorem uc_of_box {sp : SrcProgram} {n c : Nat} {vs : List Value} {g : Value × Nat}
    (h : qcall sp prims (boxCost prog) n c vs = some g) :
    ∃ k, qcall sp prims uc n c vs = some (g.1, k) ∧ k ≤ g.2 := by
  obtain ⟨gv, gc⟩ := g
  have hp : pcall sp prims n c vs = some gv := by
    rw [pcall_eq_qcall sp prims (boxCost prog), h]; rfl
  obtain ⟨k, hk⟩ := qcall_of_pcall uc hp
  obtain ⟨k', h1, h2⟩ := qcall_cle (fun c bx => uc_le_boxCost c bx) n c vs _ hk
  rw [h] at h1
  simp only [Option.some.injEq, Prod.mk.injEq] at h1
  obtain ⟨-, rfl⟩ := h1
  exact ⟨k, hk, h2⟩

/-- A run with a block count has a heap cost, with the same value. -/
theorem box_of_uc {sp : SrcProgram} {n c : Nat} {vs : List Value} {w : Value} {k : Nat}
    (h : qcall sp prims uc n c vs = some (w, k)) :
    ∃ k', qcall sp prims (boxCost prog) n c vs = some (w, k') := by
  obtain ⟨k', h1, -⟩ := qcall_cle (fun c bx => uc_le_boxCost c bx) n c vs _ h
  exact ⟨k', h1⟩

/-- **A wrapped compile under `T` gives the self program's compile a cost**,
where `front_end_words`'s and `compile_words`'s preconditions hold at what is
left of `T`. -/
theorem selfCost_of_pre {T N k : Nat} {W : List (BitVec 32)} (h : costW N W = some k) (lt : k < T)
    (pre7 : Pre_front_end_words N grammar W (T - Cost_grammar N))
    (pre6 : Pre_compile_words N (frontEndWords grammar W) (T - Cost_grammar N - Cost_front_end_words N grammar W)) :
    ∃ c, selfCost N W = some c := by
  simp only [costW] at h
  cases h8 : qcall progW prims (boxCost prog) N 8 [] with
  | none => rw [h8] at h; cases h
  | some g =>
    rw [h8] at h
    simp only [Option.bind_some] at h
    cases h7 : qcall progW prims (boxCost prog) N 7 [g.1, listVal W] with
    | none => rw [h7] at h; cases h
    | some fe =>
      rw [h7] at h
      simp only [Option.bind_some] at h
      cases h6 : qcall progW prims (boxCost prog) N 6 [fe.1] with
      | none => rw [h6] at h; cases h
      | some cw =>
        rw [h6] at h
        simp only [Option.bind_some, Option.some.injEq] at h
        obtain ⟨k8, u8, l8⟩ := uc_of_box h8
        obtain ⟨k7, u7, l7⟩ := uc_of_box h7
        obtain ⟨k6, u6, l6⟩ := uc_of_box h6
        obtain ⟨p8, c8, r8⟩ := bcert_grammar u8
        obtain ⟨p7, c7, r7⟩ := bcert_front_end_words u7 r8 (listVal_rep W) (b := T - Cost_grammar N)
          (by omega) pre7
        obtain ⟨p6, c6, r6⟩ := bcert_compile_words u6 r7
          (b := T - Cost_grammar N - Cost_front_end_words N grammar W) (by omega) pre6
        obtain ⟨b8, q8⟩ := box_of_uc p8
        obtain ⟨b7, q7⟩ := box_of_uc p7
        obtain ⟨b6, q6⟩ := box_of_uc p6
        exact ⟨W.length * consCost + b8 + b7 + b6, by simp [selfCost, q8, q7, q6]⟩

#print axioms selfCost_of_pre

end Lanius.Faithful.SelfBounded
