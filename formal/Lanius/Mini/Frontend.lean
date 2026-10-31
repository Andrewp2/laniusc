module

public import Lanius.Mini.Frontend.Types
public import Lanius.Mini.Frontend.P.noToken
public import Lanius.Mini.Frontend.P.genericClose
public import Lanius.Mini.Frontend.P.genericOpen
public import Lanius.Mini.Frontend.P.shrFirst
public import Lanius.Mini.Frontend.P.isEmptyUsize
public import Lanius.Mini.Frontend.P.hasKids
public import Lanius.Mini.Frontend.P.textSelf
public import Lanius.Mini.Frontend.P.distinct
public import Lanius.Mini.Frontend.P.noTrees
public import Lanius.Mini.Frontend.P.pathRef
public import Lanius.Mini.Frontend.P.typePathSpellings
public import Lanius.Mini.Frontend.P.moduleOr
public import Lanius.Mini.Frontend.P.typeDecls
public import Lanius.Mini.Frontend.P.noNames
public import Lanius.Mini.Frontend.P.rootInsts
public import Lanius.Mini.Frontend.P.findConst
public import Lanius.Mini.Frontend.P.variantOfDecl
public import Lanius.Mini.Frontend.P.variantIn
public import Lanius.Mini.Frontend.P.typeDeclAt
public import Lanius.Mini.Frontend.P.consTys
public import Lanius.Mini.Frontend.P.flattenTys
public import Lanius.Mini.Frontend.P.lowerTy
public import Lanius.Mini.Frontend.P.joinInsts
public import Lanius.Mini.Frontend.P.unitTy
public import Lanius.Mini.Frontend.P.wideMarker
public import Lanius.Mini.Frontend.P.intLiteral
public import Lanius.Mini.Frontend.P.flNatHalf
public import Lanius.Mini.Frontend.P.flLog2Or0
public import Lanius.Mini.Frontend.P.flRoundUp
public import Lanius.Mini.Frontend.P.flDecimal
public import Lanius.Mini.Frontend.P.flExpFirst
public import Lanius.Mini.Frontend.P.floatTyped
public import Lanius.Mini.Frontend.P.freshId
public import Lanius.Mini.Frontend.P.scalarOf
public import Lanius.Mini.Frontend.P.nullConst
public import Lanius.Mini.Frontend.P.typedLiteral
public import Lanius.Mini.Frontend.P.treeTokens
public import Lanius.Mini.Frontend.P.wideOf
public import Lanius.Mini.Frontend.P.pickTy
public import Lanius.Mini.Frontend.P.consTreeTail
public import Lanius.Mini.Frontend.P.xDivideOf
public import Lanius.Mini.Frontend.P.projectionRet
public import Lanius.Mini.Frontend.P.fnInstRet
public import Lanius.Mini.Frontend.P.isFnPath
public import Lanius.Mini.Frontend.P.isPathCall
public import Lanius.Mini.Frontend.P.sliceHead
public import Lanius.Mini.Frontend.P.consBinder
public import Lanius.Mini.Frontend.P.armsNaming
public import Lanius.Mini.Frontend.P.armsOf
public import Lanius.Mini.Frontend.P.hasConst
public import Lanius.Mini.Frontend.P.callParts
public import Lanius.Mini.Frontend.P.consBound
public import Lanius.Mini.Frontend.P.retBinds
public import Lanius.Mini.Frontend.P.matchTysOrNone
public import Lanius.Mini.Frontend.P.ifEff
public import Lanius.Mini.Frontend.P.structHead
public import Lanius.Mini.Frontend.P.variantLetHead
public import Lanius.Mini.Frontend.P.matchLetHead
public import Lanius.Mini.Frontend.P.whileEvalOf
public import Lanius.Mini.Frontend.P.setIndexOrEval
public import Lanius.Mini.Frontend.P.fieldTyAt
public import Lanius.Mini.Frontend.P.compoundEval
public import Lanius.Mini.Frontend.P.compoundOf
public import Lanius.Mini.Frontend.P.readFn
public import Lanius.Mini.Frontend.P.readDeclInst
public import Lanius.Mini.Frontend.P.readInst
public import Lanius.Mini.Frontend.P.effNamedTys
public import Lanius.Mini.Frontend.P.monoLoop
public import Lanius.Mini.Frontend.P.letClosed
public import Lanius.Mini.Frontend.P.letStructClosed
public import Lanius.Mini.Frontend.P.allocClosed
public import Lanius.Mini.Frontend.P.eDivideClosed
public import Lanius.Mini.Frontend.P.eIndexClosed
public import Lanius.Mini.Frontend.P.setEvalClosed
public import Lanius.Mini.Frontend.P.assertClosed
public import Lanius.Mini.Frontend.P.closeFuncs
public import Lanius.Mini.Frontend.P.nullAt
public import Lanius.Mini.Frontend.P.sintAt
public import Lanius.Mini.Frontend.P.firstSrc
public import Lanius.Mini.Frontend.P.negWideI32
public import Lanius.Mini.Frontend.P.wideLeftStmt
public import Lanius.Mini.Frontend.P.lxSymbolStart
public import Lanius.Mini.Frontend.P.lxSpaceEnd
public import Lanius.Mini.Frontend.P.lxBlockEnd
public import Lanius.Mini.Frontend.P.lxExponent
public import Lanius.Mini.Frontend.P.lxLeadingDot
public import Lanius.Mini.Frontend.P.lxFixed
public import Lanius.Mini.Frontend.P.lxDotAt
public import Lanius.Mini.Frontend.P.lxCanonicalKind
public import Lanius.Mini.Frontend.P.readCountedBytes
public import Lanius.Mini.Frontend.P.frontEndRead
public import Lanius.Mini.Frontend.P.frontEndWords
public import Lanius.Mini.Frontend.P.grammarPart8
public import Lanius.Mini.Frontend.P.grammarPart13
public import Lanius.Mini.Frontend.P.Inline_attachNode
public import Lanius.Mini.Frontend.P.Inline_attachParent
public import Lanius.Mini.Frontend.P.Inline_positionAt
public import Lanius.Mini.Frontend.P.Inline_variantsNamedAt
public import Lanius.Mini.Frontend.P.Inline_charOpen
public import Lanius.Mini.Frontend.P.Inline_findMethodAt
public import Lanius.Mini.Frontend.P.Inline_lxAfterFractionAt
public import Lanius.Mini.Frontend.P.Inline_lxFilterAt
public import Lanius.Mini.Frontend.P.Inline_pAddTail
public import Lanius.Mini.Frontend.P.Inline_pAndTail
public import Lanius.Mini.Frontend.P.Inline_pArgsMore
public import Lanius.Mini.Frontend.P.Inline_pBitAnd
public import Lanius.Mini.Frontend.P.Inline_pElseStmt
public import Lanius.Mini.Frontend.P.Inline_pEnumTypeParam
public import Lanius.Mini.Frontend.P.Inline_pExpr
public import Lanius.Mini.Frontend.P.Inline_pIdentPlain
public import Lanius.Mini.Frontend.P.Inline_pImplMethodsSome
public import Lanius.Mini.Frontend.P.Inline_pLeTail
public import Lanius.Mini.Frontend.P.Inline_pModTail
public import Lanius.Mini.Frontend.P.Inline_pPathMore
public import Lanius.Mini.Frontend.P.Inline_pRetVoid
public import Lanius.Mini.Frontend.P.Inline_pSelfParamPlain
public import Lanius.Mini.Frontend.P.Inline_pSelfParamTyped
public import Lanius.Mini.Frontend.P.Inline_pSelfValue
public import Lanius.Mini.Frontend.P.Inline_pStmtsMore
public import Lanius.Mini.Frontend.P.Inline_pStructFieldsAfterCommaMore
public import Lanius.Mini.Frontend.P.Inline_pStructFieldsMore
public import Lanius.Mini.Frontend.P.Inline_pTypeArgsNone
public import Lanius.Mini.Frontend.P.Inline_pTypePathIdent
public import Lanius.Mini.Frontend.P.Inline_pTypeSliceTail
public import Lanius.Mini.Frontend.P.Inline_pWhileStmt
public import Lanius.Mini.Frontend.P.Inline_tLparen
public import Lanius.Mini.Frontend.P.Inline_tRparen

/-! Generated by formal/tools/extract.py from formal/lani/mini/frontend.lani. Do not edit.

Shallow extraction: each Lanius function is the Lean definition of the same
name (snake_case becomes camelCase, methods become `Type.method`, list
operations become `Lists.name` with a spec theorem). `usize` is `Nat`, `i32` is
`BitVec 32`, `u8` is `UInt8`, `List<T>` is `List T`, `Box<T>` is `T`. The
prelude's `plus`/`minus`/`times` panic instead of wrapping, so they are
`+`/`-`/`*` on `Nat` for every run that returns.

The definitions are in 127 parts, `.P0` on, in source order, whose bodies
are hidden from other modules: a proof that unfolds one imports its part with
`import all`, so that it is rebuilt only when that part changes. -/
