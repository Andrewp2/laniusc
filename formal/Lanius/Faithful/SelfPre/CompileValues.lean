module

public import Lanius.Faithful.SelfPre.Values
public import Lanius.Faithful.SelfPre.NB
public import Lanius.Faithful.SelfPre.TS
public import Lanius.Faithful.SelfPre.CompileTypes
public import Lanius.Faithful.SelfPre.CompileEvalTypes
public import Lanius.Faithful.SelfPre.CompileNeeds
public import Lanius.Faithful.SelfPre.CompileSlots
public import Lanius.Faithful.SelfPre.EvalSlots
public import Lanius.Mini.Room
import all Lanius.Mini.Compiler.P.BinOp_annihilates
import all Lanius.Mini.Compiler.P.BinOp_commutes
import all Lanius.Mini.Compiler.P.BinOp_folds
import all Lanius.Mini.Compiler.P.BinOp_number
import all Lanius.Mini.Compiler.P.BinOp_unit
import all Lanius.Mini.Compiler.P.CmpOp_number
import all Lanius.Mini.Compiler.P.CmpOp_test
import all Lanius.Mini.Compiler.P.DivOp_number
import all Lanius.Mini.Compiler.P.Syscall_number
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.FOp_size
import all Lanius.Mini.Compiler.P.FloatTy_mask
import all Lanius.Mini.Compiler.P.FloatTy_number
import all Lanius.Mini.Compiler.P.FloatTy_rexSize
import all Lanius.Mini.Compiler.P.FloatTy_signBit
import all Lanius.Mini.Compiler.P.FloatTy_signWord
import all Lanius.Mini.Compiler.P.Instr_size
import all Lanius.Mini.Compiler.P.Expr_agrees
import all Lanius.Mini.Compiler.P.argsAgree
import all Lanius.Mini.Compiler.P.FArith_opcode
import all Lanius.Mini.Compiler.P.FCmp_predicate
import all Lanius.Mini.Compiler.P.FOp_bytes
import all Lanius.Mini.Compiler.P.FOp_opcodeBytes
import all Lanius.Mini.Compiler.P.bumpBytes
import all Lanius.Mini.Compiler.P.floatOperands
import all Lanius.Mini.Compiler.P.floatResult
import all Lanius.Mini.Compiler.P.frameMemoryBytes
import all Lanius.Mini.Compiler.P.pow2
import all Lanius.Mini.Compiler.P.FloatTy_rex
import all Lanius.Mini.Compiler.P.FloatTy_scalarPrefix
import all Lanius.Mini.Compiler.P.Instr_pieces
import all Lanius.Mini.Compiler.P.compileModule
import all Lanius.Mini.Compiler.P.importArities
import all Lanius.Mini.Compiler.P.objectFuncs
import all Lanius.Mini.Compiler.P.piecesFrom
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
import all Lanius.Mini.Compiler.P.Expr_literal
import all Lanius.Mini.Compiler.P.Func_agrees
import all Lanius.Mini.Compiler.P.Stmt_agrees
import all Lanius.Mini.Compiler.P.Stmt_kills
import all Lanius.Mini.Compiler.P.funcsAgree
import all Lanius.Mini.Compiler.P.validate
import all Lanius.Mini.Compiler.P.SrcType_floatTy
import all Lanius.Mini.Compiler.P.SrcType_isBool
import all Lanius.Mini.Compiler.P.SrcType_isChar
import all Lanius.Mini.Compiler.P.SrcType_isFloat
import all Lanius.Mini.Compiler.P.SrcType_isFloatAny
import all Lanius.Mini.Compiler.P.SrcType_isI32
import all Lanius.Mini.Compiler.P.SrcType_isInteger
import all Lanius.Mini.Compiler.P.SrcType_isIsize
import all Lanius.Mini.Compiler.P.SrcType_isPtr
import all Lanius.Mini.Compiler.P.SrcType_isScalar
import all Lanius.Mini.Compiler.P.SrcType_isSint
import all Lanius.Mini.Compiler.P.SrcType_isSintAny
import all Lanius.Mini.Compiler.P.SrcType_isStr
import all Lanius.Mini.Compiler.P.SrcType_isUint
import all Lanius.Mini.Compiler.P.SrcType_isUnit
import all Lanius.Mini.Compiler.P.SrcType_sintKind
import all Lanius.Mini.Compiler.P.SrcType_uintKind
import all Lanius.Mini.Compiler.P.SrcType_word
import all Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.UintTy_leastBits
import all Lanius.Mini.Compiler.P.UintTy_signedWord
import all Lanius.Mini.Compiler.P.UintTy_spare
import all Lanius.Mini.Compiler.P.boolBits
import all Lanius.Mini.Compiler.P.lookup
import all Lanius.Mini.Compiler.P.UintTy_isWide
import all Lanius.Mini.Compiler.P.UintTy_mask
import all Lanius.Mini.Compiler.P.Word_compute
import all Lanius.Mini.Compiler.P.Word_sameOperand
import all Lanius.Mini.Compiler.P.Word_test
import all Lanius.Mini.Compiler.P.Expr_narrow
import all Lanius.Mini.Compiler.P.FArith_number
import all Lanius.Mini.Compiler.P.FCmp_number
import all Lanius.Mini.Compiler.P.FOp_number
import all Lanius.Mini.Compiler.P.Word_keeps
import all Lanius.Mini.Compiler.P.Word_narrows
import all Lanius.Mini.Compiler.P.Word_number
import all Lanius.Mini.Compiler.P.absorbed
import all Lanius.Mini.Compiler.P.foldConstant
import all Lanius.Mini.Compiler.P.negateConstant
import all Lanius.Mini.Compiler.P.applyGuard
import all Lanius.Mini.Compiler.P.arithShiftRight
import all Lanius.Mini.Compiler.P.offsetOrArith
import all Lanius.Mini.Compiler.P.order
import all Lanius.Mini.Compiler.P.orderSint
import all Lanius.Mini.Compiler.P.orderUint
import all Lanius.Mini.Compiler.P.signKey
import all Lanius.Mini.Compiler.P.arithSint
import all Lanius.Mini.Compiler.P.arithUint
import all Lanius.Mini.Compiler.P.floatOp
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
import all Lanius.Mini.Compiler.P.armBodyScope
import all Lanius.Mini.Compiler.P.fieldPayload
import all Lanius.Mini.Compiler.P.unitPayload
import all Lanius.Mini.Compiler.P.armPayload
import all Lanius.Mini.Compiler.P.lowerArmFound
import all Lanius.Mini.Compiler.P.lowerArmStmt
import all Lanius.Mini.Compiler.P.lowerMatch
import all Lanius.Mini.Compiler.P.lowerMatchArm
import all Lanius.Mini.Compiler.P.lowerMatchArms
import all Lanius.Mini.Compiler.P.lowerMatchOn
import all Lanius.Mini.Compiler.P.armScope
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
import all Lanius.Mini.Compiler.P.assignAgrees
import all Lanius.Mini.Compiler.P.armGuard
import all Lanius.Mini.Compiler.P.assignFrom
import all Lanius.Mini.Compiler.P.lowerArm
import all Lanius.Mini.Compiler.P.lowerArmValue
import all Lanius.Mini.Compiler.P.lowerArms
import all Lanius.Mini.Compiler.P.Expr_constant
import all Lanius.Mini.Compiler.P.Expr_isConstant
import all Lanius.Mini.Compiler.P.Expr_isVar
import all Lanius.Mini.Compiler.P.Expr_isZero
import all Lanius.Mini.Compiler.P.Expr_unitOf
import all Lanius.Mini.Compiler.P.binaryConstant
import all Lanius.Mini.Compiler.P.compareConstant
import all Lanius.Mini.Compiler.P.constantIs
import all Lanius.Mini.Compiler.P.argBytes
import all Lanius.Mini.Compiler.P.arrayArg
import all Lanius.Mini.Compiler.P.arrayArgBefore
import all Lanius.Mini.Compiler.P.arrayArgChecked
import all Lanius.Mini.Compiler.P.arrayArgLocal
import all Lanius.Mini.Compiler.P.arrayArgPure
import all Lanius.Mini.Compiler.P.arrayArgSlice
import all Lanius.Mini.Compiler.P.arrayArgs
import all Lanius.Mini.Compiler.P.arrayCallCode
import all Lanius.Mini.Compiler.P.bindingBytes
import all Lanius.Mini.Compiler.P.blockLimit
import all Lanius.Mini.Compiler.P.Expr_isAtom
import all Lanius.Mini.Compiler.P.Expr_mentions
import all Lanius.Mini.Compiler.P.Expr_subst
import all Lanius.Mini.Compiler.P.allocAgrees
import all Lanius.Mini.Compiler.P.callAgrees
import all Lanius.Mini.Compiler.P.divideAgrees
import all Lanius.Mini.Compiler.P.factValue
import all Lanius.Mini.Compiler.P.frameAgrees
import all Lanius.Mini.Compiler.P.loadByteAgrees
import all Lanius.Mini.Compiler.P.loadWordAgrees
import all Lanius.Mini.Compiler.P.retAgrees
import all Lanius.Mini.Compiler.P.staticAgrees
import all Lanius.Mini.Compiler.P.storeByteAgrees
import all Lanius.Mini.Compiler.P.storeWordAgrees
import all Lanius.Mini.Compiler.P.sysAgrees
import all Lanius.Mini.Compiler.P.codeSize
import all Lanius.Mini.Compiler.P.compileExpr
import all Lanius.Mini.Compiler.P.Expr_temps
import all Lanius.Mini.Compiler.P.Expr_within
import all Lanius.Mini.Compiler.P.Stmt_temps
import all Lanius.Mini.Compiler.P.Stmt_within
import all Lanius.Mini.Compiler.P.allWithin
import all Lanius.Mini.Compiler.P.argSlots
import all Lanius.Mini.Compiler.P.argsRoom
import all Lanius.Mini.Compiler.P.argsTemps
import all Lanius.Mini.Compiler.P.arityIs
import all Lanius.Mini.Compiler.P.compileArgs
import all Lanius.Mini.Compiler.P.compileStmt
import all Lanius.Mini.Compiler.P.exprRoom
import all Lanius.Mini.Compiler.P.frameLimit
import all Lanius.Mini.Compiler.P.imageLimit
import all Lanius.Mini.Compiler.P.spend
import all Lanius.Mini.Compiler.P.stmtRoom
import all Lanius.Mini.Compiler.P.zeroLocals
import all Lanius.Mini.Compiler.P.Piece_render
import all Lanius.Mini.Compiler.P.Piece_size
import all Lanius.Mini.Compiler.P.compileModules
import all Lanius.Mini.Compiler.P.piecesSize
import all Lanius.Mini.Compiler.P.compileDeclared
import all Lanius.Mini.Compiler.P.compileLowered
import all Lanius.Mini.Compiler.P.compileOptimized
import all Lanius.Mini.Compiler.P.compileOr
import all Lanius.Mini.Compiler.P.compileSource
import all Lanius.Mini.Compiler.P.packWord
import all Lanius.Mini.Compiler.P.roundCons
import all Lanius.Mini.Compiler.P.roundEnd
import all Lanius.Mini.Compiler.P.usizeWords
import all Lanius.Mini.Compiler.P.SrcOp_lower
import all Lanius.Mini.Compiler.P.conjunction
import all Lanius.Mini.Compiler.P.disjunction
import all Lanius.Mini.Compiler.P.lowerScalarLocal
import all Lanius.Mini.Compiler.P.consArgs
import all Lanius.Mini.Compiler.P.declareFuncs
import all Lanius.Mini.Compiler.P.BinOp_compute
import all Lanius.Mini.Compiler.P.declareProgram
import all Lanius.Mini.Compiler.P.funcsReturn
import all Lanius.Mini.Compiler.P.lowBits
import all Lanius.Mini.Compiler.P.signedKey
import all Lanius.Mini.Compiler.P.elementAddress
import all Lanius.Mini.Compiler.P.lowerElement
import all Lanius.Mini.Compiler.P.lowerLoadWord
import all Lanius.Mini.Compiler.P.storeByteElement
import all Lanius.Mini.Compiler.P.addressBelow
import all Lanius.Mini.Compiler.P.elementBase
import all Lanius.Mini.Compiler.P.loadType
import all Lanius.Mini.Compiler.P.enumVariants
import all Lanius.Mini.Compiler.P.equality
import all Lanius.Mini.Compiler.P.evalDivide
import all Lanius.Mini.Compiler.P.evalDivision
import all Lanius.Mini.Compiler.P.evalNegate
import all Lanius.Mini.Compiler.P.evalThen
import all Lanius.Mini.Compiler.P.scalarCast
import all Lanius.Mini.Compiler.P.evalDivideSint
import all Lanius.Mini.Compiler.P.evalCall
import all Lanius.Mini.Compiler.P.evalHost
import all Lanius.Mini.Compiler.P.evalCast
import all Lanius.Mini.Compiler.P.evalNot
import all Lanius.Mini.Compiler.P.evalArm
import all Lanius.Mini.Compiler.P.evalSame
import all Lanius.Mini.Compiler.P.evalSlotLimit
import all Lanius.Mini.Compiler.P.dyingExtent
import all Lanius.Mini.Compiler.P.extentAfter
import all Lanius.Mini.Compiler.P.killPrefix
import all Lanius.Mini.Compiler.P.killPrefixAt
import all Lanius.Mini.Compiler.P.arith
import all Lanius.Mini.Compiler.P.floatApply
import all Lanius.Mini.Compiler.P.floatArith
import all Lanius.Mini.Compiler.P.floatCompare
import all Lanius.Mini.Compiler.P.floatOrder
import all Lanius.Mini.Compiler.P.Expr_extent
import all Lanius.Mini.Compiler.P.Stmt_extent
import all Lanius.Mini.Compiler.P.argsExtent
import all Lanius.Mini.Compiler.P.funcNeeds
import all Lanius.Mini.Compiler.P.sigs
import all Lanius.Mini.Compiler.P.sigsWith
import all Lanius.Mini.Compiler.P.UintTy_bits
import all Lanius.Mini.Compiler.P.amountGuard
import all Lanius.Mini.Compiler.P.guardAnd
import all Lanius.Mini.Compiler.P.guardOr
import all Lanius.Mini.Compiler.P.leftFalse
import all Lanius.Mini.Compiler.P.literalBelow
import all Lanius.Mini.Compiler.P.shiftGuard
import all Lanius.Mini.Compiler.P.shiftWidth
import all Lanius.Mini.Compiler.P.evalHostText
import all Lanius.Mini.Compiler.P.hostNewlineCode
import all Lanius.Mini.Compiler.P.hostRandomCode
import all Lanius.Mini.Compiler.P.hostTextCode
import all Lanius.Mini.Compiler.P.importOk
import all Lanius.Mini.Compiler.P.importsOk
import all Lanius.Mini.Compiler.P.indexGuard
import all Lanius.Mini.Compiler.P.indexOf
import all Lanius.Mini.Compiler.P.lowerIndex
import all Lanius.Mini.Compiler.P.iteThen
import all Lanius.Mini.Compiler.P.storeOne
import all Lanius.Mini.Compiler.P.firstFacts
import all Lanius.Mini.Compiler.P.killShared
import all Lanius.Mini.Compiler.P.leftTrue
import all Lanius.Mini.Compiler.P.compileProgram
import all Lanius.Mini.Compiler.P.linkedSize
import all Lanius.Mini.Compiler.P.roomAfter
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
import all Lanius.Mini.Compiler.P.Stmt_factsAfter
import all Lanius.Mini.Compiler.P.Stmt_ignores
import all Lanius.Mini.Compiler.P.Stmt_isBrk
import all Lanius.Mini.Compiler.P.Stmt_isCont
import all Lanius.Mini.Compiler.P.Stmt_isSkip
import all Lanius.Mini.Compiler.P.Stmt_jumps
import all Lanius.Mini.Compiler.P.assigned
import all Lanius.Mini.Compiler.P.longer
import all Lanius.Mini.Compiler.P.trimFacts
import all Lanius.Mini.Compiler.P.lowerAddress
import all Lanius.Mini.Compiler.P.lowerFree
import all Lanius.Mini.Compiler.P.lowerLoad
import all Lanius.Mini.Compiler.P.lowerStore
import all Lanius.Mini.Compiler.P.SrcExpr_lower
import all Lanius.Mini.Compiler.P.isOne
import all Lanius.Mini.Compiler.P.lowerApply
import all Lanius.Mini.Compiler.P.SrcStmt_declare
import all Lanius.Mini.Compiler.P.SrcStmt_returns
import all Lanius.Mini.Compiler.P.SrcType_declare
import all Lanius.Mini.Compiler.P.declareEnum
import all Lanius.Mini.Compiler.P.declareFunc
import all Lanius.Mini.Compiler.P.declareParams
import all Lanius.Mini.Compiler.P.declareStruct
import all Lanius.Mini.Compiler.P.keepIf
import all Lanius.Mini.Compiler.P.lowerBody
import all Lanius.Mini.Compiler.P.lowerFunc
import all Lanius.Mini.Compiler.P.lowerFuncCons
import all Lanius.Mini.Compiler.P.lowerFuncs
import all Lanius.Mini.Compiler.P.unitTail
import all Lanius.Mini.Compiler.P.withFrame
import all Lanius.Mini.Compiler.P.evalCallSig
import all Lanius.Mini.Compiler.P.evalChecked
import all Lanius.Mini.Compiler.P.evalCopy
import all Lanius.Mini.Compiler.P.evalFieldCopy
import all Lanius.Mini.Compiler.P.evalFieldOf
import all Lanius.Mini.Compiler.P.evalFieldType
import all Lanius.Mini.Compiler.P.evalPure
import all Lanius.Mini.Compiler.P.evalScalar
import all Lanius.Mini.Compiler.P.evalTyped
import all Lanius.Mini.Compiler.P.evalValues
import all Lanius.Mini.Compiler.P.hostByteCode
import all Lanius.Mini.Compiler.P.hostClockCode
import all Lanius.Mini.Compiler.P.hostReadCode
import all Lanius.Mini.Compiler.P.hostSleepCode
import all Lanius.Mini.Compiler.P.hostWriteCode
import all Lanius.Mini.Compiler.P.lowerCall
import all Lanius.Mini.Compiler.P.lowerCallSig
import all Lanius.Mini.Compiler.P.evalArrayElement
import all Lanius.Mini.Compiler.P.evalArrayIndex
import all Lanius.Mini.Compiler.P.evalElement
import all Lanius.Mini.Compiler.P.evalIndex
import all Lanius.Mini.Compiler.P.evalLoadByte
import all Lanius.Mini.Compiler.P.evalPick
import all Lanius.Mini.Compiler.P.evalWordElement
import all Lanius.Mini.Compiler.P.isArrayLocal
import all Lanius.Mini.Compiler.P.lowerLetIndex
import all Lanius.Mini.Compiler.P.lowerLetIndexAny
import all Lanius.Mini.Compiler.P.lowerLoadType
import all Lanius.Mini.Compiler.P.lowerSetIndex
import all Lanius.Mini.Compiler.P.pickElement
import all Lanius.Mini.Compiler.P.fromI32
import all Lanius.Mini.Compiler.P.lowerField
import all Lanius.Mini.Compiler.P.lowerFieldAt
import all Lanius.Mini.Compiler.P.lowerFieldOf
import all Lanius.Mini.Compiler.P.lowerLocal
import all Lanius.Mini.Compiler.P.lowerNegate
import all Lanius.Mini.Compiler.P.lowerNegateTyped
import all Lanius.Mini.Compiler.P.lowerNot
import all Lanius.Mini.Compiler.P.lowerNotTyped
import all Lanius.Mini.Compiler.P.lowerUnsigned
import all Lanius.Mini.Compiler.P.negateFloat
import all Lanius.Mini.Compiler.P.negateSigned
import all Lanius.Mini.Compiler.P.sintToI32
import all Lanius.Mini.Compiler.P.atLeastOne
import all Lanius.Mini.Compiler.P.lowerAlloc
import all Lanius.Mini.Compiler.P.lowerReturn
import all Lanius.Mini.Compiler.P.lowerIf
import all Lanius.Mini.Compiler.P.lowerSetCall
import all Lanius.Mini.Compiler.P.lowerSetCallArgs
import all Lanius.Mini.Compiler.P.lowerThen
import all Lanius.Mini.Compiler.P.lowerWhile
import all Lanius.Mini.Compiler.P.whileLoop
import all Lanius.Mini.Compiler.P.lowerSet
import all Lanius.Mini.Compiler.P.lowerSetField
import all Lanius.Mini.Compiler.P.lowerSetFieldAt
import all Lanius.Mini.Compiler.P.lowerSetFieldOf
import all Lanius.Mini.Compiler.P.lowerSetValue
import all Lanius.Mini.Compiler.P.lowerSetValues
import all Lanius.Mini.Compiler.P.lowerShift
import all Lanius.Mini.Compiler.P.lowerSlice
import all Lanius.Mini.Compiler.P.lowerEnumValue
import all Lanius.Mini.Compiler.P.lowerTagged
import all Lanius.Mini.Compiler.P.viewedType
import all Lanius.Mini.Compiler.P.matchDst
import all Lanius.Mini.Compiler.P.SrcEff_types
import all Lanius.Mini.Compiler.P.evalIf
import all Lanius.Mini.Compiler.P.evalIfOf
import all Lanius.Mini.Compiler.P.evalLetIn
import all Lanius.Mini.Compiler.P.evalLetInOf
import all Lanius.Mini.Compiler.P.evalMatch
import all Lanius.Mini.Compiler.P.evalMatchOf
import all Lanius.Mini.Compiler.P.lowerDiscard
import all Lanius.Mini.Compiler.P.lowerIfEval
import all Lanius.Mini.Compiler.P.lowerLet
import all Lanius.Mini.Compiler.P.lowerLetCall
import all Lanius.Mini.Compiler.P.lowerLetEval
import all Lanius.Mini.Compiler.P.lowerReturnEval
import all Lanius.Mini.Compiler.P.lowerSetEval
import all Lanius.Mini.Compiler.P.lowerWhileEval
import all Lanius.Mini.Compiler.P.matchVariants
import all Lanius.Mini.Compiler.P.moduleExports
import all Lanius.Mini.Compiler.P.Stmt_rename
import all Lanius.Mini.Compiler.P.callPieces
import all Lanius.Mini.Compiler.P.funcCount
import all Lanius.Mini.Compiler.P.importIndices
import all Lanius.Mini.Compiler.P.linkProgram
import all Lanius.Mini.Compiler.P.moduleFirsts
import all Lanius.Mini.Compiler.P.renameFuncs
import all Lanius.Mini.Compiler.P.resolveModules
import all Lanius.Mini.Compiler.P.modulesOk
import all Lanius.Mini.Compiler.P.needCapped
import all Lanius.Mini.Compiler.P.needRound
import all Lanius.Mini.Compiler.P.needRoundAt
import all Lanius.Mini.Compiler.P.restNeeds
import all Lanius.Mini.Compiler.P.sameNeeds
import all Lanius.Mini.Compiler.P.needLimit
import all Lanius.Mini.Compiler.P.needsAfter
import all Lanius.Mini.Compiler.P.Stmt_deadBefore
import all Lanius.Mini.Compiler.P.Stmt_optimize
import all Lanius.Mini.Compiler.P.loopUnlessZero
import all Lanius.Mini.Compiler.P.optimizeFuncs
import all Lanius.Mini.Compiler.P.optimizeIte
import all Lanius.Mini.Compiler.P.optimizeLoop
import all Lanius.Mini.Compiler.P.optimizeProgram
import all Lanius.Mini.Compiler.P.Expr_optimize
import all Lanius.Mini.Compiler.P.iteOrSkip
import all Lanius.Mini.Compiler.P.optimizeAll
import all Lanius.Mini.Compiler.P.optimizeAssign
import all Lanius.Mini.Compiler.P.optimizeBinary
import all Lanius.Mini.Compiler.P.optimizeBoth
import all Lanius.Mini.Compiler.P.optimizeCompare
import all Lanius.Mini.Compiler.P.optimizeLeft
import all Lanius.Mini.Compiler.P.optimizeRight
import all Lanius.Mini.Compiler.P.optimizeSeq
import all Lanius.Mini.Compiler.P.pickBranch
import all Lanius.Mini.Compiler.P.optimizeNeg
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
import all Lanius.Mini.Compiler.P.compileFunc
import all Lanius.Mini.Compiler.P.roomFits
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
import all Lanius.Mini.Compiler.P.structFields
import all Lanius.Mini.Compiler.P.factDies
import all Lanius.Mini.Compiler.P.kill
import all Lanius.Mini.Compiler.P.killTail
import all Lanius.Mini.Compiler.P.mentionsAny
import all Lanius.Mini.Compiler.P.noneDies
import all Lanius.Mini.Compiler.P.substAll
import all Lanius.Mini.Compiler.P.usizeWidth
import all Lanius.Mini.Compiler.P.widthOf
import all Lanius.Mini.Compiler.P.SrcEff_sliceUses
import all Lanius.Mini.Compiler.P.SrcStmt_calleeNeed
import all Lanius.Mini.Compiler.P.SrcStmt_sliceUses
import all Lanius.Mini.Compiler.P.arrayBytesOf
import all Lanius.Mini.Compiler.P.blockRoom
import all Lanius.Mini.Compiler.P.declBytes
import all Lanius.Mini.Compiler.P.frameBlock
import all Lanius.Mini.Compiler.P.paramsRoom
import all Lanius.Mini.Compiler.P.withBudget
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

@[expose] public section

/-! # Byte lists of the compile side (F14)

The compiler's encoders build long literal byte lists (`bumpBytes` has 42
literal bytes and two `le64`s). `post_auto` bounds each cons cell's height
by its own `omega` call over every cost atom so far, about a minute for one
such function; these lemmas let the hand proofs in `tools/pre_certs.py`
(`POST_HAND`, compile section) count lengths instead: a byte list is as high
as it is long, a list primitive's cost does not depend on its arguments and
is at least 1, and an `le32`/`le64` costs at least its 4/8 bytes. -/

namespace Lanius.Faithful.SelfPre

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget

theorem pc_hb_u8 : ∀ l : List UInt8, hb l = l.length
  | [] => rfl
  | a :: l => by simp only [hb_cons, hb_uint8, List.length_cons, pc_hb_u8 l]; omega

/-- A list primitive's cost, which does not depend on its arguments (a constant
of its own, so that `simp` does not take the rewrite for a permutation). -/
def pcCons (n : Nat) : Nat := Cost_cons_of_u8 n 0 []
def pcSingle (n : Nat) : Nat := Cost_single_of_u8 n 0
def pcLe64 (n : Nat) : Nat := Cost_le64 n 0
def pcLe32 (n : Nat) : Nat := Cost_le32 n 0

theorem pc_cons_u8 (n : Nat) (a : UInt8) (l : List UInt8) : Cost_cons_of_u8 n a l = pcCons n := by
  cases n <;> rfl

theorem pc_single_u8 (n : Nat) (a : UInt8) : Cost_single_of_u8 n a = pcSingle n := by
  cases n <;> rfl

theorem pc_cons_u8_pos (n : Nat) : 1 ≤ pcCons n := by
  cases n <;> simp only [pcCons, Cost_cons_of_u8] <;> omega

theorem pc_single_u8_pos (n : Nat) : 1 ≤ pcSingle n := by
  cases n <;> simp only [pcSingle, Cost_single_of_u8] <;> omega

theorem pc_len_le64 (v : BitVec 64) : (le64 v).length = 8 := by rfl
theorem pc_len_le32 (v : BitVec 32) : (le32 v).length = 4 := by rfl

theorem pc_le64 (n : Nat) (v : BitVec 64) : Cost_le64 n v = pcLe64 n := by
  rcases n with _ | n
  · rfl
  · simp only [pcLe64, Cost_le64, pc_cons_u8, pc_single_u8]

theorem pc_le32 (n : Nat) (v : BitVec 32) : Cost_le32 n v = pcLe32 n := by
  rcases n with _ | n
  · rfl
  · simp only [pcLe32, Cost_le32, pc_cons_u8, pc_single_u8]

theorem pc_le64_ge (n : Nat) (h : pcLe64 n < 18446744073709551616) : 8 ≤ pcLe64 n := by
  rcases n with _ | n
  · exact absurd h (Nat.lt_irrefl _)
  · simp only [pcLe64, Cost_le64, pc_cons_u8, pc_single_u8] at h ⊢
    have := pc_cons_u8_pos n
    have := pc_single_u8_pos n
    omega

theorem pc_le32_ge (n : Nat) (h : pcLe32 n < 18446744073709551616) : 4 ≤ pcLe32 n := by
  rcases n with _ | n
  · exact absurd h (Nat.lt_irrefl _)
  · simp only [pcLe32, Cost_le32, pc_cons_u8, pc_single_u8] at h ⊢
    have := pc_cons_u8_pos n
    have := pc_single_u8_pos n
    omega

/-! The encoder's small numbers (for `valueFacts`, as `val_<T>_<f>`). -/

theorem val_FloatTy_number (x : FloatTy) : FloatTy.number x ≤ 1 := by cases x <;> decide
theorem val_FArith_number (x : FArith) : FArith.number x ≤ 3 := by cases x <;> decide
theorem val_FCmp_number (x : FCmp) : FCmp.number x ≤ 2 := by cases x <;> decide
theorem val_Word_number (x : Word) : Word.number x ≤ 1 := by cases x <;> decide
theorem val_Word_prefix (x : Word) : Word.prefix x ≤ 1 := by cases x <;> decide
theorem val_MemWidth_prefix (x : MemWidth) : MemWidth.prefix x ≤ 1 := by cases x <;> decide
theorem val_FloatTy_rexSize (x : FloatTy) : FloatTy.rexSize x ≤ 1 := by cases x <;> decide
theorem val_BinOp_size (x : BinOp) : BinOp.size x ≤ 13 := by cases x <;> decide
theorem val_DivOp_size (x : DivOp) (w : Word) : DivOp.size x w ≤ 5 := by cases x <;> cases w <;> decide
theorem val_FOp_size (x : FOp) : FOp.size x ≤ 22 := by
  cases x <;> simp only [FOp.size] <;>
    first | omega | (rename_i a b; cases a <;> cases b <;> decide) | (rename_i a _; cases a <;> decide)
theorem val_FOp_number (x : FOp) : FOp.number x ≤ 19 := by
  cases x <;> simp only [FOp.number] <;>
    first | omega | (rename_i a b; cases a <;> cases b <;> decide)

/-! Code sizes: a statement's code is at most 64 bytes per unit of its weight
(`Room.lean`), which `compileFunc`'s room check bounds by the image limit, so
the pc offsets the compile adds up stay small (the compile side's
`COMPILE_OVERRIDES` in `tools/pre_certs.py`). -/

theorem val_compileStmt (base pos brk cont : Nat) (s : Stmt) :
    codeSize (compileStmt base pos brk cont s) ≤ 64 * s.weight := codeSize_le base s pos brk cont
theorem val_compileExpr (base : Nat) (e : Expr) (depth : Nat) :
    codeSize (compileExpr base e depth) ≤ 40 * e.weight := codeSize_le_expr base e depth
theorem val_compileArgs (base : Nat) (args : List Expr) (k : Nat) :
    codeSize (compileArgs base args k) + 14 * args.length ≤ 64 * argsWeight args :=
  codeSize_le_args base args k
theorem val_zeroLocals (first count : Nat) : codeSize (zeroLocals first count) = 7 * count := by
  induction count generalizing first with
  | zero => simp [zeroLocals, codeSize]
  | succ c ih => rw [zeroLocals]; simp [codeSize, Instr.size, ih]; omega

/-! Temporaries: `compileFunc` adds a function's locals and its body's
temporaries before its room check, so the Mini compile's pre lemmas carry the
most temporaries of the functions they compile (`funcsTemps`, below `K`; where
it comes from: `Lanius.Open.LowerFuncsTemps`, `Lanius.Open.OptimizeKeepsNumbers`). -/

/-- The most temporaries any of the functions' bodies uses. -/
def funcsTemps : List Func → Nat
  | [] => 0
  | f :: fs => max (Stmt.temps f.body) (funcsTemps fs)

/-- `funcsTemps` of a lowering's result (`0` when it failed). -/
def optTemps : Option (List Func) → Nat
  | none => 0
  | some fs => funcsTemps fs

theorem paramsMax_le (fs : List SrcFunc) (k : Nat) (h : ∀ f ∈ fs, paramsSize f.params ≤ k) :
    paramsMax fs ≤ k := by
  induction fs with
  | nil => simp [paramsMax]
  | cons f fs ih =>
    simp only [paramsMax, Nat.max_le]
    exact ⟨h f (List.mem_cons_self ..), ih (fun g hg => h g (List.mem_cons_of_mem _ hg))⟩


/-- A string's ASCII test, as a bound (`pre_auto` simplifies an `if`'s condition
by `hb_simp`): `lower_str` lowers only ASCII strings, so `str_words`' bytes are
below 128 (its `COMPILE_OVERRIDES` invariant, `nb chars ≤ 255`). -/
@[hb_simp] theorem strAscii_eq_true (l : List Nat) : (strAscii l = true) = (nb l < 128) := by
  induction l with
  | nil => simp only [strAscii, nb_nil]; decide
  | cons c r ih =>
    simp only [strAscii, Bool.and_eq_true, decide_eq_true_eq, ih, nb_cons]
    show (c < 128 ∧ nb r < 128) = (max c (nb r) < 128)
    apply propext; omega

@[hb_simp] theorem strAscii_eq_false (l : List Nat) : (strAscii l = false) = (128 ≤ nb l) := by
  have h := strAscii_eq_true l
  apply propext
  cases hs : strAscii l
  · rw [hs] at h
    have : ¬ nb l < 128 := by rw [← h]; simp
    simp only [true_iff]; omega
  · rw [hs] at h
    have : nb l < 128 := by rw [← h]
    simp only [Bool.true_eq_false, false_iff]; omega


/-- A body's temporaries are at most its weight, which `compileFunc`'s room check
bounds (`roomFits_stmtRoom`): `compile_func`'s `locals + temps`. -/
theorem val_Stmt_temps (s : Stmt) : Stmt.temps s ≤ Stmt.weight s := Stmt.temps_le_weight s

/-- A round packs the bytes it does not leave (as `PreBinaryWordsV3`'s proof). -/
theorem packRound_count_rest : ∀ (k : Nat) (xs : List UInt8),
    (packRound xs k).count + (packRound xs k).rest.length = xs.length
  | 0, xs => by rw [packRound.eq_def]; simp
  | k + 1, [] => by rw [packRound.eq_def]; simp [roundEnd]
  | k + 1, [a] => by rw [packRound.eq_def]; simp [roundCons, roundEnd]
  | k + 1, [a, b] => by rw [packRound.eq_def]; simp [roundCons, roundEnd]
  | k + 1, [a, b, c] => by rw [packRound.eq_def]; simp [roundCons, roundEnd]
  | k + 1, a :: b :: c :: d :: rd => by
    have ih := packRound_count_rest k rd
    rw [packRound.eq_def]
    simp only [Nat.add_one_ne_zero, if_false, roundCons, Nat.add_sub_cancel, List.length_cons]
    omega

theorem packRounds_count_rest : ∀ (fuel : Nat) (xs : List UInt8),
    (packRounds xs fuel).count + (packRounds xs fuel).rest.length = xs.length
  | 0, xs => by rw [packRounds.eq_def]; simp only [if_true]; exact packRound_count_rest _ xs
  | fuel + 1, xs => by
    have hr := packRound_count_rest 4096 xs
    rw [packRounds.eq_def]
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel]
    split
    · exact hr
    · rename_i x more heq
      have ih := packRounds_count_rest fuel (packRound xs 4096).rest
      simp only [roundJoin]
      omega

/-- A round's byte count and what it leaves are at most its bytes (`round_cons`, `round_join`). -/
theorem val_packRound (xs : List UInt8) (k : Nat) :
    (packRound xs k).count ≤ hb xs ∧ hb (packRound xs k).rest ≤ hb xs := by
  have := packRound_count_rest k xs
  simp only [pc_hb_u8]; omega

theorem val_packRounds (xs : List UInt8) (fuel : Nat) : (packRounds xs fuel).count ≤ hb xs := by
  have := packRounds_count_rest fuel xs
  simp only [pc_hb_u8]; omega

/-- The entries `layout` lays out are at most where the codes end (`link_onto`'s entries). -/
theorem val_layout : ∀ (start : Nat) (codes : List Code), nb (layout start codes) ≤ start + codesSize codes
  | _, [] => by simp only [layout, nb_nil]; omega
  | start, c :: rest => by
    have := val_layout (start + Code.size c) rest
    simp only [layout, nb_cons, nb_nat, codesSize] at *
    omega

/-- The largest number in the codes' instructions (`encode_onto`'s `nb` premise). -/
def codesNb : List Code → Nat
  | [] => 0
  | c :: rest => max (nb c.instrs) (codesNb rest)

/-- A program's numbers are its functions' (`compile_program`'s `nb`, for `vals_compileFuncs`). -/
theorem nb_Program_eq (p : Program) : nb p = nb p.funcs := rfl

end Lanius.Faithful.SelfPre
