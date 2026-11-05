module

public import Lanius.Faithful.Gen.SelfTypes
public import Lanius.Faithful.Sim.CheckFast
public import Lanius.Faithful.Sim.DeclStep
import all Lanius.Faithful.Gen.SelfTypes
import all Lanius.Mini.Compiler.P.BinOp_compute
import all Lanius.Mini.Compiler.P.BinOp_size
import all Lanius.Mini.Compiler.P.Code_image
import all Lanius.Mini.Compiler.P.Code_size
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.FOp_size
import all Lanius.Mini.Compiler.P.FloatTy_mask
import all Lanius.Mini.Compiler.P.FloatTy_number
import all Lanius.Mini.Compiler.P.FloatTy_rexSize
import all Lanius.Mini.Compiler.P.FloatTy_signBit
import all Lanius.Mini.Compiler.P.FloatTy_signWord
import all Lanius.Mini.Compiler.P.Instr_encode
import all Lanius.Mini.Compiler.P.Instr_size
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
import all Lanius.Mini.Compiler.P.SrcEff_isSlice
import all Lanius.Mini.Compiler.P.SrcEff_passesSlices
import all Lanius.Mini.Compiler.P.SrcEff_sliceCall
import all Lanius.Mini.Compiler.P.SrcEff_types
import all Lanius.Mini.Compiler.P.SrcExpr_guard
import all Lanius.Mini.Compiler.P.SrcStmt_breaksOut
import all Lanius.Mini.Compiler.P.SrcStmt_declare
import all Lanius.Mini.Compiler.P.SrcStmt_depth
import all Lanius.Mini.Compiler.P.SrcStmt_lower
import all Lanius.Mini.Compiler.P.SrcStmt_returns
import all Lanius.Mini.Compiler.P.SrcType_declare
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
import all Lanius.Mini.Compiler.P.SrcType_same
import all Lanius.Mini.Compiler.P.SrcType_sintKind
import all Lanius.Mini.Compiler.P.SrcType_size
import all Lanius.Mini.Compiler.P.SrcType_uintKind
import all Lanius.Mini.Compiler.P.SrcType_word
import all Lanius.Mini.Compiler.P.UintTy_code
import all Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.UintTy_isWide
import all Lanius.Mini.Compiler.P.UintTy_leastBits
import all Lanius.Mini.Compiler.P.UintTy_signedWord
import all Lanius.Mini.Compiler.P.UintTy_spare
import all Lanius.Mini.Compiler.P.Word_prefix
import all Lanius.Mini.Compiler.P.argBase
import all Lanius.Mini.Compiler.P.arith
import all Lanius.Mini.Compiler.P.arithShiftRight
import all Lanius.Mini.Compiler.P.arrayCall
import all Lanius.Mini.Compiler.P.arrayCallSig
import all Lanius.Mini.Compiler.P.boolBits
import all Lanius.Mini.Compiler.P.boundsGuard
import all Lanius.Mini.Compiler.P.checkThen
import all Lanius.Mini.Compiler.P.codeSize
import all Lanius.Mini.Compiler.P.compileExpr
import all Lanius.Mini.Compiler.P.copyBytes
import all Lanius.Mini.Compiler.P.declareEnum
import all Lanius.Mini.Compiler.P.declareFunc
import all Lanius.Mini.Compiler.P.declareFuncs
import all Lanius.Mini.Compiler.P.declareParams
import all Lanius.Mini.Compiler.P.declareProgram
import all Lanius.Mini.Compiler.P.declareStruct
import all Lanius.Mini.Compiler.P.declaredSame
import all Lanius.Mini.Compiler.P.declaredVariants
import all Lanius.Mini.Compiler.P.effsSlice
import all Lanius.Mini.Compiler.P.encodeFrom
import all Lanius.Mini.Compiler.P.encodeOnto
import all Lanius.Mini.Compiler.P.entriesAt
import all Lanius.Mini.Compiler.P.enumVariants
import all Lanius.Mini.Compiler.P.epilogue
import all Lanius.Mini.Compiler.P.equality
import all Lanius.Mini.Compiler.P.evalIf
import all Lanius.Mini.Compiler.P.evalIfOf
import all Lanius.Mini.Compiler.P.evalLetIn
import all Lanius.Mini.Compiler.P.evalLetInOf
import all Lanius.Mini.Compiler.P.evalMatch
import all Lanius.Mini.Compiler.P.evalMatchOf
import all Lanius.Mini.Compiler.P.expectType
import all Lanius.Mini.Compiler.P.fieldOffset
import all Lanius.Mini.Compiler.P.floatApply
import all Lanius.Mini.Compiler.P.floatArith
import all Lanius.Mini.Compiler.P.floatCompare
import all Lanius.Mini.Compiler.P.floatOrder
import all Lanius.Mini.Compiler.P.frameSize
import all Lanius.Mini.Compiler.P.funcsReturn
import all Lanius.Mini.Compiler.P.funcsSize
import all Lanius.Mini.Compiler.P.funcsSlots
import all Lanius.Mini.Compiler.P.guardAll
import all Lanius.Mini.Compiler.P.guarded
import all Lanius.Mini.Compiler.P.keepIf
import all Lanius.Mini.Compiler.P.layout
import all Lanius.Mini.Compiler.P.linkFrom
import all Lanius.Mini.Compiler.P.linkObjects
import all Lanius.Mini.Compiler.P.linkOnto
import all Lanius.Mini.Compiler.P.loadAtBytes
import all Lanius.Mini.Compiler.P.loadWordBytes
import all Lanius.Mini.Compiler.P.lookup
import all Lanius.Mini.Compiler.P.lowBits
import all Lanius.Mini.Compiler.P.lowerAppend
import all Lanius.Mini.Compiler.P.lowerAs
import all Lanius.Mini.Compiler.P.lowerBody
import all Lanius.Mini.Compiler.P.lowerDiscard
import all Lanius.Mini.Compiler.P.lowerFunc
import all Lanius.Mini.Compiler.P.lowerFuncCons
import all Lanius.Mini.Compiler.P.lowerFuncs
import all Lanius.Mini.Compiler.P.lowerIfEval
import all Lanius.Mini.Compiler.P.lowerLet
import all Lanius.Mini.Compiler.P.lowerLetCall
import all Lanius.Mini.Compiler.P.lowerLetEval
import all Lanius.Mini.Compiler.P.lowerReturnEval
import all Lanius.Mini.Compiler.P.lowerSetEval
import all Lanius.Mini.Compiler.P.lowerWhileEval
import all Lanius.Mini.Compiler.P.matchVariants
import all Lanius.Mini.Compiler.P.norm
import all Lanius.Mini.Compiler.P.objectExports
import all Lanius.Mini.Compiler.P.objectFirsts
import all Lanius.Mini.Compiler.P.objectLayout
import all Lanius.Mini.Compiler.P.objectsLayout
import all Lanius.Mini.Compiler.P.objectsOk
import all Lanius.Mini.Compiler.P.objectsSlots
import all Lanius.Mini.Compiler.P.offsetOrArith
import all Lanius.Mini.Compiler.P.order
import all Lanius.Mini.Compiler.P.orderSint
import all Lanius.Mini.Compiler.P.orderUint
import all Lanius.Mini.Compiler.P.paramScope
import all Lanius.Mini.Compiler.P.paramTypes
import all Lanius.Mini.Compiler.P.paramsSize
import all Lanius.Mini.Compiler.P.paramsValid
import all Lanius.Mini.Compiler.P.prologue
import all Lanius.Mini.Compiler.P.relative
import all Lanius.Mini.Compiler.P.render
import all Lanius.Mini.Compiler.P.renderFuncs
import all Lanius.Mini.Compiler.P.renderObjects
import all Lanius.Mini.Compiler.P.signKey
import all Lanius.Mini.Compiler.P.signedKey
import all Lanius.Mini.Compiler.P.slotRange
import all Lanius.Mini.Compiler.P.slotVars
import all Lanius.Mini.Compiler.P.stackCheck
import all Lanius.Mini.Compiler.P.stmtEval
import all Lanius.Mini.Compiler.P.storeAtBytes
import all Lanius.Mini.Compiler.P.storeWordBytes
import all Lanius.Mini.Compiler.P.structFields
import all Lanius.Mini.Compiler.P.sysBytes
import all Lanius.Mini.Compiler.P.syscallLinuxByte
import all Lanius.Mini.Compiler.P.syscallLinuxHigh
import all Lanius.Mini.Compiler.P.syscallRsiBytes
import all Lanius.Mini.Compiler.P.thenCheck
import all Lanius.Mini.Compiler.P.trap
import all Lanius.Mini.Compiler.P.unitTail
import all Lanius.Mini.Compiler.P.withFrame
import all Lanius.Mini.Compiler.P.wordElement
import all Lanius.Mini.Compiler.P.wordType
import all Lanius.Mini.Compiler.P.wordWidth
import all Lanius.Mini.Compiler.P.wrap
import all Lanius.Mini.Compiler.Types

@[expose] public section

/-! Generated by formal/tools/faithful_pure.py. Do not edit. -/

namespace Lanius.Faithful.SelfPure

open Lanius.Mini
open Lanius.Faithful
open Lanius.Faithful.Self

noncomputable section

/-- The prims, as SelfRep has them. -/
def prims : Prims :=
  { boxed := [33, 43, 74, 147, 166, 173, 188, 217, 238, 254, 311, 320, 337, 402, 481, 482, 488, 670, 684, 685, 686, 687, 689, 691, 692, 739, 824, 826, 828, 833, 937, 984, 991, 1041, 1110, 1113, 1184, 1200, 1202, 1220, 1241, 1242, 1250, 1428, 1447, 1449, 1452, 1487, 1534, 1539, 1576, 1577, 1648, 1679, 1793, 1848, 1888, 2260, 2383, 2415, 2524, 2536],
    unbox := [10, 44, 59, 76, 78, 81, 87, 99, 103, 167, 174, 181, 183, 184, 256, 274, 276, 283, 307, 313, 321, 329, 356, 358, 485, 492, 493, 558, 575, 585, 588, 599, 651, 655, 666, 671, 676, 688, 690, 693, 741, 969, 977, 982, 983, 1017, 1066, 1228, 1229, 1279, 1347, 1446, 1541, 1650, 1657, 1672, 1692, 2139, 2169, 2235, 2348, 2410] }

/-- The functions outside the pure fragment: the driver, and the helpers
only the prims call. -/
def outside : List Nat := [
  0, -- app::main::w
  1, -- app::main::oracle_read
  2, -- app::main::oracle_put
  3, -- app::main::oracle_write
  4, -- app::main::oracle_write_one
  34, -- core::mem::typed_slice_from_storage<mini::selfhost::List<i32>>
  49, -- core::mem::size_of<mini::selfhost::List<i32>>
  72, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::Rule>>
  73, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Rule>>
  82, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::SrcFunc>>
  107, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::Sym>>
  108, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Sym>>
  109, -- core::mem::typed_slice_from_storage<mini::selfhost::List<usize>>
  111, -- core::mem::typed_slice_from_storage<mini::selfhost::List<u8>>
  112, -- core::mem::typed_slice_from_storage<mini::selfhost::SrcStmt>
  132, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Sig>>
  152, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::FileInput>>
  165, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::CTree>>
  253, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::FileInput>>
  278, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::List<mini::selfhost::List<usize>>>>
  279, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::List<mini::selfhost::List<usize>>>>
  280, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Token>>
  294, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::Func>>
  295, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Func>>
  296, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::SrcParam>>
  303, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::SrcType>>
  304, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::List<mini::selfhost::SrcType>>>
  305, -- core::mem::typed_slice_from_storage<mini::selfhost::SrcType>
  309, -- core::mem::size_of<mini::selfhost::Stmt>
  310, -- core::mem::typed_slice_from_storage<mini::selfhost::Stmt>
  342, -- core::mem::size_of<mini::selfhost::SrcType>
  401, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::Sig>>
  419, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::CTree>>
  449, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::FnDecl>>
  450, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::TypeDecl>>
  494, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::Expr>>
  495, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Expr>>
  497, -- core::mem::typed_slice_from_storage<mini::selfhost::SrcExpr>
  513, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::Binding>>
  514, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Binding>>
  515, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::SrcExpr>>
  522, -- core::mem::size_of<mini::selfhost::Expr>
  523, -- core::mem::typed_slice_from_storage<mini::selfhost::Expr>
  547, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::SrcEff>>
  549, -- core::mem::typed_slice_from_storage<mini::selfhost::SrcEff>
  578, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::SrcType>>
  750, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::Code>>
  751, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Code>>
  752, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::Arity>>
  753, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Arity>>
  757, -- core::mem::size_of<mini::selfhost::List<usize>>
  807, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::List<usize>>>
  823, -- core::mem::typed_slice_from_storage<mini::selfhost::List<u64>>
  827, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::SrcStructDecl>>
  829, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::SrcEnumDecl>>
  836, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::RawTok>>
  951, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::AliasDecl>>
  976, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Ty>>
  980, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::Ty>>
  981, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Inst>>
  986, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::MFunc>>
  1001, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::Inst>>
  1002, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::TypeDecl>>
  1003, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::FnDecl>>
  1004, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::ConstDecl>>
  1005, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::ConstDecl>>
  1006, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::ImportDecl>>
  1007, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::ImportDecl>>
  1008, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::AliasDecl>>
  1009, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::ImplDecl>>
  1010, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::ImplDecl>>
  1034, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::Instr>>
  1035, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Instr>>
  1095, -- core::mem::size_of<mini::selfhost::List<u64>>
  1097, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::SrcStructDecl>>
  1098, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::SrcEnumDecl>>
  1111, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::SymRule>>
  1112, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::SymRule>>
  1140, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::List<usize>>>
  1217, -- core::mem::typed_slice_from_storage<mini::selfhost::List<core::option::Option<usize>>>
  1222, -- core::mem::typed_slice_from_storage<mini::selfhost::Ty>
  1224, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::MParam>>
  1225, -- core::mem::typed_slice_from_storage<mini::selfhost::MStmt>
  1226, -- core::mem::size_of<mini::selfhost::Ty>
  1231, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::MFunc>>
  1261, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Fact>>
  1281, -- core::mem::size_of<mini::selfhost::List<u8>>
  1324, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::SrcArm>>
  1343, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::RawTok>>
  1344, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::Token>>
  1389, -- core::mem::size_of<mini::selfhost::List<core::option::Option<mini::selfhost::SrcType>>>
  1390, -- core::mem::typed_slice_from_storage<mini::selfhost::List<core::option::Option<mini::selfhost::SrcType>>>
  1423, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::SrcFunc>>
  1434, -- core::mem::size_of<mini::selfhost::SrcStmt>
  1455, -- core::mem::size_of<mini::selfhost::List<core::option::Option<usize>>>
  1459, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::MEff>>
  1460, -- core::mem::typed_slice_from_storage<mini::selfhost::MEff>
  1469, -- core::mem::size_of<mini::selfhost::MStmt>
  1470, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::MEff>>
  1482, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::MParam>>
  1566, -- core::mem::size_of<mini::selfhost::SrcExpr>
  1578, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::LocalTy>>
  1579, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::SrcEff>>
  1581, -- core::mem::size_of<mini::selfhost::SrcEff>
  1585, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::LocalTy>>
  1623, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::Fact>>
  1649, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::SrcParam>>
  1652, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::List<mini::selfhost::SrcType>>>
  1654, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::List<mini::selfhost::Ty>>>
  1668, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::SrcExpr>>
  1669, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::SrcArm>>
  1732, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::List<mini::selfhost::CTree>>>
  1733, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::List<mini::selfhost::CTree>>>
  1743, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Local>>
  1744, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::Local>>
  1759, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::BoundGoal>>
  1855, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::BoundGoal>>
  1951, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::List<mini::selfhost::Ty>>>
  2004, -- core::mem::size_of<mini::selfhost::MEff>
  2261, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::VariantAt>>
  2296, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::VariantTy>>
  2372, -- core::mem::typed_slice_from_storage<mini::selfhost::List<bool>>
  2408, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::VariantAt>>
  2469, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Bind>>
  2480, -- core::mem::size_of<mini::selfhost::List<bool>>
  2496, -- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::EffArm>>
  2500, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::VariantTy>>
  2567, -- core::mem::size_of<mini::selfhost::List<mini::selfhost::Bind>>
  2578 -- core::mem::size_of<mini::selfhost::List<mini::selfhost::EffArm>>
]

/-- The program's declarations, as `declareProgram` gives them. -/
def decls : SrcDecls where
  structs := [
    { id := 324, fields := [ty85, .bool] },
    { id := 322, fields := [ty86, .bool] },
    { id := 320, fields := [ty86, ty85] },
    { id := 317, fields := [ty287, ty335] },
    { id := 312, fields := [ty320, ty320] },
    { id := 311, fields := [ty20, ty292] },
    { id := 309, fields := [.ptr] },
    { id := 308, fields := [ty20, ty193, ty251] },
    { id := 304, fields := [(.uint .usize), ty154, (.uint .usize)] },
    { id := 302, fields := [.ptr] },
    { id := 300, fields := [(.uint .usize), ty335] },
    { id := 297, fields := [(.uint .usize), ty154, ty317, (.uint .usize), ty154] },
    { id := 289, fields := [(.uint .usize), ty154, ty317, ty108, ty348, (.uint .usize), ty154] },
    { id := 292, fields := [.ptr] },
    { id := 291, fields := [ty20, ty155] },
    { id := 286, fields := [(.uint .usize), (.uint .usize)] },
    { id := 284, fields := [ty27, ty86] },
    { id := 278, fields := [.ptr] },
    { id := 277, fields := [ty20, ty154] },
    { id := 270, fields := [ty154, ty329] },
    { id := 273, fields := [(.uint .usize), ty154, ty317, ty154, (.uint .usize), .bool, ty154, ty154] },
    { id := 272, fields := [ty156, ty18] },
    { id := 268, fields := [(.uint .usize), ty18, ty290, ty86] },
    { id := 266, fields := [ty154, ty154, (.uint .usize)] },
    { id := 262, fields := [ty320, .bool, (.uint .usize)] },
    { id := 264, fields := [.ptr] },
    { id := 257, fields := [ty27, ty20] },
    { id := 251, fields := [.ptr] },
    { id := 249, fields := [ty301, ty154] },
    { id := 250, fields := [ty27, ty20, ty155] },
    { id := 246, fields := [.ptr] },
    { id := 238, fields := [ty188, ty292] },
    { id := 241, fields := [.ptr] },
    { id := 240, fields := [ty20, (.uint .usize), ty154] },
    { id := 233, fields := [ty27, ty86] },
    { id := 228, fields := [ty128, ty27, ty27, ty155, ty27, ty251, (.uint .usize)] },
    { id := 227, fields := [.ptr] },
    { id := 226, fields := [(.uint .usize), ty9] },
    { id := 221, fields := [ty27, ty107] },
    { id := 216, fields := [ty95, ty94, ty95, ty91, (.uint .usize), ty20] },
    { id := 211, fields := [.ptr] },
    { id := 207, fields := [(.uint .usize), (.uint .usize), ty20] },
    { id := 200, fields := [ty128, ty158, ty158, ty229] },
    { id := 202, fields := [.ptr] },
    { id := 195, fields := [.ptr] },
    { id := 194, fields := [ty20, (.uint .usize)] },
    { id := 191, fields := [.ptr] },
    { id := 186, fields := [ty95, ty72] },
    { id := 184, fields := [.ptr] },
    { id := 183, fields := [(.uint .usize), ty91] },
    { id := 168, fields := [ty158, ty197] },
    { id := 180, fields := [.ptr] },
    { id := 170, fields := [ty188, ty189, ty194] },
    { id := 179, fields := [.ptr] },
    { id := 178, fields := [.ptr] },
    { id := 176, fields := [.ptr] },
    { id := 173, fields := [.ptr] },
    { id := 172, fields := [(.uint .usize), ty154] },
    { id := 165, fields := [.ptr] },
    { id := 164, fields := [(.uint .usize), (.uint .usize), (.uint .usize)] },
    { id := 159, fields := [ty95, ty9] },
    { id := 157, fields := [ty91, ty9] },
    { id := 150, fields := [.ptr] },
    { id := 149, fields := [(.uint .usize), (.uint .usize)] },
    { id := 147, fields := [.ptr] },
    { id := 142, fields := [(.uint .usize), ty155] },
    { id := 146, fields := [.ptr] },
    { id := 145, fields := [.ptr] },
    { id := 139, fields := [.ptr] },
    { id := 138, fields := [(.uint .usize), (.uint .usize), ty9, ty146] },
    { id := 132, fields := [ty86, ty139] },
    { id := 130, fields := [ty20, ty20, ty47, (.uint .usize)] },
    { id := 127, fields := [ty128, ty127] },
    { id := 103, fields := [ty27, ty128] },
    { id := 104, fields := [ty110, ty113, ty116, ty119, ty122, ty125, ty127] },
    { id := 126, fields := [.ptr] },
    { id := 124, fields := [.ptr] },
    { id := 123, fields := [ty27, ty27, ty85] },
    { id := 121, fields := [.ptr] },
    { id := 120, fields := [ty27, ty20, ty27, ty85] },
    { id := 118, fields := [.ptr] },
    { id := 117, fields := [ty27, ty27] },
    { id := 115, fields := [.ptr] },
    { id := 114, fields := [ty27, ty20, ty85, ty85] },
    { id := 112, fields := [.ptr] },
    { id := 111, fields := [ty27, ty20, .bool, ty27, ty85, ty27, ty85, ty85] },
    { id := 109, fields := [.ptr] },
    { id := 106, fields := [ty27, ty20, ty27, .bool, ty27, ty86, ty27, ty107] },
    { id := 108, fields := [.ptr] },
    { id := 101, fields := [ty20, ty1] },
    { id := 99, fields := [.ptr] },
    { id := 98, fields := [ty72, ty9, (.uint .usize), (.uint .usize), (.uint .usize)] },
    { id := 96, fields := [ty98, ty36] },
    { id := 95, fields := [.ptr] },
    { id := 88, fields := [(.uint .usize), (.uint .usize), (.uint .usize), ty95] },
    { id := 94, fields := [.ptr] },
    { id := 92, fields := [.ptr] },
    { id := 91, fields := [.ptr] },
    { id := 85, fields := [.ptr] },
    { id := 81, fields := [ty48, ty1] },
    { id := 71, fields := [ty75, ty79, ty36] },
    { id := 79, fields := [.ptr] },
    { id := 77, fields := [(.uint .usize), ty76] },
    { id := 75, fields := [.ptr] },
    { id := 73, fields := [(.uint .usize), ty72] },
    { id := 69, fields := [ty1, (.uint .usize), ty36] },
    { id := 53, fields := [ty68, ty20, ty36, ty36] },
    { id := 68, fields := [.ptr] },
    { id := 55, fields := [(.uint .usize), ty65] },
    { id := 67, fields := [.ptr] },
    { id := 45, fields := [ty50, ty1] },
    { id := 51, fields := [.ptr] },
    { id := 47, fields := [ty47, ty20, ty20] },
    { id := 50, fields := [.ptr] },
    { id := 49, fields := [(.uint .usize), (.uint .usize), ty20] },
    { id := 43, fields := [.ptr] },
    { id := 39, fields := [(.uint .usize), ty41] },
    { id := 42, fields := [.ptr] },
    { id := 4, fields := [ty34, ty36] },
    { id := 37, fields := [.ptr] },
    { id := 35, fields := [.ptr] },
    { id := 6, fields := [ty12, ty9, ty31] },
    { id := 32, fields := [.ptr] },
    { id := 30, fields := [.ptr] },
    { id := 29, fields := [.ptr] },
    { id := 27, fields := [.ptr] },
    { id := 24, fields := [ty20, ty15] },
    { id := 26, fields := [.ptr] },
    { id := 22, fields := [.ptr] },
    { id := 20, fields := [.ptr] },
    { id := 18, fields := [.ptr] },
    { id := 15, fields := [.ptr] },
    { id := 8, fields := [(.uint .usize), ty9] },
    { id := 13, fields := [.ptr] },
    { id := 12, fields := [.ptr] },
    { id := 11, fields := [.ptr] },
    { id := 1, fields := [.ptr] }]
  enums := [
    { id := 323, variants := [[ty386], []] },
    { id := 321, variants := [[ty384], []] },
    { id := 319, variants := [[ty382], []] },
    { id := 318, variants := [[ty365], []] },
    { id := 316, variants := [[ty378], []] },
    { id := 315, variants := [[ty30], []] },
    { id := 314, variants := [[ty23], []] },
    { id := 313, variants := [[ty327], []] },
    { id := 310, variants := [[ty369], []] },
    { id := 306, variants := [[ty367], []] },
    { id := 307, variants := [[], [ty365, ty366]] },
    { id := 305, variants := [[ty335], [], []] },
    { id := 303, variants := [[ty361], []] },
    { id := 301, variants := [[], [ty343, ty359]] },
    { id := 299, variants := [[ty357], []] },
    { id := 298, variants := [[ty146], []] },
    { id := 296, variants := [[ty354], []] },
    { id := 295, variants := [[ty328], []] },
    { id := 294, variants := [[ty18], []] },
    { id := 293, variants := [[ty329], []] },
    { id := 288, variants := [[ty349], []] },
    { id := 290, variants := [[], [ty346, ty347]] },
    { id := 287, variants := [[ty287], []] },
    { id := 285, variants := [[ty343], []] },
    { id := 283, variants := [[ty341], []] },
    { id := 282, variants := [[ty114], []] },
    { id := 281, variants := [[ty14], []] },
    { id := 280, variants := [[ty301], []] },
    { id := 279, variants := [[ty302], []] },
    { id := 275, variants := [[ty335], []] },
    { id := 276, variants := [[], [ty333, ty334]] },
    { id := 274, variants := [[], [ty290, ty194], []] },
    { id := 269, variants := [[ty330], []] },
    { id := 271, variants := [[ty15], [ty327], [(.uint .usize), ty18], [ty18], [(.uint .usize), ty154, ty23], [ty15, (.uint .usize)], [ty15, ty15], [ty15], [(.uint .usize), ty15], [ty193], [ty328]] },
    { id := 267, variants := [[ty325], []] },
    { id := 265, variants := [[ty323], []] },
    { id := 261, variants := [[ty321], []] },
    { id := 263, variants := [[], [.bool, ty319]] },
    { id := 260, variants := [[ty290], []] },
    { id := 259, variants := [[ty193], []] },
    { id := 258, variants := [[ty120], []] },
    { id := 256, variants := [[ty313], []] },
    { id := 255, variants := [[ty59], []] },
    { id := 254, variants := [[ty194], []] },
    { id := 253, variants := [[.bool], []] },
    { id := 252, variants := [[ty221], []] },
    { id := 247, variants := [[ty304], []] },
    { id := 248, variants := [[], [ty302, ty303]] },
    { id := 244, variants := [[ty298], []] },
    { id := 245, variants := [[], [ty155, ty297]] },
    { id := 243, variants := [[ty213], []] },
    { id := 242, variants := [[ty179], []] },
    { id := 237, variants := [[ty293], []] },
    { id := 239, variants := [[], [ty290, ty291]] },
    { id := 236, variants := [[], [ty193, ty191]] },
    { id := 235, variants := [[ty15], []] },
    { id := 234, variants := [[ty29], []] },
    { id := 232, variants := [[(.uint .usize)], [(.uint .usize)]] },
    { id := 231, variants := [[(.uint .usize), (.uint .usize)], [(.uint .usize)]] },
    { id := 230, variants := [[ty57], []] },
    { id := 229, variants := [[ty189], []] },
    { id := 225, variants := [[], [ty269, ty270]] },
    { id := 224, variants := [[ty31], []] },
    { id := 223, variants := [[ty12], []] },
    { id := 222, variants := [[ty32], []] },
    { id := 220, variants := [[ty264], []] },
    { id := 219, variants := [[ty42], []] },
    { id := 218, variants := [[(.uint .uint8)], []] },
    { id := 217, variants := [[ty8], []] },
    { id := 215, variants := [[ty258], []] },
    { id := 214, variants := [[ty161], []] },
    { id := 213, variants := [[ty155], []] },
    { id := 212, variants := [[ty154], []] },
    { id := 210, variants := [[], [ty146, ty246]] },
    { id := 209, variants := [[ty108], []] },
    { id := 208, variants := [[ty4], []] },
    { id := 206, variants := [[(.uint .uint64)], []] },
    { id := 205, variants := [[ty111], []] },
    { id := 204, variants := [[ty195], []] },
    { id := 201, variants := [[], [ty179, ty228]] },
    { id := 203, variants := [[ty34], []] },
    { id := 199, variants := [[ty158], []] },
    { id := 198, variants := [[ty20], []] },
    { id := 197, variants := [[ty113], []] },
    { id := 196, variants := [[ty181], [(.uint .usize)]] },
    { id := 193, variants := [[], [ty221, ty222]] },
    { id := 192, variants := [[ty76], []] },
    { id := 190, variants := [[], [(.uint .uint64), ty218]] },
    { id := 189, variants := [[ty72], []] },
    { id := 188, variants := [[ty150], []] },
    { id := 187, variants := [[], [ty29, ty24]] },
    { id := 185, variants := [[ty211], []] },
    { id := 182, variants := [[], [ty203, ty204]] },
    { id := 181, variants := [[ty156], []] },
    { id := 167, variants := [[ty198], []] },
    { id := 169, variants := [[], [ty195, ty196]] },
    { id := 175, variants := [[], [(.uint .usize), ty154, ty15, ty190], [(.uint .usize), ty154, ty18, ty190], [(.uint .usize), ty154, ty156, ty18, ty190], [(.uint .usize), ty154, (.uint .usize), ty18, ty190], [(.uint .usize), ty154, (.uint .usize), ty154, ty23, ty190], [(.uint .usize), ty15], [(.uint .usize), (.uint .usize), ty15], [(.uint .usize), ty156, ty18], [ty190, ty190], [ty15, ty190, ty190], [ty15, ty190], [ty15], [(.uint .usize), ty15, (.uint .usize), ty190], [ty15, ty15, (.uint .usize)], [(.uint .usize), ty154, ty15, ty15, ty190], [(.uint .usize), ty154, (.uint .usize), ty15, ty190], [(.uint .usize), (.uint .usize), ty18, (.uint .usize), ty190], [(.uint .usize), ty20, ty190], [(.uint .usize), ty15, ty15], [(.uint .usize), ty154, ty193, ty190], [(.uint .usize), ty193], [ty193, ty190, ty190], [ty193, ty190], [ty193], [ty193], [(.uint .usize), ty193, ty193], [(.uint .usize), (.uint .usize), ty193], [], [ty193], [], [], [(.uint .usize), ty154, (.uint .usize), .bool, (.uint .usize), ty154, ty190, ty190], [(.uint .usize), ty154], [ty193, ty193], [ty30, ty193, ty193]] },
    { id := 177, variants := [[ty15], [ty156, ty191], [ty14, ty192, ty192], [ty192], [ty192], [ty9, ty192], [(.uint .usize), ty192], [ty154, ty191], [ty154, (.uint .usize), ty191], [ty192, ty154, ty154, ty27, ty191], [ty28, ty192, ty192], [(.uint .usize)], [ty154, (.uint .usize)], [(.uint .usize), ty191], [ty192, ty154, ty192, ty192], [(.uint .usize), ty154, ty192, ty154, ty192], [(.uint .usize)], [ty20], [ty154, ty192], [ty192, (.uint .usize)], [ty192, ty192]] },
    { id := 174, variants := [[], [ty154]] },
    { id := 171, variants := [[], [ty186, ty187]] },
    { id := 166, variants := [[ty128], []] },
    { id := 162, variants := [[ty183], []] },
    { id := 163, variants := [[], [ty181, ty182]] },
    { id := 161, variants := [[ty47], []] },
    { id := 160, variants := [[ty9], []] },
    { id := 158, variants := [[ty177], []] },
    { id := 156, variants := [[ty175], []] },
    { id := 155, variants := [[ty91], []] },
    { id := 154, variants := [[ty148], []] },
    { id := 153, variants := [[ty101], []] },
    { id := 152, variants := [[ty94], []] },
    { id := 151, variants := [[ty66], []] },
    { id := 148, variants := [[], [ty161, ty162]] },
    { id := 141, variants := [[], [ty156, ty157]] },
    { id := 143, variants := [[], [ty154, ty153]] },
    { id := 144, variants := [[], [], [ty4], [], [], [], [ty8], [ty152], [(.uint .usize), ty153], [ty4], [ty152, (.uint .usize)], [], [ty152]] },
    { id := 140, variants := [[ty27], []] },
    { id := 137, variants := [[], [ty148, ty149]] },
    { id := 136, variants := [[ty95], []] },
    { id := 135, variants := [[(.uint .usize)], []] },
    { id := 134, variants := [[ty68], []] },
    { id := 133, variants := [[ty131], []] },
    { id := 131, variants := [[ty140], []] },
    { id := 129, variants := [[ty85], []] },
    { id := 128, variants := [[ty96], []] },
    { id := 102, variants := [[ty129], []] },
    { id := 125, variants := [[], [ty27, ty126]] },
    { id := 122, variants := [[], [ty123, ty124]] },
    { id := 119, variants := [[], [ty120, ty121]] },
    { id := 116, variants := [[], [ty117, ty118]] },
    { id := 113, variants := [[], [ty114, ty115]] },
    { id := 110, variants := [[], [ty111, ty112]] },
    { id := 105, variants := [[], [ty108, ty109]] },
    { id := 107, variants := [[], [ty86, ty106]] },
    { id := 100, variants := [[ty104], []] },
    { id := 97, variants := [[], [ty101, ty102]] },
    { id := 86, variants := [[ty98], []] },
    { id := 87, variants := [[], [ty96, ty97]] },
    { id := 89, variants := [[], [(.uint .usize), ty91], [ty92, ty92], [ty91, ty92, ty92], [ty91, ty92], [(.uint .usize), (.uint .usize), (.uint .usize), ty94], [ty94], [], [], [(.uint .usize), (.uint .usize), ty91], [(.uint .usize), ty91], [ty91, ty91], [ty57, (.uint .usize), ty91], [ty57, ty91, ty91], [ty54, ty58, (.uint .usize), ty91, ty91], [ty62, (.uint .usize), ty94], [(.uint .usize), (.uint .usize)], [(.uint .usize), (.uint .usize)]] },
    { id := 93, variants := [[], [ty91, ty93]] },
    { id := 90, variants := [[(.uint .uint64)], [(.uint .usize)], [ty90], [ty54, ty55, ty90, ty90], [ty54, ty56, ty90, ty90], [ty61, ty90, ty90]] },
    { id := 82, variants := [[ty86], []] },
    { id := 83, variants := [[], [ty85, ty84]] },
    { id := 84, variants := [[ty45], [(.uint .usize), ty84]] },
    { id := 80, variants := [[ty82], []] },
    { id := 70, variants := [[ty80], []] },
    { id := 76, variants := [[], [ty77, ty78]] },
    { id := 78, variants := [[], [ty72, ty6]] },
    { id := 72, variants := [[], [ty73, ty74]] },
    { id := 74, variants := [[], [ty9, ty5]] },
    { id := 52, variants := [[ty69], []] },
    { id := 54, variants := [[], [ty66, ty67]] },
    { id := 56, variants := [[], [ty63, ty64]] },
    { id := 57, variants := [[(.uint .uint64)], [(.uint .usize)], [(.uint .usize)], [], [ty54, ty55, (.uint .usize)], [ty54, ty56, (.uint .usize)], [(.uint .usize)], [(.uint .usize)], [(.uint .usize), ty20, (.uint .usize), (.uint .usize)], [ty20], [(.uint .usize)], [], [(.uint .usize)], [ty57], [ty57, (.uint .usize)], [ty54, ty58, (.uint .usize)], [ty61, (.uint .usize)], [ty62, (.uint .usize)], [(.uint .usize)], [(.uint .usize)]] },
    { id := 66, variants := [[], [], [], [], []] },
    { id := 63, variants := [[ty8, ty59], [ty8, ty60], [ty8, ty54], [], []] },
    { id := 65, variants := [[], [], []] },
    { id := 64, variants := [[], [], [], []] },
    { id := 62, variants := [[], [], [], []] },
    { id := 61, variants := [[], []] },
    { id := 60, variants := [[], [], [], [], [], []] },
    { id := 59, variants := [[], [], [], [], [], [], [], [], []] },
    { id := 58, variants := [[], []] },
    { id := 44, variants := [[ty51], []] },
    { id := 46, variants := [[], [ty48, ty49]] },
    { id := 48, variants := [[], [ty45, ty46]] },
    { id := 38, variants := [[], [ty42, ty43]] },
    { id := 40, variants := [[], [ty39, ty40]] },
    { id := 41, variants := [[(.uint .usize)], [(.uint .usize)]] },
    { id := 3, variants := [[ty37], []] },
    { id := 36, variants := [[], [(.uint .uint8), ty35]] },
    { id := 5, variants := [[], [ty32, ty33]] },
    { id := 16, variants := [[], [(.uint .usize), ty9, ty15, ty16], [(.uint .usize), ty9, ty18, ty16], [(.uint .usize), ty9, (.uint .usize), ty18, ty16], [(.uint .usize), ty9, (.uint .usize), ty18, ty16], [(.uint .usize), ty9, (.uint .usize), (.uint .usize), ty23, ty16], [(.uint .usize), ty15], [(.uint .usize), (.uint .usize), ty15], [(.uint .usize), (.uint .usize), ty18], [ty16, ty16], [ty15, ty16, ty16], [ty15, ty16], [ty15], [(.uint .usize), ty15, (.uint .usize), ty16], [(.uint .usize), ty15, ty15, ty16], [ty15, ty15, ty15], [ty15, ty15, (.uint .usize)], [(.uint .usize), ty9, ty15, ty15, ty16], [(.uint .usize), ty9, (.uint .usize), ty15, ty16], [(.uint .usize), ty15, ty15], [(.uint .usize), ty9, ty29, ty16], [(.uint .usize), ty29], [ty29, ty16, ty16], [ty29, ty16], [ty29], [ty29], [(.uint .usize), ty29, ty29], [(.uint .usize), (.uint .usize), ty29], [], [ty29], [], [], [(.uint .usize), (.uint .usize), (.uint .usize), .bool, (.uint .usize), ty9, ty16, ty16], [(.uint .usize), ty9], [(.uint .usize), (.uint .usize), ty18, (.uint .usize), ty16], [(.uint .usize), ty20, ty16], [ty29, ty29], [ty30, ty29, ty29]] },
    { id := 34, variants := [[], [], [], [], [], [], [], []] },
    { id := 28, variants := [[ty15], [(.uint .usize), ty24], [ty14, ty25, ty25], [ty25], [ty25], [ty9, ty25], [(.uint .usize), ty25], [ty9, ty24], [ty9, (.uint .usize), ty24], [ty25, ty9, ty9, ty27, ty24], [ty28, ty25, ty25], [(.uint .usize)], [ty9, (.uint .usize)], [ty25, ty9, ty25, ty25], [(.uint .usize), ty9, ty25, ty9, ty25], [(.uint .usize)], [(.uint .usize), ty20], [ty9, ty25], [ty9, ty25], [ty25, (.uint .usize)], [ty25, ty25]] },
    { id := 33, variants := [[], []] },
    { id := 31, variants := [[], [ty20, ty26]] },
    { id := 23, variants := [[], [ty21, ty22]] },
    { id := 25, variants := [[], [(.uint .usize), ty19]] },
    { id := 21, variants := [[], [ty15, ty17]] },
    { id := 17, variants := [[.i32], [.bool], [ty4, (.uint .uint64)], [(.uint .usize)], [(.uint .usize), (.uint .usize)], [ty13], [ty13], [ty14, ty13, ty13], [ty9, ty13], [], [(.uint .uint32)], [ty8, (.uint .uint64)]] },
    { id := 19, variants := [[], [], [], [], [], [], [], [], [], [], [], [], [], [], [], []] },
    { id := 7, variants := [[], [ty10, ty11]] },
    { id := 9, variants := [[], [], [ty4], [(.uint .usize), ty5], [(.uint .usize), ty6], [], [ty7], [ty7, (.uint .usize)], [], [], [], [ty8], [ty4], [(.uint .usize)], [], [ty7]] },
    { id := 14, variants := [[], []] },
    { id := 10, variants := [[], [], [], [], []] },
    { id := 2, variants := [[ty1], []] },
    { id := 0, variants := [[], [.i32, ty0]] }]
  statics := []

/-- `boxPair` of each `boxed` prim. -/
def boxPairs : List (Option (Nat × SrcType)) := [
  some (1, ty1),
  some (43, ty44),
  some (42, ty41),
  some (51, ty50),
  some (126, ty127),
  some (95, ty98),
  some (92, ty95),
  some (13, ty9),
  some (99, ty103),
  some (85, ty86),
  some (94, ty94),
  some (139, ty150),
  some (91, ty91),
  some (11, ty72),
  some (68, ty68),
  some (150, ty163),
  some (26, ty20),
  some (146, ty155),
  some (147, ty158),
  some (109, ty110),
  some (112, ty113),
  some (115, ty116),
  some (118, ty119),
  some (121, ty122),
  some (124, ty125),
  some (67, ty65),
  some (191, ty219),
  some (75, ty75),
  some (79, ty79),
  some (195, ty223),
  some (32, ty27),
  some (145, ty154),
  some (180, ty197),
  some (37, ty36),
  some (165, ty183),
  some (50, ty47),
  some (202, ty229),
  some (35, ty34),
  some (20, ty31),
  some (211, ty247),
  some (176, ty194),
  some (178, ty287),
  some (173, ty188),
  some (18, ty15),
  some (29, ty213),
  some (30, ty29),
  some (227, ty271),
  some (184, ty205),
  some (15, ty12),
  some (12, ty76),
  some (22, ty18),
  some (27, ty23),
  some (108, ty107),
  some (241, ty292),
  some (251, ty304),
  some (246, ty298),
  some (179, ty193),
  some (302, ty360),
  some (264, ty320),
  some (292, ty348),
  some (278, ty335),
  some (309, ty367)]

/-- The `sigEntries` of the functions, in blocks. -/
def sigBlocks : List (Nat × List SigEntry) := [
  (41, [none, none, none, none, none, some ([], ty1), some ([ty38], ty3), some ([ty44, ty1], ty38), some ([], ty44), some ([.i32, ty1], ty1), some ([ty0], ty1), some ([ty70], ty3), some ([ty37], ty70), some ([ty1], ty52), some ([ty44, ty51], ty38), some ([ty44, ty44], ty44), some ([], ty44), some ([], ty44), some ([], ty44), some ([], ty44), some ([], ty44), some ([], ty44), some ([], ty44), some ([], ty44), some ([], ty44), some ([], ty44), some ([], ty44), some ([], ty44), some ([], ty44), some ([], ty44), some ([], ty44), some ([], ty44), some ([], ty44), some ([ty1], ty0), none, some ([ty20, ty71], ty1), some ([ty36, (.uint .usize)], ty71), some ([ty34], .bool), some ([ty81, ty37], ty70), some ([ty37], ty81), some ([ty1, (.uint .usize)], ty52)]),
  (41, [some ([.i32], (.uint .usize)), some ([ty44, ty50], ty38), some ([ty44], ty43), some ([ty43], ty44), some ([ty42, ty44], ty44), some ([ty39, ty41], ty41), some ([], ty41), some ([], ty44), none, some ([], .unit), some ([ty1, ty1], ty1), some ([ty20], (.uint .usize)), some ([ty20], ty1), some ([ty36, (.uint .usize)], ty71), some ([ty71, ty71], ty71), some ([(.uint .usize), (.uint .usize)], (.uint .usize)), some ([ty9], .bool), some ([ty31], .bool), some ([ty33], ty34), some ([ty99, ty36], ty70), some ([ty103, ty103, ty80, ty34], ty99), some ([ty34], ty103), some ([ty34, ty80], ty81), some ([], ty75), some ([], ty79), some ([], ty50), some ([ty1], ty83), some ([ty48, ty52], ty52), some ([ty44, ty50], ty87), some ([(.uint .usize), ty86], ty38), some ([ty50], (.uint .usize)), none, none, some ([ty41], ty40), some ([(.uint .usize), (.uint .usize)], (.uint .usize)), some ([ty19], ty20), some ([], ty71), some ([ty35], ty36), some ([.i32, (.uint .usize), ty71], ty71), some ([(.uint .uint8), (.uint .uint8), (.uint .uint8), (.uint .uint8)], .i32), some ([ty16], ty31)]),
  (41, [none, some ([ty100], ty70), some ([], ty98), some ([ty136, ty99], ty99), some ([ty103, ty101, ty80, ty32], ty136), some ([ty102], ty103), some ([ty34, ty20], ty103), some ([ty34], ty20), some ([ty81, ty34], ty81), some ([ty32, ty80], ty81), some ([ty1], ty105), some ([ty20, ty105], ty83), some ([ty1], ty105), some ([ty48, ty50], ty50), some ([], ty86), some ([ty138, ty87], ty87), some ([ty44, ty47, ty20, ty20], ty138), some ([ty49], ty50), some ([(.uint .usize), ty85], ty130), some ([(.uint .usize), ty129, ty143], ty38), some ([(.uint .usize), ty86, ty131], ty143), some ([ty84], ty86), some ([ty27], ty127), some ([(.uint .usize), (.uint .usize)], (.uint .usize)), some ([ty47], (.uint .usize)), none, none, none, some ([], ty36), none, none, some ([ty100], ty100), some ([ty100, ty100], .bool), some ([ty70, ty100], ty70), some ([ty100], ty70), some ([ty96, ty98], ty98), some ([ty12], (.uint .usize)), some ([ty32], (.uint .usize)), some ([ty9], (.uint .usize)), some ([ty12], .bool), some ([ty31], .bool)]),
  (41, [some ([], (.uint .usize)), some ([(.uint .usize), (.uint .usize), (.uint .usize), ty147], ty136), some ([ty31], (.uint .usize)), some ([ty9, ty147], ty147), some ([(.uint .usize), (.uint .usize), ty147], ty147), some ([ty31, ty103, ty80, ty9, ty150, (.uint .usize)], ty147), some ([ty103, (.uint .usize), (.uint .usize)], ty103), some ([ty12, (.uint .usize), ty150], ty150), some ([], ty150), none, some ([], ty103), some ([ty101, ty103], ty103), some ([ty12], ty72), some ([ty20, (.uint .usize), (.uint .usize)], (.uint .usize)), some ([ty20], ty20), some ([ty34, ty20, (.uint .usize)], ty20), some ([], ty20), some ([ty34], (.uint .usize)), some ([ty12, ty80], ty81), some ([ty81, ty31], ty81), some ([ty9, ty80], ty81), some ([ty1, (.uint .usize)], ty105), some ([ty20, ty20, ty105], ty83), some ([ty1, (.uint .usize)], ty105), some ([ty50], ty49), some ([ty85, ty86], ty86), some ([ty44, (.uint .usize), ty41, (.uint .usize), ty139], ty141), some ([ty39], ty41), some ([ty140], ty138), none, some ([ty85], (.uint .usize)), some ([], (.uint .usize)), some ([(.uint .usize), ty85], ty87), some ([ty85, (.uint .usize)], ty85), some ([(.uint .usize), ty151, ty86], ty130), some ([(.uint .usize), ty86], ty151), some ([(.uint .usize), ty131, ty158, ty158], ty38), some ([ty113, (.uint .usize)], ty158), some ([ty128], ty113), some ([ty110, (.uint .usize)], ty158), some ([ty128], ty110)]),
  (41, [some ([(.uint .usize), ty131, ty130, ty86], ty143), none, some ([ty127], ty126), some ([ty46], ty47), some ([ty98], ty98), some ([ty98, ty98], .bool), some ([ty163, ty98], ty145), some ([ty98], ty163), some ([ty68, ty36], ty70), some ([ty98], ty97), some ([ty11], ty12), some ([ty31], ty20), some ([(.uint .usize), ty12, ty20], ty146), some ([], (.uint .usize)), some ([ty146], (.uint .usize)), some ([(.uint .usize), ty20, ty31], ty146), some ([ty72], (.uint .usize)), some ([ty5], ty72), some ([ty76], (.uint .usize)), some ([ty6], ty76), some ([ty7], ty9), some ([ty9], .bool), some ([(.uint .usize), (.uint .usize)], (.uint .usize)), some ([ty95], (.uint .usize)), some ([ty95], ty92), some ([ty91], ty94), some ([(.uint .usize), ty91, ty147], ty147), some ([ty15, ty150], ty91), some ([(.uint .usize), ty171, ty147], ty147), some ([ty150, ty15, ty9], ty171), some ([ty148, ty150], ty150), some ([ty150, ty18], ty91), some ([ty150, ty9, ty18], ty171), some ([(.uint .usize), (.uint .usize), (.uint .usize), ty171, ty147], ty147), some ([ty103, ty150, (.uint .usize), ty18, ty9], ty171), some ([ty150, ty9, (.uint .usize), ty18], ty171), some ([ty147, ty147], ty147), some ([ty150, ty173, (.uint .usize), ty23, ty9, (.uint .usize)], ty147), some ([ty150, (.uint .usize)], ty173), some ([ty173, ty150, ty15], ty147), some ([ty173, (.uint .usize), ty150, ty15], ty147)]),
  (41, [some ([ty103, ty150, ty173, (.uint .usize), ty18], ty147), some ([ty174, ty147, ty147], ty147), some ([ty150, ty15, ty9], ty174), some ([(.uint .usize), ty91, ty174, ty147], ty147), some ([ty171], ty147), some ([(.uint .usize), (.uint .usize), ty174, ty147], ty147), some ([ty91, ty91], ty91), some ([(.uint .usize), ty174, ty147], ty147), some ([ty174, ty174], ty174), some ([ty174, ty174], ty147), some ([(.uint .usize), ty174, ty174], ty147), some ([ty80, ty9, ty174, ty174], ty171), some ([ty9], ty7), some ([ty80, ty150, (.uint .usize), ty9, (.uint .usize), ty15, ty147], ty147), some ([ty80, ty150, (.uint .usize), (.uint .usize), ty15, ty15], ty147), some ([ty9, ty178, ty147], ty147), some ([ty29, ty103, ty80, ty150, (.uint .usize)], ty178), some ([(.uint .usize), ty173, ty178], ty147), some ([ty29, ty103, ty80, ty150, (.uint .usize)], ty178), some ([(.uint .usize), ty178, ty147, ty147], ty147), some ([(.uint .usize), ty178, ty147], ty147), some ([(.uint .usize), ty9, ty178], ty147), some ([ty178], ty147), some ([ty80, (.uint .usize), ty173, ty178, ty178], ty147), some ([(.uint .usize), ty173, (.uint .usize), ty178], ty147), some ([ty9], ty147), some ([ty178, (.uint .usize)], ty147), some ([ty150, ty173, (.uint .usize), (.uint .usize), .bool, (.uint .usize), ty9, (.uint .usize), ty147, ty147], ty147), some ([.bool, (.uint .usize), ty9, (.uint .usize), ty150], ty150), some ([.bool, (.uint .usize)], ty147), some ([ty9, ty9], .bool), some ([(.uint .usize), (.uint .usize), ty171, ty147], ty147), some ([(.uint .usize), ty20, ty147], ty147), some ([ty103], ty102), some ([], ty72), some ([ty9, ty72], ty72), some ([ty34, ty20], ty20), some ([ty20, ty20], .bool), some ([ty81, ty12], ty81), some ([ty31, ty80], ty81), some ([(.uint .usize), ty72, ty81], ty81)]),
  (41, [some ([ty72, ty80], ty81), some ([(.uint .usize), ty76, ty81], ty81), some ([ty76, ty80], ty81), some ([(.uint .usize), ty105], ty105), some ([ty180, ty20, ty104], ty83), some ([ty20], ty180), some ([(.uint .usize), ty105], ty105), none, some ([ty86], ty84), some ([ty44, (.uint .usize), ty39, ty41, (.uint .usize), ty139], ty141), some ([ty40], ty41), some ([ty139], .bool), some ([ty85, ty86], ty138), some ([(.uint .usize), ty86], ty87), some ([ty85], ty86), some ([ty86, (.uint .usize), ty85], ty85), some ([], ty45), some ([ty27, ty185], ty130), some ([(.uint .usize), ty27, ty86], ty185), some ([], ty27), some ([(.uint .usize), ty85, ty86], ty151), some ([ty85], ty85), some ([ty131], .bool), some ([(.uint .usize), ty128, ty158, ty199], ty38), some ([(.uint .usize), (.uint .usize), ty128, ty158, ty197, (.uint .usize)], ty199), some ([], ty197), some ([], ty158), some ([ty111, ty113, (.uint .usize)], ty158), some ([ty112], ty113), some ([ty108, ty110, (.uint .usize)], ty158), some ([ty109], ty110), some ([ty131, ty129], ty131), none, none, none, some ([ty95, ty205], ty95), some ([], ty205), some ([ty97], ty98), some ([ty96, ty96], .bool), some ([], ty68), some ([ty163, ty96], ty164)]),
  (41, [some ([ty66, ty68], ty68), some ([], ty163), some ([ty161, ty163], ty163), some ([], (.uint .usize)), some ([ty36], (.uint .usize)), some ([(.uint .usize), ty68], ty146), some ([ty68, ty36], ty70), none, none, none, some ([ty20, ty20], ty20), some ([ty29], ty20), some ([ty146, ty12, ty20], ty146), some ([(.uint .usize), (.uint .usize)], ty146), some ([ty20, (.uint .usize), ty9], (.uint .usize)), some ([ty146, ty20, ty31], ty146), none, none, none, some ([ty91], (.uint .usize)), some ([ty92], ty95), some ([ty94], (.uint .usize)), none, none, some ([ty94], ty93), some ([(.uint .usize), ty91, ty95], ty95), some ([ty13], ty15), some ([ty14, ty176, ty176, ty91, ty91], ty91), some ([ty15, ty150], ty176), some ([(.uint .usize), ty94, ty95], ty95), some ([ty9], .bool), some ([ty174], ty171), some ([ty150, ty15, ty9], ty171), some ([ty150], ty149), some ([ty17], ty18), some ([ty150, ty18, ty72], ty171), some ([ty9, (.uint .usize)], ty72), some ([ty103, (.uint .usize)], ty172), some ([ty150, ty101, ty18, ty9], ty171), some ([ty150, ty76, (.uint .usize), ty18], ty171), some ([ty150, ty148, (.uint .usize), ty23, ty9, (.uint .usize)], ty147)]),
  (41, [some ([ty148, ty150, (.uint .usize)], ty173), some ([ty149], ty150), some ([(.uint .usize), ty171], ty147), some ([ty148, (.uint .usize), ty150, ty15], ty147), some ([(.uint .usize), (.uint .usize), (.uint .usize), ty171], ty147), some ([ty175, ty9], ty174), some ([(.uint .usize), ty91, ty91, ty95], ty95), some ([ty91], ty91), some ([ty91], .bool), some ([ty91], ty90), some ([ty9], .bool), some ([ty9, ty4], .bool), some ([ty80, ty9], .bool), some ([(.uint .usize), ty9], .bool), none, some ([ty173], .bool), some ([ty80, ty150, (.uint .usize), (.uint .usize), ty178], ty178), some ([ty150, ty15, (.uint .usize)], ty178), some ([ty150, (.uint .usize), ty15], ty91), some ([ty80, (.uint .usize), ty173, ty9, ty174, ty147], ty147), some ([ty150, ty15], ty174), some ([ty80, ty173, ty174, ty150, ty15], ty147), some ([ty177, ty9, ty95], ty147), some ([ty29], .bool), some ([ty29, ty103, ty150, (.uint .usize)], ty178), some ([(.uint .usize), (.uint .usize)], ty94), some ([ty172, (.uint .usize), (.uint .usize), ty212], ty178), some ([ty103, ty80, ty150, ty213, (.uint .usize)], ty212), some ([ty24], ty213), some ([ty14, (.uint .usize), ty178, ty178], ty178), some ([ty25], ty29), some ([(.uint .usize), ty178], ty178), some ([(.uint .usize), ty178], ty178), some ([ty9, (.uint .usize), ty178], ty178), some ([ty9, ty212], ty178), some ([ty9, (.uint .usize), (.uint .usize), ty212], ty178), some ([(.uint .usize), ty9, ty9, ty178, ty147, (.uint .usize), (.uint .usize)], ty178), some ([ty103, ty80, ty150, (.uint .usize), (.uint .usize), ty9, (.uint .usize), ty76, ty27, ty213], ty147), some ([(.uint .usize), ty9, ty9], (.uint .usize)), some ([ty9], ty76), some ([ty27], (.uint .usize))]),
  (41, [some ([ty213], (.uint .usize)), some ([ty28, (.uint .usize), ty178, ty178], ty178), some ([ty80, ty150, (.uint .usize), (.uint .usize)], ty178), some ([(.uint .usize), ty9, ty178, ty178, ty178], ty178), some ([(.uint .usize), ty9, ty9, ty178, ty178], ty178), some ([ty103, ty80, ty216, (.uint .usize), ty29], ty178), some ([ty20, ty72, (.uint .usize), ty150], ty216), some ([(.uint .usize)], ty20), some ([ty9], ty72), some ([ty150, (.uint .usize), (.uint .usize)], ty178), some ([ty80, (.uint .usize), ty20, (.uint .usize)], ty178), some ([ty9], ty179), some ([ty80, ty148, ty9, (.uint .usize), ty178, ty178], ty147), some ([ty148, (.uint .usize), ty178, ty178], ty147), some ([ty148, (.uint .usize), (.uint .usize), ty177], ty147), some ([ty150, (.uint .usize), .bool, (.uint .usize), ty217, .bool, (.uint .usize), ty9, (.uint .usize), ty147, ty147], ty147), some ([ty76], (.uint .usize)), some ([ty76, (.uint .usize)], ty217), some ([ty9], .bool), some ([ty72, ty72], .bool), some ([ty76, ty76], .bool), some ([ty9], .bool), some ([ty9], .bool), some ([ty9], .bool), some ([ty9, ty8], .bool), some ([ty9, ty4], .bool), some ([ty9], .bool), some ([(.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize), ty95], ty95), some ([ty20], .bool), some ([ty219], (.uint .usize)), some ([ty20], ty219), some ([(.uint .usize), (.uint .usize), ty219, ty95], ty95), none, some ([ty72], ty5), some ([ty34, ty20, ty20], ty20), some ([ty29], ty72), some ([ty72, ty72], ty72), some ([(.uint .usize), ty72, ty80, ty217], ty81), some ([ty75, (.uint .usize)], ty217), some ([ty81, ty72], ty81), some ([(.uint .usize), ty76, ty80, ty220], ty81)]),
  (41, [some ([ty79, (.uint .usize)], ty220), some ([ty81, ty76], ty81), some ([ty223, ty20, (.uint .usize), (.uint .usize)], ty184), some ([], ty223), some ([ty20, ty20, (.uint .usize), ty183], ty47), some ([ty183], ty183), some ([ty223, ty20, ty20, (.uint .usize), ty183], ty183), some ([], ty223), some ([(.uint .usize), ty20], ty20), none, some ([ty44, (.uint .usize), (.uint .usize), ty41, (.uint .usize), ty139], ty141), some ([ty44, (.uint .usize), (.uint .usize), ty41, (.uint .usize), ty139], ty141), some ([ty20], .bool), some ([ty47], .bool), some ([(.uint .usize), ty85, ty86], ty87), some ([], ty128), some ([ty185, ty185], ty185), some ([(.uint .usize), ty27, ty85], ty185), some ([], (.uint .usize)), some ([(.uint .usize), ty85, ty85], ty151), some ([], (.uint .usize)), some ([ty127], .bool), some ([ty128, ty127], .bool), some ([ty110], .bool), some ([ty122], .bool), some ([ty128], ty122), some ([(.uint .usize), ty128, ty158, ty227, ty197], ty38), some ([(.uint .usize), ty128, ty227], ty227), some ([(.uint .usize), ty128, ty227, ty155], ty227), some ([(.uint .usize), ty128, ty158, ty155], ty227), some ([ty158], ty155), some ([ty197], ty155), some ([ty158, (.uint .usize)], ty200), some ([(.uint .usize), (.uint .usize), ty128, ty158, ty197, (.uint .usize), ty232], ty199), some ([(.uint .usize), ty128, ty156], ty232), some ([ty197, ty197], ty197), some ([ty27], .bool), some ([ty156, ty158], ty158), some ([], ty155), none, none]),
  (41, [some ([ty110, ty110], ty110), some ([ty113, ty113], ty113), some ([ty116, ty116], ty116), some ([ty128], ty116), some ([ty119, ty119], ty119), some ([ty128], ty119), some ([ty122, ty122], ty122), some ([ty125, ty125], ty125), some ([ty128], ty125), some ([ty127, ty127], ty127), some ([ty128], ty127), some ([(.uint .usize), ty91], ty95), some ([ty91], ty91), some ([ty91, ty205], ty91), some ([ty95, ty95, ty205], ty95), some ([ty91, ty95, ty95], ty95), some ([ty91, ty95], ty95), some ([ty94], ty94), some ([ty94, ty205], ty94), some ([ty95, ty205, ty95], .bool), some ([ty146], .bool), some ([(.uint .usize), ty95], ty146), some ([ty95], (.uint .usize)), some ([ty95, (.uint .usize), ty163, (.uint .usize)], .bool), some ([], (.uint .usize)), some ([ty63, ty65], ty65), some ([(.uint .usize), (.uint .usize)], ty65), some ([ty65, ty65], ty65), some ([(.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize), ty95], ty65), some ([ty65], (.uint .usize)), some ([ty68], ty67), some ([ty163], ty162), some ([(.uint .usize), (.uint .usize), ty68], ty146), some ([ty66], (.uint .usize)), some ([ty67], ty68), some ([(.uint .usize), ty68], ty20), some ([ty20, (.uint .usize), ty68, ty36], ty36), some ([ty20], ty19), some ([ty213], ty20), some ([ty20, (.uint .usize)], .bool), some ([ty9], (.uint .usize))]),
  (41, [some ([ty90], ty91), some ([ty93], ty94), none, none, some ([(.uint .usize)], ty95), none, some ([ty176, ty176], ty91), some ([ty91, ty91], ty91), some ([ty176], ty91), some ([ty176], ty91), some ([.bool], (.uint .uint64)), some ([ty4, (.uint .uint64)], ty176), some ([ty173], ty176), some ([ty173, (.uint .usize)], ty176), some ([ty176], ty176), some ([ty176], ty176), some ([ty14, ty176, ty176], ty176), some ([ty9, ty176], ty176), some ([ty8, (.uint .uint64)], ty176), some ([ty173, ty9], ty171), some ([ty173, (.uint .usize), ty9], ty171), none, none, none, some ([ty150, ty18, ty72], ty171), some ([ty150, (.uint .usize), ty217, ty18], ty171), some ([ty150, (.uint .usize), .bool, ty76, ty23, ty9, (.uint .usize)], ty147), some ([(.uint .usize), ty179, ty150, ty15], ty147), some ([ty72, (.uint .usize)], (.uint .usize)), some ([ty72, (.uint .usize)], ty179), none, none, some ([ty4], (.uint .usize)), some ([ty80, ty9], .bool), some ([(.uint .usize), ty72], .bool), some ([(.uint .usize), ty76], .bool), some ([ty80, ty148, ty9, (.uint .usize), ty178], ty178), some ([ty148, (.uint .usize), ty178], ty178), some ([(.uint .usize), ty91, ty175], ty177), some ([ty150, ty15, (.uint .usize), ty173], ty178), some ([ty150, ty15, (.uint .usize), ty173, (.uint .usize)], ty178)]),
  (41, [some ([ty148, ty91], ty91), some ([(.uint .usize), ty174, ty147], ty147), some ([ty173, ty9, ty174], ty174), some ([ty80, (.uint .usize), ty173, ty9, ty174, ty147], ty147), some ([ty175], ty174), some ([ty80, ty148, ty174, ty150, ty15], ty147), some ([ty213], .bool), some ([ty103, ty150, (.uint .usize), (.uint .usize), ty213], ty178), some ([], ty94), some ([ty91, ty94], ty94), some ([ty101, (.uint .usize), (.uint .usize), ty211], ty178), some ([(.uint .usize), (.uint .usize), ty211], ty178), some ([], (.uint .usize)), some ([ty177, ty212], ty212), none, some ([ty14, (.uint .usize), ty177, ty177], ty178), none, some ([(.uint .usize), ty177, ty176], ty178), some ([ty175], ty176), some ([ty175], ty176), some ([ty9, ty175], ty176), some ([ty9, ty72, ty211], ty178), some ([ty9, ty76, (.uint .usize), (.uint .usize), ty211], ty178), some ([(.uint .usize), ty9, ty9, ty177, ty95, (.uint .usize), (.uint .usize)], ty178), some ([ty103, ty80, ty216, (.uint .usize), (.uint .usize), ty9, (.uint .usize), ty29, ty213, ty147], ty147), some ([ty26], ty27), some ([], ty76), some ([ty28, (.uint .usize), ty177, ty177], ty178), some ([ty80, ty9, (.uint .usize)], ty178), some ([(.uint .usize), ty9, ty177, ty177, ty177], ty178), some ([(.uint .usize), ty9, ty9, ty177, ty177], ty178), some ([(.uint .usize), ty9, ty20, ty72, (.uint .usize), ty150], ty216), some ([ty148, (.uint .usize)], ty178), some ([ty36, (.uint .usize), ty20], .bool), some ([ty148, (.uint .usize), ty177, ty177], ty147), some ([ty148, (.uint .usize), ty177, ty177], ty147), some ([ty80, ty148, ty9, (.uint .usize), ty177, ty177], ty147), some ([(.uint .usize), ty9, (.uint .usize), (.uint .usize), ty178, ty178], ty147), some ([(.uint .usize), ty179, (.uint .usize), ty177], ty147), some ([(.uint .usize), .bool, (.uint .usize), ty171, (.uint .usize), ty147, ty147], ty147), some ([ty150, (.uint .usize), ty72, .bool, (.uint .usize), ty9], ty171)]),
  (41, [some ([ty8], (.uint .usize)), some ([ty218], ty219), some ([(.uint .uint64)], ty219), some ([(.uint .uint64), ty219], ty219), none, some ([(.uint .usize), (.uint .usize)], (.uint .usize)), some ([ty31, ty20], (.uint .usize)), some ([ty213], ty72), some ([.bool, ty80], ty81), some ([ty73, ty75], ty75), some ([ty73, ty75, (.uint .usize)], ty217), some ([ty74], ty75), some ([ty77, ty79], ty79), some ([ty77, ty79, (.uint .usize)], ty220), some ([ty78], ty79), some ([], ty183), some ([ty223, ty20, (.uint .usize)], ty224), some ([ty181, ty184], ty184), some ([(.uint .usize), ty181], ty181), some ([ty20, (.uint .usize)], ty20), some ([ty221, ty223], ty223), some ([], ty223), some ([], ty47), some ([ty20, ty20, ty181, ty183], ty47), some ([ty20, ty20, (.uint .usize), (.uint .usize)], ty20), some ([ty182], ty183), some ([ty181, ty183], ty183), some ([ty223, ty20, ty20, ty181, ty183], ty183), some ([ty44, (.uint .usize), (.uint .usize), ty45, ty47, ty41, (.uint .usize), ty139], ty141), some ([ty44, (.uint .usize), (.uint .usize), (.uint .usize), ty20, ty41, (.uint .usize), ty139], ty141), some ([(.uint .usize)], .bool), some ([ty87, ty87], ty87), some ([ty85], .bool), some ([ty85], ty86), some ([], ty110), some ([], ty113), some ([], ty116), some ([], ty119), some ([], ty122), some ([], ty125), some ([], ty127)]),
  (41, [some ([ty128, ty185], ty185), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([ty244], ty185), some ([(.uint .usize), ty27, ty85], ty244), some ([], (.uint .usize)), some ([ty225], ty185), some ([ty233, ty225], ty225), some ([ty27, ty85, .bool, ty27, ty85, ty85, ty151], ty233), some ([(.uint .usize), ty85], ty151), some ([], (.uint .usize)), some ([ty114], ty116), some ([ty45], ty20), some ([ty85, (.uint .usize)], ty45), some ([], (.uint .usize)), some ([(.uint .usize), ty27, ty151, ty85, ty85, ty85], ty185), some ([], (.uint .usize)), some ([ty27, ty151, ty85, ty185], ty185), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([ty27, ty151], ty185), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([ty27, ty20, ty151, ty85], ty185), some ([(.uint .usize), ty85], ty151), some ([], (.uint .usize)), some ([ty85], .bool), some ([ty85], ty85), some ([ty151], ty185), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([ty20], ty27), some ([], (.uint .usize)), some ([ty226, ty151], ty151), some ([ty127, ty27], .bool), some ([ty126], ty127), some ([ty128, ty27], .bool), some ([ty179], .bool), some ([ty20], ty179), some ([ty121], ty122)]),
  (41, [some ([(.uint .usize), ty230, ty197], ty231), some ([(.uint .usize), ty128, ty158, ty158], ty229), some ([ty34], ty38), some ([ty34, ty34], ty34), some ([ty158, .bool], ty227), some ([ty247], .bool), some ([(.uint .usize), (.uint .usize), ty128, ty158, ty247], ty247), some ([ty158], (.uint .usize)), some ([ty158], ty247), some ([(.uint .usize), ty128, ty158, ty154, ty155], ty227), some ([ty153], ty155), some ([(.uint .usize), ty128, ty158, ty227, ty155], ty227), some ([(.uint .usize), ty128, ty154], ty227), some ([ty154, ty155], ty155), some ([ty155], ty153), some ([ty157], ty158), some ([ty155, ty155], ty155), some ([ty188], ty155), some ([ty189], ty155), some ([ty194], ty155), some ([ty196], ty197), some ([ty158, ty158], ty158), some ([ty194], ty158), some ([ty195, ty197], ty197), some ([ty113, (.uint .usize)], ty233), some ([(.uint .usize), ty128, ty111, ty156], ty232), some ([ty251, ty156, ty128], ty232), some ([(.uint .usize), ty128, ty156], ty251), some ([ty158], ty157), some ([ty110], ty109), some ([ty113], ty112), some ([ty116], ty115), some ([ty115], ty116), some ([ty119], ty118), some ([ty118], ty119), some ([ty122], ty121), some ([ty125], ty124), some ([ty124], ty125), some ([ty91, (.uint .usize)], .bool), some ([ty91], ty91), some ([ty54, ty55, ty91, ty91], ty91)]),
  (41, [some ([ty54, ty56, ty91, ty91], ty91), some ([ty205, (.uint .usize)], ty91), some ([ty95, ty205], ty205), some ([ty95, ty95], .bool), some ([ty95, ty95], ty95), some ([ty91], ty234), some ([(.uint .uint64), ty95, ty95], ty95), some ([ty91, ty95, ty95], ty95), some ([(.uint .uint64), ty91, ty95], ty95), some ([ty95], .bool), some ([(.uint .usize), ty91, ty95], .bool), some ([ty95, ty95, ty205, ty95], .bool), some ([ty95, ty95, ty205, ty95], .bool), some ([ty91, ty95, ty95, ty205, ty95], .bool), some ([ty234, ty95, ty95, ty205, ty95], .bool), some ([ty91], ty234), some ([ty234], .bool), some ([ty91], .bool), some ([ty91, ty95, ty95], .bool), some ([(.uint .usize), (.uint .usize), (.uint .usize), ty94, ty95], .bool), some ([ty94, ty95], .bool), some ([ty95], .bool), some ([ty95], .bool), some ([(.uint .usize), (.uint .usize), ty91, ty95], .bool), some ([(.uint .usize), ty91, ty95], .bool), some ([ty91, ty91, ty95], .bool), some ([ty57, (.uint .usize), ty91, ty95], .bool), some ([ty57, ty91, ty91, ty95], .bool), some ([ty54, ty58, (.uint .usize), ty91, ty91, ty95], .bool), some ([ty62, (.uint .usize), ty94, ty95], .bool), some ([(.uint .usize), (.uint .usize), ty95], .bool), some ([(.uint .usize), (.uint .usize), ty95], .bool), some ([ty146, ty91], ty146), some ([ty146, ty95], ty146), some ([ty146, ty94], ty146), some ([ty146, (.uint .usize)], ty146), some ([ty91], (.uint .usize)), some ([ty94, (.uint .usize)], (.uint .usize)), some ([ty91, (.uint .usize)], .bool), some ([ty163, (.uint .usize), (.uint .usize), (.uint .usize)], .bool), some ([ty94], (.uint .usize))]),
  (41, [some ([(.uint .usize), ty94], .bool), some ([ty65], ty64), some ([], ty65), some ([ty64], ty65), some ([(.uint .usize), ty91, (.uint .usize)], ty65), some ([ty63], ty65), some ([(.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize), ty65, ty95], ty65), some ([(.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize), ty65, ty95, ty95], ty65), some ([(.uint .usize), (.uint .usize), ty65, ty95], ty65), some ([(.uint .usize), ty94, (.uint .usize)], ty65), some ([(.uint .usize), ty94, (.uint .usize)], ty20), some ([ty63], (.uint .usize)), none, none, none, none, some ([ty36, ty36], ty36), some ([(.uint .usize)], ty36), some ([ty237, (.uint .usize), ty65, ty36], ty36), none, some ([(.uint .uint64), ty91], ty91), some ([ty9], (.uint .uint64)), some ([ty4], (.uint .uint64)), some ([ty148], ty176), some ([ty148, (.uint .usize)], ty176), some ([ty14, ty175, ty175], ty176), some ([ty9, ty175], ty176), some ([ty8], (.uint .uint64)), some ([ty148, ty9], ty171), some ([ty148, (.uint .usize), ty9], ty171), some ([ty171, ty171], ty171), some ([(.uint .usize), ty171], ty171), some ([ty23], (.uint .usize)), some ([ty150, (.uint .usize), (.uint .usize), ty9, (.uint .usize), ty76, ty23], ty147), some ([(.uint .usize), ty9, ty150, ty15], ty147), some ([ty9, ty72, (.uint .usize)], (.uint .usize)), some ([ty217, ty72], .bool), some ([ty80, ty72], .bool), some ([ty220, ty76], .bool), some ([ty80, ty76], .bool), some ([ty148, (.uint .usize), ty177], ty178)]),
  (41, [some ([ty148, (.uint .usize), ty177], ty178), some ([ty80, ty148, ty9, (.uint .usize), ty177], ty178), some ([(.uint .usize), ty9, (.uint .usize), (.uint .usize), ty178], ty178), some ([(.uint .usize), ty9, ty171], ty178), some ([ty150, ty15, (.uint .usize), ty148, (.uint .usize)], ty178), some ([ty148, ty9, ty174], ty174), some ([ty80, ty148, ty9, ty91, (.uint .usize), ty95], ty147), some ([ty80, ty148, ty9, ty174, ty150, ty15], ty147), some ([ty29], .bool), some ([(.uint .usize), (.uint .usize), ty101, ty150, ty213], ty178), some ([(.uint .usize)], ty95), some ([(.uint .uint64), (.uint .usize)], ty95), some ([(.uint .usize)], ty95), some ([(.uint .usize)], ty95), some ([(.uint .uint64), (.uint .usize)], ty95), some ([(.uint .usize)], ty95), some ([(.uint .usize), (.uint .usize), ty211], ty178), some ([ty14], (.uint .usize)), some ([(.uint .usize), ty91, ty95], ty95), some ([ty14, ty9, (.uint .usize)], ty91), some ([(.uint .usize), ty177], ty95), some ([ty9], .bool), some ([ty175, ty260], ty176), some ([ty9], ty260), some ([ty9], ty238), some ([ty4, ty91], ty91), some ([ty9, ty72, (.uint .usize), (.uint .usize), ty211], ty178), some ([(.uint .usize), (.uint .usize), ty147, ty213, ty147], ty147), none, some ([ty28], ty58), some ([ty28, (.uint .usize), ty177, ty177, ty4], ty178), some ([ty9], ty238), some ([ty28, (.uint .usize), ty177, ty177, ty4], ty178), some ([ty80, ty9, (.uint .usize)], ty178), some ([ty261, (.uint .usize)], .bool), some ([ty36, (.uint .usize)], ty261), some ([ty177, ty177, ty9, (.uint .usize), ty91, ty147], ty147), some ([ty9, ty94, (.uint .usize), ty91, (.uint .usize)], ty147), some ([(.uint .usize), (.uint .usize), ty91], ty91), some ([(.uint .usize), ty9, (.uint .usize), (.uint .usize), ty177, ty177], ty147), some ([(.uint .usize), ty9, (.uint .usize), ty177], ty147)]),
  (41, [some ([.bool], ty171), some ([.bool, ty171], ty171), some ([ty216, ty15, ty9], ty171), none, some ([ty219], ty218), some ([ty29, ty20], (.uint .usize)), some ([ty75], ty74), none, some ([ty79], ty78), none, some ([ty20, (.uint .usize)], ty146), some ([ty223, ty20, (.uint .usize), (.uint .usize)], ty224), some ([ty181, ty183], ty183), some ([ty223], ty222), some ([ty45, ty47], ty47), some ([ty20, ty181], ty45), none, some ([ty181], ty183), some ([ty181, ty181], ty181), some ([(.uint .usize)], .bool), some ([ty223, ty20, ty181], (.uint .usize)), some ([ty85, ty141], ty141), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([ty45], ty45), some ([ty45], ty45), some ([ty44, (.uint .usize), (.uint .usize), (.uint .usize), ty20, (.uint .usize), ty20, ty41, (.uint .usize), ty139], ty141), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize))]),
  (41, [some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize))]),
  (41, [some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([ty86, ty87], ty87), some ([ty108], ty110), some ([ty27, ty20, ty151, ty87], ty244), some ([ty27, ty20, ty151, ty265], ty244), some ([(.uint .usize), ty86], ty265), some ([ty111, ty113], ty113), some ([ty86], ty151), some ([ty85], ty45), some ([(.uint .usize), ty27, ty27, ty85, ty85, ty86], ty225), some ([ty123, ty128], ty128), some ([ty117], ty119), some ([ty120], ty122), some ([.bool, ty151], ty151), some ([ty86], .bool), some ([], (.uint .usize)), some ([ty20, ty20], .bool), some ([], ty20), some ([ty20], (.uint .usize)), some ([ty27], ty26), some ([ty20, ty151], ty151), some ([ty27, ty27], .bool), some ([ty27], .bool), some ([ty27, ty27], ty27), some ([ty113, ty27], ty27)]),
  (41, [some ([ty110, ty27], ty27), some ([ty122, ty27], ty27), some ([ty116, ty27], ty27), some ([ty110, ty27, ty27], .bool), some ([ty20, (.uint .usize), (.uint .usize), (.uint .usize)], .bool), some ([ty20, (.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize)], .bool), some ([ty20, (.uint .usize), (.uint .usize)], .bool), some ([ty20, (.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize)], .bool), none, some ([], ty34), some ([ty266, ty231], ty231), some ([ty267, ty179, ty268], ty266), some ([(.uint .usize), ty230, ty188], ty267), some ([(.uint .usize), ty230, ty189], ty179), some ([(.uint .usize), ty230, ty194], ty268), some ([], ty229), some ([ty179, ty229], ty229), some ([(.uint .usize), ty128, ty158, (.uint .usize), ty155], ty179), some ([ty34], .bool), some ([ty34], .bool), some ([ty36, ty34], ty34), some ([ty34], ty37), some ([ty32, ty34], ty34), some ([ty34, ty9, ty271, ty31], ty31), some ([ty12], ty271), some ([ty146], .bool), some ([ty246], ty247), some ([(.uint .usize), (.uint .usize), ty128, ty158, ty247, ty247], ty247), some ([(.uint .usize), ty128, ty158, ty247, ty158, ty247], ty247), some ([], ty247), some ([ty146, ty247], ty247), some ([ty158, ty154], .bool), some ([ty154], ty155), none, some ([ty152], ty154), some ([ty156, ty227], ty227), some ([(.uint .usize), ty128, (.uint .usize), ty155], ty227), none, none, some ([ty187], ty188), some ([ty190], ty194)]),
  (41, [some ([ty154], ty152), some ([ty193], ty155), none, some ([ty158, ty156], ty158), some ([ty156], ty158), some ([ty158, ty158], ty158), some ([ty193], ty158), some ([ty197], ty196), some ([(.uint .usize), ty128, ty111, ty155], ty232), some ([ty111, ty156], .bool), some ([ty232, ty156], ty232), some ([(.uint .usize), ty128, ty111, ty155], ty232), some ([ty155], ty155), some ([ty186], ty188), some ([ty113], (.uint .usize)), some ([(.uint .usize), ty128, ty154], ty252), some ([ty155, (.uint .usize)], ty251), none, none, none, none, none, none, none, none, none, none, some ([(.uint .uint64)], (.uint .uint64)), some ([ty54, ty55, (.uint .uint64), (.uint .uint64), ty91, ty91], ty91), some ([ty54, ty55, (.uint .uint64), ty91, ty91], ty91), some ([ty54, ty55, ty91, ty91, (.uint .uint64)], ty91), some ([ty54, ty56, (.uint .uint64), (.uint .uint64)], .bool), some ([ty203, (.uint .usize), ty205], ty91), some ([ty204], ty205), some ([ty205, (.uint .usize), ty91], ty205), some ([ty205, (.uint .usize)], ty205), some ([ty95, (.uint .usize)], .bool), some ([ty91, ty91], .bool), some ([ty234], ty234), some ([ty54, ty55, ty234, ty234], ty234), some ([ty54, ty56, ty234, ty234], ty234)]),
  (41, [some ([ty234, (.uint .uint64)], .bool), some ([ty94, ty94], .bool), some ([ty57], (.uint .usize)), some ([ty54], (.uint .usize)), some ([ty58], (.uint .usize)), some ([ty62], (.uint .usize)), some ([(.uint .usize), ty91], ty146), some ([(.uint .usize), ty94], ty146), some ([ty163, (.uint .usize)], ty256), none, none, some ([ty55], (.uint .usize)), some ([ty54], (.uint .usize)), some ([ty57], (.uint .usize)), some ([ty58, ty54], (.uint .usize)), some ([ty61], (.uint .usize)), some ([ty36], ty35), some ([(.uint .uint8), ty36], ty36), some ([(.uint .uint8)], ty36), some ([.i32], ty36), some ([(.uint .usize)], (.uint .usize)), some ([], ty36), some ([ty63, ty237, (.uint .usize)], ty36), some ([ty91, (.uint .uint64)], .bool), some ([ty4], (.uint .uint64)), some ([(.uint .usize), ty179], ty176), some ([ty55, ty175, ty175], ty176), some ([ty55, ty175, ty175], ty176), some ([ty55, ty175, ty175], ty176), some ([ty175, ty175], ty176), some ([ty56, ty175, ty175], ty176), some ([ty56, ty175, ty175], ty176), some ([ty175, ty175], ty176), some ([ty175, ty175], ty176), some ([ty175], ty176), some ([ty4, ty175], ty176), some ([ty175], ty176), some ([ty8, ty175], ty176), some ([ty4, ty175], ty176), some ([(.uint .usize), ty179, ty9], ty171), some ([ty94, ty94], ty94)]),
  (41, [some ([ty22], ty23), some ([(.uint .usize), (.uint .usize), (.uint .usize), ty91, ty171, ty23, ty147], ty147), some ([ty216, ty15], ty91), some ([(.uint .usize), ty174], ty147), some ([ty9, (.uint .usize), ty91, (.uint .usize), ty95], ty95), some ([(.uint .usize), ty9, (.uint .usize), (.uint .usize), ty177], ty178), some ([ty150, ty15, (.uint .usize), ty179], ty178), some ([ty148, ty174], ty174), some ([ty148, ty9, ty174, ty150, ty15], ty147), some ([ty148, ty9, ty174, ty150, ty15], ty147), some ([ty148, ty9, ty174, ty150, ty15], ty147), some ([ty150, ty213, ty72, (.uint .usize), (.uint .usize)], ty259), some ([(.uint .usize), (.uint .usize), ty101, ty258], ty178), some ([(.uint .usize)], ty95), some ([(.uint .usize)], ty95), some ([ty8], ty54), some ([ty8], (.uint .uint64)), some ([ty4], .bool), some ([ty4, ty91], ty91), some ([ty4, (.uint .usize)], ty91), some ([ty28], ty58), some ([(.uint .usize), (.uint .usize)], ty177), some ([ty57, ty91, ty174], ty147), some ([ty9], ty57), some ([ty91, (.uint .usize)], ty91), some ([ty94, (.uint .usize)], ty174), some ([ty72, ty94, (.uint .usize), ty91, (.uint .usize)], ty147), some ([ty91, ty94, (.uint .usize), ty91, (.uint .usize), (.uint .usize), ty76], ty147), some ([(.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize)], ty95), none, some ([ty213, ty20], (.uint .usize)), none, none, some ([(.uint .usize)], .bool), some ([ty20, (.uint .usize)], (.uint .usize)), some ([(.uint .usize)], .bool), some ([(.uint .usize), ty281], ty224), some ([ty20, (.uint .usize)], ty281), some ([(.uint .usize)], .bool), some ([ty20, (.uint .usize)], (.uint .usize)), some ([(.uint .usize), (.uint .usize), ty282], ty224)]),
  (41, [some ([(.uint .usize), .bool, ty20, (.uint .usize)], ty282), some ([(.uint .usize)], .bool), some ([ty223, ty20, (.uint .usize)], ty224), some ([ty183], ty182), none, none, some ([ty47], ty46), some ([ty181, ty20], ty45), some ([ty20, (.uint .usize)], ty20), some ([ty20, ty223], ty146), some ([(.uint .usize), ty47], .bool), some ([ty44, (.uint .usize)], ty263), some ([ty44, (.uint .usize), (.uint .usize), (.uint .usize), ty42, ty20, ty20, ty41, (.uint .usize), ty139], ty141), some ([ty86, ty86], ty86), some ([ty27, ty20, ty27, ty283], ty244), some ([ty86], ty283), some ([], ty107), some ([ty20, ty87, ty265], ty265), some ([(.uint .usize), ty85], ty87), some ([ty85, ty86], ty151), some ([(.uint .usize), ty27, ty27, ty85, ty85, ty85], ty233), some ([ty123, ty125], ty125), some ([], (.uint .usize)), some ([], ty20), some ([], ty20), some ([], ty20), some ([], ty20), some ([], ty20), some ([], ty20), some ([], ty20), some ([], ty20), some ([], ty20), some ([], ty20), none, some ([ty20, ty27], ty27), some ([ty27, ty20], .bool), some ([ty111, ty113, ty27], ty27), some ([ty108, ty110, ty27], ty27), some ([ty120, ty122, ty27], ty27), some ([ty114, ty116, ty27], ty27), some ([ty108, ty27, ty27], .bool)]),
  (41, [some ([ty20, (.uint .usize)], .bool), some ([ty32, ty231], ty231), some ([], ty12), some ([(.uint .usize), ty179, ty267], ty267), some ([(.uint .usize), ty230, ty154], ty179), some ([(.uint .usize), ty179, ty15, ty268], ty268), some ([(.uint .usize), ty179, ty18, ty268], ty268), some ([(.uint .usize), ty179, ty146, ty18, ty268], ty268), some ([ty158, ty156, (.uint .usize)], ty146), some ([(.uint .usize), ty179, (.uint .usize), ty18, ty268], ty268), some ([(.uint .usize), ty179, (.uint .usize), ty146, ty23, ty268], ty268), some ([ty179], ty146), some ([(.uint .usize), ty146, ty18], ty268), some ([ty268, ty268], ty268), some ([ty15, ty268, ty268], ty268), some ([ty15, ty268], ty268), some ([(.uint .usize), ty15, (.uint .usize), ty268], ty268), some ([(.uint .usize), ty179, ty15, ty15, ty268], ty268), some ([(.uint .usize), ty179, (.uint .usize), ty15, ty268], ty268), some ([(.uint .usize), (.uint .usize), ty18, (.uint .usize), ty268], ty268), some ([(.uint .usize), ty20, ty268], ty268), some ([(.uint .usize), ty179, ty284, ty268], ty268), some ([(.uint .usize), ty230, ty193], ty284), some ([(.uint .usize), ty284], ty268), some ([ty284, ty268, ty268], ty268), some ([ty284, ty268], ty268), some ([ty284], ty268), some ([ty284], ty268), some ([(.uint .usize), ty284, ty284], ty268), some ([(.uint .usize), (.uint .usize), ty284], ty268), some ([ty284], ty268), some ([(.uint .usize), ty146, (.uint .usize), .bool, (.uint .usize), ty179, ty268, ty268], ty268), some ([.bool, ty179], ty179), some ([(.uint .usize), ty179], ty268), some ([ty284, ty284], ty268), some ([ty30, ty284, ty284], ty268), some ([ty229], ty228), some ([ty110, (.uint .usize)], ty244), some ([(.uint .usize), ty128, ty158, .bool, ty146, (.uint .usize), ty155], ty179), some ([ty31], .bool), some ([ty12], .bool)]),
  (41, [some ([ty12], ty146), some ([ty9], .bool), some ([ty31], ty146), some ([], (.uint .usize)), some ([ty31], (.uint .usize)), some ([ty12], .bool), some ([ty9], .bool), some ([ty31], .bool), some ([ty36, ty31], ty31), some ([ty31], ty36), some ([ty34], ty36), some ([ty34], ty33), some ([ty271, ty179, ty15], ty15), some ([ty31], ty16), some ([(.uint .usize), ty9, ty271], ty271), some ([ty271, ty217, ty18], ty18), some ([ty179], ty217), some ([ty34, (.uint .usize)], ty217), some ([ty220, (.uint .usize)], ty217), some ([ty179], ty220), some ([ty271, ty220, ty9, ty23], ty23), some ([ty271, (.uint .usize)], ty179), some ([ty217, (.uint .usize)], ty179), some ([ty179], ty179), some ([ty34, ty271, ty179, ty29], ty29), some ([ty9, (.uint .usize)], ty72), some ([], ty271), some ([ty269, ty271], ty271), none, some ([ty247, ty247], .bool), some ([(.uint .usize), ty128, ty158, ty247, ty156, ty158, ty247], ty247), some ([ty247], ty246), some ([ty158, ty156], .bool), none, some ([(.uint .usize), ty128, .bool, (.uint .usize), ty155], ty227), none, none, none, some ([ty287], ty155), some ([ty191], ty287), some ([ty192], ty193)]),
  (41, [some ([ty287], ty158), none, some ([ty128, ty27], ty27), some ([ty45], (.uint .usize)), some ([ty155], (.uint .usize)), some ([ty294, ty277, (.uint .usize)], ty232), some ([(.uint .usize), ty276, ty111, ty292, ty86], ty294), some ([], ty292), some ([(.uint .usize), ty276, ty85], ty277), some ([ty111], .bool), some ([ty155], ty251), some ([ty194], ty190), some ([ty287], ty191), some ([ty188], ty287), some ([ty277], ty251), some ([(.uint .usize), ty128, ty111, ty276], .bool), some ([(.uint .usize), ty85, ty86, ty232], ty232), some ([ty232, ty146], ty232), some ([(.uint .usize), ty276, ty294, ty277, ty85, ty85], ty232), some ([ty276, ty86], ty146), some ([ty188], ty187), some ([(.uint .usize), ty128, (.uint .usize), ty155], ty252), some ([ty55], .bool), some ([ty54, ty55, (.uint .uint64), (.uint .uint64)], (.uint .uint64)), some ([ty55], .bool), some ([ty55], .bool), some ([ty54, (.uint .uint64), (.uint .uint64)], .bool), some ([ty55], (.uint .uint64)), some ([ty54, ty91], .bool), some ([ty56, (.uint .uint64), (.uint .uint64)], .bool), some ([(.uint .uint64)], (.uint .uint64)), none, some ([ty91], .bool), some ([ty91, (.uint .usize)], .bool), some ([ty203, ty205], ty205), some ([ty205], ty205), some ([ty205, (.uint .usize), (.uint .usize)], ty205), some ([ty205, (.uint .usize), (.uint .usize), (.uint .usize)], (.uint .usize)), some ([ty95, (.uint .usize)], .bool), some ([ty95], .bool), some ([ty94, (.uint .usize)], .bool)]),
  (41, [some ([ty91, ty234], .bool), some ([ty91, ty91], .bool), some ([ty54, ty55, ty91, ty91, ty91], .bool), some ([ty54, ty55, ty91, ty91, ty91], .bool), some ([ty54, ty56, ty91, ty91, ty91], .bool), some ([ty61, ty91, ty91, ty91], .bool), some ([ty54, ty55, (.uint .uint64), (.uint .uint64)], ty234), some ([ty55, (.uint .uint64)], ty234), some ([ty162], ty163), some ([ty8], (.uint .usize)), none, some ([(.uint .uint64)], ty36), some ([(.uint .usize)], ty36), some ([(.uint .usize)], ty36), some ([ty55, ty54, (.uint .usize)], ty36), some ([ty54, ty56, (.uint .usize)], ty36), some ([(.uint .usize), (.uint .usize)], .i32), some ([(.uint .usize), ty20, (.uint .usize)], ty36), some ([(.uint .usize)], (.uint .usize)), some ([(.uint .usize)], ty36), some ([(.uint .usize)], ty36), some ([(.uint .usize), (.uint .usize)], ty20), some ([], ty36), some ([(.uint .usize)], ty36), some ([], ty36), some ([(.uint .usize)], ty36), some ([ty57], ty36), some ([ty57, (.uint .usize)], ty36), some ([ty58, ty54, (.uint .usize)], ty36), some ([ty61, (.uint .usize)], ty36), some ([ty62, (.uint .usize)], ty36), some ([(.uint .usize)], ty36), some ([(.uint .usize), ty9], ty176), some ([ty55, ty175, ty175, ty260], ty176), some ([ty9], .bool), some ([ty55, ty175, ty175, ty238], ty176), some ([ty55, ty175, ty175, ty238], ty176), some ([ty9], .bool), some ([ty56, ty175, ty175, ty260], ty176), some ([ty91], ty91), some ([ty56, ty175, ty175, ty238], ty176)]),
  (41, [some ([ty56, ty175, ty175, ty238], ty176), some ([ty9], ty54), some ([ty4, ty91], ty91), some ([ty4, ty91], ty91), some ([ty4, ty91], ty91), some ([ty4, ty4, ty91], ty91), some ([ty4, ty91], ty91), some ([ty8, ty54, ty91], ty176), some ([ty4, ty176], ty176), some ([ty8, ty8, ty91], ty176), some ([ty4], ty54), some ([(.uint .usize), ty9, ty9], ty171), none, some ([ty72, (.uint .usize), ty91, (.uint .usize), ty95], ty95), some ([(.uint .usize), ty91, (.uint .usize), (.uint .usize), ty76], ty95), some ([(.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize)], ty95), some ([(.uint .usize), ty9, ty171], ty178), some ([(.uint .usize), ty9, ty91], ty174), some ([ty150, ty29, ty9, (.uint .usize), (.uint .usize), ty259], ty259), some ([ty150, ty29], (.uint .usize)), some ([ty4], (.uint .uint64)), some ([ty4], (.uint .uint64)), some ([ty9], ty280), some ([ty91, ty147, ty147], ty147), some ([ty20], (.uint .usize)), some ([ty20, (.uint .usize)], ty146), some ([ty20, (.uint .usize), (.uint .usize)], ty282), some ([ty20, (.uint .usize)], ty281), some ([ty20], (.uint .usize)), some ([(.uint .usize), .bool, (.uint .usize), ty20, (.uint .usize)], ty282), some ([ty223, ty20, (.uint .usize), (.uint .usize)], ty224), none, none, some ([], ty20), some ([ty20, ty221, ty223], ty146), some ([ty222], ty223), some ([], (.uint .usize)), some ([ty47], .bool), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([ty47], .bool)]),
  (41, [some ([], (.uint .usize)), some ([ty47], .bool), some ([], (.uint .usize)), some ([ty44, (.uint .usize), (.uint .usize), ty141, ty41, (.uint .usize)], ty141), some ([ty85, ty283], ty283), some ([ty20, ty86, ty265], ty265), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([ty27, ty27], .bool), some ([ty20], .bool), some ([ty10, ty12], ty12), some ([ty179], ty179), some ([(.uint .usize), ty230, (.uint .usize), ty155, ty146], ty179), some ([ty179, (.uint .usize)], ty179), some ([ty179], ty179), some ([ty156, ty158, ty156, (.uint .usize)], ty146), some ([ty146, ty296], ty284), some ([(.uint .usize), ty230, ty287], ty296), some ([ty14, ty284, ty284], ty284), some ([ty284], ty284), some ([ty284], ty284), some ([ty9, ty284], ty284), some ([(.uint .usize), ty284], ty284), some ([ty179, ty296], ty284), some ([ty179, (.uint .usize), ty296], ty284), some ([ty284, ty179, ty179, ty27, ty296], ty284), some ([ty28, ty284, ty284], ty284), some ([ty179, (.uint .usize)], ty284), some ([ty284, ty179, ty284, ty284], ty284), some ([(.uint .usize), ty179, ty284, ty179, ty284], ty284), some ([ty179, ty284], ty284), some ([ty284, (.uint .usize)], ty284), some ([ty284, ty284], ty284), none, none, some ([ty146, ty220], ty179), some ([(.uint .usize), ty128, ty158, ty299], ty220), some ([(.uint .usize), ty128, (.uint .usize), ty155], ty299)]),
  (41, [some ([ty146, ty217], ty179), some ([(.uint .usize), ty128, ty158, ty252], ty217), some ([ty15], .bool), some ([ty18], .bool), some ([ty23], .bool), some ([ty29], .bool), some ([ty146, .bool, ty146], ty146), some ([ty9], ty146), some ([ty15], .bool), some ([ty18], .bool), some ([ty23], .bool), some ([.bool], ty146), some ([ty146, ty146], ty146), some ([.bool, ty146], ty146), some ([], ty146), some ([ty146, (.uint .usize)], ty146), some ([ty29], .bool), some ([(.uint .usize), (.uint .usize)], ty146), some ([ty29], (.uint .usize)), some ([(.uint .usize)], .bool), some ([ty72], .bool), some ([ty76], .bool), some ([ty15], .bool), some ([ty18], .bool), some ([ty23], .bool), some ([ty29], .bool), some ([ty20], .bool), some ([ty36, ty29], ty29), some ([ty29], ty36), none, some ([ty179, .i32, ty15], ty15), some ([ty15], ty234), some ([ty179, (.uint .uint64), ty15], ty15), some ([ty179, ty15, ty15], ty15), some ([ty15], ty13), some ([ty14, ty179, ty179, ty179], ty179), some ([ty271, ty15], ty179), some ([ty14, ty179, ty179, ty179], ty179), some ([ty179, (.uint .uint64), ty15], ty15), some ([ty179, ty9, ty15], ty286), none]),
  (41, [some ([], ty18), some ([ty15, ty18], ty18), some ([ty217], ty179), some ([ty217], ty217), some ([ty34, (.uint .usize)], ty266), some ([ty12], ty72), some ([], ty23), some ([ty21, ty23], ty23), some ([ty20, ty217, ty271], ty271), some ([ty220], ty220), some ([ty269, ty271, (.uint .usize)], ty179), some ([ty270], ty271), some ([ty213], ty24), some ([ty34, ty271, ty217, ty213], ty213), some ([ty29], ty25), some ([ty34, ty271, ty29], ty179), some ([ty34, ty271, ty220, ty9, ty27, ty213], ty213), some ([ty271], ty270), some ([ty146, ty247, ty247], .bool), some ([(.uint .usize), ty128, ty158, ty247, ty156, ty146], ty146), none, some ([ty156, ty156], .bool), some ([(.uint .usize), ty128, ty252], ty227), some ([ty299], ty252), none, none, some ([ty110, ty27], ty27), some ([], ty188), some ([(.uint .usize), ty276, ty111, ty292, ty85, ty86], ty294), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([ty251], ty277), some ([(.uint .usize), ty276, ty85], ty251), none, none, some ([], ty287), some ([ty193, ty287], ty287), some ([(.uint .usize), ty128, ty305], .bool), some ([(.uint .usize), ty276, ty85, ty85], ty305), some ([ty85], ty85)]),
  (41, [some ([.bool, ty195], ty232), some ([(.uint .usize), ty86, ty86, ty188], .bool), some ([.bool, ty195], ty232), some ([ty194, (.uint .usize)], .bool), some ([(.uint .usize), ty276, ty293, ty277, ty85, ty85], ty232), some ([ty276, ty85], ty146), none, some ([(.uint .usize), ty276, ty86], ty252), some ([ty128, ty27, ty27, ty155], ty276), some ([ty55, (.uint .uint64), (.uint .uint64)], (.uint .uint64)), some ([ty91], .bool), some ([ty205], ty204), some ([ty205, (.uint .usize)], .bool), some ([ty205, (.uint .usize)], ty205), some ([ty205, (.uint .usize)], ty205), some ([ty203, (.uint .usize), ty205], ty205), some ([.bool, (.uint .usize), (.uint .usize)], (.uint .usize)), some ([ty203, (.uint .usize)], .bool), some ([ty55], (.uint .usize)), some ([ty91, ty54, ty55], .bool), some ([ty56], (.uint .usize)), some ([ty61], (.uint .usize)), some ([(.uint .usize)], .i32), some ([(.uint .usize)], ty36), some ([ty54], ty36), some ([ty55], ty36), some ([ty56, ty54], (.uint .uint8)), some ([(.uint .usize)], (.uint .uint64)), some ([ty57], ty36), some ([ty58, ty54], ty36), some ([ty58], ty36), some ([ty58], ty36), some ([ty61], ty36), some ([ty62], ty36), some ([ty62], (.uint .uint8)), some ([ty62], (.uint .uint8)), some ([ty55, ty175, ty175, ty8], ty176), some ([ty55, ty175, ty175, ty4], ty176), some ([ty55, ty175, ty175, ty4], ty176), some ([ty56, ty175, ty175, ty8], ty176), some ([ty56, ty175, ty175, ty4], ty176)]),
  (41, [some ([ty56, ty175, ty175, ty4], ty176), some ([ty171, ty91, ty259], ty259), some ([ty173, ty9, ty9, (.uint .usize), (.uint .usize), (.uint .usize), ty259], ty259), some ([ty173], (.uint .usize)), some ([ty4], ty280), some ([(.uint .usize), ty20], (.uint .usize)), some ([ty146, (.uint .usize)], .bool), some ([(.uint .usize)], ty146), some ([(.uint .usize), ty20, (.uint .usize), (.uint .usize)], ty282), some ([ty20, (.uint .usize), (.uint .usize)], ty281), some ([(.uint .usize), ty20], (.uint .usize)), some ([ty223, ty20, (.uint .usize), (.uint .usize)], ty224), some ([ty223, ty20, (.uint .usize)], ty224), some ([], (.uint .usize)), some ([ty47, (.uint .usize), (.uint .usize)], .bool), some ([], (.uint .usize)), some ([ty86, ty107], ty107), some ([ty12], ty11), some ([ty229, (.uint .usize)], ty295), some ([ty9], ty179), some ([], ty213), some ([ty284, ty296], ty296), some ([ty76], ty6), some ([ty217, ty220], ty220), some ([ty297], ty298), some ([(.uint .usize), ty276, ty107], ty299), some ([ty179, ty217], ty217), some ([(.uint .usize), ty128, ty158, ty154], ty179), some ([ty9], .bool), some ([ty213], .bool), some ([(.uint .usize), ty146], ty146), some ([ty72], ty146), some ([ty76], ty146), some ([(.uint .usize), ty146], ty146), some ([(.uint .usize), (.uint .usize)], ty146), some ([ty213], .bool), some ([ty213], (.uint .usize)), some ([(.uint .usize)], (.uint .usize)), some ([ty213], .bool), some ([ty27], .bool), some ([ty36, ty213], ty213)]),
  (41, [some ([ty213], ty36), some ([ty20], ty36), some ([ty9, .i32, ty15], ty15), some ([ty9, ty15], ty234), some ([(.uint .uint64), ty15], ty15), some ([(.uint .uint64), ty15], ty15), some ([ty4, (.uint .uint64), ty15], ty15), some ([ty4, ty15, ty15], ty15), none, some ([ty14], .bool), some ([ty179, ty179], ty179), some ([ty14], .bool), some ([ty14, ty179, ty179], ty179), some ([ty9], ty179), some ([ty4, (.uint .uint64), ty15], ty15), some ([(.uint .uint64), ty15], ty15), some ([ty4, (.uint .uint64), ty15], ty15), some ([ty8, ty9, ty15], ty286), some ([ty18], ty17), some ([ty23], ty22), none, none, some ([ty29, ty213], ty213), none, some ([ty34, (.uint .usize)], ty179), some ([ty27], ty20), some ([ty27], ty27), none, some ([(.uint .usize), ty128, ty158, ty247, ty156], ty146), some ([ty155, ty155], .bool), some ([ty227, ty227], ty227), some ([ty298], ty155), some ([ty108, ty110, ty27], ty27), some ([ty85], ty45), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([ty292, (.uint .usize)], .bool), some ([ty111, ty85], ty138), some ([(.uint .usize), ty276, ty85], ty251), some ([ty186, ty294], ty294)]),
  (41, [some ([ty290, ty292], ty292), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([ty251], ty251), some ([], (.uint .usize)), some ([ty251, ty146], ty251), some ([ty85], ty146), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([(.uint .usize), ty276, ty151], ty251), some ([(.uint .usize), ty85, ty85], ty151), some ([(.uint .usize), ty276, ty151, ty87], ty251), some ([(.uint .usize), ty128, ty304], .bool), some ([ty305, ty305], ty305), some ([(.uint .usize), ty276, ty86], ty305), some ([(.uint .usize), ty276, ty85], ty305), some ([ty154], .bool), some ([ty308], .bool), some ([(.uint .usize), ty86, ty20], ty308), some ([ty293, ty189, ty309], ty232), some ([(.uint .usize), ty276, ty292, ty85, ty309], ty309), some ([(.uint .usize), ty276, ty292, ty85], ty309), some ([ty251, ty252], ty252), some ([ty54], .bool), none, some ([ty205, (.uint .usize)], .bool), some ([ty205, (.uint .usize)], ty205), some ([ty59], (.uint .usize)), some ([ty60], (.uint .usize)), some ([ty56], (.uint .uint8)), some ([ty56], (.uint .uint8)), some ([ty8], ty36), some ([ty8], (.uint .uint8)), some ([ty59], (.uint .uint8)), some ([ty8], ty36), some ([ty60], (.uint .uint8)), some ([ty310, ty8, ty175, ty175], ty176), some ([ty55], ty310), some ([ty8, ty56, ty91, ty91], ty91), some ([ty148, ty9, ty9, (.uint .usize), (.uint .usize), (.uint .usize), ty259], ty259), some ([(.uint .usize)], .bool)]),
  (41, [some ([(.uint .usize), (.uint .usize)], .bool), some ([(.uint .usize), ty20, (.uint .usize)], ty282), some ([ty20, (.uint .usize)], ty281), some ([ty20, (.uint .usize)], ty281), some ([ty20, (.uint .usize)], ty281), some ([ty223, ty20], ty306), some ([ty20, (.uint .usize), ty221], ty224), some ([(.uint .usize), ty47, (.uint .usize), (.uint .usize)], .bool), some ([ty107], ty106), none, some ([ty228], ty229), some ([ty9], ty146), none, some ([ty72, ty220], ty220), none, some ([], ty298), some ([ty252, ty299], ty299), some ([ty106], ty107), some ([ty9, ty217], ty217), some ([ty146, ty146], ty146), some ([(.uint .usize), (.uint .usize)], ty146), some ([], (.uint .usize)), some ([.i32, ty15], ty15), some ([ty4, .i32, ty15], ty15), some ([ty4], .bool), some ([ty4, .i32, ty15], ty15), some ([ty4], (.uint .uint64)), some ([ty8, ty15, ty15], ty286), none, none, some ([(.uint .usize), ty128, ty158, ty247, .bool, ty156], ty146), some ([ty154, ty154], .bool), some ([ty291], ty292), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([ty251], ty251), some ([], (.uint .usize)), some ([ty186, ty188], ty188), some ([ty292], ty291), some ([], (.uint .usize))]),
  (41, [some ([], (.uint .usize)), some ([ty20, (.uint .usize)], ty146), some ([ty276, ty27], ty251), some ([(.uint .usize), ty276, ty27, ty252], ty251), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([ty276, ty27], ty146), some ([ty276, (.uint .usize), ty252], ty251), some ([(.uint .usize), ty276, ty86], ty252), some ([(.uint .usize), ty128, ty302], .bool), some ([ty303], ty304), some ([ty304, ty305], ty305), some ([], ty304), some ([(.uint .usize), ty276, ty85], ty305), some ([], (.uint .usize)), some ([(.uint .usize), ty276, ty86], ty305), some ([ty251], .bool), some ([ty154], ty251), some ([ty308, ty308], ty308), some ([(.uint .usize), ty85, ty20], ty86), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([ty317, ty309], ty309), some ([(.uint .usize), ty276, ty292, ty251, ty85], ty317), some ([(.uint .usize), ty276, ty292, ty86], ty309), some ([ty154, ty252], ty252), some ([ty203, (.uint .usize), ty205], ty205), some ([ty8], ty36), some ([ty9], (.uint .usize)), some ([ty148, ty9, ty9, (.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize), ty258], ty259), some ([(.uint .usize), (.uint .usize), ty20, (.uint .usize)], ty282), some ([ty20, (.uint .usize)], (.uint .usize)), some ([ty20, (.uint .usize), (.uint .usize)], ty281), some ([ty20, ty282], ty281), some ([ty221, ty306, ty20], ty306), some ([ty20, (.uint .usize)], (.uint .usize)), some ([ty20, (.uint .usize)], ty282), some ([], (.uint .usize)), some ([], (.uint .usize))]),
  (41, [some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([ty47], .bool), none, none, some ([ty72], ty146), some ([ty76], ty146), some ([ty72, ty76], ty76), some ([ty155, ty299], ty299), some ([ty4, .i32], .bool), some ([ty158, ty247, ty299], ty146), some ([ty158, ty247, ty252], ty146), some ([ty4], (.uint .usize)), some ([ty8, ty8], .bool), none, none, some ([(.uint .usize), ty20, (.uint .usize)], ty146), some ([ty27], ty226), some ([ty276, ty20], ty251), some ([ty276, ty27, ty20], ty251), some ([ty276, ty146, ty252], ty251), some ([ty27], ty314), some ([ty122, ty27, ty20], ty315), some ([ty276, ty27, ty20], ty27), some ([(.uint .usize), ty128, ty120, ty155], ty251), some ([ty110, ty27, ty20, (.uint .usize)], ty146), some ([.bool, (.uint .usize), ty155], ty251), some ([ty276, (.uint .usize), ty155], .bool), some ([(.uint .usize), ty276, ty85], ty251), some ([(.uint .usize), ty128, ty125, ty302], .bool), none, some ([ty304, ty304], ty304), some ([], (.uint .usize)), some ([(.uint .usize), ty276, ty20, ty87], ty305)]),
  (41, [some ([(.uint .usize), ty85, ty20], .bool), some ([], (.uint .usize)), some ([ty85, ty20], .bool), some ([(.uint .usize), ty276, ty292, ty85], ty286), some ([(.uint .usize), ty276, ty292, ty251, ty85], ty317), some ([(.uint .usize), ty276, ty292, ty85, ty86], ty309), some ([.bool, ty258], ty259), some ([(.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize)], ty95), some ([(.uint .usize), (.uint .usize)], ty91), some ([(.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize)], ty95), some ([(.uint .usize), (.uint .usize), ty20, (.uint .usize)], ty282), some ([(.uint .usize), (.uint .usize)], (.uint .usize)), some ([ty20, (.uint .usize)], ty281), some ([ty20, ty20], .bool), some ([ty221, ty221], ty221), some ([ty20], (.uint .usize)), some ([ty20, (.uint .usize)], ty282), some ([], (.uint .usize)), some ([ty47, (.uint .usize)], .bool), some ([ty155, ty298], ty298), some ([ty158, ty247, ty155], ty146), some ([ty8], (.uint .usize)), some ([ty27, ty20, (.uint .usize)], ty146), some ([ty20], ty251), some ([ty20, ty314], ty314), some ([ty120, ty122, ty27, ty20], ty315), some ([ty128, ty119, ty27, ty20], ty151), some ([ty108, ty110, ty27, ty20, (.uint .usize)], ty146), some ([], (.uint .usize)), some ([(.uint .usize), ty128, ty123, ty302], .bool), some ([ty304], ty303), some ([(.uint .usize), ty276, ty20, ty86], ty305), some ([(.uint .usize), ty85], ty138), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([ty226, ty20], .bool), some ([ty85], ty226), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize))]),
  (41, [some ([], (.uint .usize)), some ([], (.uint .usize)), some ([(.uint .usize), ty276, ty292, ty85], ty286), some ([(.uint .usize)], .bool), some ([(.uint .usize), ty276, ty292, ty286, ty85], ty286), some ([], (.uint .usize)), some ([(.uint .usize), ty276, ty286, ty85], ty286), some ([], (.uint .usize)), some ([ty286], ty286), some ([], (.uint .usize)), some ([ty286], ty286), some ([(.uint .usize), ty276, ty292, ty85, ty85], ty286), some ([], (.uint .usize)), some ([(.uint .usize), ty276, ty292, ty85], ty286), some ([], (.uint .usize)), some ([ty318], ty286), some ([ty276, ty292, ty85], ty318), some ([], (.uint .usize)), some ([ty20], ty286), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([ty20], ty286), some ([], (.uint .usize)), some ([ty20], ty286), some ([(.uint .usize), ty276, ty292, ty317, ty85], ty317), some ([(.uint .usize), ty276, ty317, ty85], ty317), some ([ty317], ty317), some ([ty317], ty317), some ([(.uint .usize), ty276, ty292, ty251, ty85], ty317), some ([(.uint .usize), ty276, ty292, ty251, ty85], ty317), some ([], (.uint .usize)), some ([(.uint .usize), ty276, ty292, ty251, ty85], ty317), some ([], (.uint .usize)), some ([(.uint .usize), ty276, ty292, ty251, ty85], ty317), some ([], (.uint .usize)), some ([(.uint .usize), ty276, ty292, ty85, ty86], ty309), some ([(.uint .usize), ty276, ty292, ty85], ty309), some ([ty309, ty309], ty309), some ([(.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize)], ty95), some ([(.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize)], ty95)]),
  (41, [some ([ty20, (.uint .usize), (.uint .usize)], ty281), some ([(.uint .usize), ty20], (.uint .usize)), some ([(.uint .usize), ty20, (.uint .usize)], ty282), some ([ty298], ty297), some ([ty158, ty247, ty154], ty146), some ([ty20, ty27, ty20, (.uint .usize)], ty146), some ([ty9], ty251), some ([ty128, ty117, ty119, ty27, ty20], ty151), some ([(.uint .usize), ty128, ty123, ty302], ty252), some ([(.uint .usize), ty128, ty123, ty302, ty276], .bool), none, some ([ty337, ty305], ty305), some ([ty251, ty338], ty337), some ([(.uint .usize), ty276, ty85], ty338), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([(.uint .usize), ty276, ty292, ty286, ty339, ty85], ty286), some ([(.uint .usize)], ty339), some ([ty179, ty286], ty286), some ([(.uint .usize), ty276, ty85], ty179), some ([ty276, ty292, ty85, ty85], ty286), some ([(.uint .usize), ty276, ty151], ty286), some ([ty292, ty20], ty318), some ([], ty20), some ([ty20], ty146), some ([(.uint .usize)], ty286), some ([(.uint .usize), ty20], ty286), some ([ty20, ty320, (.uint .usize)], ty322), some ([], ty320), some ([ty321], ty15), some ([(.uint .usize), ty317, ty317], ty317)]),
  (41, [some ([ty179, ty317], ty317), some ([ty193], ty286), some ([ty193], ty192), some ([ty85], .bool), some ([(.uint .usize), ty276, ty292, ty251, ty85, ty85], ty317), some ([ty85], .bool), some ([(.uint .usize), ty276, ty292, ty251, ty85], ty317), some ([], (.uint .usize)), some ([ty318, ty317], ty317), some ([(.uint .usize), ty276, ty292, ty251, ty317, ty85], ty317), some ([(.uint .usize), ty276, ty292, ty85], ty317), some ([.bool, ty317], ty317), some ([ty318], .bool), some ([ty340], .bool), some ([ty116, ty27, ty20], ty340), some ([(.uint .usize), ty276, ty292, ty251, ty344, ty86], ty317), some ([ty276, ty313], ty344), some ([], (.uint .usize)), some ([(.uint .usize), ty276, ty292, ty251, (.uint .usize), ty108, ty86], ty317), some ([(.uint .usize), ty276, ty292, ty251, ty317, ty85], ty317), some ([], (.uint .usize)), some ([ty251], ty324), some ([ty323, ty146, ty317], ty317), some ([ty323, ty345], ty317), some ([(.uint .usize), ty276, ty292, ty252, ty86], ty345), some ([ty154, (.uint .usize)], ty155), some ([(.uint .usize), ty276, ty292, ty85], .bool), some ([(.uint .usize), ty276, (.uint .usize), ty20, ty85, ty86], ty309), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([(.uint .usize), ty276, ty292, ty85], .bool), some ([(.uint .usize), ty276, ty292, ty290, ty85, ty309], ty309), some ([(.uint .usize), ty85], .bool), some ([(.uint .usize), ty276, ty292, ty290, ty85, ty309], ty309), some ([(.uint .usize), ty276, ty292, ty290, ty351, ty86], ty326), some ([(.uint .usize), ty276, ty292, ty154, ty85], ty351), some ([(.uint .usize), (.uint .usize), ty18, (.uint .usize), ty309], ty309), some ([ty290], (.uint .usize)), some ([(.uint .usize), ty154, ty351, ty309], ty309), some ([], (.uint .usize)), some ([(.uint .usize), ty276, ty292, ty85], ty331)]),
  (41, [some ([(.uint .usize), ty154, ty329, ty309], ty309), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([(.uint .usize), ty85], ty138), some ([(.uint .usize), ty276, ty292, ty85, ty332], ty309), some ([(.uint .usize), ty276, ty292, ty85], ty309), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([(.uint .usize), ty276, ty292, ty85, ty309, ty309], ty309), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([(.uint .usize), ty276, ty292, ty85, ty309], ty309), some ([], (.uint .usize)), some ([(.uint .usize), ty276, ty292, ty85], ty309), some ([(.uint .usize), ty85], .bool), some ([(.uint .usize), ty85], ty138), some ([(.uint .usize), ty85], .bool), some ([(.uint .usize), ty276, ty292, ty85], ty309), some ([(.uint .usize), ty276, ty292, ty85], ty309), some ([ty194, ty309], ty309), some ([(.uint .usize), (.uint .usize), ty20, (.uint .usize)], ty282), none, some ([ty247, ty146], ty146), some ([ty128, ty27, ty20], ty151), some ([(.uint .usize), ty276, ty27, ty85, ty154, ty335], ty336), some ([], ty335), some ([ty27, ty336], ty252), some ([(.uint .usize), ty276, ty27, ty86, ty155, ty335], ty336), some ([ty301], ty155), some ([ty338, ty301], .bool), some ([(.uint .usize), ty276, ty85], ty338), some ([ty251, ty154], .bool), some ([ty302, ty305], ty305), some ([], (.uint .usize)), some ([ty276, ty151, ty252], ty338), some ([(.uint .usize), ty85, ty85], ty151), some ([(.uint .usize), ty276, ty87], ty252), some ([(.uint .usize), ty276, ty292, ty15, ty339, ty85], ty286)]),
  (41, [some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([ty9, ty286], ty286), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([(.uint .usize), ty276, ty20], ty179), some ([(.uint .usize), ty146], ty286), some ([ty276, ty154, ty20], ty146), some ([(.uint .usize), ty128, ty114], ty286), some ([ty290, ty292, ty20], ty318), some ([(.uint .usize), ty20, ty20], ty146), some ([ty146], ty286), some ([ty20], ty286), some ([ty320, (.uint .usize), (.uint .usize), .bool, (.uint .usize)], ty322), some ([(.uint .usize), ty20, ty320, (.uint .usize)], ty322), some ([(.uint .usize), (.uint .usize), ty320, .bool, (.uint .usize)], (.uint .usize)), some ([], (.uint .usize)), some ([ty28, ty317, ty317], ty317), some ([], (.uint .usize)), some ([ty14, ty317, ty317], ty317), none, some ([ty151, ty27], .bool), some ([], ty27), some ([], ty27), some ([], ty20)]),
  (41, [some ([], ty20), some ([(.uint .usize), ty276, ty292, ty86], ty317), some ([], ty20), some ([(.uint .usize), ty276, ty292, ty86], ty317), some ([(.uint .usize), ty85, ty85], ty342), some ([ty27], ty314), some ([(.uint .usize), ty276, ty292, ty251, ty313, ty86, ty86], ty317), some ([(.uint .usize)], .bool), some ([(.uint .usize), ty276, ty292, ty251, ty358, ty85, ty287, ty86], ty317), some ([(.uint .usize), ty128, ty113, (.uint .usize), ty20, ty154], ty358), some ([ty193], ty287), some ([(.uint .usize), ty276, ty292, ty251, ty193, ty85], ty317), some ([ty114, ty116, ty27, ty20], ty340), some ([ty252], .bool), some ([ty108, (.uint .usize), ty251], ty252), some ([(.uint .usize), ty128, (.uint .usize), (.uint .usize), ty252], ty252), some ([(.uint .usize), ty276, ty292, (.uint .usize), ty108, (.uint .usize), ty252, ty345], ty317), some ([ty276, ty20], ty344), some ([ty276, ty27, ty20], ty344), some ([ty360], ty344), some ([ty110, ty27, ty20, (.uint .usize)], ty360), some ([ty27, ty86], .bool), some ([(.uint .usize), ty128, (.uint .usize), ty252], ty252), some ([(.uint .usize), ty276, ty292, (.uint .usize), ty108, ty252, ty345], ty317), some ([ty86], ty86), some ([(.uint .usize), ty276, ty292, ty193], ty251), some ([ty154], ty200), some ([(.uint .usize), ty276, ty292, ty251, ty193, ty154, ty108, ty299, ty85], ty317), some ([(.uint .usize), ty276, ty292, ty251, (.uint .usize), ty193, ty154, ty86, ty345], ty317), some ([ty251, ty86], ty252), some ([ty86], ty86), some ([ty154], ty324), some ([ty193, (.uint .usize)], ty287), some ([ty287], (.uint .usize)), some ([ty317, ty345], ty345), some ([ty252], ty251), some ([ty252], ty252), some ([(.uint .usize), ty85], .bool), some ([(.uint .usize), ty85], ty226), some ([(.uint .usize), ty276, (.uint .usize), ty20, ty20, ty86], ty309), some ([ty85], .bool)]),
  (41, [some ([(.uint .usize), ty276, ty292, ty85], .bool), some ([(.uint .usize), ty87], .bool), some ([(.uint .usize), ty276, ty292, ty85], ty350), some ([(.uint .usize), ty276, ty349, ty85], ty87), some ([ty349, ty309], ty309), some ([(.uint .usize), ty276, ty292, ty349, ty290, ty194, (.uint .usize), ty348, ty86], ty309), some ([ty351], ty352), some ([ty154], ty146), some ([(.uint .usize), ty276, ty292, (.uint .usize), (.uint .usize), ty18, ty85, ty86], ty326), some ([(.uint .usize), ty276, ty292, ty85], ty351), some ([(.uint .usize), ty276, ty292, ty85], ty351), some ([ty154, ty317], ty351), some ([(.uint .usize), ty276, ty292, ty85], ty353), some ([ty353], ty331), some ([(.uint .usize), ty276, ty292, ty317], ty331), some ([(.uint .usize), ty154, ty329, ty194], ty309), some ([ty85], ty138), some ([(.uint .usize), ty276, ty292, ty85], ty355), some ([ty354, ty309], ty309), some ([(.uint .usize), ty276, ty292, ty354, ty332, .bool, .bool, ty86], ty309), some ([(.uint .usize), ty276, ty292, ty85], ty309), some ([ty317], ty309), some ([ty317, ty309, ty309], ty309), some ([ty317, ty309], ty309), some ([(.uint .usize), ty276, ty292, ty85], ty309), some ([(.uint .usize), ty276, ty292, ty349, (.uint .usize), ty348, ty86], ty309), some ([], (.uint .usize)), some ([(.uint .usize), ty276, ty292, ty85, (.uint .usize), ty85], ty309), some ([(.uint .usize), ty276, ty292, ty138, (.uint .usize), ty85], ty309), some ([(.uint .usize), ty276, ty292, ty85], ty309), some ([ty247, (.uint .usize)], ty356), some ([.bool, ty27], ty151), some ([ty128, ty27], .bool), some ([ty154], ty251), some ([(.uint .usize), ty276, ty27, ty151, ty87, ty154, ty335], ty336), some ([ty27, ty335], ty252), some ([(.uint .usize), ty276, ty27, ty86, ty155, ty336], ty336), some ([(.uint .usize), ty276, ty27, ty85, ty154, ty335], ty336), some ([ty301, ty301], .bool), some ([ty302, ty304], ty304), some ([ty276, ty313, ty252], ty338)]),
  (41, [some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([ty14, ty15, ty286], ty286), some ([ty154], ty179), some ([ty251], ty179), some ([ty244, ty20], ty146), some ([ty286], .bool), some ([ty251, ty47], ty286), some ([ty85], ty47), some ([ty251, ty286], ty286), some ([ty146, ty20, ty20], ty146), some ([(.uint .usize)], ty146), some ([ty20, (.uint .usize)], ty146), some ([(.uint .usize), ty20], ty286), some ([(.uint .usize)], .bool), some ([ty320, (.uint .usize)], ty320), some ([ty20, ty320, (.uint .usize), (.uint .usize)], ty322), some ([ty20, ty320, (.uint .usize), (.uint .usize)], ty322), some ([ty320], ty146), some ([(.uint .usize), (.uint .usize), ty320, .bool, (.uint .usize), (.uint .usize)], (.uint .usize)), some ([ty14, ty193, ty193], ty193), some ([], ty20), some ([], ty20), some ([], ty20), some ([ty276, ty292, ty138], ty317), some ([ty276, ty292, ty138], ty317), some ([ty20, ty87], ty342), some ([ty20, ty342], ty342), some ([ty27], .bool), some ([ty276, ty313], .bool), some ([(.uint .usize), ty276, ty292, ty251, ty313, ty86, ty86], ty317), some ([ty86], .bool), some ([(.uint .usize), ty276, ty292, ty251, (.uint .usize), ty111, ty336, ty287, ty86], ty317), some ([(.uint .usize), ty276, ty111, ty335, ty85], ty336), some ([(.uint .usize), ty128, ty111, ty113, (.uint .usize), ty20, ty154], ty358), some ([ty251, ty85], ty251), some ([(.uint .usize), ty276, ty251, ty20], ty358), some ([ty276, ty193, ty251, ty20], ty317), some ([ty193], .bool), some ([ty193, ty317], ty317)]),
  (41, [some ([ty292, ty193], ty318), some ([.bool, ty155], ty252), some ([ty298, (.uint .usize)], ty252), some ([(.uint .usize), ty276, ty292, (.uint .usize), ty108, ty252, ty87, ty287], ty251), some ([ty107, (.uint .usize)], ty87), some ([ty110, ty119, ty27, ty20], ty360), some ([ty343, ty360], ty360), some ([ty359], ty360), some ([ty110, ty146, ty20], ty344), some ([], ty360), some ([ty108, ty110, ty27, ty20, (.uint .usize)], ty360), some ([(.uint .usize), ty276, ty292, ty15], ty251), some ([(.uint .usize), ty128, ty156], ty251), some ([ty14, ty251], ty251), some ([.bool, ty251, ty251], ty251), some ([ty193], .bool), some ([ty318], ty251), some ([ty292, (.uint .usize)], ty318), some ([(.uint .usize), ty128, ty251, (.uint .usize)], ty251), some ([ty251], ty251), some ([ty193, ty154, ty251, ty368], ty317), some ([(.uint .usize), ty276, ty292, ty251, ty108, ty348, ty86], ty368), some ([ty27, ty298], ty348), some ([ty154], .bool), some ([(.uint .usize), ty276, ty292, ty251, ty287], ty251), some ([ty292, (.uint .usize), ty193, ty154, ty154, ty86, ty287], ty317), some ([ty154, ty86], ty155), some ([], ty20), some ([ty85, ty85], ty226), some ([(.uint .usize), ty276, (.uint .usize), ty20, ty20, ty85], ty309), some ([ty85], .bool), some ([(.uint .usize), ty86], .bool), some ([(.uint .usize), ty86], .bool), some ([(.uint .usize), ty86], (.uint .usize)), some ([(.uint .usize), ty276, ty292, ty85, ty317], ty350), some ([(.uint .usize), ty276, ty108, ty348, ty86], ty87), some ([(.uint .usize), ty276, ty292, ty349, ty290, ty194, (.uint .usize), ty346, ty85, ty309], ty309), some ([ty347], ty348), some ([.bool, (.uint .usize)], ty146), some ([ty251], .bool), some ([ty351, (.uint .usize)], .bool)]),
  (41, [some ([(.uint .usize), ty276, ty292, ty85], ty351), some ([ty353], ty351), some ([ty154, ty193], ty329), some ([(.uint .usize), ty276, ty292, ty85], ty353), some ([.bool, ty154, ty329], ty331), some ([ty193], .bool), some ([.bool, (.uint .usize), ty15, (.uint .usize), ty194], ty309), some ([ty154], .bool), some ([ty251, (.uint .usize), ty15, ty15, ty194], ty309), some ([.bool, (.uint .usize), ty154, ty328, ty194], ty309), some ([ty276, ty292, ty85, ty193, ty154], ty355), some ([.bool, ty354], ty309), some ([(.uint .usize), ty276, ty292, ty354, ty332, .bool, .bool, ty85, ty86], ty309), some ([(.uint .usize), ty154, ty351], ty309), some ([ty193], ty194), some ([ty193, ty194, ty194], ty194), some ([ty193, ty194], ty194), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([(.uint .usize), (.uint .usize), (.uint .usize), ty154, ty15, (.uint .usize), ty309], ty309), some ([], (.uint .usize)), some ([ty290], ty362), some ([(.uint .usize), (.uint .usize), ty361, ty309], ty309), some ([.bool, (.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize), ty154, ty309], ty309), some ([(.uint .usize), ty276, ty292, ty349, (.uint .usize), ty346, ty85, ty309], ty309), some ([ty276, ty292, ty85], .bool), some ([(.uint .usize), ty276, ty292, ty85, ty85], ty309), some ([(.uint .usize), ty276, ty292, ty290, (.uint .usize), ty85], ty309), some ([(.uint .usize), ty276, ty292, ty290, ty20, ty85], ty309), some ([(.uint .usize), ty276, ty292, ty290, ty85, ty85], ty309), some ([(.uint .usize), ty276, ty292, ty85, (.uint .usize), ty85], ty309), some ([ty352], ty309), some ([(.uint .usize), ty276, ty292, ty85], ty352), some ([], ty20), some ([(.uint .usize), ty276, ty292, ty87], ty309), some ([ty317], ty309), some ([ty85], .bool), some ([ty353], ty309)]),
  (41, [some ([(.uint .usize), ty276, ty292, ty85], ty353), some ([(.uint .usize), ty276, ty27, ty27, ty86, ty154, ty335], ty336), some ([ty335, ty20], ty251), some ([ty15], .bool), some ([ty154, .bool, ty146], ty286), some ([ty154, .bool, ty146], ty286), some ([], ty20), some ([ty45], ty47), some ([ty86], ty47), some ([ty154, ty15], ty286), some ([(.uint .usize), ty20, (.uint .usize)], ty146), some ([(.uint .usize), ty20, (.uint .usize)], ty146), some ([ty20], ty286), some ([(.uint .usize), ty20], ty286), some ([ty20, (.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize)], ty286), some ([ty320, ty320, .bool], ty320), some ([ty320], ty320), some ([(.uint .usize), (.uint .usize)], ty320), some ([(.uint .usize), ty20, ty320, (.uint .usize), (.uint .usize)], ty322), some ([(.uint .usize), ty20, ty320, (.uint .usize), (.uint .usize)], ty322), some ([.bool, ty146], ty146), some ([ty319], ty320), some ([(.uint .usize)], (.uint .usize)), some ([(.uint .usize), (.uint .usize), ty320, ty320], (.uint .usize)), some ([ty320, (.uint .usize)], ty320), some ([.bool], ty320), some ([.bool, ty318], ty317), some ([.bool, ty318], ty317), some ([], ty27), some ([ty276, ty27, ty20], .bool), some ([ty146], .bool), some ([ty113, ty27, ty20, (.uint .usize)], ty146), some ([(.uint .usize), ty276, ty292, ty251, ty358, ty287, ty86], ty317), some ([(.uint .usize), ty276, ty292, ty251, (.uint .usize), ty111, ty86, ty86], ty317), some ([(.uint .usize), ty276, ty292, ty251, (.uint .usize), ty111, ty335, ty287, ty86], ty317), some ([ty27, ty252, ty335], ty336), some ([(.uint .usize), ty128, ty111, ty154], ty363), some ([.bool, (.uint .usize), ty335], ty358), some ([(.uint .usize), ty128, ty113, ty20, ty154], .bool), some ([ty154], ty154), some ([ty128, ty193, ty154, (.uint .usize)], ty193)]),
  (41, [some ([ty193], ty146), some ([(.uint .usize), ty276, ty292, ty287], ty252), some ([(.uint .usize), ty252], ty251), some ([(.uint .usize), ty276, ty27, ty86, ty155, ty335], ty336), some ([ty110, ty117, ty119, ty27, ty20], ty360), some ([ty360], ty359), none, some ([ty108, (.uint .usize), ty20], ty344), some ([ty318], ty251), some ([(.uint .usize), ty128, ty318, (.uint .usize)], ty251), some ([ty15], .bool), some ([(.uint .usize), ty128, ty111, ty156], ty251), some ([ty154], ty251), some ([ty290, ty292, (.uint .usize)], ty318), some ([(.uint .usize), ty128, ty154, (.uint .usize)], ty251), some ([ty251, ty367], ty251), some ([ty367], ty27), some ([ty367], ty287), some ([(.uint .usize), ty276, ty108, ty348, ty86], ty87), some ([(.uint .usize), ty276, ty292, ty251, ty108, ty348, ty86], ty368), some ([], ty348), some ([ty346, ty348], ty348), some ([ty15, ty154, ty154, .bool, .bool, ty86, ty287], ty317), some ([.bool, (.uint .usize), ty154, ty193, ty154, ty317], ty317), some ([], (.uint .usize)), some ([ty20], ty226), some ([ty251], .bool), some ([(.uint .usize), ty276, (.uint .usize), ty20, ty20, ty85], ty309), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([(.uint .usize), ty85], ty138), some ([(.uint .usize), ty85], .bool), some ([.bool], (.uint .usize)), some ([ty276, ty292, ty85, ty193, ty154, ty108, ty299], ty350), some ([(.uint .usize), ty276, ty86], ty308), some ([(.uint .usize), ty276, ty108, ty348, ty86, .bool], ty87), some ([(.uint .usize), ty276, ty292, ty108, ty346, ty85], ty370), some ([ty349, (.uint .usize), ty369, ty346, ty309, ty309], ty309), some ([ty369], ty292), some ([(.uint .usize), ty276, ty292, ty290, ty194, ty85], ty309)]),
  (41, [none, some ([ty146, (.uint .usize)], .bool), some ([ty15], ty146), some ([(.uint .usize), ty276, ty292, ty85, ty85], ty351), some ([ty193, ty374], ty329), some ([ty193], ty374), some ([ty193, (.uint .usize), ty286], ty329), some ([.bool, ty193, ty352], ty329), some ([ty287], ty352), some ([.bool, ty193, (.uint .usize), ty352], ty329), some ([ty193, ty146, ty154, ty375], ty329), some ([ty27, ty287], ty375), some ([ty85], .bool), some ([(.uint .usize), ty276, ty292, ty85], ty353), some ([ty85], .bool), some ([(.uint .usize), ty276, ty292, ty85], ty353), some ([ty15], .bool), some ([ty328, ty194], ty194), some ([ty292, (.uint .usize), (.uint .usize), ty193, ty154, ty154], ty355), some ([ty85], .bool), some ([ty86, ty309], ty309), some ([(.uint .usize), ty276, ty292, ty332, ty85], ty309), some ([ty286, ty309, ty309], ty309), some ([(.uint .usize), ty154, ty85], ty286), some ([ty85], .bool), some ([ty85], .bool), some ([.bool, ty194], ty309), some ([(.uint .usize), ty324], ty362), some ([(.uint .usize), ty276, ty292, ty85], ty309), some ([ty318], .bool), some ([.bool, ty309], ty309), some ([ty193, (.uint .usize), ty317], ty309), some ([(.uint .usize), ty276, ty292, ty290, (.uint .usize), ty353, ty85], ty309), some ([(.uint .usize), (.uint .usize), ty317], ty309), some ([(.uint .usize), (.uint .usize), ty317, ty317], ty309), some ([(.uint .usize), ty276, ty292, ty376, ty85, ty85], ty309), some ([(.uint .usize)], ty376), some ([(.uint .usize), ty317], ty309), some ([(.uint .usize), ty193, ty317], ty317), some ([(.uint .usize), ty276, ty292, ty290, ty146, (.uint .usize), ty85], ty309), some ([ty15, ty15, ty146, ty18], ty309)]),
  (41, [some ([ty15], ty146), some ([(.uint .usize), ty276, ty292, ty86], ty352), some ([ty317], ty309), some ([], (.uint .usize)), some ([(.uint .usize), ty276, ty292, (.uint .usize), (.uint .usize), ty317], ty353), some ([ty27, ty27, ty86], ty226), some ([ty335, ty20, ty154], ty336), some ([ty27, ty86], ty251), some ([.bool, ty335], ty336), some ([(.uint .usize), ty276, ty27, ty146, ty86, ty200, ty335], ty336), some ([ty333, ty335, ty20], ty251), some ([ty334], ty335), some ([ty234], .bool), some ([ty154, .bool, (.uint .usize)], ty286), some ([ty47, ty47], ty47), some ([ty4, (.uint .uint64)], ty286), some ([.i32], ty286), some ([ty4, .i32], ty286), some ([ty15, ty15], ty286), some ([ty8, ty15], ty286), some ([ty4, ty15], ty286), some ([ty154, ty9, ty15], ty286), some ([(.uint .usize), (.uint .usize), ty20, (.uint .usize)], ty146), some ([ty146, ty20], ty286), some ([(.uint .usize)], ty146), some ([(.uint .usize), (.uint .usize), ty20], ty286), some ([(.uint .usize), ty20, (.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize)], ty286), some ([.bool], ty320), some ([.bool, ty320], ty320), some ([.bool, .bool], .bool), some ([.bool, .bool, .bool], .bool), some ([(.uint .usize)], .bool), some ([(.uint .usize)], (.uint .usize)), some ([ty20, ty320, (.uint .usize), (.uint .usize)], ty322), some ([.bool], ty146), none, some ([ty320], (.uint .usize)), some ([(.uint .usize), (.uint .usize)], (.uint .usize)), some ([.bool], (.uint .usize)), some ([(.uint .usize), (.uint .usize), ty320, ty320], .bool), some ([ty320, (.uint .usize)], ty320)]),
  (41, [some ([ty320, ty320], ty373), some ([ty320, ty320, .bool], .bool), some ([ty320], .bool), some ([.bool, ty320], ty320), some ([ty320], (.uint .usize)), some ([ty320], ty319), some ([], ty20), some ([], ty20), some ([], ty20), some ([ty276, ty226], .bool), some ([ty276, ty146, ty20], .bool), some ([ty111, ty113, ty27, ty20, (.uint .usize)], ty146), some ([(.uint .usize), ty276, (.uint .usize), ty111, ty86], ty200), some ([.bool, ty345], ty345), some ([(.uint .usize), ty128, ty111, ty252], ty252), some ([ty292, ty252, ty345], ty345), some ([(.uint .usize), ty276, ty292, ty251, (.uint .usize), ty111, ty335, ty287, ty345], ty317), some ([ty252, ty287], ty252), some ([(.uint .usize), ty276, ty292, ty252, ty86], ty345), some ([(.uint .usize), ty111], ty87), some ([(.uint .usize), ty276, ty292, (.uint .usize), ty111, ty27, ty86, ty379], ty317), some ([(.uint .usize), ty276, ty292, ty111, ty27, ty86, ty287, ty86, ty336], ty379), some ([(.uint .usize), ty128, ty111, ty27, ty335, ty251], ty336), some ([ty27, ty155, ty335], ty336), some ([(.uint .usize), ty276, ty27, ty85, ty154, ty335], ty363), some ([ty128, ty111], ty276), some ([ty363], .bool), some ([ty128, ty154, (.uint .usize)], ty156), some ([(.uint .usize), ty276, ty27, ty86, ty155, ty336], ty336), some ([ty360, ty360], ty360), none, some ([ty111], ty138), some ([ty366], ty367), some ([(.uint .usize), ty276, ty108, ty348, ty86, .bool], ty87), some ([], ty367), some ([ty381, ty368], ty368), some ([(.uint .usize), ty276, ty292, ty251, ty108, ty346, ty85], ty381), some ([ty348], ty347), some ([ty15, ty154, ty154, .bool, ty85, ty193, ty86, ty317], ty317), some ([.bool, ty20], ty226), some ([(.uint .usize), ty276, (.uint .usize), ty20, ty20, (.uint .usize), ty138], ty309)]),
  (41, [some ([ty85], ty138), some ([ty292, (.uint .usize), (.uint .usize), ty193, ty154, ty108, ty348, ty154], ty350), some ([ty308, ty308], ty308), some ([(.uint .usize), ty276, ty85], ty308), some ([(.uint .usize), ty276, ty108, ty348, ty86, .bool], ty87), some ([(.uint .usize), ty108, ty348, ty86], ty87), some ([], (.uint .usize)), some ([ty151, ty108, ty20], .bool), some ([], (.uint .usize)), some ([ty276, ty292, ty86, ty155], ty370), some ([ty349, (.uint .usize), ty20, ty155, ty194, ty194], ty309), some ([(.uint .usize), ty276, ty292, ty290, ty194, ty85], ty309), some ([ty290], (.uint .usize)), some ([ty290], ty154), some ([ty352], ty351), some ([ty352], ty351), some ([ty352], ty351), some ([(.uint .usize), ty276, ty318, (.uint .usize)], ty353), some ([.bool, (.uint .usize)], ty287), some ([.bool, ty354], ty355), some ([ty226], .bool), some ([(.uint .usize), ty286], ty286), some ([(.uint .usize), ty276, ty292, ty85], ty309), some ([ty193], .bool), some ([(.uint .usize), ty193], .bool), some ([.bool, (.uint .usize), (.uint .usize), ty328], ty309), some ([(.uint .usize), (.uint .usize), ty193], ty194), some ([(.uint .usize), ty193, ty193], ty194), some ([ty30, ty193, (.uint .usize), ty317], ty309), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([(.uint .usize), ty193], ty194), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([(.uint .usize)], ty339)]),
  (41, [some ([ty15], ty146), some ([.bool, ty15], ty146), some ([ty9], .bool), some ([ty286, ty352], ty352), some ([(.uint .usize), ty276, (.uint .usize), ty317, ty251, (.uint .usize)], ty353), some ([.bool, ty20], ty226), some ([ty333, ty335], ty335), some ([.bool, ty20], ty251), some ([(.uint .usize), ty276, ty27, .bool, ty86, ty155, ty335], ty336), none, some ([.bool, (.uint .usize)], ty286), some ([ty4, .bool, (.uint .usize)], ty286), some ([.bool, (.uint .usize)], ty286), some ([ty4, .bool, (.uint .usize)], ty286), some ([ty286], ty286), some ([(.uint .usize)], (.uint .usize)), some ([(.uint .usize), (.uint .usize)], ty146), some ([(.uint .usize), ty20, ty320, (.uint .usize), (.uint .usize)], ty322), some ([ty373, .bool, ty320], ty373), some ([.bool, .bool, .bool], .bool), none, some ([.bool, (.uint .usize), ty155], ty200), some ([ty292, ty252, ty287], ty345), some ([ty200, ty287], ty317), some ([(.uint .usize), ty128, (.uint .usize), ty111, ty335, ty252, ty251], ty200), some ([ty287, ty287], ty287), some ([(.uint .usize), ty276, ty292, ty251, ty85], ty317), some ([ty111, ty86], ty87), some ([(.uint .usize), ty276, ty292, (.uint .usize), ty111, ty27, ty86, ty378], ty200), some ([.bool, ty379], ty379), some ([(.uint .usize), ty128, ty111, ty27, ty85, ty335], ty251), some ([(.uint .usize), ty276, ty292, ty111, ty27, ty85, ty86, ty86, ty335, ty317], ty379), some ([ty292, ty251, ty317], ty317), some ([ty193, ty379], ty379), some ([(.uint .usize), ty276, ty292, ty111, ty27, ty85, ty193, ty335], ty336), some ([(.uint .usize), ty276, ty27, ty151, ty87, ty154, ty335], ty363), none, some ([(.uint .usize), ty276, ty108, ty348, ty86], ty87), some ([ty365, ty367], ty367), some ([(.uint .usize), ty276, ty251, ty370, ty85], ty381), none]),
  (41, [some ([ty86, ty193], ty317), some ([.bool, ty286, ty193], ty317), some ([ty15, ty154, ty85], ty286), some ([ty286, ty154, ty193, ty317], ty317), some ([ty20], ty226), some ([(.uint .usize), ty276, (.uint .usize), ty20, ty20, (.uint .usize), ty85], ty309), some ([], (.uint .usize)), some ([.bool, ty349], ty350), some ([ty276, ty87], ty308), some ([ty86], ty383), some ([(.uint .usize), ty276, ty108, ty348, ty86, ty138], ty87), some ([(.uint .usize), ty108, ty348, ty382], ty87), some ([(.uint .usize), ty108, ty348, ty86], ty87), some ([ty27, ty108], .bool), some ([ty276, ty292, ty85, ty154, ty86, ty155], ty370), some ([ty15, ty146, ty18], ty351), some ([], ty20), some ([(.uint .usize), ty287], .bool), some ([(.uint .usize), ty193, ty193, ty286], ty194), some ([(.uint .usize), (.uint .uint64), (.uint .usize), (.uint .usize)], ty146), some ([ty15, ty352], ty352), some ([.bool, (.uint .usize), ty317, ty154, (.uint .usize), ty154, ty299, ty299], ty353), some ([ty108], .bool), some ([ty335], ty334), some ([(.uint .usize), (.uint .usize)], ty146), some ([ty20, ty320, (.uint .usize), (.uint .usize), .bool], ty322), some ([ty320, ty320, .bool], ty320), some ([ty292, ty251, ty193], ty317), some ([(.uint .usize), ty128, (.uint .usize), ty111, ty335, ty252, ty154], ty200), some ([(.uint .usize), ty128, (.uint .usize), ty111, ty335, ty252], ty200), some ([ty138, ty87], ty87), some ([(.uint .usize), ty252], ty200), some ([(.uint .usize), ty276, ty27, ty86, ty252, ty335], ty336), some ([(.uint .usize), ty276, ty27, ty27, ty86, ty154, ty335], ty363), some ([(.uint .usize), ty86], ty308), some ([ty367], ty366), some ([(.uint .usize), ty276, ty369, ty317], ty381), some ([ty128, ty251, ty317], ty317), some ([.bool, ty193], ty317), some ([ty15, ty286], ty286), some ([(.uint .usize), ty20], ty226)]),
  (41, [some ([(.uint .usize), ty276, ty85], .bool), some ([(.uint .usize), ty87, (.uint .usize), ty20, ty20, (.uint .usize)], ty309), some ([ty276, ty86], .bool), some ([ty85], ty383), some ([ty85, ty383], ty383), some ([(.uint .usize), ty108, ty348, ty86], .bool), some ([ty138, ty385], ty87), some ([(.uint .usize), ty276, ty108, ty348, ty86, ty138], ty385), some ([(.uint .usize), ty108, ty348, ty86], .bool), some ([(.uint .usize), ty108, ty348, ty86, ty85], ty87), some ([ty86], (.uint .usize)), some ([ty348], (.uint .usize)), some ([(.uint .usize), ty108, ty348, ty86], ty87), some ([ty226], .bool), some ([ty110, ty20], .bool), some ([(.uint .usize), ty370], ty370), some ([(.uint .usize), ty317, ty154, (.uint .usize), ty154, ty299, ty299], ty353), some ([], ty20), some ([], ty20), some ([], ty20), some ([], ty20), some ([], ty20), some ([], ty20), some ([], ty20), some ([], ty20), none, some ([(.uint .usize), ty20, ty320, (.uint .usize), (.uint .usize), .bool], ty322), some ([ty292, ty251, ty146, ty193], ty317), some ([ty251], ty251), some ([(.uint .usize), ty128, (.uint .usize), ty111, ty27, ty336, ty154], ty200), some ([ty85, ty87], ty87), some ([ty336], ty363), some ([.bool, ty335], ty363), some ([(.uint .usize), ty276, ty27, ty146, ty86, ty200, ty335], ty363), some ([ty308], ty308), some ([(.uint .usize), ty85], ty308), none, some ([ty128, ty154, ty193], ty193), some ([.bool], ty226), some ([.bool, (.uint .usize), ty226], ty226), some ([(.uint .usize)], .bool)]),
  (41, [some ([ty27], .bool), some ([(.uint .usize), ty276, ty86], .bool), some ([.bool, ty286, (.uint .usize), ty20, (.uint .usize)], ty309), some ([ty86], .bool), some ([(.uint .usize), ty85, ty20], .bool), some ([(.uint .usize), ty85], ty286), some ([ty276, ty85], .bool), some ([(.uint .usize), ty108, ty348, ty85], .bool), some ([ty138, ty384], ty87), some ([ty387, ty385], ty385), some ([(.uint .usize), ty276, ty346, ty87, ty138], ty387), some ([(.uint .usize), ty108, ty20, ty86], ty87), some ([(.uint .usize), ty108, ty20, ty86], ty86), some ([ty85, ty346], ty85), some ([(.uint .usize), ty317, ty154, ty251, (.uint .usize), ty154, ty252], ty353), some ([ty252], ty251), some ([.bool, ty155], ty252), some ([ty20, ty320, (.uint .usize), (.uint .usize), .bool, (.uint .usize)], ty322), some ([(.uint .usize), ty154, ty318, ty193], ty317), some ([(.uint .usize), ty276, ty27, .bool, ty86, ty155, ty335], ty363), some ([ty128, ty154, ty156, ty191, ty193], ty193), some ([ty27], .bool), some ([ty251], .bool), some ([], ty27), some ([(.uint .usize), ty87, ty20], .bool), some ([ty85, ty85], ty286), some ([ty276, ty226], .bool), some ([(.uint .usize), ty108, ty20, ty85], .bool), some ([.bool, ty86], ty87), some ([ty386, ty385], ty385), some ([ty138, ty346], ty387), some ([(.uint .usize), ty276, ty346, ty85, ty86, ty86, ty138, ty308], ty387), some ([ty308, ty85, ty87], ty87), some ([(.uint .usize), ty108, ty20, ty85], ty308), some ([.bool, ty85, ty86], ty86), some ([ty85, ty155], ty85), some ([(.uint .usize), ty20, ty320, (.uint .usize), (.uint .usize), .bool, (.uint .usize)], ty322), some ([(.uint .usize), ty276, ty27, ty86, ty155, ty335], ty363), some ([.bool, ty154, ty156, ty191, ty193], ty193), some ([ty27], .bool), some ([], ty20)]),
  (41, [some ([(.uint .usize), ty276, ty346, ty85, ty86, ty86, ty138, .bool], ty387), some ([ty108, ty20, ty151], ty308), some ([], (.uint .usize)), some ([ty85, (.uint .usize), ty155], ty86), some ([(.uint .usize), ty276, ty27, ty86, ty155, ty363], ty363), some ([(.uint .usize), ty276, ty27, ty85, ty154, ty335], ty363), some ([], ty20), some ([ty27], .bool), some ([(.uint .usize), ty276, ty346, ty85, ty86, ty138], ty387), some ([(.uint .usize), ty276, ty85, ty86], ty387), some ([ty85, (.uint .usize)], ty85), some ([(.uint .usize), ty85], ty87), some ([(.uint .usize), ty276, ty346, ty85, ty86, ty86, ty138], ty387), some ([ty85, ty308], ty387), some ([ty276, ty86, (.uint .usize)], ty146), some ([(.uint .usize), ty276, ty346, ty85, ty86, (.uint .usize), ty86, ty138], ty387), some ([ty85, .bool], ty387), some ([.bool, (.uint .usize), ty146], ty146), some ([ty86, (.uint .usize)], ty138), some ([(.uint .usize), ty276, ty85, ty86, (.uint .usize), ty85, ty154, ty87, ty138], ty387), some ([(.uint .usize), ty276, ty86, (.uint .usize), ty86], ty87), some ([(.uint .usize), ty276, ty85, ty86, (.uint .usize), ty85, ty154, ty86, ty85], ty387), some ([ty85, ty86, (.uint .usize), ty85, ty86], ty85), some ([(.uint .usize), ty276, ty86, (.uint .usize), ty85, .bool, ty87, ty87], ty87), some ([ty86], .bool), some ([ty86], .bool), some ([(.uint .usize), ty85, ty86, (.uint .usize), ty85, ty86, ty85, ty308], ty387), some ([(.uint .usize), ty276, ty154, ty86], ty308), some ([ty86, (.uint .usize), ty85], ty86), some ([ty85], ty85), some ([ty85], ty85), some ([.bool, ty138, ty87], ty87), some ([ty276, ty86, ty86, (.uint .usize), (.uint .usize), .bool], .bool), some ([(.uint .usize), ty276, ty85, ty85], ty138), some ([(.uint .usize), ty85, ty86, (.uint .usize), ty85, ty86, ty85, .bool], ty387), some ([(.uint .usize), ty276, ty244, ty86], ty308), some ([ty85], ty85), some ([ty276, ty85, ty85, .bool, .bool], .bool), some ([ty85, ty85, ty308], ty138), some ([(.uint .usize), ty226, ty85], ty308), some ([ty85, ty85], ty85)]),
  (14, [some ([ty85, ty86, (.uint .usize), ty85, ty86, ty85, ty308], ty387), some ([(.uint .usize), ty86, (.uint .usize), (.uint .usize), ty85], ty308), some ([(.uint .usize), ty276, ty108, ty86], ty308), some ([ty85, ty20], ty85), some ([], ty20), some ([ty226, ty226], .bool), some ([.bool, ty85, ty85], ty138), some ([(.uint .usize), ty86, ty20], ty308), some ([ty85, ty86, (.uint .usize), ty85, ty86, ty85, .bool], ty387), some ([(.uint .usize), ty85, .bool, ty85], ty308), some ([(.uint .usize), ty276, ty108, ty27, ty86], ty308), some ([ty85], ty85), some ([(.uint .usize), ty276, ty108, ty20, ty86], ty308), some ([(.uint .usize), ty276, ty108, ty20, ty85], ty308)])]

end

theorem sigBlocks_len : blocksLen sigBlocks = true := by decide +kernel

theorem sigBlocks_outside : noneAt 0 (sigBlocks.map Prod.snd).flatten = outside := by decide +kernel

end Lanius.Faithful.SelfPure
