module

public import Lanius.Mini.Reading.Prods
public import Lanius.Mini.Reading.Clash
import all Lanius.Mini.Frontend.P.attach
import all Lanius.Mini.Frontend.P.only
import all Lanius.Mini.Frontend.P.shrFirst
import all Lanius.Mini.Frontend.P.shrSecond
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

@[expose] public section
/-! The production numbers unfolded, so that `omega` can tell two of them apart. -/

namespace Lanius.Mini.Prod

macro "unfold_prods" : tactic => `(tactic| simp only [pAdd, pAddTail, pAndTail, pAndexpr, pArgsAfterCommaMore, pArgsAfterCommaTrailing, pArgsEnd, pArgsMore, pArgsNone, pArgsSome, pAssign, pAssignAdd, pAssignBand, pAssignBor, pAssignDiv, pAssignEnd, pAssignMod, pAssignMul, pAssignSet, pAssignShl, pAssignShr, pAssignSub, pAssignXor, pBandTail, pBase, pBitAnd, pBitOr, pBitXor, pBlockStmt, pBorTail, pBreakStmt, pCast, pCastTypeName, pCastTypePath, pCastTypePathEnd, pCastTypePathIdent, pChar, pCompare, pConst, pContinueStmt, pContractsNone, pContractsMore, pRequires, pDivTail, pElseNone, pElseStmt, pEnum, pEnumTypeParam, pEnumTypeParamsAfterCommaMore, pEnumTypeParamsMore, pEnumTypeParamsSome, pEnumVariantFieldsAfterCommaMore, pEnumVariantFieldsAfterCommaTrailing, pEnumVariantFieldsEnd, pEnumVariantFieldsMore, pEnumVariantFieldsNone, pEnumVariantFieldsSome, pEnumVariantUnit, pEnumVariantsAfterCommaMore, pEnumVariantsAfterCommaTrailing, pEnumVariantsEnd, pEnumVariantsMore, pEnumVariantsNone, pEnumVariantsSome, pEqTail, pEquality, pExpr, pExprStmt, pExternFn, pFalse, pFile, pFloat, pFn, pForIterRangeFromStart, pForStmt, pGeTail, pGenericArgumentType, pGroup, pGtTail, pIdent, pIdentPlain, pIfStmt, pImplFn, pImplInherent, pImplMethod, pImplMethodPub, pImplMethodsMore, pImplMethodsSome, pImplTrait, pImport, pImportPath, pInt, pItemPub, pItemsEnd, pItemsMore, pLeTail, pLetInit, pLetStmt, pLetType, pLetTypeNone, pArmBlock, pLtTail, pMatchArmsAfterCommaMore, pMatchArmsAfterCommaTrailing, pMatchArmsEnd, pMatchArmsMore, pMatchArmsNone, pMatchArmsSome, pMatchExpr, pMemberTypeArgsNone, pMemberTypeArgsSome, pModTail, pModule, pMul, pMulTail, pNeTail, pNeg, pNot, pOrTail, pOrexpr, pParamNamed, pParamSelf, pParamSelfRef, pParamsAfterCommaMore, pParamsAfterCommaTrailing, pParamsEnd, pParamsMore, pParamsNone, pParamsSome, pPath, pPathEnd, pPathIdent, pPathIdentArgs, pPathMore, pPathTypeArgsAfterCommaMore, pPathTypeArgsMore, pPatternIdent, pPatternInt, pPatternTrue, pPatternFalse, pPatternPlain, pPatternsAfterCommaMore, pPatternsAfterCommaTrailing, pPatternsEnd, pPatternsMore, pPatternsNone, pPatternsSome, pPostfix, pPostfixCall, pPostfixEnd, pPostfixIndex, pPostfixTry, pPostfixMember, pRangeBound, pRangeBoundName, pRangeExclusive, pRangeStartInt, pRetType, pRetVoid, pReturnStmt, pReturnValue, pReturnVoid, pSelfParamPlain, pSelfParamTyped, pSelfValue, pShift, pShlTail, pShrTail, pStmtsEnd, pStmtsMore, pStruct, pStructFieldsAfterCommaMore, pStructFieldsAfterCommaTrailing, pStructFieldsEnd, pStructFieldsMore, pStructFieldsNone, pStructFieldsSome, pStructLit, pStructLitFieldsAfterCommaMore, pStructLitFieldsAfterCommaTrailing, pStructLitFieldsEnd, pStructLitFieldsMore, pStructLitFieldsNone, pStructLitFieldsSome, pSubTail, pTrait, pTrue, pTypeAlias, pTypeArgsAfterCommaMore, pTypeArgsMore, pTypeArgsNone, pTypeArgsSome, pTypeArray, pTypeIdent, pTypeNever, pTypePathEnd, pTypePathIdent, pTypePathMore, pTypeSliceTail, pWhereNone, pWhileStmt, pXorTail, pArrayLit, pArraySome, pArrayMore, pArrayEnd, pArrayRepeat, pArrayAfterCommaMore, pArrayAfterCommaTrailing, pTypeArrayTail, pTypeArrayLenConstant, pGenericArgumentInteger] at *)

/-- Close a goal whose hypotheses give one node two different productions. -/
macro "prod_clash" : tactic => `(tactic| (exfalso; prods_clash))

end Lanius.Mini.Prod
