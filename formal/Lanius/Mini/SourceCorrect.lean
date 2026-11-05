module

public import Lanius.Mini.Validate
public import Lanius.Mini.LowerEval
public import Lanius.Mini.Compiler.P.compileSource
public import Lanius.Mini.Compiler.P.packWord
public import Lanius.Mini.Compiler.P.roundCons
public import Lanius.Mini.Compiler.P.roundEnd
public import Lanius.Mini.Compiler.P.usizeWords
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
/-! The verified compiler's top-level theorem for the Core subset: if Core
evaluates a call of a source function to a value, the machine code that
`compileSource` produces returns slots representing that value, provided the
stack has room for the call's nesting depth. `compileSource` runs the
unverified optimizer, and the theorem covers its output through the proved
validator (`compileOptimized_correct`). -/

namespace Lanius.Mini

variable {sx : Statics}

open Lanius.X86.Machine
open Lanius.Core (Value)

theorem evalExprs_values {P : Core.Program} {st : Semantics.State} :
    ∀ {vs : List Value} {fuel : Nat} {values : List Value} {st' : Semantics.State},
      Semantics.evalExprs fuel P st (vs.map Core.Expr.value) = .done values st' →
      values = vs ∧ st' = st := by
  intro vs
  induction vs with
  | nil =>
    intro fuel values st' run
    cases fuel with
    | zero => simp [Semantics.evalExprs] at run
    | succ fuel =>
      simp only [List.map_nil, Semantics.evalExprs, Semantics.Outcome.done.injEq] at run
      exact ⟨run.1.symm, run.2.symm⟩
  | cons v rest ih =>
    intro fuel values st' run
    cases fuel with
    | zero => simp [Semantics.evalExprs] at run
    | succ fuel =>
      cases fuel with
      | zero => simp [Semantics.evalExprs, Semantics.evalExpr] at run
      | succ fuel =>
        simp only [List.map_cons, Semantics.evalExprs, Semantics.evalExpr] at run
        split at run
        · rename_i rvs fin restRun
          simp only [Semantics.Outcome.done.injEq] at run
          obtain ⟨rfl, rfl⟩ := run
          obtain ⟨rfl, rfl⟩ := ih restRun
          exact ⟨rfl, rfl⟩
        all_goals simp at run

/-- Core's starting state for a process given the streams of `io`: an empty
heap, no cells, and a world holding standard input, the clocks' readings and
the secure bytes the process is given, and nothing else. -/
def startState (io : Lanius.X86.Machine.Io) : Semantics.State :=
  { world :=
      { standardInput := io.input
        monotonicReadings := io.monotonic
        systemReadings := io.realtime
        secureByteStream := io.entropy } }

theorem startState_fresh (io : Lanius.X86.Machine.Io) : (startState io).Fresh :=
  ⟨fun _ mem => by simp [startState] at mem, Views.ViewsHold.nil rfl⟩

/-- Core's starting state for the mini heap's input, and a mini heap whose
cursor is 1, whose bytes from 1 up are zero, and whose trace is empty. -/
theorem HeapCorr.empty {heap : Heap} (start : heap.cursor = 1) (zero : ∀ a, 1 ≤ a → heap.bytes a = 0)
    (small : heap.limit < 2 ^ 62) (silent : heap.io.trace = []) :
    HeapCorr (startState heap.io).heap (startState heap.io).world heap :=
  { cursor := start, pos := Nat.le_refl _, unbounded := rfl, small
    sized := fun _ mem => by cases mem
    below := fun _ mem => by cases mem
    apart := fun _ mem => by cases mem
    unique := fun _ mem => by cases mem
    bytes := fun _ mem => by cases mem
    zero := fun a ge _ => zero a ge
    out := by rw [silent]; rfl
    err := by rw [silent]; rfl
    closed := rfl
    input := rfl
    streams := ⟨rfl, rfl, rfl⟩ }

/-- `compileSource_correct` from any Core state whose cells are fresh and
whose heap the mini heap represents (`HeapCorr`), not just the empty one:
Core runs `f(args)` from `st` to `v` and `final`; the compiled `f` returns
`results` representing `v`, and its heap `after` represents Core's final heap.
A client that built values in the heap (a `Vec`, say) composes through this. -/
theorem compileSource_correct_from {sp : SrcProgram} {binary : Binary}
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
    exact ⟨depth, results, after, holds, len, hc',
      fun s imageBase window enough bounded loaded apart imageHeap entry params heapAt stack =>
        compileOptimized_correct compiledProgram returns s imageBase window enough bounded loaded apart
          imageHeap entry params heapAt stack⟩

/-- Core runs `f(args)` from the empty state whose standard input is the
mini heap's (`startState`) to `v`, ending with its heap's
next free address at `final.heap.nextAddress`, and `bits` lay the arguments
out by parameter type (a struct one slot per field). Then the compiled `f`,
entered by a near call with `bits` in its parameter slots and a `heap` whose
cursor is 1, whose bytes from 1 up are zero, and whose limit Core's final
next address does not pass, returns `results` representing `v` in the same
slots, laid out the same way, with the heap's cursor at Core's final next
address. When the mini heap's trace starts empty, the bytes the compiled code
writes to the standard output and error (the machine's trace is `after`'s,
`Returned.io`) are those Core's world gained. -/
theorem compileSource_correct {sp : SrcProgram} {binary : Binary}
    (compiled : compileSource sp = some binary) {f : Nat} {func : SrcFunc}
    (found : sp.funcs[f]? = some func) {args : List Value} {bits : List (BitVec 64)}
    (typed : FieldsHold sx [] (paramTypes func.params) args (Func.entry bits) 0)
    (bitsLen : bits.length = paramsSize func.params) {fuel : Nat} {v : Value}
    {final : Semantics.State} {heap : Heap} (start : heap.cursor = 1)
    (zero : ∀ a, 1 ≤ a → heap.bytes a = 0) (small : heap.limit < 2 ^ 62) (silent : heap.io.trace = [])
    (runs : Semantics.evalExpr fuel sp.toCore (startState heap.io) (.call f (args.map Core.Expr.value)) =
      .done v final)
    (fits : final.heap.nextAddress ≤ heap.limit) (frameRoom : 0 < sp.need f → heap.limit + sp.need f ≤ heap.fsp ∧ heap.fsp ≤ heap.top ∧ heap.top < 2 ^ 62)
    (statics : heap.StaticsAt sx) (ofSp : sx.bytes = sp.decls.statics) :
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
  obtain ⟨depth, results, after, holds, len, hc, run⟩ := compileSource_correct_from compiled found typed bitsLen
    (st := startState heap.io) (startState_fresh _) (HeapCorr.empty start zero small silent) runs fits frameRoom statics ofSp
  exact ⟨depth, results, after, holds, len, hc.cursor, hc.out, hc.err, run⟩

end Lanius.Mini
