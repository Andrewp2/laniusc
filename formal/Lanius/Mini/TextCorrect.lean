module

public import Lanius.Mini.ParseUnique
public import Lanius.Mini.Reading.Det.Program
public import Lanius.Mini.SourceStops
public import Lanius.Mini.Compiler.P.SrcExpr_guard
public import Lanius.Mini.Compiler.P.boundsGuard
public import Lanius.Mini.Compiler.P.checkThen
public import Lanius.Mini.Compiler.P.expectType
public import Lanius.Mini.Compiler.P.guardAll
public import Lanius.Mini.Compiler.P.guarded
public import Lanius.Mini.Compiler.P.lowerAppend
public import Lanius.Mini.Compiler.P.lowerAs
public import Lanius.Mini.Compiler.P.slotVars
public import Lanius.Mini.Compiler.P.thenCheck
public import Lanius.Mini.Compiler.P.trap
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.FOp_size
import all Lanius.Mini.Compiler.P.FloatTy_mask
import all Lanius.Mini.Compiler.P.FloatTy_number
import all Lanius.Mini.Compiler.P.FloatTy_rexSize
import all Lanius.Mini.Compiler.P.FloatTy_signBit
import all Lanius.Mini.Compiler.P.FloatTy_signWord
import all Lanius.Mini.Compiler.P.Instr_size
import all Lanius.Mini.Compiler.P.FArith_opcode
import all Lanius.Mini.Compiler.P.FCmp_predicate
import all Lanius.Mini.Compiler.P.FOp_bytes
import all Lanius.Mini.Compiler.P.FOp_opcodeBytes
import all Lanius.Mini.Compiler.P.bumpBytes
import all Lanius.Mini.Compiler.P.floatOperands
import all Lanius.Mini.Compiler.P.floatResult
import all Lanius.Mini.Compiler.P.frameMemoryBytes
import all Lanius.Mini.Compiler.P.pow2
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
import all Lanius.Mini.Compiler.P.SrcExpr_guard
import all Lanius.Mini.Compiler.P.boundsGuard
import all Lanius.Mini.Compiler.P.checkThen
import all Lanius.Mini.Compiler.P.expectType
import all Lanius.Mini.Compiler.P.guardAll
import all Lanius.Mini.Compiler.P.guarded
import all Lanius.Mini.Compiler.P.lowerAppend
import all Lanius.Mini.Compiler.P.lowerAs
import all Lanius.Mini.Compiler.P.slotVars
import all Lanius.Mini.Compiler.P.thenCheck
import all Lanius.Mini.Compiler.P.trap
import all Lanius.Mini.Compiler.P.SrcType_same
import all Lanius.Mini.Compiler.P.SrcType_size
import all Lanius.Mini.Compiler.P.fieldOffset
import all Lanius.Mini.Compiler.P.norm
import all Lanius.Mini.Compiler.P.wrap
import all Lanius.Mini.Compiler.P.BinOp_bytes
import all Lanius.Mini.Compiler.P.BinOp_opcode
import all Lanius.Mini.Compiler.P.CmpOp_setcc
import all Lanius.Mini.Compiler.P.CmpOp_setccSigned
import all Lanius.Mini.Compiler.P.CmpOp_setccUnsigned
import all Lanius.Mini.Compiler.P.DivOp_bytes
import all Lanius.Mini.Compiler.P.DivOp_extend
import all Lanius.Mini.Compiler.P.DivOp_opcode
import all Lanius.Mini.Compiler.P.DivOp_result
import all Lanius.Mini.Compiler.P.Word_rex
import all Lanius.Mini.Compiler.P.arities
import all Lanius.Mini.Compiler.P.compileFuncs
import all Lanius.Mini.Compiler.P.fspLoad
import all Lanius.Mini.Compiler.P.fspSave
import all Lanius.Mini.Compiler.P.le32
import all Lanius.Mini.Compiler.P.le64
import all Lanius.Mini.Compiler.P.slotCompare
import all Lanius.Mini.Compiler.P.slotLoad
import all Lanius.Mini.Compiler.P.slotOffset
import all Lanius.Mini.Compiler.P.slotOperands
import all Lanius.Mini.Compiler.P.slotStore
import all Lanius.Mini.Compiler.P.Piece_render
import all Lanius.Mini.Compiler.P.Piece_size
import all Lanius.Mini.Compiler.P.compileModules
import all Lanius.Mini.Compiler.P.piecesSize
import all Lanius.Mini.Compiler.P.compileSource
import all Lanius.Mini.Compiler.P.packWord
import all Lanius.Mini.Compiler.P.roundCons
import all Lanius.Mini.Compiler.P.roundEnd
import all Lanius.Mini.Compiler.P.usizeWords
import all Lanius.Mini.Compiler.P.Code_image
import all Lanius.Mini.Compiler.P.Code_size
import all Lanius.Mini.Compiler.P.Instr_encode
import all Lanius.Mini.Compiler.P.argBase
import all Lanius.Mini.Compiler.P.copyBytes
import all Lanius.Mini.Compiler.P.encodeFrom
import all Lanius.Mini.Compiler.P.encodeOnto
import all Lanius.Mini.Compiler.P.epilogue
import all Lanius.Mini.Compiler.P.frameSize
import all Lanius.Mini.Compiler.P.layout
import all Lanius.Mini.Compiler.P.linkFrom
import all Lanius.Mini.Compiler.P.linkOnto
import all Lanius.Mini.Compiler.P.loadAtBytes
import all Lanius.Mini.Compiler.P.loadWordBytes
import all Lanius.Mini.Compiler.P.prologue
import all Lanius.Mini.Compiler.P.relative
import all Lanius.Mini.Compiler.P.slotRange
import all Lanius.Mini.Compiler.P.stackCheck
import all Lanius.Mini.Compiler.P.storeAtBytes
import all Lanius.Mini.Compiler.P.storeWordBytes
import all Lanius.Mini.Compiler.P.sysBytes
import all Lanius.Mini.Compiler.P.syscallLinuxByte
import all Lanius.Mini.Compiler.P.syscallLinuxHigh
import all Lanius.Mini.Compiler.P.syscallRsiBytes
import all Lanius.Mini.Compiler.P.SrcEff_isSlice
import all Lanius.Mini.Compiler.P.SrcEff_passesSlices
import all Lanius.Mini.Compiler.P.SrcEff_sliceCall
import all Lanius.Mini.Compiler.P.SrcStmt_breaksOut
import all Lanius.Mini.Compiler.P.SrcStmt_depth
import all Lanius.Mini.Compiler.P.SrcStmt_lower
import all Lanius.Mini.Compiler.P.arrayCall
import all Lanius.Mini.Compiler.P.arrayCallSig
import all Lanius.Mini.Compiler.P.effsSlice
import all Lanius.Mini.Compiler.P.paramScope
import all Lanius.Mini.Compiler.P.paramTypes
import all Lanius.Mini.Compiler.P.paramsSize
import all Lanius.Mini.Compiler.P.paramsValid
import all Lanius.Mini.Compiler.P.stmtEval
import all Lanius.Mini.Compiler.P.needCapped
import all Lanius.Mini.Compiler.P.needRound
import all Lanius.Mini.Compiler.P.needRoundAt
import all Lanius.Mini.Compiler.P.restNeeds
import all Lanius.Mini.Compiler.P.sameNeeds
import all Lanius.Mini.Compiler.P.needsAfter
import all Lanius.Mini.Compiler.P.putElement
import all Lanius.Mini.Compiler.P.storeArrayElement
import all Lanius.Mini.Compiler.P.storeEval
import all Lanius.Mini.Compiler.P.storeEvalByte
import all Lanius.Mini.Compiler.P.storeEvalElement
import all Lanius.Mini.Compiler.P.storeEvalWord
import all Lanius.Mini.Compiler.P.storePick
import all Lanius.Mini.Compiler.P.storeType
import all Lanius.Mini.Compiler.P.withinLayout
import all Lanius.Mini.Compiler.P.lowerSetIndexOf
import all Lanius.Mini.Compiler.P.storeAny
import all Lanius.Mini.Compiler.P.storeWordElement
import all Lanius.Mini.Compiler.P.structFields
import all Lanius.Mini.Compiler.P.factDies
import all Lanius.Mini.Compiler.P.kill
import all Lanius.Mini.Compiler.P.killTail
import all Lanius.Mini.Compiler.P.mentionsAny
import all Lanius.Mini.Compiler.P.noneDies
import all Lanius.Mini.Compiler.P.substAll
import all Lanius.Mini.Compiler.P.usizeWidth
import all Lanius.Mini.Compiler.P.widthOf
import all Lanius.Mini.Compiler.P.wordElement
import all Lanius.Mini.Compiler.P.SrcEff_eval
import all Lanius.Mini.Compiler.P.evalLen
import all Lanius.Mini.Compiler.P.evalLenOf
import all Lanius.Mini.Compiler.P.evalStr
import all Lanius.Mini.Compiler.P.evalStride
import all Lanius.Mini.Compiler.P.evalStrideOf
import all Lanius.Mini.Compiler.P.evalWordStride
import all Lanius.Mini.Compiler.P.staticByteIs
import all Lanius.Mini.Compiler.P.storeEvalThen
import all Lanius.Mini.Compiler.P.strPlaced
import all Lanius.Mini.Compiler.P.wordStride
import all Lanius.Mini.Compiler.P.declaredSame
import all Lanius.Mini.Compiler.P.declaredVariants
import all Lanius.Mini.Compiler.P.wordType
import all Lanius.Mini.Compiler.P.wordWidth
import all Lanius.Mini.Compiler.Types
import all Lanius.Mini.Frontend.P.allocClosed
import all Lanius.Mini.Frontend.P.eApplyClosed
import all Lanius.Mini.Frontend.P.eCallClosed
import all Lanius.Mini.Frontend.P.letIndexClosed
import all Lanius.Mini.Frontend.P.letSliceClosed
import all Lanius.Mini.Frontend.P.letStrClosed
import all Lanius.Mini.Frontend.P.letViewClosed
import all Lanius.Mini.Frontend.P.anyNested
import all Lanius.Mini.Frontend.P.armNaming
import all Lanius.Mini.Frontend.P.colFits
import all Lanius.Mini.Frontend.P.columnArm
import all Lanius.Mini.Frontend.P.columnArms
import all Lanius.Mini.Frontend.P.columnFit
import all Lanius.Mini.Frontend.P.columnSub
import all Lanius.Mini.Frontend.P.endsWild
import all Lanius.Mini.Frontend.P.firstAt
import all Lanius.Mini.Frontend.P.firstNested
import all Lanius.Mini.Frontend.P.isLast
import all Lanius.Mini.Frontend.P.mentions
import all Lanius.Mini.Frontend.P.namedKnown
import all Lanius.Mini.Frontend.P.namedPath
import all Lanius.Mini.Frontend.P.quietArm
import all Lanius.Mini.Frontend.P.quietIn
import all Lanius.Mini.Frontend.P.quietSub
import all Lanius.Mini.Frontend.P.rowCons
import all Lanius.Mini.Frontend.P.rowFits
import all Lanius.Mini.Frontend.P.rowPats
import all Lanius.Mini.Frontend.P.rowsNaming
import all Lanius.Mini.Frontend.P.sameOptName
import all Lanius.Mini.Frontend.P.subArm
import all Lanius.Mini.Frontend.P.wildPat
import all Lanius.Mini.Frontend.P.armsByVariant
import all Lanius.Mini.Frontend.P.armsNaming
import all Lanius.Mini.Frontend.P.textUnderscore
import all Lanius.Mini.Frontend.P.allBinders
import all Lanius.Mini.Frontend.P.andKnown
import all Lanius.Mini.Frontend.P.armNested
import all Lanius.Mini.Frontend.P.armsOf
import all Lanius.Mini.Frontend.P.binderNameOk
import all Lanius.Mini.Frontend.P.isBinderPat
import all Lanius.Mini.Frontend.P.isWildPat
import all Lanius.Mini.Frontend.P.notKnown
import all Lanius.Mini.Frontend.P.orKnown
import all Lanius.Mini.Frontend.P.patsNested
import all Lanius.Mini.Frontend.P.assertClosed
import all Lanius.Mini.Frontend.P.closeParams
import all Lanius.Mini.Frontend.P.closeRet
import all Lanius.Mini.Frontend.P.closeStmt
import all Lanius.Mini.Frontend.P.consFunc
import all Lanius.Mini.Frontend.P.consFuncTail
import all Lanius.Mini.Frontend.P.consSrcParam
import all Lanius.Mini.Frontend.P.setFieldEvalClosed
import all Lanius.Mini.Frontend.P.srcFunc
import all Lanius.Mini.Frontend.P.anyBlockArm
import all Lanius.Mini.Frontend.P.blockArmsOf
import all Lanius.Mini.Frontend.P.eqLit
import all Lanius.Mini.Frontend.P.isBlockMatch
import all Lanius.Mini.Frontend.P.isLitInit
import all Lanius.Mini.Frontend.P.isLitStmt
import all Lanius.Mini.Frontend.P.litCond
import all Lanius.Mini.Frontend.P.litEnd
import all Lanius.Mini.Frontend.P.litFirst
import all Lanius.Mini.Frontend.P.litHeadIf
import all Lanius.Mini.Frontend.P.litLast
import all Lanius.Mini.Frontend.P.litMatchHead
import all Lanius.Mini.Frontend.P.litMatchParts
import all Lanius.Mini.Frontend.P.litMatchTyped
import all Lanius.Mini.Frontend.P.litPattern
import all Lanius.Mini.Frontend.P.litWanted
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
import all Lanius.Mini.Frontend.P.callParts
import all Lanius.Mini.Frontend.P.effLocal
import all Lanius.Mini.Frontend.P.pureLocal
import all Lanius.Mini.Frontend.P.viewArray
import all Lanius.Mini.Frontend.P.viewLocal
import all Lanius.Mini.Frontend.P.wantElem
import all Lanius.Mini.Frontend.P.effPlace
import all Lanius.Mini.Frontend.P.hasAt
import all Lanius.Mini.Frontend.P.isRefTy
import all Lanius.Mini.Frontend.P.projection
import all Lanius.Mini.Frontend.P.referent
import all Lanius.Mini.Frontend.P.referentOr
import all Lanius.Mini.Frontend.P.xAtOf
import all Lanius.Mini.Frontend.P.closeFuncs
import all Lanius.Mini.Frontend.P.isizeTy
import all Lanius.Mini.Frontend.P.aliasNamesIn
import all Lanius.Mini.Frontend.P.collect
import all Lanius.Mini.Frontend.P.collectFiles
import all Lanius.Mini.Frontend.P.collectedWith
import all Lanius.Mini.Frontend.P.constNamesIn
import all Lanius.Mini.Frontend.P.enumNamedOk
import all Lanius.Mini.Frontend.P.enumsNamedOk
import all Lanius.Mini.Frontend.P.fileCollected
import all Lanius.Mini.Frontend.P.fileDecls
import all Lanius.Mini.Frontend.P.fileItems
import all Lanius.Mini.Frontend.P.fnNamesIn
import all Lanius.Mini.Frontend.P.isNoneType
import all Lanius.Mini.Frontend.P.moduleGlobals
import all Lanius.Mini.Frontend.P.moduleNamesOk
import all Lanius.Mini.Frontend.P.modulesDistinctNames
import all Lanius.Mini.Frontend.P.noNames
import all Lanius.Mini.Frontend.P.noPrimitive
import all Lanius.Mini.Frontend.P.noPrimitiveAlias
import all Lanius.Mini.Frontend.P.noneMember
import all Lanius.Mini.Frontend.P.typeNamesIn
import all Lanius.Mini.Frontend.P.typeOnlyNamesIn
import all Lanius.Mini.Frontend.P.wellNamed
import all Lanius.Mini.Frontend.P.compoundEval
import all Lanius.Mini.Frontend.P.assignment
import all Lanius.Mini.Frontend.P.compoundOf
import all Lanius.Mini.Frontend.P.writesLocal
import all Lanius.Mini.Frontend.P.anyVariant
import all Lanius.Mini.Frontend.P.armNamed
import all Lanius.Mini.Frontend.P.armNames
import all Lanius.Mini.Frontend.P.armOf
import all Lanius.Mini.Frontend.P.armPrefix
import all Lanius.Mini.Frontend.P.armsNamingAt
import all Lanius.Mini.Frontend.P.bindersOf
import all Lanius.Mini.Frontend.P.consBinder
import all Lanius.Mini.Frontend.P.zipVariants
import all Lanius.Mini.Frontend.P.consBound
import all Lanius.Mini.Frontend.P.argsOfItems
import all Lanius.Mini.Frontend.P.boundGoals
import all Lanius.Mini.Frontend.P.boundOrNone
import all Lanius.Mini.Frontend.P.boundPathSpellings
import all Lanius.Mini.Frontend.P.calleeEnv
import all Lanius.Mini.Frontend.P.consGoal
import all Lanius.Mini.Frontend.P.consGoalTail
import all Lanius.Mini.Frontend.P.consTree
import all Lanius.Mini.Frontend.P.consTreeTail
import all Lanius.Mini.Frontend.P.goalAt
import all Lanius.Mini.Frontend.P.goalsOf
import all Lanius.Mini.Frontend.P.instFrom
import all Lanius.Mini.Frontend.P.joinGoals
import all Lanius.Mini.Frontend.P.joinGoalsTail
import all Lanius.Mini.Frontend.P.paramPatterns
import all Lanius.Mini.Frontend.P.patternOf
import all Lanius.Mini.Frontend.P.patternsOf
import all Lanius.Mini.Frontend.P.retPattern
import all Lanius.Mini.Frontend.P.traitAt
import all Lanius.Mini.Frontend.P.traitOfBound
import all Lanius.Mini.Frontend.P.traitOfTy
import all Lanius.Mini.Frontend.P.traitSplit
import all Lanius.Mini.Frontend.P.consTys
import all Lanius.Mini.Frontend.P.fieldTys
import all Lanius.Mini.Frontend.P.payloadList
import all Lanius.Mini.Frontend.P.payloadTys
import all Lanius.Mini.Frontend.P.consName
import all Lanius.Mini.Frontend.P.consNameTail
import all Lanius.Mini.Frontend.P.distinct
import all Lanius.Mini.Frontend.P.distinctModules
import all Lanius.Mini.Frontend.P.moduleMember
import all Lanius.Mini.Frontend.P.position
import all Lanius.Mini.Frontend.P.sameSpellings
import all Lanius.Mini.Frontend.P.singleName
import all Lanius.Mini.Frontend.P.bindsZip
import all Lanius.Mini.Frontend.P.divergeArm
import all Lanius.Mini.Frontend.P.armValueTrees
import all Lanius.Mini.Frontend.P.bindsOfTys
import all Lanius.Mini.Frontend.P.isFalseArm
import all Lanius.Mini.Frontend.P.isTrueArm
import all Lanius.Mini.Frontend.P.litTy
import all Lanius.Mini.Frontend.P.methodBinds
import all Lanius.Mini.Frontend.P.tyPerArm
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
import all Lanius.Mini.Frontend.P.eCastClosed
import all Lanius.Mini.Frontend.P.eDivideClosed
import all Lanius.Mini.Frontend.P.eNegClosed
import all Lanius.Mini.Frontend.P.eNotClosed
import all Lanius.Mini.Frontend.P.eArraySliceClosed
import all Lanius.Mini.Frontend.P.eDerefClosed
import all Lanius.Mini.Frontend.P.eIndexClosed
import all Lanius.Mini.Frontend.P.ePlaceAtClosed
import all Lanius.Mini.Frontend.P.ePlaceFieldClosed
import all Lanius.Mini.Frontend.P.setPlaceClosed
import all Lanius.Mini.Frontend.P.setPlaceOpClosed
import all Lanius.Mini.Frontend.P.closeEff
import all Lanius.Mini.Frontend.P.consSrcEff
import all Lanius.Mini.Frontend.P.eIfClosed
import all Lanius.Mini.Frontend.P.eLetClosed
import all Lanius.Mini.Frontend.P.eMatchClosed
import all Lanius.Mini.Frontend.P.eStructClosed
import all Lanius.Mini.Frontend.P.eVariantClosed
import all Lanius.Mini.Frontend.P.letEvalClosed
import all Lanius.Mini.Frontend.P.effNamedTys
import all Lanius.Mini.Frontend.P.stmtCalls
import all Lanius.Mini.Frontend.P.externBody
import all Lanius.Mini.Frontend.P.externFunc
import all Lanius.Mini.Frontend.P.argsOf
import all Lanius.Mini.Frontend.P.armBinders
import all Lanius.Mini.Frontend.P.armValues
import all Lanius.Mini.Frontend.P.bareEff
import all Lanius.Mini.Frontend.P.consEffArm
import all Lanius.Mini.Frontend.P.consExpr
import all Lanius.Mini.Frontend.P.consExprTail
import all Lanius.Mini.Frontend.P.effTy
import all Lanius.Mini.Frontend.P.effsTys
import all Lanius.Mini.Frontend.P.elemTyOf
import all Lanius.Mini.Frontend.P.exprsOf
import all Lanius.Mini.Frontend.P.fieldTyAt
import all Lanius.Mini.Frontend.P.fieldTyOf
import all Lanius.Mini.Frontend.P.fnInstRet
import all Lanius.Mini.Frontend.P.headTy
import all Lanius.Mini.Frontend.P.indexTy
import all Lanius.Mini.Frontend.P.instRet
import all Lanius.Mini.Frontend.P.isOwnerAt
import all Lanius.Mini.Frontend.P.isScalarOwner
import all Lanius.Mini.Frontend.P.isSomeIndex
import all Lanius.Mini.Frontend.P.isTypeOwner
import all Lanius.Mini.Frontend.P.resultTy
import all Lanius.Mini.Frontend.P.tailTys
import all Lanius.Mini.Frontend.P.xMatchOf
import all Lanius.Mini.Frontend.P.addInst
import all Lanius.Mini.Frontend.P.addInsts
import all Lanius.Mini.Frontend.P.declEnv
import all Lanius.Mini.Frontend.P.findAlias
import all Lanius.Mini.Frontend.P.findConst
import all Lanius.Mini.Frontend.P.findVariant
import all Lanius.Mini.Frontend.P.floatCode
import all Lanius.Mini.Frontend.P.ifItem
import all Lanius.Mini.Frontend.P.instIndex
import all Lanius.Mini.Frontend.P.instMember
import all Lanius.Mini.Frontend.P.isModule
import all Lanius.Mini.Frontend.P.sameFloat
import all Lanius.Mini.Frontend.P.sameInst
import all Lanius.Mini.Frontend.P.sameTy
import all Lanius.Mini.Frontend.P.uintCode
import all Lanius.Mini.Frontend.P.variantsNamed
import all Lanius.Mini.Frontend.P.amountWant
import all Lanius.Mini.Frontend.P.boundTys
import all Lanius.Mini.Frontend.P.eitherTy
import all Lanius.Mini.Frontend.P.firstIds
import all Lanius.Mini.Frontend.P.firstSrc
import all Lanius.Mini.Frontend.P.knownApply
import all Lanius.Mini.Frontend.P.knownCast
import all Lanius.Mini.Frontend.P.operandWant
import all Lanius.Mini.Frontend.P.restIds
import all Lanius.Mini.Frontend.P.restPayloads
import all Lanius.Mini.Frontend.P.restSrc
import all Lanius.Mini.Frontend.P.wideAt
import all Lanius.Mini.Frontend.P.wideIsizeAt
import all Lanius.Mini.Frontend.P.wideSintAt
import all Lanius.Mini.Frontend.P.wideUintAt
import all Lanius.Mini.Frontend.P.flDecimal
import all Lanius.Mini.Frontend.P.flDigit
import all Lanius.Mini.Frontend.P.flExpDigits
import all Lanius.Mini.Frontend.P.flFinish
import all Lanius.Mini.Frontend.P.flPush
import all Lanius.Mini.Frontend.P.flExpFirst
import all Lanius.Mini.Frontend.P.flExpPart
import all Lanius.Mini.Frontend.P.flExpSign
import all Lanius.Mini.Frontend.P.flFracPart
import all Lanius.Mini.Frontend.P.flIntPart
import all Lanius.Mini.Frontend.P.floatLiteral
import all Lanius.Mini.Frontend.P.floatMarker
import all Lanius.Mini.Frontend.P.floatPick
import all Lanius.Mini.Frontend.P.floatPickOf
import all Lanius.Mini.Frontend.P.floatWant
import all Lanius.Mini.Frontend.P.flDivStep
import all Lanius.Mini.Frontend.P.flDivmod
import all Lanius.Mini.Frontend.P.flLog2Or0
import all Lanius.Mini.Frontend.P.flOdd
import all Lanius.Mini.Frontend.P.flSat
import all Lanius.Mini.Frontend.P.flBit
import all Lanius.Mini.Frontend.P.flLog2
import all Lanius.Mini.Frontend.P.flLog2Up
import all Lanius.Mini.Frontend.P.flLowBit
import all Lanius.Mini.Frontend.P.flNatHalf
import all Lanius.Mini.Frontend.P.flNatOdd
import all Lanius.Mini.Frontend.P.flOfNat
import all Lanius.Mini.Frontend.P.flPow2
import all Lanius.Mini.Frontend.P.flToNat
import all Lanius.Mini.Frontend.P.flDecimalAt
import all Lanius.Mini.Frontend.P.flRatioOk
import all Lanius.Mini.Frontend.P.flRound
import all Lanius.Mini.Frontend.P.flRoundUp
import all Lanius.Mini.Frontend.P.consType
import all Lanius.Mini.Frontend.P.consTypeTail
import all Lanius.Mini.Frontend.P.consTypes
import all Lanius.Mini.Frontend.P.consTypesTail
import all Lanius.Mini.Frontend.P.flatPayloads
import all Lanius.Mini.Frontend.P.flattenTys
import all Lanius.Mini.Frontend.P.refType
import all Lanius.Mini.Frontend.P.sliceType
import all Lanius.Mini.Frontend.P.weightAddTo
import all Lanius.Mini.Frontend.P.weightLimit
import all Lanius.Mini.Frontend.P.weightSum
import all Lanius.Mini.Frontend.P.arrayType
import all Lanius.Mini.Frontend.P.enumSrc
import all Lanius.Mini.Frontend.P.srcWeight
import all Lanius.Mini.Frontend.P.structSrc
import all Lanius.Mini.Frontend.P.weighed
import all Lanius.Mini.Frontend.P.weightAdd
import all Lanius.Mini.Frontend.P.weightArray
import all Lanius.Mini.Frontend.P.weightTimes
import all Lanius.Mini.Frontend.P.findLocal
import all Lanius.Mini.Frontend.P.findLocalId
import all Lanius.Mini.Frontend.P.floatTyped
import all Lanius.Mini.Frontend.P.localOf
import all Lanius.Mini.Frontend.P.negateSome
import all Lanius.Mini.Frontend.P.negatedFloat
import all Lanius.Mini.Frontend.P.arrayLocal
import all Lanius.Mini.Frontend.P.arrayLocalOf
import all Lanius.Mini.Frontend.P.forArray
import all Lanius.Mini.Frontend.P.forRange
import all Lanius.Mini.Frontend.P.forSlice
import all Lanius.Mini.Frontend.P.matchOfPostfix
import all Lanius.Mini.Frontend.P.matchPrimary
import all Lanius.Mini.Frontend.P.fieldExpr
import all Lanius.Mini.Frontend.P.fieldIn
import all Lanius.Mini.Frontend.P.fieldIndex
import all Lanius.Mini.Frontend.P.freshId
import all Lanius.Mini.Frontend.P.localExpr
import all Lanius.Mini.Frontend.P.memberOf
import all Lanius.Mini.Frontend.P.frontEndWords
import all Lanius.Mini.Frontend.P.grammarPart0
import all Lanius.Mini.Frontend.P.grammarPart1
import all Lanius.Mini.Frontend.P.grammarPart2
import all Lanius.Mini.Frontend.P.grammarPart3
import all Lanius.Mini.Frontend.P.grammarPart4
import all Lanius.Mini.Frontend.P.grammarPart5
import all Lanius.Mini.Frontend.P.grammarPart6
import all Lanius.Mini.Frontend.P.grammarPart7
import all Lanius.Mini.Frontend.P.declWeight
import all Lanius.Mini.Frontend.P.fieldsWeight
import all Lanius.Mini.Frontend.P.funcsOnto
import all Lanius.Mini.Frontend.P.funcsTys
import all Lanius.Mini.Frontend.P.instWeight
import all Lanius.Mini.Frontend.P.isNoneWeight
import all Lanius.Mini.Frontend.P.loweredAll
import all Lanius.Mini.Frontend.P.monoLoop
import all Lanius.Mini.Frontend.P.namedWeight
import all Lanius.Mini.Frontend.P.paramTys
import all Lanius.Mini.Frontend.P.payloadsWeight
import all Lanius.Mini.Frontend.P.retTys
import all Lanius.Mini.Frontend.P.seedTys
import all Lanius.Mini.Frontend.P.stmtTys
import all Lanius.Mini.Frontend.P.tyKnown
import all Lanius.Mini.Frontend.P.tyWeight
import all Lanius.Mini.Frontend.P.typeTable
import all Lanius.Mini.Frontend.P.typeTableMore
import all Lanius.Mini.Frontend.P.tysWeight
import all Lanius.Mini.Frontend.P.unweighed
import all Lanius.Mini.Frontend.P.weighAgain
import all Lanius.Mini.Frontend.P.weighRound
import all Lanius.Mini.Frontend.P.weighRounds
import all Lanius.Mini.Frontend.P.weighedMore
import all Lanius.Mini.Frontend.P.allWeighed
import all Lanius.Mini.Frontend.P.closeNamed
import all Lanius.Mini.Frontend.P.closeTy
import all Lanius.Mini.Frontend.P.srcEnumId
import all Lanius.Mini.Frontend.P.tableWeighed
import all Lanius.Mini.Frontend.P.typesWeighed
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
import all Lanius.Mini.Frontend.P.armEff
import all Lanius.Mini.Frontend.P.declInst
import all Lanius.Mini.Frontend.P.effBinary
import all Lanius.Mini.Frontend.P.effCalled
import all Lanius.Mini.Frontend.P.effCasts
import all Lanius.Mini.Frontend.P.fieldExpects
import all Lanius.Mini.Frontend.P.hasConst
import all Lanius.Mini.Frontend.P.inferArgs
import all Lanius.Mini.Frontend.P.inferEff
import all Lanius.Mini.Frontend.P.knownArgs
import all Lanius.Mini.Frontend.P.namedInferred
import all Lanius.Mini.Frontend.P.paramExpects
import all Lanius.Mini.Frontend.P.pureList
import all Lanius.Mini.Frontend.P.skipExpects
import all Lanius.Mini.Frontend.P.variantExpects
import all Lanius.Mini.Frontend.P.xStructOf
import all Lanius.Mini.Frontend.P.xVariantOf
import all Lanius.Mini.Frontend.P.hasKids
import all Lanius.Mini.Frontend.P.isLink
import all Lanius.Mini.Frontend.P.joinItems
import all Lanius.Mini.Frontend.P.joinSecond
import all Lanius.Mini.Frontend.P.kidToken
import all Lanius.Mini.Frontend.P.leafToken
import all Lanius.Mini.Frontend.P.listItems
import all Lanius.Mini.Frontend.P.sameText
import all Lanius.Mini.Frontend.P.spelled
import all Lanius.Mini.Frontend.P.ifEff
import all Lanius.Mini.Frontend.P.setEff
import all Lanius.Mini.Frontend.P.setFieldEff
import all Lanius.Mini.Frontend.P.setIndexEff
import all Lanius.Mini.Frontend.P.setIndexPure
import all Lanius.Mini.Frontend.P.whileEff
import all Lanius.Mini.Frontend.P.ifNotWrites
import all Lanius.Mini.Frontend.P.knownTrue
import all Lanius.Mini.Frontend.P.refChecked
import all Lanius.Mini.Frontend.P.selfRefId
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
import all Lanius.Mini.Frontend.P.isMatchStmt
import all Lanius.Mini.Frontend.P.isPathCall
import all Lanius.Mini.Frontend.P.isTryCall
import all Lanius.Mini.Frontend.P.isTryLocal
import all Lanius.Mini.Frontend.P.isTryMethod
import all Lanius.Mini.Frontend.P.textCore
import all Lanius.Mini.Frontend.P.textErr
import all Lanius.Mini.Frontend.P.textI32ArrayDataPtr
import all Lanius.Mini.Frontend.P.textMem
import all Lanius.Mini.Frontend.P.textNone
import all Lanius.Mini.Frontend.P.textOk
import all Lanius.Mini.Frontend.P.textOption
import all Lanius.Mini.Frontend.P.textOptionTy
import all Lanius.Mini.Frontend.P.textResult
import all Lanius.Mini.Frontend.P.textResultTy
import all Lanius.Mini.Frontend.P.textSome
import all Lanius.Mini.Frontend.P.allocHead
import all Lanius.Mini.Frontend.P.allocShifted
import all Lanius.Mini.Frontend.P.castShift
import all Lanius.Mini.Frontend.P.isTryEnum
import all Lanius.Mini.Frontend.P.isUsize
import all Lanius.Mini.Frontend.P.literalShift
import all Lanius.Mini.Frontend.P.shiftOf
import all Lanius.Mini.Frontend.P.shiftOfU64
import all Lanius.Mini.Frontend.P.consWild
import all Lanius.Mini.Frontend.P.isUnderscore
import all Lanius.Mini.Frontend.P.isWildArm
import all Lanius.Mini.Frontend.P.wildAlone
import all Lanius.Mini.Frontend.P.wildArmFor
import all Lanius.Mini.Frontend.P.wildBinder
import all Lanius.Mini.Frontend.P.wildBinders
import all Lanius.Mini.Frontend.P.wildSplit
import all Lanius.Mini.Frontend.P.wildTail
import all Lanius.Mini.Frontend.P.bareVariant
import all Lanius.Mini.Frontend.P.importedVariants
import all Lanius.Mini.Frontend.P.itemImport
import all Lanius.Mini.Frontend.P.itemOf
import all Lanius.Mini.Frontend.P.onlyVariant
import all Lanius.Mini.Frontend.P.pathModule
import all Lanius.Mini.Frontend.P.consInst
import all Lanius.Mini.Frontend.P.isLevel
import all Lanius.Mini.Frontend.P.joinInsts
import all Lanius.Mini.Frontend.P.negated
import all Lanius.Mini.Frontend.P.notted
import all Lanius.Mini.Frontend.P.tailOp
import all Lanius.Mini.Frontend.P.tyInsts
import all Lanius.Mini.Frontend.P.wideDecimal
import all Lanius.Mini.Frontend.P.letClosed
import all Lanius.Mini.Frontend.P.armTyClosed
import all Lanius.Mini.Frontend.P.ifClosed
import all Lanius.Mini.Frontend.P.letCallClosed
import all Lanius.Mini.Frontend.P.letEnumClosed
import all Lanius.Mini.Frontend.P.letMatchClosed
import all Lanius.Mini.Frontend.P.letStructClosed
import all Lanius.Mini.Frontend.P.matchArmClosed
import all Lanius.Mini.Frontend.P.setCallClosed
import all Lanius.Mini.Frontend.P.thenClosed
import all Lanius.Mini.Frontend.P.unreachableClosed
import all Lanius.Mini.Frontend.P.whileClosed
import all Lanius.Mini.Frontend.P.lowerTy
import all Lanius.Mini.Frontend.P.callLetHead
import all Lanius.Mini.Frontend.P.evalHead
import all Lanius.Mini.Frontend.P.evalLetHead
import all Lanius.Mini.Frontend.P.ifSameTys
import all Lanius.Mini.Frontend.P.indexLetHead
import all Lanius.Mini.Frontend.P.matchLetHead
import all Lanius.Mini.Frontend.P.singleTy
import all Lanius.Mini.Frontend.P.armBinder
import all Lanius.Mini.Frontend.P.armBinding
import all Lanius.Mini.Frontend.P.armBlockList
import all Lanius.Mini.Frontend.P.armBlockOf
import all Lanius.Mini.Frontend.P.armStmt
import all Lanius.Mini.Frontend.P.boundScope
import all Lanius.Mini.Frontend.P.ifOne
import all Lanius.Mini.Frontend.P.isBlockArm
import all Lanius.Mini.Frontend.P.localIdOf
import all Lanius.Mini.Frontend.P.localTyOf
import all Lanius.Mini.Frontend.P.matchInit
import all Lanius.Mini.Frontend.P.matchStmtEnum
import all Lanius.Mini.Frontend.P.matchStmtHead
import all Lanius.Mini.Frontend.P.matchStmtIf
import all Lanius.Mini.Frontend.P.matchStmtOn
import all Lanius.Mini.Frontend.P.matchStmtParts
import all Lanius.Mini.Frontend.P.matchStmtValue
import all Lanius.Mini.Frontend.P.someBlockArm
import all Lanius.Mini.Frontend.P.stmtArms
import all Lanius.Mini.Frontend.P.valueArms
import all Lanius.Mini.Frontend.P.arrayOf
import all Lanius.Mini.Frontend.P.arrayRepeatOf
import all Lanius.Mini.Frontend.P.divergeCall
import all Lanius.Mini.Frontend.P.divergeChecked
import all Lanius.Mini.Frontend.P.divergeEff
import all Lanius.Mini.Frontend.P.effInferred
import all Lanius.Mini.Frontend.P.instBound
import all Lanius.Mini.Frontend.P.matchTysOrNone
import all Lanius.Mini.Frontend.P.aliasDecls
import all Lanius.Mini.Frontend.P.collectFront
import all Lanius.Mini.Frontend.P.externTree
import all Lanius.Mini.Frontend.P.fnsDecls
import all Lanius.Mini.Frontend.P.hostExtern
import all Lanius.Mini.Frontend.P.hostId
import all Lanius.Mini.Frontend.P.implMethods
import all Lanius.Mini.Frontend.P.itemDecls
import all Lanius.Mini.Frontend.P.methodDecl
import all Lanius.Mini.Frontend.P.methodsOf
import all Lanius.Mini.Frontend.P.textFillSecureBytes
import all Lanius.Mini.Frontend.P.textLaniusStd
import all Lanius.Mini.Frontend.P.textMonotonicRead
import all Lanius.Mini.Frontend.P.textReadStdin
import all Lanius.Mini.Frontend.P.textSleepMsI32
import all Lanius.Mini.Frontend.P.textSystemRead
import all Lanius.Mini.Frontend.P.textWriteByte
import all Lanius.Mini.Frontend.P.textWriteNewline
import all Lanius.Mini.Frontend.P.textWriteStderr
import all Lanius.Mini.Frontend.P.textWriteStdout
import all Lanius.Mini.Frontend.P.textWriteText
import all Lanius.Mini.Frontend.P.typeDecls
import all Lanius.Mini.Frontend.P.withImpl
import all Lanius.Mini.Frontend.P.withImplDecl
import all Lanius.Mini.Frontend.P.consField
import all Lanius.Mini.Frontend.P.consFnDecl
import all Lanius.Mini.Frontend.P.consVariant
import all Lanius.Mini.Frontend.P.consVariantTail
import all Lanius.Mini.Frontend.P.enumDeclOf
import all Lanius.Mini.Frontend.P.fieldsOf
import all Lanius.Mini.Frontend.P.fnDeclOf
import all Lanius.Mini.Frontend.P.freeParams
import all Lanius.Mini.Frontend.P.ifUnbounded
import all Lanius.Mini.Frontend.P.importDecls
import all Lanius.Mini.Frontend.P.itemBody
import all Lanius.Mini.Frontend.P.joinDecls
import all Lanius.Mini.Frontend.P.moduleDecls
import all Lanius.Mini.Frontend.P.moduleOr
import all Lanius.Mini.Frontend.P.modulePath
import all Lanius.Mini.Frontend.P.noDecls
import all Lanius.Mini.Frontend.P.paramSpellings
import all Lanius.Mini.Frontend.P.structDeclFields
import all Lanius.Mini.Frontend.P.structDeclOf
import all Lanius.Mini.Frontend.P.typeDecl
import all Lanius.Mini.Frontend.P.typeParams
import all Lanius.Mini.Frontend.P.unbounded
import all Lanius.Mini.Frontend.P.variantPayload
import all Lanius.Mini.Frontend.P.variantsOf
import all Lanius.Mini.Frontend.P.allNameSome
import all Lanius.Mini.Frontend.P.armsExact
import all Lanius.Mini.Frontend.P.armsInOrder
import all Lanius.Mini.Frontend.P.armsOrWild
import all Lanius.Mini.Frontend.P.namesSome
import all Lanius.Mini.Frontend.P.usesWild
import all Lanius.Mini.Frontend.P.wildOrder
import all Lanius.Mini.Frontend.P.calleeParams
import all Lanius.Mini.Frontend.P.calleeRet
import all Lanius.Mini.Frontend.P.knownEff
import all Lanius.Mini.Frontend.P.knownExpr
import all Lanius.Mini.Frontend.P.leastCast
import all Lanius.Mini.Frontend.P.litEff
import all Lanius.Mini.Frontend.P.litExpr
import all Lanius.Mini.Frontend.P.litExprs
import all Lanius.Mini.Frontend.P.litFuncs
import all Lanius.Mini.Frontend.P.litSrcArms
import all Lanius.Mini.Frontend.P.litStmt
import all Lanius.Mini.Frontend.P.negLeast
import all Lanius.Mini.Frontend.P.negLeastAt
import all Lanius.Mini.Frontend.P.negWideAt
import all Lanius.Mini.Frontend.P.negWideI32
import all Lanius.Mini.Frontend.P.negWideIsize
import all Lanius.Mini.Frontend.P.negWideSint
import all Lanius.Mini.Frontend.P.paramLocals
import all Lanius.Mini.Frontend.P.srcParamTys
import all Lanius.Mini.Frontend.P.wideLeft
import all Lanius.Mini.Frontend.P.wideLeftArms
import all Lanius.Mini.Frontend.P.wideLeftEff
import all Lanius.Mini.Frontend.P.wideLeftExprs
import all Lanius.Mini.Frontend.P.withLocal
import all Lanius.Mini.Frontend.P.blockValue
import all Lanius.Mini.Frontend.P.nestedUsed
import all Lanius.Mini.Frontend.P.nestedWith
import all Lanius.Mini.Frontend.P.checkedBound
import all Lanius.Mini.Frontend.P.checkedEff
import all Lanius.Mini.Frontend.P.checkedEffs
import all Lanius.Mini.Frontend.P.checkedStmt
import all Lanius.Mini.Frontend.P.hasLocal
import all Lanius.Mini.Frontend.P.hasTy
import all Lanius.Mini.Frontend.P.hasTys
import all Lanius.Mini.Frontend.P.letHead
import all Lanius.Mini.Frontend.P.matchOrder
import all Lanius.Mini.Frontend.P.nestedChecked
import all Lanius.Mini.Frontend.P.nestedOrder
import all Lanius.Mini.Frontend.P.noBlock
import all Lanius.Mini.Frontend.P.orderBy
import all Lanius.Mini.Frontend.P.postfixHead
import all Lanius.Mini.Frontend.P.sameDeclArgs
import all Lanius.Mini.Frontend.P.stmtArmOrder
import all Lanius.Mini.Frontend.P.stmtOrderBy
import all Lanius.Mini.Frontend.P.genericTail
import all Lanius.Mini.Frontend.P.kid
import all Lanius.Mini.Frontend.P.kidsOf
import all Lanius.Mini.Frontend.P.noToken
import all Lanius.Mini.Frontend.P.startsWithKind
import all Lanius.Mini.Frontend.P.withKid
import all Lanius.Mini.Frontend.P.argsSegment
import all Lanius.Mini.Frontend.P.consSegment
import all Lanius.Mini.Frontend.P.noTrees
import all Lanius.Mini.Frontend.P.pathName
import all Lanius.Mini.Frontend.P.pathSpellings
import all Lanius.Mini.Frontend.P.nullAt
import all Lanius.Mini.Frontend.P.negSintConst
import all Lanius.Mini.Frontend.P.nullConst
import all Lanius.Mini.Frontend.P.sintConst
import all Lanius.Mini.Frontend.P.sintFits
import all Lanius.Mini.Frontend.P.sintWide
import all Lanius.Mini.Frontend.P.explicitChecked
import all Lanius.Mini.Frontend.P.explicitInst
import all Lanius.Mini.Frontend.P.findMethod
import all Lanius.Mini.Frontend.P.fitIf
import all Lanius.Mini.Frontend.P.fitOf
import all Lanius.Mini.Frontend.P.fitTy
import all Lanius.Mini.Frontend.P.fnBoundsOk
import all Lanius.Mini.Frontend.P.implArgs
import all Lanius.Mini.Frontend.P.implFit
import all Lanius.Mini.Frontend.P.implWhere
import all Lanius.Mini.Frontend.P.inferInst
import all Lanius.Mini.Frontend.P.inferRet
import all Lanius.Mini.Frontend.P.isMisfit
import all Lanius.Mini.Frontend.P.itemGoals
import all Lanius.Mini.Frontend.P.noMethod
import all Lanius.Mini.Frontend.P.paramGoals
import all Lanius.Mini.Frontend.P.paramsGoals
import all Lanius.Mini.Frontend.P.predsGoals
import all Lanius.Mini.Frontend.P.sameTrait
import all Lanius.Mini.Frontend.P.traitHolds
import all Lanius.Mini.Frontend.P.traitIs
import all Lanius.Mini.Frontend.P.tyIs
import all Lanius.Mini.Frontend.P.uniqueFound
import all Lanius.Mini.Frontend.P.whereGoals
import all Lanius.Mini.Frontend.P.pathRef
import all Lanius.Mini.Frontend.P.arrayParts
import all Lanius.Mini.Frontend.P.barePrim
import all Lanius.Mini.Frontend.P.bindTy
import all Lanius.Mini.Frontend.P.expectedArray
import all Lanius.Mini.Frontend.P.exprTy
import all Lanius.Mini.Frontend.P.exprsTys
import all Lanius.Mini.Frontend.P.findBind
import all Lanius.Mini.Frontend.P.indexElem
import all Lanius.Mini.Frontend.P.paramNamed
import all Lanius.Mini.Frontend.P.paramSpelling
import all Lanius.Mini.Frontend.P.pickTy
import all Lanius.Mini.Frontend.P.primIf
import all Lanius.Mini.Frontend.P.repeatTy
import all Lanius.Mini.Frontend.P.sameOrNone
import all Lanius.Mini.Frontend.P.sliceElem
import all Lanius.Mini.Frontend.P.appendedUse
import all Lanius.Mini.Frontend.P.colQuiet
import all Lanius.Mini.Frontend.P.colsQuiet
import all Lanius.Mini.Frontend.P.coveredBy
import all Lanius.Mini.Frontend.P.coveredUse
import all Lanius.Mini.Frontend.P.covers
import all Lanius.Mini.Frontend.P.coversAll
import all Lanius.Mini.Frontend.P.coversDecl
import all Lanius.Mini.Frontend.P.coversEnum
import all Lanius.Mini.Frontend.P.hiddenExpr
import all Lanius.Mini.Frontend.P.hiddenPat
import all Lanius.Mini.Frontend.P.hiddenPath
import all Lanius.Mini.Frontend.P.knownUse
import all Lanius.Mini.Frontend.P.nestArm
import all Lanius.Mini.Frontend.P.nestAt
import all Lanius.Mini.Frontend.P.nestInner
import all Lanius.Mini.Frontend.P.nestPats
import all Lanius.Mini.Frontend.P.nestUse
import all Lanius.Mini.Frontend.P.plainNaming
import all Lanius.Mini.Frontend.P.quietUse
import all Lanius.Mini.Frontend.P.replaceAt
import all Lanius.Mini.Frontend.P.shadowIf
import all Lanius.Mini.Frontend.P.textHidden
import all Lanius.Mini.Frontend.P.wildInner
import all Lanius.Mini.Frontend.P.diverges
import all Lanius.Mini.Frontend.P.initTys
import all Lanius.Mini.Frontend.P.lastTy
import all Lanius.Mini.Frontend.P.neverRet
import all Lanius.Mini.Frontend.P.projectionRet
import all Lanius.Mini.Frontend.P.applyEff
import all Lanius.Mini.Frontend.P.consEff
import all Lanius.Mini.Frontend.P.purePart
import all Lanius.Mini.Frontend.P.xApplyOf
import all Lanius.Mini.Frontend.P.xCallOf
import all Lanius.Mini.Frontend.P.xCastInto
import all Lanius.Mini.Frontend.P.xDivideOf
import all Lanius.Mini.Frontend.P.xIndexOf
import all Lanius.Mini.Frontend.P.xNegOf
import all Lanius.Mini.Frontend.P.xNotOf
import all Lanius.Mini.Frontend.P.readDeclInst
import all Lanius.Mini.Frontend.P.effCalls
import all Lanius.Mini.Frontend.P.readInst
import all Lanius.Mini.Frontend.P.boundArgs
import all Lanius.Mini.Frontend.P.matchTy
import all Lanius.Mini.Frontend.P.namedParts
import all Lanius.Mini.Frontend.P.repeatEff
import all Lanius.Mini.Frontend.P.argExpected
import all Lanius.Mini.Frontend.P.bindArg
import all Lanius.Mini.Frontend.P.retBinds
import all Lanius.Mini.Frontend.P.findFn
import all Lanius.Mini.Frontend.P.findType
import all Lanius.Mini.Frontend.P.rootInsts
import all Lanius.Mini.Frontend.P.seedInsts
import all Lanius.Mini.Frontend.P.applyOf
import all Lanius.Mini.Frontend.P.castInto
import all Lanius.Mini.Frontend.P.castTypeOf
import all Lanius.Mini.Frontend.P.castValue
import all Lanius.Mini.Frontend.P.casts
import all Lanius.Mini.Frontend.P.namedScalar
import all Lanius.Mini.Frontend.P.negatedInt
import all Lanius.Mini.Frontend.P.scalarOf
import all Lanius.Mini.Frontend.P.uintInRange
import all Lanius.Mini.Frontend.P.uintMask
import all Lanius.Mini.Frontend.P.selfRefOf
import all Lanius.Mini.Frontend.P.discardClosed
import all Lanius.Mini.Frontend.P.ifEvalClosed
import all Lanius.Mini.Frontend.P.returnEvalClosed
import all Lanius.Mini.Frontend.P.setEvalClosed
import all Lanius.Mini.Frontend.P.setIndexEvalClosed
import all Lanius.Mini.Frontend.P.whileEvalClosed
import all Lanius.Mini.Frontend.P.fieldEvalStmt
import all Lanius.Mini.Frontend.P.setIndexOrEval
import all Lanius.Mini.Frontend.P.nestedOrPlain
import all Lanius.Mini.Frontend.P.plainUse
import all Lanius.Mini.Frontend.P.rowsUse
import all Lanius.Mini.Frontend.P.shadowUse
import all Lanius.Mini.Frontend.P.wildUse
import all Lanius.Mini.Frontend.P.attach
import all Lanius.Mini.Frontend.P.only
import all Lanius.Mini.Frontend.P.shrFirst
import all Lanius.Mini.Frontend.P.shrSecond
import all Lanius.Mini.Frontend.P.intAt
import all Lanius.Mini.Frontend.P.intLiteralAt
import all Lanius.Mini.Frontend.P.payloadAt
import all Lanius.Mini.Frontend.P.repeatSrc
import all Lanius.Mini.Frontend.P.sintAt
import all Lanius.Mini.Frontend.P.srcElement
import all Lanius.Mini.Frontend.P.srcFields
import all Lanius.Mini.Frontend.P.srcVariants
import all Lanius.Mini.Frontend.P.tyAt
import all Lanius.Mini.Frontend.P.tyLocal
import all Lanius.Mini.Frontend.P.allocPath
import all Lanius.Mini.Frontend.P.armBound
import all Lanius.Mini.Frontend.P.armValue
import all Lanius.Mini.Frontend.P.builtinPath
import all Lanius.Mini.Frontend.P.callPathHead
import all Lanius.Mini.Frontend.P.consArm
import all Lanius.Mini.Frontend.P.consArmTail
import all Lanius.Mini.Frontend.P.deallocPath
import all Lanius.Mini.Frontend.P.fieldValues
import all Lanius.Mini.Frontend.P.isPath
import all Lanius.Mini.Frontend.P.isSomeName
import all Lanius.Mini.Frontend.P.namedSplit
import all Lanius.Mini.Frontend.P.sameNames
import all Lanius.Mini.Frontend.P.sliceHead
import all Lanius.Mini.Frontend.P.viewPath
import all Lanius.Mini.Frontend.P.structHead
import all Lanius.Mini.Frontend.P.member
import all Lanius.Mini.Frontend.P.primitive
import all Lanius.Mini.Frontend.P.spelled0
import all Lanius.Mini.Frontend.P.spelled1
import all Lanius.Mini.Frontend.P.spelled2
import all Lanius.Mini.Frontend.P.spelled3
import all Lanius.Mini.Frontend.P.spelled4
import all Lanius.Mini.Frontend.P.spelled5
import all Lanius.Mini.Frontend.P.textAlloc
import all Lanius.Mini.Frontend.P.textAllocator
import all Lanius.Mini.Frontend.P.textAssert
import all Lanius.Mini.Frontend.P.textDealloc
import all Lanius.Mini.Frontend.P.textSelf
import all Lanius.Mini.Frontend.P.textSliceFromRawParts
import all Lanius.Mini.Frontend.P.textSliceStride
import all Lanius.Mini.Frontend.P.textStr
import all Lanius.Mini.Frontend.P.textStringDataPtr
import all Lanius.Mini.Frontend.P.textTypedSliceFromRawParts
import all Lanius.Mini.Frontend.P.treeTokens
import all Lanius.Mini.Frontend.P.wideI32
import all Lanius.Mini.Frontend.P.wideIsize
import all Lanius.Mini.Frontend.P.wideSint
import all Lanius.Mini.Frontend.P.wideUint
import all Lanius.Mini.Frontend.P.triedErr
import all Lanius.Mini.Frontend.P.triedShape
import all Lanius.Mini.Frontend.P.triedCall
import all Lanius.Mini.Frontend.P.triedIf
import all Lanius.Mini.Frontend.P.triedLocal
import all Lanius.Mini.Frontend.P.triedOf
import all Lanius.Mini.Frontend.P.tryCallOf
import all Lanius.Mini.Frontend.P.tryMethodOf
import all Lanius.Mini.Frontend.P.inferred
import all Lanius.Mini.Frontend.P.isPtrTy
import all Lanius.Mini.Frontend.P.letHeadOrEval
import all Lanius.Mini.Frontend.P.literalHead
import all Lanius.Mini.Frontend.P.pureInferred
import all Lanius.Mini.Frontend.P.thenOf
import all Lanius.Mini.Frontend.P.thenRest
import all Lanius.Mini.Frontend.P.tryLet
import all Lanius.Mini.Frontend.P.tryStmt
import all Lanius.Mini.Frontend.P.untypedEval
import all Lanius.Mini.Frontend.P.untypedHead
import all Lanius.Mini.Frontend.P.untypedIf
import all Lanius.Mini.Frontend.P.untypedTry
import all Lanius.Mini.Frontend.P.tryLetHead
import all Lanius.Mini.Frontend.P.tryPayload
import all Lanius.Mini.Frontend.P.tryRest
import all Lanius.Mini.Frontend.P.tryHead
import all Lanius.Mini.Frontend.P.tryLocalOf
import all Lanius.Mini.Frontend.P.tryOfInit
import all Lanius.Mini.Frontend.P.tryPostfix
import all Lanius.Mini.Frontend.P.arityOk
import all Lanius.Mini.Frontend.P.arrayLen
import all Lanius.Mini.Frontend.P.arrayTy
import all Lanius.Mini.Frontend.P.bareOf
import all Lanius.Mini.Frontend.P.bareTy
import all Lanius.Mini.Frontend.P.consTy
import all Lanius.Mini.Frontend.P.consTyTail
import all Lanius.Mini.Frontend.P.consTysTail
import all Lanius.Mini.Frontend.P.decimal
import all Lanius.Mini.Frontend.P.namedArgs
import all Lanius.Mini.Frontend.P.namedChecked
import all Lanius.Mini.Frontend.P.namedOf
import all Lanius.Mini.Frontend.P.primOrNamed
import all Lanius.Mini.Frontend.P.sliceTy
import all Lanius.Mini.Frontend.P.tyOf
import all Lanius.Mini.Frontend.P.typeDeclAt
import all Lanius.Mini.Frontend.P.splitLast
import all Lanius.Mini.Frontend.P.splitMore
import all Lanius.Mini.Frontend.P.typePathSpellings
import all Lanius.Mini.Frontend.P.literalAs
import all Lanius.Mini.Frontend.P.typedLiteral
import all Lanius.Mini.Frontend.P.unitTy
import all Lanius.Mini.Frontend.P.consUse
import all Lanius.Mini.Frontend.P.joinUse
import all Lanius.Mini.Frontend.P.usedArms
import all Lanius.Mini.Frontend.P.variantArm
import all Lanius.Mini.Frontend.P.variantArms
import all Lanius.Mini.Frontend.P.wildUsed
import all Lanius.Mini.Frontend.P.enumVariant
import all Lanius.Mini.Frontend.P.paramTy
import all Lanius.Mini.Frontend.P.primTy
import all Lanius.Mini.Frontend.P.scalarSrc
import all Lanius.Mini.Frontend.P.srcTy
import all Lanius.Mini.Frontend.P.variantByPath
import all Lanius.Mini.Frontend.P.variantIn
import all Lanius.Mini.Frontend.P.pureArms
import all Lanius.Mini.Frontend.P.variantLetHead
import all Lanius.Mini.Frontend.P.variantOfDecl
import all Lanius.Mini.Frontend.P.effActs
import all Lanius.Mini.Frontend.P.setEvalOf
import all Lanius.Mini.Frontend.P.setIndexEvalOf
import all Lanius.Mini.Frontend.P.setOrEval
import all Lanius.Mini.Frontend.P.setTryOrEval
import all Lanius.Mini.Frontend.P.stmtUnless
import all Lanius.Mini.Frontend.P.trySet
import all Lanius.Mini.Frontend.P.whileEvalOf
import all Lanius.Mini.Frontend.P.whileOrEval
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
import all Lanius.Mini.Frontend.P.wideMarker
import all Lanius.Mini.Frontend.P.applyTy
import all Lanius.Mini.Frontend.P.bareInt
import all Lanius.Mini.Frontend.P.dashText
import all Lanius.Mini.Frontend.P.exprOf
import all Lanius.Mini.Frontend.P.fieldTy
import all Lanius.Mini.Frontend.P.givesBool
import all Lanius.Mini.Frontend.P.localTy
import all Lanius.Mini.Frontend.P.peel
import all Lanius.Mini.Frontend.P.shiftOp
import all Lanius.Mini.Frontend.P.structFieldTys
import all Lanius.Mini.Frontend.P.wideConst
import all Lanius.Mini.Frontend.P.wideDigits
import all Lanius.Mini.Frontend.P.wideOf
import all Lanius.Mini.Frontend.P.wideSigned
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
import all Lanius.Mini.Frontend.P.checkedFunc
public import Lanius.Mini.Compiler.P.compileSource
public import Lanius.Mini.Compiler.P.packWord
public import Lanius.Mini.Compiler.P.roundCons
public import Lanius.Mini.Compiler.P.roundEnd
public import Lanius.Mini.Compiler.P.usizeWords
public import Lanius.Mini.Compiler.P.lowerReturnUnit
public import Lanius.Mini.Compiler.P.lowerSetFieldEval
public import Lanius.Mini.Compiler.P.lowerUnreachable
public import Lanius.Mini.Compiler.P.lowerView
public import Lanius.Mini.Compiler.P.setFieldEvalAt
public import Lanius.Mini.Compiler.P.setFieldEvalOf
public import Lanius.Mini.Compiler.P.storeArray
public import Lanius.Mini.Compiler.P.strAscii
public import Lanius.Mini.Compiler.P.strWords
public import Lanius.Mini.Compiler.P.viewStores
public import Lanius.Mini.Compiler.P.blockAt
public import Lanius.Mini.Compiler.P.blockLoad
public import Lanius.Mini.Compiler.P.blockStore
public import Lanius.Mini.Compiler.P.elementLoads
public import Lanius.Mini.Compiler.P.elementStores
public import Lanius.Mini.Compiler.P.idAbsent
public import Lanius.Mini.Compiler.P.lowerAssert
public import Lanius.Mini.Compiler.P.lowerSetIndexAny
public import Lanius.Mini.Compiler.P.lowerSetIndexEval
public import Lanius.Mini.Compiler.P.lowerStr
public import Lanius.Mini.Compiler.P.packedWidth
public import Lanius.Mini.Compiler.P.strStores
public import Lanius.Mini.Compiler.P.SrcEff_isSlice
public import Lanius.Mini.Compiler.P.SrcEff_passesSlices
public import Lanius.Mini.Compiler.P.SrcEff_sliceCall
public import Lanius.Mini.Compiler.P.SrcStmt_breaksOut
public import Lanius.Mini.Compiler.P.SrcStmt_depth
public import Lanius.Mini.Compiler.P.SrcStmt_lower
public import Lanius.Mini.Compiler.P.arrayCall
public import Lanius.Mini.Compiler.P.arrayCallSig
public import Lanius.Mini.Compiler.P.effsSlice
public import Lanius.Mini.Compiler.P.paramScope
public import Lanius.Mini.Compiler.P.paramTypes
public import Lanius.Mini.Compiler.P.paramsSize
public import Lanius.Mini.Compiler.P.paramsValid
public import Lanius.Mini.Compiler.P.stmtEval
public import Lanius.Mini.Compiler.P.argBytes
public import Lanius.Mini.Compiler.P.arrayArg
public import Lanius.Mini.Compiler.P.arrayArgBefore
public import Lanius.Mini.Compiler.P.arrayArgChecked
public import Lanius.Mini.Compiler.P.arrayArgLocal
public import Lanius.Mini.Compiler.P.arrayArgPure
public import Lanius.Mini.Compiler.P.arrayArgSlice
public import Lanius.Mini.Compiler.P.arrayArgs
public import Lanius.Mini.Compiler.P.arrayCallCode
public import Lanius.Mini.Compiler.P.bindingBytes
public import Lanius.Mini.Compiler.P.blockLimit
public import Lanius.Mini.Compiler.P.Expr_extent
public import Lanius.Mini.Compiler.P.Stmt_extent
public import Lanius.Mini.Compiler.P.argsExtent
public import Lanius.Mini.Compiler.P.funcNeeds
public import Lanius.Mini.Compiler.P.sigs
public import Lanius.Mini.Compiler.P.sigsWith
public import Lanius.Mini.Compiler.P.needCapped
public import Lanius.Mini.Compiler.P.needRound
public import Lanius.Mini.Compiler.P.needRoundAt
public import Lanius.Mini.Compiler.P.restNeeds
public import Lanius.Mini.Compiler.P.sameNeeds
public import Lanius.Mini.Compiler.P.needsAfter
public import Lanius.Mini.Compiler.P.SrcEff_sliceUses
public import Lanius.Mini.Compiler.P.SrcStmt_calleeNeed
public import Lanius.Mini.Compiler.P.SrcStmt_sliceUses
public import Lanius.Mini.Compiler.P.arrayBytesOf
public import Lanius.Mini.Compiler.P.blockRoom
public import Lanius.Mini.Compiler.P.declBytes
public import Lanius.Mini.Compiler.P.frameBlock
public import Lanius.Mini.Compiler.P.paramsRoom
public import Lanius.Mini.Compiler.P.withBudget
public import Lanius.Mini.Frontend.P.Inline_attachAfter
public import Lanius.Mini.Frontend.P.Inline_attachTerm
public import Lanius.Mini.Frontend.P.Inline_genericCloseAt
public import Lanius.Mini.Frontend.P.grammar
public import Lanius.Mini.Frontend.P.grammarPart13
public import Lanius.Mini.Frontend.P.grammarPart14
public import Lanius.Mini.Frontend.P.grammarPart15
public import Lanius.Mini.Frontend.P.grammarPart16
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
/-! # From source text to machine code (roadmap steps V5, V8f)

`compileText` is the verified compiler on source files: the front end on
each file's bytes and laniusc's parse tree for it, then `compileSource`. Its
theorems mention no parse tree. `TextReading sources sp` says that `sp` is
what the texts mean: each lexes (`lexTokens`) to tokens that have a parse
tree for `file` that is `Picked`, and `sp` is a reading of those trees
(`Reading`, the inductive relation of `Mini/Reading/`). A text has at most
one reading (`textReading_unique`): its trees are unique (V4) and the
relation is deterministic (`reading_unique`, F1). `TextBuilt sources sp`:
`buildFiles` reads `sp` off those trees, so it is the reading
(`textBuilt_reading`).

`compileText_correct`: when `compileText` returns a binary, the files have
exactly one reading `sp`, and for every source function whose Core call
completes, the binary's code for it returns that call's value, as in
`compileSource_correct`. `compileText_behaviour`: any run of that code that
stops at a state other than a fault comes from a Core call that completes
or reaches an undefined trap, as in `compileSource_behaviour`. laniusc's
parser is not trusted: a wrong tree is rejected, and a right one changes
nothing. -/

namespace Lanius.Mini

variable {sx : Statics}

open Lanius.X86.Machine
open Lanius.Core (Value)

/-- The verified compiler on source files with laniusc's parse trees. -/
def compileText (files : List SourceFile) : Option Binary :=
  match sourceProgramFiles files with
  | some sp => compileSource sp
  | none => none

/-- The fuel `buildFiles` is given for files with these tokens and trees. -/
def textFuel : List (List Token) → List CTree → Nat
  | [], [] => 16
  | [], _ :: _ => 16
  | _ :: _, [] => 16
  | tokens :: more, root :: roots => 4 * (root.preorder.length + tokens.length) + textFuel more roots

/-- The front end's program: each source text lexes to tokens with a
`Picked` parse tree for `file`, and `buildFiles` reads `sp` off the trees. -/
def TextBuilt (sources : List (List Lanius.Compiler.Lexer.Byte)) (sp : SrcProgram) : Prop :=
  ∃ (tokens : List (List Token)) (roots : List CTree),
    ListRel (fun source toks => lexTokens source = some toks) sources tokens ∧
    ListRel (fun toks root => Shape grammar 0 root ∧ Picked root toks []) tokens roots ∧
    buildFiles (textFuel tokens roots) roots = some sp

theorem textBuilt_roots : ∀ {sources : List (List Lanius.Compiler.Lexer.Byte)} {tokens₁ tokens₂ : List (List Token)}
    {roots₁ roots₂ : List CTree},
    ListRel (fun source toks => lexTokens source = some toks) sources tokens₁ →
    ListRel (fun source toks => lexTokens source = some toks) sources tokens₂ →
    ListRel (fun toks root => Shape grammar 0 root ∧ Picked root toks []) tokens₁ roots₁ →
    ListRel (fun toks root => Shape grammar 0 root ∧ Picked root toks []) tokens₂ roots₂ →
    tokens₁ = tokens₂ ∧ roots₁ = roots₂
  | [], _, _, _, _, .nil, .nil, .nil, .nil => ⟨rfl, rfl⟩
  | _ :: _, _, _, _, _, .cons l₁ ls₁, .cons l₂ ls₂, .cons ⟨s₁, p₁⟩ rs₁, .cons ⟨s₂, p₂⟩ rs₂ => by
    rw [l₁, Option.some.injEq] at l₂
    subst l₂
    obtain rfl := grammar_unique s₁ p₁ s₂ p₂
    obtain ⟨rfl, rfl⟩ := textBuilt_roots ls₁ ls₂ rs₁ rs₂
    exact ⟨rfl, rfl⟩

/-- `sp` is what the source texts mean: each lexes to tokens with a `Picked`
parse tree for `file`, and `sp` is a reading of the trees. -/
def TextReading (sources : List (List Lanius.Compiler.Lexer.Byte)) (sp : SrcProgram) : Prop :=
  ∃ (tokens : List (List Token)) (roots : List CTree),
    ListRel (fun source toks => lexTokens source = some toks) sources tokens ∧
    ListRel (fun toks root => Shape grammar 0 root ∧ Picked root toks []) tokens roots ∧
    Reading.Reading roots sp

/-- What the front end builds is a reading. -/
theorem textBuilt_reading {sources : List (List Lanius.Compiler.Lexer.Byte)} {sp : SrcProgram}
    (h : TextBuilt sources sp) : TextReading sources sp := by
  obtain ⟨tokens, roots, l, r, b⟩ := h
  exact ⟨tokens, roots, l, r, Reading.buildFiles_sound b⟩

/-- A text has at most one reading. -/
theorem textReading_unique {sources : List (List Lanius.Compiler.Lexer.Byte)} {sp₁ sp₂ : SrcProgram}
    (h₁ : TextReading sources sp₁) (h₂ : TextReading sources sp₂) : sp₁ = sp₂ := by
  obtain ⟨tokens₁, roots₁, l₁, r₁, b₁⟩ := h₁
  obtain ⟨tokens₂, roots₂, l₂, r₂, b₂⟩ := h₂
  obtain ⟨rfl, rfl⟩ := textBuilt_roots l₁ l₂ r₁ r₂
  exact Reading.reading_unique b₁ b₂

theorem filesFuel_text : ∀ {files : List SourceFile} {inputs : List FileInput} {roots : List CTree},
    LexRel files inputs → TreeRel inputs roots → filesFuel inputs = textFuel (inputs.map FileInput.tokens) roots
  | [], [], [], .nil, .nil => rfl
  | _ :: _, _ :: _, _ :: _, .cons _ ls, .cons ⟨_, _, pre⟩ rs => by
    simp only [filesFuel, List.map_cons, textFuel, pre, filesFuel_text ls rs]

/-- The several-file front end's program is the one it builds from the
files' sources. -/
theorem sourceProgramFiles_built {files : List SourceFile} {sp : SrcProgram}
    (h : sourceProgramFiles files = some sp) : TextBuilt (files.map SourceFile.source) sp := by
  obtain ⟨inputs, roots, lex, val, b⟩ := sourceProgramFiles_sound h
  have lexed : ∀ {fs : List SourceFile} {is : List FileInput}, LexRel fs is →
      ListRel (fun source toks => lexTokens source = some toks) (fs.map SourceFile.source) (is.map FileInput.tokens) := by
    intro fs is l
    induction l with
    | nil => exact .nil
    | cons h _ ih => exact .cons h.1 ih
  have trees : ∀ {is : List FileInput} {rs : List CTree}, TreeRel is rs →
      ListRel (fun toks root => Shape grammar 0 root ∧ Picked root toks []) (is.map FileInput.tokens) rs := by
    intro is rs t
    induction t with
    | nil => exact .nil
    | cons h _ ih => exact .cons ⟨h.1, h.2.1⟩ ih
  exact ⟨_, roots, lexed lex, trees val, by rw [← filesFuel_text lex val]; exact b⟩

/-- `compileText`'s program: the files' sources' one reading. -/
theorem compileText_reading {files : List SourceFile} {binary : Binary} (h : compileText files = some binary) :
    ∃ sp, TextReading (files.map SourceFile.source) sp ∧
      (∀ sp', TextReading (files.map SourceFile.source) sp' → sp' = sp) ∧ compileSource sp = some binary := by
  unfold compileText at h
  cases hs : sourceProgramFiles files with
  | none => simp [hs] at h
  | some sp =>
    rw [hs] at h
    have built := sourceProgramFiles_built hs
    have reading := textBuilt_reading built
    exact ⟨sp, reading, fun _ r => textReading_unique r reading, h⟩

/-- The verified compiler from source text: the files mean `sp`
(`TextReading`) and nothing else, and when Core runs a call `f(args)` of it from the empty
state to `v`, the binary's code for `f`, entered by a near call with the
arguments laid out by type and a fresh heap, returns `v`'s slots (premises
and conclusion as in `compileSource_correct`). -/
theorem compileText_correct {files : List SourceFile} {binary : Binary} (h : compileText files = some binary) :
    ∃ sp, TextReading (files.map SourceFile.source) sp ∧
      (∀ sp', TextReading (files.map SourceFile.source) sp' → sp' = sp) ∧
      ∀ {f : Nat} {func : SrcFunc}, sp.funcs[f]? = some func →
      ∀ {args : List Value} {bits : List (BitVec 64)}, FieldsHold sx [] (paramTypes func.params) args (Func.entry bits) 0 →
      bits.length = paramsSize func.params →
      ∀ {fuel : Nat} {v : Value} {final : Semantics.State} {heap : Heap}, heap.cursor = 1 →
      (∀ a, 1 ≤ a → heap.bytes a = 0) → heap.limit < 2 ^ 62 → heap.io.trace = [] →
      Semantics.evalExpr fuel sp.toCore (startState heap.io) (.call f (args.map Core.Expr.value)) = .done v final →
      final.heap.nextAddress ≤ heap.limit → (0 < sp.need f → heap.limit + sp.need f ≤ heap.fsp ∧ heap.fsp ≤ heap.top ∧ heap.top < 2 ^ 62) →
      heap.StaticsAt sx → sx.bytes = sp.decls.statics →
      ∃ depth results after, func.ret.HoldsAt sx [] v (Func.entry results) 0 ∧ results.length = func.ret.size ∧
        after.cursor = final.heap.nextAddress ∧ final.world.standardOutput = outputOf 1 after.io.trace ∧
        final.world.standardError = outputOf 2 after.io.trace ∧
        ∀ (s : State) (imageBase : BitVec 64) (window : Nat),
          binary.stackNeed depth ≤ window → window ≤ 2 ^ 62 →
          CodeAt s.memory imageBase binary.image →
          (∀ index, index < binary.image.length →
            ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index)) →
          (∀ index, index < binary.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index)) →
          s.rip = imageBase + BitVec.ofNat 64 (binary.entries.getD f 0) →
          (∀ k (bound : k < bits.length),
            read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = bits[k]) →
          HeapAt window s heap → StackAt binary.guard window s →
          ∃ n s', Steps n s s' ∧ Det n s s' ∧ Returned window s s' results after := by
  obtain ⟨sp, reading, unique, compiled⟩ := compileText_reading h
  refine ⟨sp, reading, unique, ?_⟩
  intro f func found args bits typed bitsLen fuel v final heap start zero small silent runs fits frameRoom statics ofSp
  exact compileSource_correct compiled found typed bitsLen start zero small silent runs fits frameRoom statics ofSp

/-- Every behaviour of the verified compiler's code from source text: a run of
the binary's code for `f` (premises as in `compileSource_behaviour`) that
stops at a state other than a fault comes from a Core call of the files'
one reading that completes within the heap's limit, or that reaches an
undefined trap. -/
theorem compileText_behaviour {files : List SourceFile} {binary : Binary} (h : compileText files = some binary) :
    ∃ sp, TextReading (files.map SourceFile.source) sp ∧
      (∀ sp', TextReading (files.map SourceFile.source) sp' → sp' = sp) ∧
      ∀ {f : Nat} {func : SrcFunc}, sp.funcs[f]? = some func →
      ∀ {args : List Value} {bits : List (BitVec 64)}, FieldsHold sx [] (paramTypes func.params) args (Func.entry bits) 0 →
      bits.length = paramsSize func.params →
      ∀ {heap : Heap}, heap.cursor = 1 → (∀ a, 1 ≤ a → heap.bytes a = 0) → heap.limit < 2 ^ 62 →
      heap.io.trace = [] → 1 ≤ heap.limit → (0 < sp.need f → heap.limit + sp.need f ≤ heap.fsp ∧ heap.fsp ≤ heap.top ∧ heap.top < 2 ^ 62) →
      heap.StaticsAt sx → sx.bytes = sp.decls.statics →
      ∀ (s : State) (imageBase : BitVec 64) (window : Nat), window ≤ 2 ^ 62 →
        CodeAt s.memory imageBase binary.image →
        (∀ index, index < binary.image.length →
          ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index)) →
        (∀ index, index < binary.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index)) →
        s.rip = imageBase + BitVec.ofNat 64 (binary.entries.getD f 0) →
        (∀ k (bound : k < bits.length),
          read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = bits[k]) →
        HeapAt window s heap → StackAt binary.guard window s →
        ∀ {m : Nat} {u : State}, Steps m s u → (∀ v, ¬Lanius.X86.Machine.Step u v) → ¬Lanius.X86.Machine.Fault u →
        (∃ fuel v final, Semantics.evalExpr fuel sp.toCore (startState heap.io) (.call f (args.map Core.Expr.value)) = .done v final ∧
          final.heap.nextAddress ≤ heap.limit) ∨
        ∃ fuel r st, Semantics.evalExpr fuel sp.toCore (startState heap.io) (.call f (args.map Core.Expr.value)) = .trapped r st ∧
          undefinedTrap r = true ∧ st.heap.nextAddress ≤ heap.limit := by
  obtain ⟨sp, reading, unique, compiled⟩ := compileText_reading h
  refine ⟨sp, reading, unique, ?_⟩
  intro f func found args bits typed bitsLen heap start zero small silent room frameRoom statics ofSp s imageBase window
    bounded loaded apart imageHeap entry params heapAt stack m u run stuck clean
  exact compileSource_behaviour compiled found typed bitsLen start zero small silent room frameRoom statics ofSp s imageBase window bounded loaded
    apart imageHeap entry params heapAt stack run stuck clean

end Lanius.Mini
