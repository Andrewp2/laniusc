module

public import Lanius.Mini.Extract.Types
public import Lanius.Mini.Extract.P.txExtract
public import Lanius.Mini.Extract.P.txPrelude
public import Lanius.Mini.Extract.P.txOptionPath
public import Lanius.Mini.Extract.P.txOption
public import Lanius.Mini.Extract.P.txBox
public import Lanius.Mini.Extract.P.txUsize
public import Lanius.Mini.Extract.P.txBool
public import Lanius.Mini.Extract.P.txLeanOption
public import Lanius.Mini.Extract.P.txPublicImport
public import Lanius.Mini.Extract.P.txPublicSection
public import Lanius.Mini.Extract.P.txPartHead2
public import Lanius.Mini.Extract.P.txPartTail4
public import Lanius.Mini.Extract.P.txErrNest
public import Lanius.Mini.Extract.P.txErrMutualPrelude
public import Lanius.Mini.Extract.P.txErrFn0
public import Lanius.Mini.Extract.P.txErrPattern0
public import Lanius.Mini.Extract.P.txErrPattern
public import Lanius.Mini.Extract.P.txOpXor
public import Lanius.Mini.Extract.P.txOpEq
public import Lanius.Mini.Extract.P.txOpPlus
public import Lanius.Mini.Extract.P.txKwInstance
public import Lanius.Mini.Extract.P.txKwLet
public import Lanius.Mini.Extract.P.txKwUniverse
public import Lanius.Mini.Extract.P.txLeanMax
public import Lanius.Mini.Extract.P.txLeanLength
public import Lanius.Mini.Extract.P.txLeanSetWidth
public import Lanius.Mini.Extract.P.txLeanIf
public import Lanius.Mini.Extract.P.txLeanThen
public import Lanius.Mini.Extract.P.txLeanDef
public import Lanius.Mini.Extract.P.txLeanExpose
public import Lanius.Mini.Extract.P.txLeanTypeBinder
public import Lanius.Mini.Extract.P.txNameMinus
public import Lanius.Mini.Extract.P.txNameSingle
public import Lanius.Mini.Extract.P.txErrLiteral1
public import Lanius.Mini.Extract.P.txErrCast1
public import Lanius.Mini.Extract.P.txErrMatch1
public import Lanius.Mini.Extract.P.txErrAssign
public import Lanius.Mini.Extract.P.txErrListOp0
public import Lanius.Mini.Extract.P.txErrListOp
public import Lanius.Mini.Extract.P.txLeanKeywords4
public import Lanius.Mini.Extract.P.txLeanKeywords9
public import Lanius.Mini.Extract.P.txLeanKeywords15
public import Lanius.Mini.Extract.P.txSpecEmpty0
public import Lanius.Mini.Extract.P.txSpecSingle1
public import Lanius.Mini.Extract.P.txSpecGet3
public import Lanius.Mini.Extract.P.txSpecGet4
public import Lanius.Mini.Extract.P.txSpecGetOr3
public import Lanius.Mini.Extract.P.txProofGetOr3
public import Lanius.Mini.Extract.P.txProofGetOr
public import Lanius.Mini.Extract.P.txHeaderA2
public import Lanius.Mini.Extract.P.txHeaderB7
public import Lanius.Mini.Extract.P.txHeaderB12
public import Lanius.Mini.Extract.P.txHeaderB27
public import Lanius.Mini.Extract.P.txHeaderC3
public import Lanius.Mini.Extract.P.txHeaderC10
public import Lanius.Mini.Extract.P.txTerminationFuel1
public import Lanius.Mini.Extract.P.txErrInlineExternal1
public import Lanius.Mini.Extract.P.exDrop
public import Lanius.Mini.Extract.P.exStrip
public import Lanius.Mini.Extract.P.exLowerFirst
public import Lanius.Mini.Extract.P.exFirstOr
public import Lanius.Mini.Extract.P.exStart
public import Lanius.Mini.Extract.P.exKeepGap
public import Lanius.Mini.Extract.P.exTyEq
public import Lanius.Mini.Extract.P.exTailOp
public import Lanius.Mini.Extract.P.exReadParams
public import Lanius.Mini.Extract.P.exReadItems
public import Lanius.Mini.Extract.P.exFileItems
public import Lanius.Mini.Extract.P.exShapes
public import Lanius.Mini.Extract.P.exAtom
public import Lanius.Mini.Extract.P.exWithErrs
public import Lanius.Mini.Extract.P.exInfixAssoc
public import Lanius.Mini.Extract.P.exFindMethod
public import Lanius.Mini.Extract.P.exSpecRule
public import Lanius.Mini.Extract.P.exIdentStart
public import Lanius.Mini.Extract.P.exAnyIn
public import Lanius.Mini.Extract.P.exCtorPayloads
public import Lanius.Mini.Extract.P.exShapesOf
public import Lanius.Mini.Extract.P.exListElem
public import Lanius.Mini.Extract.P.exBoxedOrNone
public import Lanius.Mini.Extract.P.exWordOp
public import Lanius.Mini.Extract.P.exAssigned
public import Lanius.Mini.Extract.P.exKeywordErrs
public import Lanius.Mini.Extract.P.exExpose
public import Lanius.Mini.Extract.P.exSpecStatement
public import Lanius.Mini.Extract.P.exAddDef
public import Lanius.Mini.Extract.P.exCrcBit
public import Lanius.Mini.Extract.P.exEndsPart
public import Lanius.Mini.Extract.P.exUnitWheres
public import Lanius.Mini.Extract.P.exFlushRun
public import Lanius.Mini.Extract.P.exByLastOne
public import Lanius.Mini.Extract.P.exCxFn
public import Lanius.Mini.Extract.P.exCxMethods
public import Lanius.Mini.Extract.P.exNamedIf
public import Lanius.Mini.Extract.P.exItemErr
public import Lanius.Mini.Extract.P.Inline_exSplitAt
public import Lanius.Mini.Extract.P.Inline_exIdentPrefixAt
public import Lanius.Mini.Extract.P.Inline_xpCast
public import Lanius.Mini.Extract.P.Inline_xpCompare
public import Lanius.Mini.Extract.P.Inline_xpContractsNone
public import Lanius.Mini.Extract.P.Inline_xpExprStmt
public import Lanius.Mini.Extract.P.Inline_xpLetInit
public import Lanius.Mini.Extract.P.Inline_xpModTail
public import Lanius.Mini.Extract.P.Inline_xpPathMore
public import Lanius.Mini.Extract.P.Inline_xpPatternPlain
public import Lanius.Mini.Extract.P.Inline_xpShift

/-! Generated by formal/tools/extract.py from formal/lani/mini/extract.lani. Do not edit.

Shallow extraction: each Lanius function is the Lean definition of the same
name (snake_case becomes camelCase, methods become `Type.method`, list
operations become `Lists.name` with a spec theorem). `usize` is `Nat`, `i32` is
`BitVec 32`, `u8` is `UInt8`, `List<T>` is `List T`, `Box<T>` is `T`. The
prelude's `plus`/`minus`/`times` panic instead of wrapping, so they are
`+`/`-`/`*` on `Nat` for every run that returns.

The definitions are in 106 parts, `.P0` on, in source order, whose bodies
are hidden from other modules: a proof that unfolds one imports its part with
`import all`, so that it is rebuilt only when that part changes. -/
