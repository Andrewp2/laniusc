module

public import Lanius.Mini.TextCorrect
public import Lanius.Mini.LexCorrect
public import Lanius.Mini.Compiler.P.compileSource
public import Lanius.Mini.Compiler.P.packWord
public import Lanius.Mini.Compiler.P.roundCons
public import Lanius.Mini.Compiler.P.roundEnd
public import Lanius.Mini.Compiler.P.usizeWords
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
import all Lanius.Mini.Compiler.P.compileSource
import all Lanius.Mini.Compiler.P.packWord
import all Lanius.Mini.Compiler.P.roundCons
import all Lanius.Mini.Compiler.P.roundEnd
import all Lanius.Mini.Compiler.P.usizeWords
import all Lanius.Mini.Compiler.P.binaryWords
import all Lanius.Mini.Compiler.P.compileWords
import all Lanius.Mini.Compiler.P.elfBase
import all Lanius.Mini.Compiler.P.elfBeforeImage
import all Lanius.Mini.Compiler.P.imageWords
import all Lanius.Mini.Compiler.P.packRound
import all Lanius.Mini.Compiler.P.packRounds
import all Lanius.Mini.Compiler.P.roundJoin
import all Lanius.Mini.Compiler.P.UintTy_code
import all Lanius.Mini.Compiler.P.entriesAt
import all Lanius.Mini.Compiler.P.funcsSize
import all Lanius.Mini.Compiler.P.funcsSlots
import all Lanius.Mini.Compiler.P.linkObjects
import all Lanius.Mini.Compiler.P.objectExports
import all Lanius.Mini.Compiler.P.objectFirsts
import all Lanius.Mini.Compiler.P.objectLayout
import all Lanius.Mini.Compiler.P.objectsLayout
import all Lanius.Mini.Compiler.P.objectsOk
import all Lanius.Mini.Compiler.P.objectsSlots
import all Lanius.Mini.Compiler.P.render
import all Lanius.Mini.Compiler.P.renderFuncs
import all Lanius.Mini.Compiler.P.renderObjects
import all Lanius.Mini.Compiler.P.copyBinding
import all Lanius.Mini.Compiler.P.copyField
import all Lanius.Mini.Compiler.P.copyFieldAt
import all Lanius.Mini.Compiler.P.copyFieldOf
import all Lanius.Mini.Compiler.P.lowerArgs
import all Lanius.Mini.Compiler.P.lowerCopy
import all Lanius.Mini.Compiler.P.lowerLiteral
import all Lanius.Mini.Compiler.P.lowerSingle
import all Lanius.Mini.Compiler.P.lowerStructFields
import all Lanius.Mini.Compiler.P.lowerTag
import all Lanius.Mini.Compiler.P.lowerValue
import all Lanius.Mini.Compiler.P.lowerVariant
import all Lanius.Mini.Compiler.P.repeatType
import all Lanius.Mini.Compiler.P.elementOf
import all Lanius.Mini.Compiler.P.evalApply
import all Lanius.Mini.Compiler.P.evalDivideUint
import all Lanius.Mini.Compiler.P.evalLoad
import all Lanius.Mini.Compiler.P.evalOperands
import all Lanius.Mini.Compiler.P.evalPayload
import all Lanius.Mini.Compiler.P.evalRight
import all Lanius.Mini.Compiler.P.evalStruct
import all Lanius.Mini.Compiler.P.evalStructOf
import all Lanius.Mini.Compiler.P.evalTagged
import all Lanius.Mini.Compiler.P.evalVariant
import all Lanius.Mini.Compiler.P.operandGuard
import all Lanius.Mini.Compiler.P.overflowGuard
import all Lanius.Mini.Compiler.P.shortCircuit
import all Lanius.Mini.Compiler.P.signedDiv
import all Lanius.Mini.Compiler.P.unsignedDiv
import all Lanius.Mini.Compiler.P.SrcEff_sliceUses
import all Lanius.Mini.Compiler.P.SrcStmt_calleeNeed
import all Lanius.Mini.Compiler.P.SrcStmt_sliceUses
import all Lanius.Mini.Compiler.P.arrayBytesOf
import all Lanius.Mini.Compiler.P.blockRoom
import all Lanius.Mini.Compiler.P.declBytes
import all Lanius.Mini.Compiler.P.frameBlock
import all Lanius.Mini.Compiler.P.paramsRoom
import all Lanius.Mini.Compiler.P.withBudget
import all Lanius.Mini.Compiler.P.Expr_extent
import all Lanius.Mini.Compiler.P.Stmt_extent
import all Lanius.Mini.Compiler.P.argsExtent
import all Lanius.Mini.Compiler.P.funcNeeds
import all Lanius.Mini.Compiler.P.sigs
import all Lanius.Mini.Compiler.P.sigsWith
import all Lanius.Mini.Compiler.P.castTo
import all Lanius.Mini.Compiler.P.castToFloat
import all Lanius.Mini.Compiler.P.castToI32
import all Lanius.Mini.Compiler.P.castToIsize
import all Lanius.Mini.Compiler.P.castToSint
import all Lanius.Mini.Compiler.P.castToUint
import all Lanius.Mini.Compiler.P.floatToFloat
import all Lanius.Mini.Compiler.P.ifNarrow
import all Lanius.Mini.Compiler.P.intToFloat
import all Lanius.Mini.Compiler.P.lowerCast
import all Lanius.Mini.Compiler.P.lowerFloat
import all Lanius.Mini.Compiler.P.sintToUint
import all Lanius.Mini.Compiler.P.sintToWide
import all Lanius.Mini.Compiler.P.lowerReturnUnit
import all Lanius.Mini.Compiler.P.lowerSetFieldEval
import all Lanius.Mini.Compiler.P.lowerUnreachable
import all Lanius.Mini.Compiler.P.lowerView
import all Lanius.Mini.Compiler.P.setFieldEvalAt
import all Lanius.Mini.Compiler.P.setFieldEvalOf
import all Lanius.Mini.Compiler.P.storeArray
import all Lanius.Mini.Compiler.P.strAscii
import all Lanius.Mini.Compiler.P.strWords
import all Lanius.Mini.Compiler.P.viewStores
import all Lanius.Mini.Compiler.P.blockAt
import all Lanius.Mini.Compiler.P.blockLoad
import all Lanius.Mini.Compiler.P.blockStore
import all Lanius.Mini.Compiler.P.elementLoads
import all Lanius.Mini.Compiler.P.elementStores
import all Lanius.Mini.Compiler.P.idAbsent
import all Lanius.Mini.Compiler.P.lowerAssert
import all Lanius.Mini.Compiler.P.lowerSetIndexAny
import all Lanius.Mini.Compiler.P.lowerSetIndexEval
import all Lanius.Mini.Compiler.P.lowerStr
import all Lanius.Mini.Compiler.P.packedWidth
import all Lanius.Mini.Compiler.P.strStores
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
import all Lanius.Mini.Frontend.P.frontEndRead
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
import all Lanius.Mini.Frontend.P.lxBaseDigit
import all Lanius.Mini.Frontend.P.lxBlockEnd
import all Lanius.Mini.Frontend.P.lxDigitRun
import all Lanius.Mini.Frontend.P.lxDigitTail
import all Lanius.Mini.Frontend.P.lxExponentDigits
import all Lanius.Mini.Frontend.P.byteAfter
import all Lanius.Mini.Frontend.P.lexSource
import all Lanius.Mini.Frontend.P.lxAsText
import all Lanius.Mini.Frontend.P.lxCanonicalKind
import all Lanius.Mini.Frontend.P.lxFilter
import all Lanius.Mini.Frontend.P.lxKeywordRules
import all Lanius.Mini.Frontend.P.lxRangePair
import all Lanius.Mini.Frontend.P.lxRanges
import all Lanius.Mini.Frontend.P.lxSymbolRules
import all Lanius.Mini.Frontend.P.lxToken
import all Lanius.Mini.Frontend.P.lxTokenText
import all Lanius.Mini.Frontend.P.lxTokens
import all Lanius.Mini.Frontend.P.numsAfter
import all Lanius.Mini.Frontend.P.readBytes
import all Lanius.Mini.Frontend.P.readCountedNums
import all Lanius.Mini.Frontend.P.readNums
import all Lanius.Mini.Frontend.P.wordNum
import all Lanius.Mini.Frontend.P.lxDotAt
import all Lanius.Mini.Frontend.P.lxDropTo
import all Lanius.Mini.Frontend.P.lxKeyword
import all Lanius.Mini.Frontend.P.lxOneAt
import all Lanius.Mini.Frontend.P.lxOneFirst
import all Lanius.Mini.Frontend.P.lxPrepend
import all Lanius.Mini.Frontend.P.lxRaw
import all Lanius.Mini.Frontend.P.lxShift
import all Lanius.Mini.Frontend.P.lxSymbol
import all Lanius.Mini.Frontend.P.lxSymbolAt
import all Lanius.Mini.Frontend.P.lxTrivia
import all Lanius.Mini.Frontend.P.lxAfterFraction
import all Lanius.Mini.Frontend.P.lxBaseOf
import all Lanius.Mini.Frontend.P.lxExponent
import all Lanius.Mini.Frontend.P.lxFinishDecimal
import all Lanius.Mini.Frontend.P.lxFraction
import all Lanius.Mini.Frontend.P.lxFractionDigits
import all Lanius.Mini.Frontend.P.lxNumber
import all Lanius.Mini.Frontend.P.lxPrefixedBase
import all Lanius.Mini.Frontend.P.lxFixed
import all Lanius.Mini.Frontend.P.lxBest
import all Lanius.Mini.Frontend.P.lxBestAt
import all Lanius.Mini.Frontend.P.lxDelimited
import all Lanius.Mini.Frontend.P.lxFixedAt
import all Lanius.Mini.Frontend.P.lxFromNumber
import all Lanius.Mini.Frontend.P.lxLeadingDot
import all Lanius.Mini.Frontend.P.lxLonger
import all Lanius.Mini.Frontend.P.lxStartsWith
import all Lanius.Mini.Frontend.P.lxBlock
import all Lanius.Mini.Frontend.P.lxLineEnd
import all Lanius.Mini.Frontend.P.lxQuoted
import all Lanius.Mini.Frontend.P.lxSpaceEnd
import all Lanius.Mini.Frontend.P.lxDrop
import all Lanius.Mini.Frontend.P.lxIdentEnd
import all Lanius.Mini.Frontend.P.lxIdentRun
import all Lanius.Mini.Frontend.P.lxIsByte
import all Lanius.Mini.Frontend.P.lxLineRun
import all Lanius.Mini.Frontend.P.lxSpaceRun
import all Lanius.Mini.Frontend.P.lxSymbolStart
import all Lanius.Mini.Frontend.P.lxTake
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
import all Lanius.Mini.Frontend.P.fileLexed
import all Lanius.Mini.Frontend.P.filesAfter
import all Lanius.Mini.Frontend.P.readCountedBytes
import all Lanius.Mini.Frontend.P.readCountedFiles
import all Lanius.Mini.Frontend.P.readFile
import all Lanius.Mini.Frontend.P.readFileEnd
import all Lanius.Mini.Frontend.P.readFileParents
import all Lanius.Mini.Frontend.P.readFiles
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
public import Lanius.Mini.Compiler.P.binaryWords
public import Lanius.Mini.Compiler.P.compileWords
public import Lanius.Mini.Compiler.P.elfBase
public import Lanius.Mini.Compiler.P.elfBeforeImage
public import Lanius.Mini.Compiler.P.imageWords
public import Lanius.Mini.Compiler.P.packRound
public import Lanius.Mini.Compiler.P.packRounds
public import Lanius.Mini.Compiler.P.roundJoin
public import Lanius.Mini.Frontend.P.frontEndRead
public import Lanius.Mini.Frontend.P.frontEndWords
public import Lanius.Mini.Frontend.P.grammarPart0
public import Lanius.Mini.Frontend.P.grammarPart1
public import Lanius.Mini.Frontend.P.grammarPart2
public import Lanius.Mini.Frontend.P.grammarPart3
public import Lanius.Mini.Frontend.P.grammarPart4
public import Lanius.Mini.Frontend.P.grammarPart5
public import Lanius.Mini.Frontend.P.grammarPart6
public import Lanius.Mini.Frontend.P.grammarPart7
public import Lanius.Mini.Frontend.P.Inline_attachAfter
public import Lanius.Mini.Frontend.P.Inline_attachTerm
public import Lanius.Mini.Frontend.P.Inline_genericCloseAt
public import Lanius.Mini.Frontend.P.grammar
public import Lanius.Mini.Frontend.P.grammarPart13
public import Lanius.Mini.Frontend.P.grammarPart14
public import Lanius.Mini.Frontend.P.grammarPart15
public import Lanius.Mini.Frontend.P.grammarPart16
public import Lanius.Mini.Frontend.P.byteAfter
public import Lanius.Mini.Frontend.P.lexSource
public import Lanius.Mini.Frontend.P.lxAsText
public import Lanius.Mini.Frontend.P.lxCanonicalKind
public import Lanius.Mini.Frontend.P.lxFilter
public import Lanius.Mini.Frontend.P.lxKeywordRules
public import Lanius.Mini.Frontend.P.lxRangePair
public import Lanius.Mini.Frontend.P.lxRanges
public import Lanius.Mini.Frontend.P.lxSymbolRules
public import Lanius.Mini.Frontend.P.lxToken
public import Lanius.Mini.Frontend.P.lxTokenText
public import Lanius.Mini.Frontend.P.lxTokens
public import Lanius.Mini.Frontend.P.numsAfter
public import Lanius.Mini.Frontend.P.readBytes
public import Lanius.Mini.Frontend.P.readCountedNums
public import Lanius.Mini.Frontend.P.readNums
public import Lanius.Mini.Frontend.P.wordNum
public import Lanius.Mini.Frontend.P.fileLexed
public import Lanius.Mini.Frontend.P.filesAfter
public import Lanius.Mini.Frontend.P.readCountedBytes
public import Lanius.Mini.Frontend.P.readCountedFiles
public import Lanius.Mini.Frontend.P.readFile
public import Lanius.Mini.Frontend.P.readFileEnd
public import Lanius.Mini.Frontend.P.readFileParents
public import Lanius.Mini.Frontend.P.readFiles
public import Lanius.Mini.Frontend.P.attach
public import Lanius.Mini.Frontend.P.only
public import Lanius.Mini.Frontend.P.shrFirst
public import Lanius.Mini.Frontend.P.shrSecond

@[expose] public section
/-! # The driver's words are source files (roadmap step V5)

The self program's entry reads its input as 32-bit words (`frontEndWords`):
the file count, then each file's bytes, productions and parents, each a
count and then the values (`filesWords`). It lexes each file with the
extracted lexer, which is `lexTokens` (`lexSource_eq`, V3). So on the words of
files it is the several-file front end (`frontEndWords_files`), and any words
it accepts are the words of files whose numbers fit (`frontEndWords_some`).
With `compileWords`, the self program's function from input to output words
is `compileText` (`compileWords_files`, `compileWords_some`). -/

namespace Lanius.Mini

open Lanius.Compiler.Lexer (Byte)

/-- A count, then the numbers, one word each. -/
def countedWords (ns : List Nat) : List (BitVec 32) :=
  BitVec.ofNat 32 ns.length :: ns.map (BitVec.ofNat 32)

/-- A file's words: its counted bytes, productions and parents. -/
def fileWords (f : SourceFile) : List (BitVec 32) :=
  countedWords (vals f.source) ++ countedWords f.prods ++ countedWords f.parents

/-- The driver's input for these files. -/
def filesWords (files : List SourceFile) : List (BitVec 32) :=
  BitVec.ofNat 32 files.length :: files.flatMap fileWords

/-- A list's count and numbers fit in words. -/
def NumsFit (ns : List Nat) : Prop := ns.length < 2 ^ 32 ∧ ∀ n ∈ ns, n < 2 ^ 32

/-- A file's counts and numbers fit in words. -/
def FileFits (f : SourceFile) : Prop := f.source.length < 2 ^ 32 ∧ NumsFit f.prods ∧ NumsFit f.parents

/-- The files' counts and numbers fit in words. -/
def FilesFit (files : List SourceFile) : Prop := files.length < 2 ^ 32 ∧ ∀ f ∈ files, FileFits f

theorem wordNum_ofNat {n : Nat} (h : n < 2 ^ 32) : wordNum (BitVec.ofNat 32 n) = n := by
  simp [wordNum, Nat.mod_eq_of_lt h]

theorem ofNat_wordNum (w : BitVec 32) : BitVec.ofNat 32 (wordNum w) = w := by
  apply BitVec.eq_of_toNat_eq
  simp [wordNum]

theorem wordNum_lt (w : BitVec 32) : wordNum w < 2 ^ 32 := w.isLt

/-! ## Reading the words of files -/

theorem readNums_words : ∀ (ns : List Nat) (rest : List (BitVec 32)), (∀ n ∈ ns, n < 2 ^ 32) →
    readNums (ns.map (BitVec.ofNat 32) ++ rest) ns.length = some { nums := ns, rest := rest }
  | [], rest, _ => by unfold readNums; simp
  | n :: ns, rest, h => by
    unfold readNums
    simp only [List.length_cons, Nat.add_one_ne_zero, if_false, List.map_cons, List.cons_append,
      Nat.add_sub_cancel]
    rw [readNums_words ns rest (fun m hm => h m (by simp [hm])), wordNum_ofNat (h n (by simp))]
    rfl

theorem readCountedNums_words {ns : List Nat} (rest : List (BitVec 32)) (fit : NumsFit ns) :
    readCountedNums (countedWords ns ++ rest) = some { nums := ns, rest := rest } := by
  simp only [countedWords, List.cons_append, readCountedNums, wordNum_ofNat fit.1]
  exact readNums_words ns rest fit.2

theorem readBytes_words : ∀ (ns : List Nat) (rest : List (BitVec 32)), (∀ n ∈ ns, n < 256) →
    readBytes (ns.map (BitVec.ofNat 32) ++ rest) ns.length = some { nums := ns, rest := rest }
  | [], rest, _ => by unfold readBytes; simp
  | n :: ns, rest, h => by
    have hn := h n (by simp)
    unfold readBytes
    simp only [List.length_cons, Nat.add_one_ne_zero, if_false, List.map_cons, List.cons_append,
      Nat.add_sub_cancel]
    rw [readBytes_words ns rest (fun m hm => h m (by simp [hm])), wordNum_ofNat (by omega)]
    simp only [byteAfter, show ¬255 < n by omega, if_false]
    rfl

theorem vals_lt (source : List Byte) : ∀ n ∈ vals source, n < 256 := by
  intro n hn
  obtain ⟨b, -, rfl⟩ := List.mem_map.1 hn
  exact b.isLt

theorem readCountedBytes_words {source : List Byte} (rest : List (BitVec 32)) (fit : source.length < 2 ^ 32) :
    readCountedBytes (countedWords (vals source) ++ rest) = some { nums := vals source, rest := rest } := by
  simp only [countedWords, List.cons_append, readCountedBytes]
  rw [wordNum_ofNat (by simpa using fit)]
  exact readBytes_words (vals source) rest (vals_lt source)

theorem readFile_words {f : SourceFile} (rest : List (BitVec 32)) (fit : FileFits f) :
    readFile (fileWords f ++ rest) =
      match lexTokens f.source with
      | some tokens => some { file := { tokens := tokens, prods := f.prods, parents := f.parents }, rest := rest }
      | none => none := by
  simp only [fileWords, List.append_assoc, readFile]
  rw [readCountedBytes_words _ fit.1]
  simp only [readFileParents]
  rw [readCountedNums_words _ fit.2.1]
  simp only [readFileEnd]
  rw [readCountedNums_words _ fit.2.2]
  simp only [fileLexed, lexSource_eq]
  cases lexTokens f.source with
  | some tokens => rfl
  | none => rfl

theorem readFiles_words : ∀ (files : List SourceFile) (rest : List (BitVec 32)), (∀ f ∈ files, FileFits f) →
    readFiles (files.flatMap fileWords ++ rest) files.length =
      match lexFiles files with
      | some inputs => some { files := inputs, rest := rest }
      | none => none
  | [], rest, _ => by unfold readFiles; simp [lexFiles]
  | f :: more, rest, fit => by
    unfold readFiles
    simp only [List.length_cons, Nat.add_one_ne_zero, if_false, List.flatMap_cons, List.append_assoc,
      Nat.add_sub_cancel]
    rw [readFile_words _ (fit f (by simp))]
    have ih := readFiles_words more rest (fun g hg => fit g (by simp [hg]))
    cases hl : lexTokens f.source with
    | none => simp [lexFiles, hl]
    | some tokens =>
      simp only
      rw [ih]
      cases hm : lexFiles more with
      | none => simp [lexFiles, hl, hm, filesAfter]
      | some inputs => simp [lexFiles, hl, hm, filesAfter]

/-- On the words of files, the driver's front end is the several-file front
end. -/
theorem frontEndWords_files {files : List SourceFile} (fit : FilesFit files) :
    frontEndWords grammar (filesWords files) = sourceProgramFiles files := by
  have h := readFiles_words files [] fit.2
  rw [List.append_nil] at h
  simp only [frontEndWords, filesWords, readCountedFiles, wordNum_ofNat fit.1, h, sourceProgramFiles]
  cases lexFiles files with
  | none => rfl
  | some inputs => rfl

/-! ## Words the driver accepts are the words of files -/

theorem readNums_some : ∀ (count : Nat) (words : List (BitVec 32)) (r : NumsRead), readNums words count = some r →
    r.nums.length = count ∧ (∀ n ∈ r.nums, n < 2 ^ 32) ∧ words = r.nums.map (BitVec.ofNat 32) ++ r.rest
  | 0, words, r, h => by
    unfold readNums at h
    simp only [if_true, Option.some.injEq] at h
    subst h
    simp
  | count + 1, [], r, h => by unfold readNums at h; simp at h
  | count + 1, w :: ws, r, h => by
    unfold readNums at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    cases hr : readNums ws count with
    | none => simp [hr, numsAfter] at h
    | some r' =>
      simp only [hr, numsAfter, Option.some.injEq] at h
      subst h
      obtain ⟨len, lt, eq⟩ := readNums_some count ws r' hr
      refine ⟨by simp [len], ?_, by simp [ofNat_wordNum, eq]⟩
      intro n hn
      simp only [List.mem_cons] at hn
      rcases hn with rfl | hn
      · exact wordNum_lt w
      · exact lt n hn

theorem readCountedNums_some {words : List (BitVec 32)} {r : NumsRead} (h : readCountedNums words = some r) :
    NumsFit r.nums ∧ words = countedWords r.nums ++ r.rest := by
  cases words with
  | nil => simp [readCountedNums] at h
  | cons w ws =>
    simp only [readCountedNums] at h
    obtain ⟨len, lt, eq⟩ := readNums_some _ ws r h
    refine ⟨⟨by rw [len]; exact wordNum_lt w, lt⟩, ?_⟩
    simp [countedWords, len, ofNat_wordNum, eq]

theorem readBytes_some : ∀ (count : Nat) (words : List (BitVec 32)) (r : NumsRead), readBytes words count = some r →
    r.nums.length = count ∧ (∀ n ∈ r.nums, n < 256) ∧ words = r.nums.map (BitVec.ofNat 32) ++ r.rest
  | 0, words, r, h => by
    unfold readBytes at h
    simp only [if_true, Option.some.injEq] at h
    subst h
    simp
  | count + 1, [], r, h => by unfold readBytes at h; simp at h
  | count + 1, w :: ws, r, h => by
    unfold readBytes at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    by_cases big : 255 < wordNum w
    · simp [byteAfter, big] at h
    · simp only [byteAfter, big, if_false] at h
      cases hr : readBytes ws count with
      | none => simp [hr, numsAfter] at h
      | some r' =>
        simp only [hr, numsAfter, Option.some.injEq] at h
        subst h
        obtain ⟨len, lt, eq⟩ := readBytes_some count ws r' hr
        refine ⟨by simp [len], ?_, by simp [ofNat_wordNum, eq]⟩
        intro n hn
        simp only [List.mem_cons] at hn
        rcases hn with rfl | hn
        · omega
        · exact lt n hn

theorem bytes_of_lt : ∀ (ns : List Nat), (∀ n ∈ ns, n < 256) → ∃ source : List Byte, vals source = ns
  | [], _ => ⟨[], rfl⟩
  | n :: ns, h => by
    obtain ⟨source, eq⟩ := bytes_of_lt ns (fun m hm => h m (by simp [hm]))
    exact ⟨⟨n, h n (by simp)⟩ :: source, by simp [eq]⟩

theorem readCountedBytes_some {words : List (BitVec 32)} {r : NumsRead} (h : readCountedBytes words = some r) :
    ∃ source : List Byte, vals source = r.nums ∧ source.length < 2 ^ 32 ∧ words = countedWords r.nums ++ r.rest := by
  cases words with
  | nil => simp [readCountedBytes] at h
  | cons w ws =>
    simp only [readCountedBytes] at h
    obtain ⟨len, lt, eq⟩ := readBytes_some _ ws r h
    obtain ⟨source, vs⟩ := bytes_of_lt r.nums lt
    refine ⟨source, vs, ?_, ?_⟩
    · have : (vals source).length = source.length := List.length_map _
      rw [← this, vs, len]
      exact wordNum_lt w
    · simp [countedWords, len, ofNat_wordNum, eq]

theorem readFile_some {words : List (BitVec 32)} {r : FileRead} (h : readFile words = some r) :
    ∃ f, FileFits f ∧ words = fileWords f ++ r.rest := by
  unfold readFile at h
  cases hb : readCountedBytes words with
  | none => simp [hb] at h
  | some b =>
    obtain ⟨source, vs, len, wb⟩ := readCountedBytes_some hb
    simp only [hb, readFileParents] at h
    cases hp : readCountedNums b.rest with
    | none => simp [hp] at h
    | some p =>
      obtain ⟨pfit, wp⟩ := readCountedNums_some hp
      simp only [hp, readFileEnd] at h
      cases hq : readCountedNums p.rest with
      | none => simp [hq] at h
      | some q =>
        obtain ⟨qfit, wq⟩ := readCountedNums_some hq
        simp only [hq, fileLexed] at h
        cases hl : lexSource b.nums with
        | none => simp [hl] at h
        | some tokens =>
          simp only [hl, Option.some.injEq] at h
          subst h
          refine ⟨{ source := source, prods := p.nums, parents := q.nums }, ⟨len, pfit, qfit⟩, ?_⟩
          simp only [fileWords, vs, List.append_assoc]
          rw [wb, wp, wq]

theorem readFiles_some : ∀ (count : Nat) (words : List (BitVec 32)) (r : FilesRead), readFiles words count = some r →
    ∃ files : List SourceFile, files.length = count ∧ (∀ f ∈ files, FileFits f) ∧
      words = files.flatMap fileWords ++ r.rest
  | 0, words, r, h => by
    unfold readFiles at h
    simp only [if_true, Option.some.injEq] at h
    subst h
    exact ⟨[], rfl, by simp, rfl⟩
  | count + 1, words, r, h => by
    unfold readFiles at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    cases hf : readFile words with
    | none => simp [hf] at h
    | some fr =>
      obtain ⟨f, fit, wf⟩ := readFile_some hf
      simp only [hf] at h
      cases hr : readFiles fr.rest count with
      | none => simp [hr, filesAfter] at h
      | some r' =>
        simp only [hr, filesAfter, Option.some.injEq] at h
        subst h
        obtain ⟨files, len, fits, wr⟩ := readFiles_some count fr.rest r' hr
        refine ⟨f :: files, by simp [len], ?_, ?_⟩
        · intro g hg
          simp only [List.mem_cons] at hg
          rcases hg with rfl | hg
          · exact fit
          · exact fits g hg
        · rw [wf, wr]
          simp

/-- Words the driver's front end accepts are the words of files whose
numbers fit, and its program is theirs. -/
theorem frontEndWords_some {words : List (BitVec 32)} {sp : SrcProgram} (h : frontEndWords grammar words = some sp) :
    ∃ files, FilesFit files ∧ words = filesWords files ∧ sourceProgramFiles files = some sp := by
  have decoded : ∃ files, FilesFit files ∧ words = filesWords files := by
    unfold frontEndWords at h
    cases hr : readCountedFiles words with
    | none => simp [hr] at h
    | some r =>
      simp only [hr, frontEndRead] at h
      cases words with
      | nil => simp [readCountedFiles] at hr
      | cons w ws =>
        simp only [readCountedFiles] at hr
        obtain ⟨files, len, fits, wr⟩ := readFiles_some _ ws r hr
        cases hrest : r.rest with
        | cons _ _ => simp [hrest] at h
        | nil =>
          refine ⟨files, ⟨by rw [len]; exact wordNum_lt w, fits⟩, ?_⟩
          rw [filesWords, len, ofNat_wordNum, wr, hrest, List.append_nil]
  obtain ⟨files, fit, rfl⟩ := decoded
  exact ⟨files, fit, rfl, by rw [← frontEndWords_files fit]; exact h⟩

/-! ## The self program's function is `compileText` -/

/-- On the words of files, the self program's function gives the words of
`compileText`'s binary. -/
theorem compileWords_files {files : List SourceFile} (fit : FilesFit files) :
    compileWords (frontEndWords grammar (filesWords files)) = binaryWords (compileText files) := by
  rw [frontEndWords_files fit, compileText]
  cases sourceProgramFiles files with
  | none => rfl
  | some sp => rfl

/-- Words the self program's function accepts are the words of files, and
its output is the words of `compileText`'s binary for them. -/
theorem compileWords_some {words out : List (BitVec 32)} (h : compileWords (frontEndWords grammar words) = some out) :
    ∃ files binary, FilesFit files ∧ words = filesWords files ∧ compileText files = some binary ∧
      binaryWords (some binary) = some out := by
  cases hf : frontEndWords grammar words with
  | none => simp [hf, compileWords] at h
  | some sp =>
    obtain ⟨files, fit, rfl, hs⟩ := frontEndWords_some hf
    cases hc : compileSource sp with
    | none => simp [hf, compileWords, hc, binaryWords] at h
    | some binary =>
      refine ⟨files, binary, fit, rfl, by simp [compileText, hs, hc], ?_⟩
      simpa [hf, compileWords, hc] using h

end Lanius.Mini
