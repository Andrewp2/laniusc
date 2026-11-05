module

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

@[expose] public section
/-! # Every outcome of a compiled call, from any Core state

`compileSource_outcome_from` puts `compileSource_correct_from` and
`compileSource_stops_from` together for any stack window: the compiled `f`,
entered from an x86 state that represents a Core state `st`, either faults
(every run of it that stops, stops at a fault), or returns deterministically
what a completed Core call `f(args)` returns, with its heap representing
Core's final heap, or Core's call reaches an undefined trap. -/

namespace Lanius.Mini

variable {sx : Statics}

open Lanius.X86.Machine
open Lanius.Core (Value)

/-- `compileSource_correct_from` for any stack window: the compiled `f`
returns, or the window is below what the run needs and it faults. -/
theorem compileSource_contract_from {sp : SrcProgram} {binary : Binary}
    (compiled : compileSource sp = some binary) {f : Nat} {func : SrcFunc}
    (found : sp.funcs[f]? = some func) {args : List Value} {bits : List (BitVec 64)}
    (typed : FieldsHold sx [] (paramTypes func.params) args (Func.entry bits) 0)
    (bitsLen : bits.length = paramsSize func.params) {fuel : Nat} {v : Value}
    {st final : Semantics.State} {heap : Heap} (fresh : st.Fresh) (hc : HeapCorr st.heap st.world heap)
    (runs : Semantics.evalExpr fuel sp.toCore st (.call f (args.map Core.Expr.value)) = .done v final)
    (fits : final.heap.nextAddress ≤ heap.limit) (frameRoom : 0 < sp.need f → heap.limit + sp.need f ≤ heap.fsp ∧ heap.fsp ≤ heap.top ∧ heap.top < 2 ^ 62)
    (statics : heap.StaticsAt sx) (ofSp : sx.bytes = sp.decls.statics) :
    ∃ depth results after, func.ret.HoldsAt sx [] v (Func.entry results) 0 ∧ results.length = func.ret.size ∧
      HeapCorr final.heap final.world after ∧
      ∀ imageBase window, Contract binary imageBase (binary.stackNeed depth) window f bits heap results after := by
  obtain ⟨_, _, funcs, lowered, compiledProgram⟩ := compileSource_some compiled
  haveI : StaticsOf sp sx := ⟨ofSp⟩
  cases fuel with
  | zero => simp [Semantics.evalExpr] at runs
  | succ k =>
    obtain ⟨func', values, afterArgs, completed, c, argsRun, found', _, bodyRun, result, rfl⟩ :=
      call_inv (List.getElem?_eq_some_iff.mp found).1 runs
    rw [found] at found'
    cases found'
    obtain ⟨rfl, rfl⟩ := evalExprs_values argsRun
    obtain ⟨_, _, depth, results, after, _, returns, holds, len, hc', -⟩ :=
      body_sound (mp := { funcs := funcs, statics := sp.decls.statics }) (hp := heap) lowered (stmt_sound lowered k) found
        fresh hc (LentHomes.start _ frameRoom statics) (Nat.le_refl _) (fun _ mem => by simp at mem) typed bitsLen bodyRun result fits
    refine ⟨depth, results, after, holds, len, hc', fun imageBase window => ?_⟩
    rcases compileOptimized_some compiledProgram with original | ⟨q, accepted, optimized⟩
    · exact compiled_contract original imageBase depth f bits heap results after returns window
    · exact compiled_contract optimized imageBase depth f bits heap results after (returns.validated accepted) window

/-- Every outcome of the compiled `f` entered from an x86 state that
represents the Core state `st` (premises as in `compileSource_stops_from`):
it faults, or Core's call completes within the heap's limit and the compiled
code returns its results with a heap that represents Core's final heap, or
Core's call reaches an undefined trap within the heap's limit. -/
theorem compileSource_outcome_from {sp : SrcProgram} {binary : Binary}
    (compiled : compileSource sp = some binary) {f : Nat} {func : SrcFunc}
    (found : sp.funcs[f]? = some func) {args : List Value} {bits : List (BitVec 64)}
    (typed : FieldsHold sx [] (paramTypes func.params) args (Func.entry bits) 0)
    (bitsLen : bits.length = paramsSize func.params) {st : Semantics.State} {heap : Heap}
    (fresh : st.Fresh) (hc : HeapCorr st.heap st.world heap) (within : st.heap.nextAddress ≤ heap.limit) (frameRoom : 0 < sp.need f → heap.limit + sp.need f ≤ heap.fsp ∧ heap.fsp ≤ heap.top ∧ heap.top < 2 ^ 62)
    (statics : heap.StaticsAt sx) (ofSp : sx.bytes = sp.decls.statics)
    (s : State) (imageBase : BitVec 64) (window : Nat) (bounded : window ≤ 2 ^ 62)
    (loaded : CodeAt s.memory imageBase binary.image)
    (apart : ∀ index, index < binary.image.length →
      ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index))
    (imageHeap : ∀ index, index < binary.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index))
    (entry : s.rip = imageBase + BitVec.ofNat 64 (binary.entries.getD f 0))
    (params : ∀ k (bound : k < bits.length),
      read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = bits[k])
    (heapAt : HeapAt window s heap) (stack : StackAt binary.guard window s) :
    Faults s ∨
    (∃ fuel v final, Semantics.evalExpr fuel sp.toCore st (.call f (args.map Core.Expr.value)) = .done v final ∧
      final.heap.nextAddress ≤ heap.limit ∧
      ∃ results after, func.ret.HoldsAt sx [] v (Func.entry results) 0 ∧ results.length = func.ret.size ∧
        HeapCorr final.heap final.world after ∧ ∃ n s', Steps n s s' ∧ Det n s s' ∧ Returned window s s' results after) ∨
    ∃ fuel r st', Semantics.evalExpr fuel sp.toCore st (.call f (args.map Core.Expr.value)) = .trapped r st' ∧
      undefinedTrap r = true ∧ st'.heap.nextAddress ≤ heap.limit := by
  by_cases fails : ∀ fuel, Failing heap.limit (Semantics.evalExpr fuel sp.toCore st (.call f (args.map Core.Expr.value)))
  · exact .inl (compileSource_stops_from compiled found typed bitsLen fresh hc within frameRoom statics ofSp fails s imageBase window bounded
      loaded apart imageHeap entry params heapAt stack)
  · obtain ⟨fuel, notFailing⟩ := Classical.not_forall.mp fails
    rcases not_failing notFailing with ⟨v, final, done, fits⟩ | ⟨r, st', trapped, undefined, bound⟩
    · obtain ⟨depth, results, after, holds, len, hc', contract⟩ :=
        compileSource_contract_from compiled found typed bitsLen fresh hc done fits frameRoom statics ofSp
      rcases contract imageBase window s bounded loaded apart imageHeap entry params heapAt stack with
        ⟨n, s', run, det, ret⟩ | ⟨-, faults⟩
      · exact .inr (.inl ⟨fuel, v, final, done, fits, results, after, holds, len, hc', n, s', run, det, ret⟩)
      · exact .inl faults
    · exact .inr (.inr ⟨fuel, r, st', trapped, undefined, bound⟩)

/-- `compileSource_outcome_from` with the reason for a fault kept (review
finding 5): the compiled `f` faults only when Core's call fails at every fuel
(it diverges, stops at a checked trap, or completes with the heap past the
mini heap's limit), or when Core's call completes within the limit and the
stack window is below what the compiled run needs. Otherwise it returns
Core's results, or Core's call reaches an undefined trap. -/
theorem compileSource_outcome_reason {sp : SrcProgram} {binary : Binary}
    (compiled : compileSource sp = some binary) {f : Nat} {func : SrcFunc}
    (found : sp.funcs[f]? = some func) {args : List Value} {bits : List (BitVec 64)}
    (typed : FieldsHold sx [] (paramTypes func.params) args (Func.entry bits) 0)
    (bitsLen : bits.length = paramsSize func.params) {st : Semantics.State} {heap : Heap}
    (fresh : st.Fresh) (hc : HeapCorr st.heap st.world heap) (within : st.heap.nextAddress ≤ heap.limit) (frameRoom : 0 < sp.need f → heap.limit + sp.need f ≤ heap.fsp ∧ heap.fsp ≤ heap.top ∧ heap.top < 2 ^ 62)
    (statics : heap.StaticsAt sx) (ofSp : sx.bytes = sp.decls.statics)
    (s : State) (imageBase : BitVec 64) (window : Nat) (bounded : window ≤ 2 ^ 62)
    (loaded : CodeAt s.memory imageBase binary.image)
    (apart : ∀ index, index < binary.image.length →
      ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index))
    (imageHeap : ∀ index, index < binary.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index))
    (entry : s.rip = imageBase + BitVec.ofNat 64 (binary.entries.getD f 0))
    (params : ∀ k (bound : k < bits.length),
      read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = bits[k])
    (heapAt : HeapAt window s heap) (stack : StackAt binary.guard window s) :
    ((∀ fuel, Failing heap.limit (Semantics.evalExpr fuel sp.toCore st (.call f (args.map Core.Expr.value)))) ∧
      Faults s) ∨
    (∃ fuel v final depth, Semantics.evalExpr fuel sp.toCore st (.call f (args.map Core.Expr.value)) = .done v final ∧
      final.heap.nextAddress ≤ heap.limit ∧ window < binary.stackNeed depth ∧ Faults s) ∨
    (∃ fuel v final, Semantics.evalExpr fuel sp.toCore st (.call f (args.map Core.Expr.value)) = .done v final ∧
      final.heap.nextAddress ≤ heap.limit ∧
      ∃ results after, func.ret.HoldsAt sx [] v (Func.entry results) 0 ∧ results.length = func.ret.size ∧
        HeapCorr final.heap final.world after ∧ ∃ n s', Steps n s s' ∧ Det n s s' ∧ Returned window s s' results after) ∨
    ∃ fuel r st', Semantics.evalExpr fuel sp.toCore st (.call f (args.map Core.Expr.value)) = .trapped r st' ∧
      undefinedTrap r = true ∧ st'.heap.nextAddress ≤ heap.limit := by
  by_cases fails : ∀ fuel, Failing heap.limit (Semantics.evalExpr fuel sp.toCore st (.call f (args.map Core.Expr.value)))
  · exact .inl ⟨fails, compileSource_stops_from compiled found typed bitsLen fresh hc within frameRoom statics ofSp fails s imageBase window
      bounded loaded apart imageHeap entry params heapAt stack⟩
  · obtain ⟨fuel, notFailing⟩ := Classical.not_forall.mp fails
    rcases not_failing notFailing with ⟨v, final, done, fits⟩ | ⟨r, st', trapped, undefined, bound⟩
    · obtain ⟨depth, results, after, holds, len, hc', contract⟩ :=
        compileSource_contract_from compiled found typed bitsLen fresh hc done fits frameRoom statics ofSp
      rcases contract imageBase window s bounded loaded apart imageHeap entry params heapAt stack with
        ⟨n, s', run, det, ret⟩ | ⟨short, faults⟩
      · exact .inr (.inr (.inl ⟨fuel, v, final, done, fits, results, after, holds, len, hc', n, s', run, det, ret⟩))
      · exact .inr (.inl ⟨fuel, v, final, depth, done, fits, short, faults⟩)
    · exact .inr (.inr (.inr ⟨fuel, r, st', trapped, undefined, bound⟩))

end Lanius.Mini
