module

public import Lanius.Mini.Room
public import Lanius.Mini.Compiler.P.SrcEff_sliceUses
public import Lanius.Mini.Compiler.P.SrcStmt_calleeNeed
public import Lanius.Mini.Compiler.P.SrcStmt_sliceUses
public import Lanius.Mini.Compiler.P.arrayBytesOf
public import Lanius.Mini.Compiler.P.blockRoom
public import Lanius.Mini.Compiler.P.declBytes
public import Lanius.Mini.Compiler.P.frameBlock
public import Lanius.Mini.Compiler.P.paramsRoom
public import Lanius.Mini.Compiler.P.withBudget
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
public import Lanius.Mini.Compiler.P.compileDeclared
public import Lanius.Mini.Compiler.P.compileLowered
public import Lanius.Mini.Compiler.P.compileOptimized
public import Lanius.Mini.Compiler.P.compileOr
public import Lanius.Mini.Compiler.P.compileSource
public import Lanius.Mini.Compiler.P.packWord
public import Lanius.Mini.Compiler.P.roundCons
public import Lanius.Mini.Compiler.P.roundEnd
public import Lanius.Mini.Compiler.P.usizeWords
public import Lanius.Mini.Compiler.P.BinOp_compute
public import Lanius.Mini.Compiler.P.declareProgram
public import Lanius.Mini.Compiler.P.funcsReturn
public import Lanius.Mini.Compiler.P.lowBits
public import Lanius.Mini.Compiler.P.signedKey
public import Lanius.Mini.Compiler.P.Expr_extent
public import Lanius.Mini.Compiler.P.Stmt_extent
public import Lanius.Mini.Compiler.P.argsExtent
public import Lanius.Mini.Compiler.P.funcNeeds
public import Lanius.Mini.Compiler.P.sigs
public import Lanius.Mini.Compiler.P.sigsWith
public import Lanius.Mini.Compiler.P.SrcStmt_declare
public import Lanius.Mini.Compiler.P.SrcStmt_returns
public import Lanius.Mini.Compiler.P.SrcType_declare
public import Lanius.Mini.Compiler.P.declareEnum
public import Lanius.Mini.Compiler.P.declareFunc
public import Lanius.Mini.Compiler.P.declareParams
public import Lanius.Mini.Compiler.P.declareStruct
public import Lanius.Mini.Compiler.P.keepIf
public import Lanius.Mini.Compiler.P.lowerBody
public import Lanius.Mini.Compiler.P.lowerFunc
public import Lanius.Mini.Compiler.P.lowerFuncCons
public import Lanius.Mini.Compiler.P.lowerFuncs
public import Lanius.Mini.Compiler.P.unitTail
public import Lanius.Mini.Compiler.P.withFrame
public import Lanius.Mini.Compiler.P.needCapped
public import Lanius.Mini.Compiler.P.needRound
public import Lanius.Mini.Compiler.P.needRoundAt
public import Lanius.Mini.Compiler.P.restNeeds
public import Lanius.Mini.Compiler.P.sameNeeds
public import Lanius.Mini.Compiler.P.needLimit
public import Lanius.Mini.Compiler.P.needsAfter
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
import all Lanius.Mini.Compiler.P.compileDeclared
import all Lanius.Mini.Compiler.P.compileLowered
import all Lanius.Mini.Compiler.P.compileOptimized
import all Lanius.Mini.Compiler.P.compileOr
import all Lanius.Mini.Compiler.P.compileSource
import all Lanius.Mini.Compiler.P.packWord
import all Lanius.Mini.Compiler.P.roundCons
import all Lanius.Mini.Compiler.P.roundEnd
import all Lanius.Mini.Compiler.P.usizeWords
import all Lanius.Mini.Compiler.P.BinOp_compute
import all Lanius.Mini.Compiler.P.declareProgram
import all Lanius.Mini.Compiler.P.funcsReturn
import all Lanius.Mini.Compiler.P.lowBits
import all Lanius.Mini.Compiler.P.signedKey
import all Lanius.Mini.Compiler.P.Expr_extent
import all Lanius.Mini.Compiler.P.Stmt_extent
import all Lanius.Mini.Compiler.P.argsExtent
import all Lanius.Mini.Compiler.P.funcNeeds
import all Lanius.Mini.Compiler.P.sigs
import all Lanius.Mini.Compiler.P.sigsWith
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
import all Lanius.Mini.Compiler.P.needCapped
import all Lanius.Mini.Compiler.P.needRound
import all Lanius.Mini.Compiler.P.needRoundAt
import all Lanius.Mini.Compiler.P.restNeeds
import all Lanius.Mini.Compiler.P.sameNeeds
import all Lanius.Mini.Compiler.P.needLimit
import all Lanius.Mini.Compiler.P.needsAfter
import all Lanius.Mini.Compiler.P.SrcEff_sliceUses
import all Lanius.Mini.Compiler.P.SrcStmt_calleeNeed
import all Lanius.Mini.Compiler.P.SrcStmt_sliceUses
import all Lanius.Mini.Compiler.P.arrayBytesOf
import all Lanius.Mini.Compiler.P.blockRoom
import all Lanius.Mini.Compiler.P.declBytes
import all Lanius.Mini.Compiler.P.frameBlock
import all Lanius.Mini.Compiler.P.paramsRoom
import all Lanius.Mini.Compiler.P.withBudget

@[expose] public section

/-! The frame block's room check (F14): `frame_block` takes each parameter's and each let's block
bytes (`declBytes`) out of `blockLimit` as they add up (`paramsRoom`, `blockRoom`), so no sum the
lowering makes passes `2 ^ 64`, and a block over the limit is `2 ^ 31`.

`paramsRoom` and `blockRoom` take out the sums `paramsBytes` and `SrcStmt.blockBytes` (the
unchecked sums the compiler added before the check), so `frameBlock` is `frameBytes`, the unchecked
block, when it fits and `2 ^ 31` when not (`frameBlock_eq`). `lowerFunc` rejects a block of `2 ^ 31`
or more either way, and `lowerFuncs` fails when one function does.

The needs (`needRound`) are saturated at `needLimit` (2^40, more frame memory than any binary has),
and a round at the limit stays there (`needsAfter_sticky`), so needs below the limit at the end were
below it in every round and are the unchecked ones (`needsAfter_unchecked`). `lowerFunc` rejects a
function whose need reaches the limit. So `compileSource` is `compileSourceUnchecked`, the compiler
with the unchecked sums and needs, for a program whose needs are below the limit (`NeedsBelow`), and
rejects the others (`compileSource_unchecked`). -/

set_option linter.unusedVariables false

namespace Lanius.Mini

/-! The unchecked sums. -/

def paramsBytes : List SrcParam → List Nat → Nat
  | [], _ => 0
  | p :: rest, uses => declBytes uses p.id p.ty + paramsBytes rest uses

def SrcStmt.blockBytes (self : SrcStmt) (uses : List Nat) : Nat :=
  match self with
  | .nop => 0
  | .let id ty value body => declBytes uses id ty + SrcStmt.blockBytes body uses
  | .letStruct id ty fields body => declBytes uses id ty + SrcStmt.blockBytes body uses
  | .letCall id ty callee args body => declBytes uses id ty + SrcStmt.blockBytes body uses
  | .letEnum id ty variant payload body => declBytes uses id ty + SrcStmt.blockBytes body uses
  | .letMatch id ty scrutinee enumId arms body => declBytes uses id ty + SrcStmt.blockBytes body uses
  | .set id value => 0
  | .setField id index value => 0
  | .setCall id callee args => 0
  | .then first second => SrcStmt.blockBytes first uses + SrcStmt.blockBytes second uses
  | .if condition thenBranch elseBranch => SrcStmt.blockBytes thenBranch uses + SrcStmt.blockBytes elseBranch uses
  | .while condition body => SrcStmt.blockBytes body uses
  | .return value => 0
  | .letAlloc id size shift body => SrcStmt.blockBytes body uses
  | .letLoad id pointer offset body => SrcStmt.blockBytes body uses
  | .setByte pointer offset value => 0
  | .free pointer size shift => 0
  | .letSlice id element pointer length body => SrcStmt.blockBytes body uses
  | .letIndex id ty slice index body => declBytes uses id ty + SrcStmt.blockBytes body uses
  | .setIndex slice index value => 0
  | .letEval id ty value body => declBytes uses id ty + SrcStmt.blockBytes body uses
  | .setEval id value => 0
  | .ifEval condition thenBranch elseBranch => SrcStmt.blockBytes thenBranch uses + SrcStmt.blockBytes elseBranch uses
  | .whileEval condition body => SrcStmt.blockBytes body uses
  | .returnEval value => 0
  | .discard value => 0
  | .setIndexEval slice index value => 0
  | .setFieldEval id field value => 0
  | .returnUnit => 0
  | .assert condition => 0
  | .break => 0
  | .continue => 0
  | .matchArm scrutinee enumId variant binds binder ty body rest => SrcStmt.blockBytes body uses + SrcStmt.blockBytes rest uses
  | .unreachable id ty => 0
  | .letView id length fields pointer body => SrcStmt.blockBytes body uses
  | .letStr pointer chars body => SrcStmt.blockBytes body uses
  | .setPlace aplace avalue => 0
  | .setPlaceOp aop aplace avalue => 0

/-- The block without the check: every parameter's and let's block bytes. -/
def frameBytes (func : SrcFunc) : Nat :=
  let uses : List Nat := SrcStmt.sliceUses func.body
  paramsBytes func.params uses + SrcStmt.blockBytes func.body uses

theorem paramsRoom_eq (uses : List Nat) :
    ∀ (params : List SrcParam) (room : Nat), paramsRoom room params uses = takeOut room (paramsBytes params uses)
  | [], room => by simp [paramsRoom, paramsBytes, takeOut]
  | p :: rest, room => by
    simp only [paramsRoom, paramsBytes, spend, paramsRoom_eq uses rest, takeOut]
    by_cases h1 : declBytes uses p.id p.ty ≤ room <;>
      by_cases h2 : declBytes uses p.id p.ty + paramsBytes rest uses ≤ room <;> room_fin

theorem blockRoom_eq (uses : List Nat) (s : SrcStmt) :
    ∀ room, blockRoom room uses s = takeOut room (SrcStmt.blockBytes s uses) := by
  induction s with
  | nop => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | «let» id ty value body ih =>
    intro room
    simp only [blockRoom, SrcStmt.blockBytes, spend, ih, takeOut]
    by_cases h1 : declBytes uses id ty ≤ room <;>
      by_cases h2 : declBytes uses id ty + SrcStmt.blockBytes body uses ≤ room <;> room_fin
  | letStruct id ty fields body ih =>
    intro room
    simp only [blockRoom, SrcStmt.blockBytes, spend, ih, takeOut]
    by_cases h1 : declBytes uses id ty ≤ room <;>
      by_cases h2 : declBytes uses id ty + SrcStmt.blockBytes body uses ≤ room <;> room_fin
  | letCall id ty callee args body ih =>
    intro room
    simp only [blockRoom, SrcStmt.blockBytes, spend, ih, takeOut]
    by_cases h1 : declBytes uses id ty ≤ room <;>
      by_cases h2 : declBytes uses id ty + SrcStmt.blockBytes body uses ≤ room <;> room_fin
  | letEnum id ty variant payload body ih =>
    intro room
    simp only [blockRoom, SrcStmt.blockBytes, spend, ih, takeOut]
    by_cases h1 : declBytes uses id ty ≤ room <;>
      by_cases h2 : declBytes uses id ty + SrcStmt.blockBytes body uses ≤ room <;> room_fin
  | letMatch id ty scrutinee enumId arms body ih =>
    intro room
    simp only [blockRoom, SrcStmt.blockBytes, spend, ih, takeOut]
    by_cases h1 : declBytes uses id ty ≤ room <;>
      by_cases h2 : declBytes uses id ty + SrcStmt.blockBytes body uses ≤ room <;> room_fin
  | set id value => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | setField id index value => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | setCall id callee args => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | «then» first second ih1 ih2 =>
    intro room
    simp only [blockRoom, SrcStmt.blockBytes, ih1, ih2, takeOut]
    by_cases h1 : SrcStmt.blockBytes first uses ≤ room <;>
      by_cases h2 : SrcStmt.blockBytes first uses + SrcStmt.blockBytes second uses ≤ room <;> room_fin
  | «if» condition thenBranch elseBranch ih1 ih2 =>
    intro room
    simp only [blockRoom, SrcStmt.blockBytes, ih1, ih2, takeOut]
    by_cases h1 : SrcStmt.blockBytes thenBranch uses ≤ room <;>
      by_cases h2 : SrcStmt.blockBytes thenBranch uses + SrcStmt.blockBytes elseBranch uses ≤ room <;> room_fin
  | «while» condition body ih => intro room; simp only [blockRoom, SrcStmt.blockBytes, ih]
  | «return» value => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | letAlloc id size shift body ih => intro room; simp only [blockRoom, SrcStmt.blockBytes, ih]
  | letLoad id pointer offset body ih => intro room; simp only [blockRoom, SrcStmt.blockBytes, ih]
  | setByte pointer offset value => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | free pointer size shift => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | letSlice id element pointer length body ih => intro room; simp only [blockRoom, SrcStmt.blockBytes, ih]
  | letIndex id ty slice index body ih =>
    intro room
    simp only [blockRoom, SrcStmt.blockBytes, spend, ih, takeOut]
    by_cases h1 : declBytes uses id ty ≤ room <;>
      by_cases h2 : declBytes uses id ty + SrcStmt.blockBytes body uses ≤ room <;> room_fin
  | setIndex slice index value => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | letEval id ty value body ih =>
    intro room
    simp only [blockRoom, SrcStmt.blockBytes, spend, ih, takeOut]
    by_cases h1 : declBytes uses id ty ≤ room <;>
      by_cases h2 : declBytes uses id ty + SrcStmt.blockBytes body uses ≤ room <;> room_fin
  | setEval id value => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | ifEval condition thenBranch elseBranch ih1 ih2 =>
    intro room
    simp only [blockRoom, SrcStmt.blockBytes, ih1, ih2, takeOut]
    by_cases h1 : SrcStmt.blockBytes thenBranch uses ≤ room <;>
      by_cases h2 : SrcStmt.blockBytes thenBranch uses + SrcStmt.blockBytes elseBranch uses ≤ room <;> room_fin
  | whileEval condition body ih => intro room; simp only [blockRoom, SrcStmt.blockBytes, ih]
  | returnEval value => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | discard value => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | setIndexEval slice index value => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | setFieldEval id field value => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | returnUnit => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | assert condition => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | «break» => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | «continue» => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | matchArm scrutinee enumId variant binds binder ty body rest ih1 ih2 =>
    intro room
    simp only [blockRoom, SrcStmt.blockBytes, ih1, ih2, takeOut]
    by_cases h1 : SrcStmt.blockBytes body uses ≤ room <;>
      by_cases h2 : SrcStmt.blockBytes body uses + SrcStmt.blockBytes rest uses ≤ room <;> room_fin
  | unreachable id ty => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | letView id length fields pointer body ih => intro room; simp only [blockRoom, SrcStmt.blockBytes, ih]
  | letStr pointer chars body ih => intro room; simp only [blockRoom, SrcStmt.blockBytes, ih]
  | setPlace aplace avalue => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | setPlaceOp aop aplace avalue => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]

/-- The checked block is the unchecked one when it fits the limit, and `2 ^ 31` when not. -/
theorem frameBlock_eq (func : SrcFunc) :
    frameBlock func = if frameBytes func ≤ blockLimit then frameBytes func else 2147483648 := by
  simp only [frameBlock, frameBytes, paramsRoom_eq, blockRoom_eq, takeOut]
  by_cases h1 : paramsBytes func.params (SrcStmt.sliceUses func.body) ≤ blockLimit <;>
    by_cases h2 : paramsBytes func.params (SrcStmt.sliceUses func.body) +
      SrcStmt.blockBytes func.body (SrcStmt.sliceUses func.body) ≤ blockLimit <;> room_fin

theorem frameBlock_le (func : SrcFunc) : frameBlock func ≤ 2147483648 := by
  rw [frameBlock_eq]
  by_cases h : frameBytes func ≤ blockLimit <;> simp only [h, if_true, if_false] <;> simp only [blockLimit] at * <;> omega

/-! The compiler with the unchecked sums and needs. -/

def needRoundUnchecked : List SrcFunc → List Nat → List Nat
  | [], _ => []
  | f :: rest, prev => (frameBytes f + SrcStmt.calleeNeed f.body prev) :: needRoundUnchecked rest prev

def needsAfterUnchecked (funcs : List SrcFunc) (prev : List Nat) : Nat → List Nat
  | 0 => needRoundUnchecked funcs prev
  | rounds + 1 =>
    if sameNeeds (needRoundUnchecked funcs prev) prev then needRoundUnchecked funcs prev
    else needsAfterUnchecked funcs (needRoundUnchecked funcs prev) rounds

def sigsUnchecked (funcs : List SrcFunc) : List Sig :=
  sigsWith funcs (needsAfterUnchecked funcs [] funcs.length)

def lowerFuncUnchecked (sigs : List Sig) (own : Sig) (decls : SrcDecls) (func : SrcFunc) : Option Func :=
  let count : Nat := paramsSize func.params
  let block : Nat := frameBytes func
  if decide (0 < SrcType.size func.ret) && paramsValid func.params && !(SrcStmt.breaksOut func.body) &&
      decide (block ≤ own.need) && decide (block < 2147483648) then
    lowerBody count (SrcType.size func.ret) (SrcStmt.depth func.body) (unitTail func.ret (withFrame count block
      (SrcStmt.lower func.body (withBudget sigs (own.need - block) block) decls func.ret (paramScope func.params 0 []) count)))
  else
    none

def lowerFuncsUnchecked (sigs : List Sig) : List Sig → SrcDecls → List SrcFunc → Option (List Func)
  | _, _, [] => some []
  | [], _, _ :: _ => none
  | sig :: others, decls, func :: rest =>
    lowerFuncCons (lowerFuncUnchecked sigs sig decls func) (lowerFuncsUnchecked sigs others decls rest)

def compileSourceUnchecked (prog : SrcProgram) : Option Binary :=
  if funcsReturn prog.funcs then
    match declareProgram prog with
    | none => none
    | some d => compileLowered (lowerFuncsUnchecked (sigsUnchecked prog.funcs) (sigsUnchecked prog.funcs) d prog.funcs) d.statics
  else
    none

/-- Every function's need, as the compiler computes it, is below the limit. -/
def NeedsBelow (funcs : List SrcFunc) : Prop := ∀ i < funcs.length, (funcNeeds funcs).getD i 0 < needLimit

instance (funcs : List SrcFunc) : Decidable (NeedsBelow funcs) := by unfold NeedsBelow; infer_instance

/-! The saturated needs: a round at the limit stays there, and a round below it is the unchecked one. -/

theorem restNeeds_getD (mine : List Nat) (i : Nat) : (restNeeds mine).getD i 0 = mine.getD (i + 1) 0 := by
  cases mine <;> simp [restNeeds]

theorem needRoundAt_sticky (prev : List Nat) :
    ∀ (funcs : List SrcFunc) (mine : List Nat) (i : Nat), i < funcs.length → needLimit ≤ mine.getD i 0 →
      (needRoundAt funcs prev mine).getD i 0 = needLimit
  | [], _, _, lt, _ => by simp at lt
  | f :: rest, mine, 0, _, le => by simp only [needRoundAt, List.getD_cons_zero, needCapped, if_pos le]
  | f :: rest, mine, i + 1, lt, le => by
    simp only [needRoundAt, List.getD_cons_succ]
    exact needRoundAt_sticky prev rest (restNeeds mine) i (by simp at lt; omega) (by rw [restNeeds_getD]; exact le)

theorem needsAfter_sticky (funcs : List SrcFunc) :
    ∀ (rounds : Nat) (prev : List Nat) (i : Nat), i < funcs.length → needLimit ≤ prev.getD i 0 →
      (needsAfter funcs prev rounds).getD i 0 = needLimit
  | 0, prev, i, lt, le => by
    rw [needsAfter]; simp only [if_true]; exact needRoundAt_sticky prev funcs prev i lt le
  | rounds + 1, prev, i, lt, le => by
    have hn := needRoundAt_sticky prev funcs prev i lt le
    rw [needsAfter]
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel]
    split
    · exact hn
    · exact needsAfter_sticky funcs rounds (needRound funcs prev) i lt (by simp only [needRound, hn]; omega)

theorem needRoundAt_unchecked {funcs : List SrcFunc} (fits : ∀ f ∈ funcs, frameBytes f ≤ blockLimit)
    (prev : List Nat) : ∀ (mine : List Nat), (∀ i < funcs.length, (needRoundAt funcs prev mine).getD i 0 < needLimit) →
      needRoundAt funcs prev mine = needRoundUnchecked funcs prev := by
  induction funcs with
  | nil => intro _ _; rfl
  | cons f rest ih =>
    intro mine below
    have hf : frameBlock f = frameBytes f := by
      rw [frameBlock_eq]; simp only [fits f (List.mem_cons_self ..), if_true]
    have head := below 0 (by simp)
    simp only [needRoundAt, List.getD_cons_zero] at head
    have tail := ih (fun g mem => fits g (List.mem_cons_of_mem f mem)) (restNeeds mine) fun i lt => by
      have := below (i + 1) (by simp; omega)
      simpa [needRoundAt] using this
    simp only [needRoundAt, needRoundUnchecked, tail, hf]
    simp only [needCapped] at head ⊢
    by_cases h1 : needLimit ≤ mine.getD 0 0
    · simp only [h1, if_true] at head; omega
    · by_cases h2 : needLimit ≤ frameBlock f + SrcStmt.calleeNeed f.body prev
      · simp only [h1, h2, if_true, if_false] at head; omega
      · rw [hf] at h2; simp only [h1, h2, if_false]

theorem needsAfter_unchecked {funcs : List SrcFunc} (fits : ∀ f ∈ funcs, frameBlock f = frameBytes f)
    (fits' : ∀ f ∈ funcs, frameBytes f ≤ blockLimit) :
    ∀ (rounds : Nat) (prev : List Nat), (∀ i < funcs.length, (needsAfter funcs prev rounds).getD i 0 < needLimit) →
      needsAfter funcs prev rounds = needsAfterUnchecked funcs prev rounds
  | 0, prev, below => by
    rw [needsAfter] at below ⊢
    simp only [if_true] at below ⊢
    exact needRoundAt_unchecked fits' prev prev below
  | rounds + 1, prev, below => by
    have next_below : ∀ i < funcs.length, (needRound funcs prev).getD i 0 < needLimit := by
      intro i lt
      apply Classical.byContradiction
      intro h
      have le : needLimit ≤ (needRound funcs prev).getD i 0 := by omega
      have := below i lt
      rw [needsAfter] at this
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at this
      split at this
      · omega
      · rw [needsAfter_sticky funcs rounds _ i lt le] at this; omega
    have hn : needRound funcs prev = needRoundUnchecked funcs prev := needRoundAt_unchecked fits' prev prev next_below
    rw [needsAfter] at below ⊢
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at below ⊢
    simp only [needsAfterUnchecked, ← hn]
    split
    · rfl
    · rename_i same
      simp only [same] at below
      exact needsAfter_unchecked fits fits' rounds (needRound funcs prev) below

theorem sigs_unchecked {funcs : List SrcFunc} (fits : ∀ f ∈ funcs, frameBytes f ≤ blockLimit)
    (below : NeedsBelow funcs) : sigs funcs = sigsUnchecked funcs := by
  have fits' : ∀ f ∈ funcs, frameBlock f = frameBytes f := fun f mem => by
    rw [frameBlock_eq]; simp only [fits f mem, if_true]
  simp only [sigs, sigsUnchecked]
  rw [← needsAfter_unchecked fits' fits _ _ below]
  rfl

theorem sigsWith_need : ∀ (funcs : List SrcFunc) (needs : List Nat) (sig : Sig), sig ∈ sigsWith funcs needs →
    ∃ i < funcs.length, sig.need = needs.getD i 0
  | [], _, _, mem => by simp [sigsWith] at mem
  | f :: rest, needs, sig, mem => by
    simp only [sigsWith, List.mem_cons] at mem
    rcases mem with rfl | mem
    · exact ⟨0, by simp, by simp⟩
    · obtain ⟨i, lt, eq⟩ := sigsWith_need rest (restNeeds needs) sig mem
      exact ⟨i + 1, by simp; omega, by rw [eq, restNeeds_getD]⟩

/-! Every block fits and every need is below the limit: the two compilers agree. -/

theorem lowerFuncs_unchecked (S : List Sig) (decls : SrcDecls) :
    ∀ (own : List Sig) (funcs : List SrcFunc), (∀ f ∈ funcs, frameBytes f ≤ blockLimit) →
      (∀ sig ∈ own, sig.need < needLimit) →
      lowerFuncs S own decls funcs = lowerFuncsUnchecked S own decls funcs
  | own, [], _, _ => by cases own <;> rfl
  | [], _ :: _, _, _ => rfl
  | sig :: others, func :: rest, fits, small => by
    have hf : frameBlock func = frameBytes func := by
      rw [frameBlock_eq]; simp only [fits func (List.mem_cons_self ..), if_true]
    have hs : sig.need < needLimit := small sig (List.mem_cons_self ..)
    simp only [lowerFuncs, lowerFuncsUnchecked, lowerFunc, lowerFuncUnchecked, hf, hs, decide_true, Bool.and_true,
      lowerFuncs_unchecked S decls others rest (fun g mem => fits g (List.mem_cons_of_mem func mem))
        (fun g mem => small g (List.mem_cons_of_mem sig mem))]

/-! A block does not fit, or a need reaches the limit: the compiler rejects the program. -/

theorem lowerFuncs_none {lower : List Sig → Sig → SrcDecls → SrcFunc → Option Func}
    {lowers : List Sig → List Sig → SrcDecls → List SrcFunc → Option (List Func)}
    (empty : ∀ S decls func rest, lowers S [] decls (func :: rest) = none)
    (cons : ∀ S sig others decls func rest,
      lowers S (sig :: others) decls (func :: rest) = lowerFuncCons (lower S sig decls func) (lowers S others decls rest))
    (S : List Sig) (decls : SrcDecls) :
    ∀ (own : List Sig) (funcs : List SrcFunc) (i : Nat), i < funcs.length →
      (∀ sig f, own[i]? = some sig → funcs[i]? = some f → lower S sig decls f = none) → lowers S own decls funcs = none
  | _, [], _, lt, _ => by simp at lt
  | [], func :: rest, _, _, _ => empty S decls func rest
  | sig :: others, func :: rest, 0, _, bad => by
    rw [cons, bad sig func rfl rfl]; rfl
  | sig :: others, func :: rest, i + 1, lt, bad => by
    rw [cons, lowerFuncs_none empty cons S decls others rest i (by simp at lt; omega)
      (fun sig' f h1 h2 => bad sig' f (by simpa using h1) (by simpa using h2))]
    cases lower S sig decls func <;> rfl

theorem lowerFunc_big {func : SrcFunc} (big : ¬ frameBytes func ≤ blockLimit) (S : List Sig) (sig : Sig)
    (decls : SrcDecls) : lowerFunc S sig decls func = none := by
  have hf : frameBlock func = 2147483648 := by rw [frameBlock_eq]; simp only [big, if_false]
  simp only [lowerFunc, hf, Nat.lt_irrefl, decide_false, Bool.and_false, Bool.false_and, Bool.false_eq_true,
    if_false]

theorem lowerFunc_needy {sig : Sig} (needy : needLimit ≤ sig.need) (S : List Sig) (func : SrcFunc)
    (decls : SrcDecls) : lowerFunc S sig decls func = none := by
  have h : ¬ sig.need < needLimit := by omega
  simp only [lowerFunc, h, decide_false, Bool.and_false, Bool.false_eq_true, if_false]

theorem lowerFuncUnchecked_big {func : SrcFunc} (big : ¬ frameBytes func ≤ blockLimit) (S : List Sig) (sig : Sig)
    (decls : SrcDecls) : lowerFuncUnchecked S sig decls func = none := by
  have h : ¬ frameBytes func < 2147483648 := by simp only [blockLimit] at big; omega
  simp only [lowerFuncUnchecked, h, decide_false, Bool.and_false, Bool.false_eq_true, if_false]

theorem sigsWith_getElem : ∀ (funcs : List SrcFunc) (needs : List Nat) (i : Nat) (sig : Sig),
    (sigsWith funcs needs)[i]? = some sig → sig.need = needs.getD i 0
  | [], _, _, _, h => by simp [sigsWith] at h
  | f :: rest, needs, 0, sig, h => by simp only [sigsWith, List.getElem?_cons_zero, Option.some.injEq] at h; subst h; rfl
  | f :: rest, needs, i + 1, sig, h => by
    simp only [sigsWith, List.getElem?_cons_succ] at h
    rw [sigsWith_getElem rest (restNeeds needs) i sig h, restNeeds_getD]

/-- The frame block's room check and the needs' limit change no result of the compiler for a
program whose functions' needs are below the limit (more frame memory than any binary has), and
reject the others. -/
theorem compileSource_unchecked (prog : SrcProgram) :
    compileSource prog = if NeedsBelow prog.funcs then compileSourceUnchecked prog else none := by
  simp only [compileSource, compileSourceUnchecked, compileDeclared]
  by_cases ret : funcsReturn prog.funcs = true
  · simp only [ret, if_true]
    cases hd : declareProgram prog with
    | none => simp only [hd]; split <;> rfl
    | some d =>
      simp only [hd]
      by_cases fits : ∀ f ∈ prog.funcs, frameBytes f ≤ blockLimit
      · by_cases below : NeedsBelow prog.funcs
        · simp only [below, if_true]
          rw [lowerFuncs_unchecked _ d _ _ fits, sigs_unchecked fits below]
          intro sig mem
          obtain ⟨i, lt, eq⟩ := sigsWith_need prog.funcs _ sig mem
          rw [eq]; exact below i lt
        · simp only [below, if_false]
          obtain ⟨i, lt, needy⟩ : ∃ i < prog.funcs.length, needLimit ≤ (funcNeeds prog.funcs).getD i 0 := by
            apply Classical.byContradiction
            intro h
            exact below fun i lt => by
              apply Classical.byContradiction
              intro h'
              exact h ⟨i, lt, by omega⟩
          rw [lowerFuncs_none (lower := lowerFunc) (lowers := lowerFuncs) (fun _ _ _ _ => rfl)
            (fun _ _ _ _ _ _ => rfl) _ d _ _ i lt fun sig f hs _ => lowerFunc_needy
              (by rw [sigsWith_getElem _ _ i sig hs]; exact needy) _ f d]
          rfl
      · rcases Classical.not_forall.mp fits with ⟨big, hbig⟩
        rcases Classical.not_imp.mp hbig with ⟨mem, over⟩
        obtain ⟨i, hi⟩ := List.mem_iff_getElem?.mp mem
        have lt : i < prog.funcs.length := by
          rcases List.getElem?_eq_some_iff.mp hi with ⟨lt, -⟩; exact lt
        have bad : ∀ {lower : List Sig → Sig → SrcDecls → SrcFunc → Option Func},
            (∀ S sig, lower S sig d big = none) →
            ∀ (S own : List Sig), ∀ sig f, own[i]? = some sig → prog.funcs[i]? = some f → lower S sig d f = none :=
          fun h S own sig f _ hf => by rw [hi, Option.some.injEq] at hf; subst hf; exact h S sig
        rw [lowerFuncs_none (lower := lowerFunc) (lowers := lowerFuncs) (fun _ _ _ _ => rfl)
            (fun _ _ _ _ _ _ => rfl) _ d _ _ i lt (bad (fun S sig => lowerFunc_big over S sig d) _ _),
          lowerFuncs_none (lower := lowerFuncUnchecked) (lowers := lowerFuncsUnchecked)
            (fun _ _ _ _ => rfl) (fun _ _ _ _ _ _ => rfl) _ d _ _ i lt
            (bad (fun S sig => lowerFuncUnchecked_big over S sig d) _ _)]
        split <;> rfl
  · simp only [ret, Bool.false_eq_true, if_false]
    split <;> rfl

end Lanius.Mini
