module

public import Lanius.Faithful.Safe.Stmt
public import Lanius.Faithful.Safe.Prims
public import Lanius.Faithful.Sim.Func
public import Lanius.Mini.Compiler.P.storeArray
public import Lanius.Mini.Compiler.P.arrayCallSig
public import Lanius.Mini.Compiler.P.bindingBytes
public import Lanius.Mini.Compiler.P.funcNeeds
public import Lanius.Mini.Compiler.P.needRound
public import Lanius.Mini.Compiler.P.needsAfter
public import Lanius.Mini.Compiler.P.withBudget
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.FArith_opcode
import all Lanius.Mini.Compiler.P.FloatTy_rex
import all Lanius.Mini.Compiler.P.Instr_pieces
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.SrcExpr_guard
import all Lanius.Mini.Compiler.P.SrcType_size
import all Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.UintTy_isWide
import all Lanius.Mini.Compiler.P.UintTy_mask
import all Lanius.Mini.Compiler.P.applyGuard
import all Lanius.Mini.Compiler.P.arithShiftRight
import all Lanius.Mini.Compiler.P.arithUint
import all Lanius.Mini.Compiler.P.arities
import all Lanius.Mini.Compiler.P.armBodyScope
import all Lanius.Mini.Compiler.P.armPayload
import all Lanius.Mini.Compiler.P.armScope
import all Lanius.Mini.Compiler.P.assignFrom
import all Lanius.Mini.Compiler.P.codeSize
import all Lanius.Mini.Compiler.P.compileArgs
import all Lanius.Mini.Compiler.P.compileModules
import all Lanius.Mini.Compiler.P.conjunction
import all Lanius.Mini.Compiler.P.consArgs
import all Lanius.Mini.Compiler.P.elementAddress
import all Lanius.Mini.Compiler.P.elementBase
import all Lanius.Mini.Compiler.P.enumVariants
import all Lanius.Mini.Compiler.P.equality
import all Lanius.Mini.Compiler.P.evalDivide
import all Lanius.Mini.Compiler.P.evalDivideSint
import all Lanius.Mini.Compiler.P.evalNot
import all Lanius.Mini.Compiler.P.evalSame
import all Lanius.Mini.Compiler.P.floatApply
import all Lanius.Mini.Compiler.P.guardAnd
import all Lanius.Mini.Compiler.P.hostRandomCode
import all Lanius.Mini.Compiler.P.imageLimit
import all Lanius.Mini.Compiler.P.importOk
import all Lanius.Mini.Compiler.P.importsOk
import all Lanius.Mini.Compiler.P.indexOf
import all Lanius.Mini.Compiler.P.iteThen
import all Lanius.Mini.Compiler.P.leftTrue
import all Lanius.Mini.Compiler.P.loadAtBytes
import all Lanius.Mini.Compiler.P.lowerAddress
import all Lanius.Mini.Compiler.P.lowerApply
import all Lanius.Mini.Compiler.P.lowerCallSig
import all Lanius.Mini.Compiler.P.lowerLoadType
import all Lanius.Mini.Compiler.P.lowerLocal
import all Lanius.Mini.Compiler.P.lowerReturn
import all Lanius.Mini.Compiler.P.lowerSetCallArgs
import all Lanius.Mini.Compiler.P.lowerSetValues
import all Lanius.Mini.Compiler.P.lowerShift
import all Lanius.Mini.Compiler.P.lowerSlice
import all Lanius.Mini.Compiler.P.lowerTagged
import all Lanius.Mini.Compiler.P.matchDst
import all Lanius.Mini.Compiler.P.matchVariants
import all Lanius.Mini.Compiler.P.moduleExports
import all Lanius.Mini.Compiler.P.moduleFirsts
import all Lanius.Mini.Compiler.P.modulesOk
import all Lanius.Mini.Compiler.P.render
import all Lanius.Mini.Compiler.P.repeatType
import all Lanius.Mini.Compiler.P.shortCircuit
import all Lanius.Mini.Compiler.P.sintToUint
import all Lanius.Mini.Compiler.P.storeArray
import all Lanius.Mini.Compiler.P.arrayCallSig
import all Lanius.Mini.Compiler.P.bindingBytes
import all Lanius.Mini.Compiler.P.funcNeeds
import all Lanius.Mini.Compiler.P.needRound
import all Lanius.Mini.Compiler.P.needsAfter
import all Lanius.Mini.Compiler.P.withBudget
import all Lanius.Mini.Compiler.P.storeEvalWord
import all Lanius.Mini.Compiler.P.storeType
import all Lanius.Mini.Compiler.P.storeWordElement
import all Lanius.Mini.Compiler.P.structFields
import all Lanius.Mini.Compiler.P.usizeWidth
import all Lanius.Mini.Compiler.P.widthOf
import all Lanius.Mini.Compiler.P.wordElement
import all Lanius.Mini.Compiler.P.wordStride
import all Lanius.Mini.Compiler.P.wordWidth
import all Lanius.Mini.Compiler.Types

@[expose] public section
/-! # No call Core runs traps undefined

By strong induction on the fuel, beside `func_sim`: a function the purity
checker accepts traps only definedly (`body_safe`, with the calls below), and
so do `boxed` and `unbox` (`boxed_safe`, `unbox_safe`). -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State evalExprs)

section
variable {sp : SrcProgram} {prims : Prims} {outside : List Nat}

/-- The purity checker accepts no `break` or `continue`, so a pure body has
no loose one. -/
theorem stmtOk_inside {boxes : Boxes} {ret : SrcType} :
    ∀ {tenv : TEnv} {s : SrcStmt}, stmtOk sp outside boxes ret tenv s = true → s.breaksOut = false := by
  intro tenv s
  induction s generalizing tenv with
  | «let» _ _ _ _ ih | letStruct _ _ _ _ ih | letCall _ _ _ _ _ ih | letEnum _ _ _ _ _ ih
  | letEval _ _ _ _ ih =>
    intro ok
    simp only [stmtOk] at ok
    split at ok
    · exact ih ok
    · simp at ok
  | «then» _ _ ih1 ih2 =>
    intro ok
    simp only [stmtOk, Bool.and_eq_true] at ok
    simp [SrcStmt.breaksOut, ih1 ok.1, ih2 ok.2]
  | «if» _ _ _ ih1 ih2 | ifEval _ _ _ ih1 ih2 =>
    intro ok
    simp only [stmtOk, Bool.and_eq_true] at ok
    simp [SrcStmt.breaksOut, ih1 ok.1.2, ih2 ok.2]
  | nop | letMatch | set | setField | setCall | «while» | «return» | letAlloc | letLoad | setByte
  | free | letSlice | letIndex | setIndex | setEval | whileEval | returnEval | discard | setIndexEval
  | setFieldEval | returnUnit | «assert» | «break» | «continue» | matchArm | unreachable =>
    intro ok; simp_all [stmtOk, SrcStmt.breaksOut]

theorem func_safe (pure : PureProg sp prims outside) (primsOk : PrimsOk sp prims) :
    ∀ m, FuncSafe sp prims outside m := by
  have calls := func_sim pure primsOk
  intro m
  induction m using Nat.strongRecOn with
  | _ m ih =>
  intro c f values ps st completed r found notOut len inv bound args run
  cases hp : prims.isPrim c with
  | false =>
    rcases run with run | ⟨d, run, rfl | ⟨bad, -⟩⟩
    · exact body_safe calls (fun i lt => ih i lt) (pure c f found hp notOut) inv bound args run
    · rfl
    · have ends := stmt_ends sp m (stmtOk_inside (pure c f found hp notOut)) run
      rcases bad with rfl | rfl <;> exact ends.elim
  | true =>
    have mem : c ∈ prims.boxed ∨ c ∈ prims.unbox := by simpa [Prims.isPrim] using hp
    rcases mem with mem | mem
    · obtain ⟨t, id, sizeOf, slice, panic, hf, hs, hl, hpn, el, -, laid⟩ := primsOk.1 c mem
      rw [hf, Option.some.injEq] at found
      subst found
      rcases run with run | ⟨d, run, rfl | ⟨bad, -⟩⟩
      · exact boxed_safe hs hl hpn el laid inv args _ _ _ run bound
      · rfl
      · have ends := stmt_ends sp m (by simp [boxedFunc, SrcStmt.breaksOut]) run
        rcases bad with rfl | rfl <;> exact ends.elim
    · obtain ⟨t, id, slice, hf, hl, el, box⟩ := primsOk.2 c mem
      rw [hf, Option.some.injEq] at found
      subst found
      rcases run with run | ⟨d, run, rfl | ⟨bad, -⟩⟩
      · exact unbox_safe hl el box inv args _ _ _ run bound
      · rfl
      · have ends := stmt_ends sp m (by simp [unboxFunc, SrcStmt.breaksOut]) run
        rcases bad with rfl | rfl <;> exact ends.elim

/-- A call of a function inside the pure subset, on arguments whose
completed runs mean pure values: its body traps definedly. -/
theorem safeE_call_pure (fs : ∀ m, FuncSafe sp prims outside m) {c : Nat} {f : SrcFunc} {st : State}
    {args : List Core.Expr} (found : sp.funcs[c]? = some f) (notOut : outside.contains c = false)
    (sa : SafeEs sp.toCore st args)
    (rels : ∀ {k values s}, evalExprs k sp.toCore st args = .done values s →
      Inv s ∧ ∃ ps, VRels sp.toCore (boxElem sp prims) s.heap (f.params.map SrcParam.ty) values ps) :
    SafeE sp.toCore st (.call c args) := by
  intro k r s h bound
  obtain ⟨j, -, ha | ⟨values, after, hargs, ⟨-, arity⟩ | ⟨f', completed, found', -, rfl, hb⟩⟩⟩ :=
    call_trap_inv (inside_of found) h
  · exact sa _ _ _ ha bound
  · obtain ⟨-, ps, rs⟩ := rels hargs
    exact (arity f found (VRels.length_params rs)).elim
  · rw [found, Option.some.injEq] at found'
    subst found'
    obtain ⟨inv, ps, rs⟩ := rels hargs
    exact fs (completed := completed) _ found notOut (VRels.length_params rs) inv bound rs hb

end

end Lanius.Faithful
