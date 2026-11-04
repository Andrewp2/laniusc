module

public import Lanius.Mini.ViewLower
public import Lanius.Mini.LowerStmt
public import Lanius.Mini.WorldTrace
public import Lanius.Mini.Stops
public import Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.FArith_opcode
import all Lanius.Mini.Compiler.P.FloatTy_rex
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.SrcExpr_guard
import all Lanius.Mini.Compiler.P.SrcType_same
import all Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.UintTy_isWide
import all Lanius.Mini.Compiler.P.UintTy_mask
import all Lanius.Mini.Compiler.P.Word_compute
import all Lanius.Mini.Compiler.P.Word_narrows
import all Lanius.Mini.Compiler.P.applyGuard
import all Lanius.Mini.Compiler.P.arithShiftRight
import all Lanius.Mini.Compiler.P.arithUint
import all Lanius.Mini.Compiler.P.arities
import all Lanius.Mini.Compiler.P.armBodyScope
import all Lanius.Mini.Compiler.P.armPayload
import all Lanius.Mini.Compiler.P.armScope
import all Lanius.Mini.Compiler.P.arrayCallSig
import all Lanius.Mini.Compiler.P.assignFrom
import all Lanius.Mini.Compiler.P.callAgrees
import all Lanius.Mini.Compiler.P.codeSize
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
import all Lanius.Mini.Compiler.P.extentAfter
import all Lanius.Mini.Compiler.P.floatApply
import all Lanius.Mini.Compiler.P.funcNeeds
import all Lanius.Mini.Compiler.P.guardAnd
import all Lanius.Mini.Compiler.P.hostRandomCode
import all Lanius.Mini.Compiler.P.evalHost
import all Lanius.Mini.Compiler.P.indexOf
import all Lanius.Mini.Compiler.P.iteThen
import all Lanius.Mini.Compiler.P.killShared
import all Lanius.Mini.Compiler.P.leftTrue
import all Lanius.Mini.Compiler.P.loadAtBytes
import all Lanius.Mini.Compiler.P.longer
import all Lanius.Mini.Compiler.P.lowerAddress
import all Lanius.Mini.Compiler.P.lowerApply
import all Lanius.Mini.Compiler.P.lowerBody
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
import all Lanius.Mini.Compiler.P.needCapped
import all Lanius.Mini.Compiler.P.needsAfter
import all Lanius.Mini.Compiler.P.render
import all Lanius.Mini.Compiler.P.repeatType
import all Lanius.Mini.Compiler.P.shortCircuit
import all Lanius.Mini.Compiler.P.sintToUint
import all Lanius.Mini.Compiler.P.storeArray
import all Lanius.Mini.Compiler.P.strStores
import all Lanius.Mini.Compiler.P.storeEvalWord
import all Lanius.Mini.Compiler.P.storeType
import all Lanius.Mini.Compiler.P.storeWordElement
import all Lanius.Mini.Compiler.P.structFields
import all Lanius.Mini.Compiler.P.substAll
import all Lanius.Mini.Compiler.P.usizeWidth
import all Lanius.Mini.Compiler.P.widthOf
import all Lanius.Mini.Compiler.P.withBudget
import all Lanius.Mini.Compiler.P.wordElement
import all Lanius.Mini.Compiler.P.wordStride
import all Lanius.Mini.Compiler.P.wordWidth
import all Lanius.Mini.Compiler.Types
public import Lanius.Mini.Compiler.P.SrcExpr_guard
public import Lanius.Mini.Compiler.P.SrcType_same
public import Lanius.Mini.Compiler.P.UintTy_half
public import Lanius.Mini.Compiler.P.UintTy_isWide
public import Lanius.Mini.Compiler.P.armScope
public import Lanius.Mini.Compiler.P.consArgs
public import Lanius.Mini.Compiler.P.elementBase
public import Lanius.Mini.Compiler.P.evalDivide
public import Lanius.Mini.Compiler.P.evalDivideSint
public import Lanius.Mini.Compiler.P.evalNot
public import Lanius.Mini.Compiler.P.evalSame
public import Lanius.Mini.Compiler.P.hostRandomCode
public import Lanius.Mini.Compiler.P.longer
public import Lanius.Mini.Compiler.P.lowerBody
public import Lanius.Mini.Compiler.P.lowerCallSig
public import Lanius.Mini.Compiler.P.lowerLoadType
public import Lanius.Mini.Compiler.P.lowerLocal
public import Lanius.Mini.Compiler.P.matchDst
public import Lanius.Mini.Compiler.P.matchVariants
public import Lanius.Mini.Compiler.P.shortCircuit
public import Lanius.Mini.Compiler.P.withBudget
public import Lanius.Mini.Compiler.P.funcNeeds
public import Lanius.Mini.Compiler.P.storeArray
public import Lanius.Mini.Compiler.P.strStores
public import Lanius.Mini.Compiler.P.arrayCallSig
public import Lanius.Mini.Compiler.P.bindingBytes
public import Lanius.Mini.Compiler.P.needCapped
public import Lanius.Mini.Compiler.P.needsAfter
public import Lanius.Mini.Compiler.P.storeEvalWord
public import Lanius.Mini.Compiler.P.wordElement
public import Lanius.Mini.Compiler.P.wordStride

@[expose] public section
/-! A string's pointer (`LetStr`, SEMANTIC_DECISIONS "Addressed locals" point
6): `let p = core::mem::string_data_ptr("...");`. Core maps the string's
UTF-8 bytes, zero-padded to whole words (`stringStorage`), into a fresh
borrowed heap block (`mapStringDataPtr`). The verified compiler, for an ASCII
string, bump-allocates a block of that size and stores the bytes into it as
words (`strWords`), the pointer in the let's slot. -/

namespace Lanius.Mini

variable {bud : Budget} {sx : Statics} {places : List Addressed}

open Lanius.Core (Value)
open Lanius.Semantics (State Cell Completion evalExpr evalExprs execStmt restoreLocals)

/-! ## The string's bytes -/

/-- Each scalar value's low byte. -/
def asciiBytes (chars : List Nat) : List UInt8 := chars.map UInt8.ofNat

theorem strAscii_cons {c : Nat} {rest : List Nat} (h : strAscii (c :: rest) = true) :
    c < 128 ∧ strAscii rest = true := by
  simp only [strAscii, Bool.and_eq_true, decide_eq_true_eq] at h
  exact h

/-- An ASCII string's UTF-8 bytes are its scalar values. -/
theorem utf8Bytes_strValue : ∀ (chars : List Nat), strAscii chars = true →
    World.utf8Bytes (strValue chars) = asciiBytes chars := by
  intro chars ascii
  simp only [World.utf8Bytes, strValue, String.toUTF8_eq_toByteArray, String.bytes_ofList, List.utf8Encode,
    List.toList_data_toByteArray, asciiBytes]
  induction chars with
  | nil => rfl
  | cons c rest ih =>
    obtain ⟨small, more⟩ := strAscii_cons ascii
    simp only [List.map_cons, List.flatMap_cons, ih more]
    have valid : c.isValidChar := Or.inl (by omega)
    have hv : (Char.ofNatAux c valid).val.toNat = c := rfl
    have one : (Char.ofNat c).utf8Size = 1 := by
      rw [Char.utf8Size_eq_one_iff, Char.ofNat, dif_pos valid, UInt32.le_iff_toNat_le, hv]
      show c ≤ 127
      omega
    rw [String.utf8EncodeChar_eq_singleton one]
    simp only [List.singleton_append, List.cons.injEq, and_true]
    rw [Char.ofNat, dif_pos valid]
    apply UInt8.toNat.inj
    simp only [UInt32.toNat_toUInt8, hv]
    rfl

/-- A literal the statics hold, from `offset`: ASCII, and its bytes there. -/
theorem strPlaced_bytes {statics : List UInt8} : ∀ {chars : List Nat} {offset : Nat},
    strPlaced statics offset chars = true →
      strAscii chars = true ∧ (statics.drop offset).take chars.length = asciiBytes chars
  | [], _, _ => ⟨rfl, by simp [asciiBytes]⟩
  | c :: rest, offset, h => by
    simp only [strPlaced, Bool.and_eq_true, decide_eq_true_eq] at h
    obtain ⟨⟨small, byte⟩, more⟩ := h
    obtain ⟨ascii, tail⟩ := strPlaced_bytes more
    cases found : statics[offset]? with
    | none => simp [found, staticByteIs] at byte
    | some b =>
      simp only [found, staticByteIs, decide_eq_true_eq] at byte
      have hc := congrArg BitVec.toNat byte
      simp only [BitVec.toNat_setWidth, BitVec.toNat_ofNat] at hc
      have b8 : b.toNat < 256 := b.toNat_lt
      have hb : b = UInt8.ofNat c := by
        apply UInt8.toNat_inj.mp
        simp only [UInt8.toNat_ofNat']
        omega
      obtain ⟨lt, get⟩ := List.getElem?_eq_some_iff.mp found
      refine ⟨by simp [strAscii, small, ascii], ?_⟩
      rw [List.drop_eq_getElem_cons lt, get, List.length_cons, List.take_succ_cons, tail, hb]
      rfl

/-- The bytes the stores write: each word's low four bytes, in order. -/
def wordBytes : List (BitVec 64) → List UInt8
  | [] => []
  | w :: more => Semantics.encodeNatLE 4 w.toNat ++ wordBytes more

theorem wordBytes_length : ∀ (ws : List (BitVec 64)), (wordBytes ws).length = 4 * ws.length
  | [] => rfl
  | w :: more => by
    simp only [wordBytes, List.length_append, wordBytes_length more, Semantics.encodeNatLE, List.length_map,
      List.length_range, List.length_cons]
    omega

/-- Four bytes packed little-endian into a word, and its low four bytes. -/
theorem encode_four {n a b c d : Nat} (ha : a < 256) (hb : b < 256) (hc : c < 256) (hd : d < 256)
    (hn : n = a + b * 256 + c * 65536 + d * 16777216) :
    Semantics.encodeNatLE 4 n = [UInt8.ofNat a, UInt8.ofNat b, UInt8.ofNat c, UInt8.ofNat d] := by
  subst hn
  show [UInt8.ofNat (_ / 256 ^ 0 % 256), UInt8.ofNat (_ / 256 ^ 1 % 256), UInt8.ofNat (_ / 256 ^ 2 % 256),
    UInt8.ofNat (_ / 256 ^ 3 % 256)] = _
  simp only [List.cons.injEq, and_true]
  refine ⟨?_, ?_, ?_, ?_⟩ <;> congr 1 <;> simp only [Nat.reducePow] <;> omega

theorem ofNat_small {n : Nat} (h : n < 2 ^ 32) : (BitVec.ofNat 64 n).toNat = n := by
  simp only [BitVec.toNat_ofNat]; exact Nat.mod_eq_of_lt (by omega)

/-- An ASCII string's words hold its bytes, then zeros to a whole word:
Core's `stringStorage`. -/
theorem strWords_bytes : ∀ (chars : List Nat), strAscii chars = true →
    wordBytes (strWords chars) = asciiBytes chars ++ List.replicate ((4 - chars.length % 4) % 4) 0
  | [], _ => rfl
  | [a], h => by
    obtain ⟨ha, -⟩ := strAscii_cons h
    simp only [strWords, wordBytes, List.append_nil, asciiBytes, List.map_cons, List.map_nil,
      List.length_cons, List.length_nil]
    rw [encode_four (a := a) (b := 0) (c := 0) (d := 0) (by omega) (by omega) (by omega) (by omega)
      (by rw [ofNat_small (by omega)]; omega)]
    rfl
  | [a, b], h => by
    obtain ⟨ha, h⟩ := strAscii_cons h
    obtain ⟨hb, -⟩ := strAscii_cons h
    simp only [strWords, wordBytes, List.append_nil, asciiBytes, List.map_cons, List.map_nil,
      List.length_cons, List.length_nil]
    rw [encode_four (a := a) (b := b) (c := 0) (d := 0) (by omega) (by omega) (by omega) (by omega)
      (by rw [ofNat_small (by omega)]; omega)]
    rfl
  | [a, b, c], h => by
    obtain ⟨ha, h⟩ := strAscii_cons h
    obtain ⟨hb, h⟩ := strAscii_cons h
    obtain ⟨hc, -⟩ := strAscii_cons h
    simp only [strWords, wordBytes, List.append_nil, asciiBytes, List.map_cons, List.map_nil,
      List.length_cons, List.length_nil]
    rw [encode_four (a := a) (b := b) (c := c) (d := 0) (by omega) (by omega) (by omega) (by omega)
      (by rw [ofNat_small (by omega)]; omega)]
    rfl
  | a :: b :: c :: d :: rest, h => by
    obtain ⟨ha, h⟩ := strAscii_cons h
    obtain ⟨hb, h⟩ := strAscii_cons h
    obtain ⟨hc, h⟩ := strAscii_cons h
    obtain ⟨hd, h⟩ := strAscii_cons h
    simp only [strWords, wordBytes]
    rw [encode_four (a := a) (b := b) (c := c) (d := d) (by omega) (by omega) (by omega) (by omega)
      (by rw [ofNat_small (by omega)]), strWords_bytes rest h]
    have pad : (rest.length + 1 + 1 + 1 + 1) % 4 = rest.length % 4 := by omega
    simp only [asciiBytes, List.map_cons, List.length_cons, List.cons_append, List.nil_append, pad]

/-- An ASCII string's words are Core's storage of the string. -/
theorem strWords_storage {chars : List Nat} (h : strAscii chars = true) :
    wordBytes (strWords chars) = Semantics.stringStorage (strValue chars) := by
  rw [strWords_bytes chars h, Semantics.stringStorage, utf8Bytes_strValue chars h]
  simp only [asciiBytes, List.length_map]

theorem strWords_pos : ∀ {chars : List Nat}, chars ≠ [] → 0 < (strWords chars).length
  | [], ne => absurd rfl ne
  | [_], _ => by simp [strWords]
  | [_, _], _ => by simp [strWords]
  | [_, _, _], _ => by simp [strWords]
  | _ :: _ :: _ :: _ :: _, _ => by simp [strWords]

/-- The words' bytes are the string's, padded by fewer than a word. -/
theorem strWords_length {chars : List Nat} (h : strAscii chars = true) :
    4 * (strWords chars).length < chars.length + 4 := by
  have := congrArg List.length (strWords_bytes chars h)
  simp only [wordBytes_length, List.length_append, asciiBytes, List.length_map, List.length_replicate] at this
  omega

/-! ## The stores -/

/-- The stores of `strStores`: the words' low four bytes, packed from the
address in `pointer` plus `offset`. -/
theorem strStores_exec {mp : Program} {d : Nat} {env : Env} {pointer p : Nat} {rest : Stmt} {out : Outcome}
    (at_ : (env pointer).toNat = p) :
    ∀ (ws : List (BitVec 64)) {offset : Nat} {hp : Heap}, p + offset + 4 * ws.length ≤ hp.top →
      p + offset + 4 * ws.length < 2 ^ 64 →
      Exec mp d env (hp.writeBytes (p + offset) (wordBytes ws)) rest out →
      Exec mp d env hp (strStores pointer offset ws rest) out
  | [], offset, hp, _, _, exec => exec
  | w :: more, offset, hp, top, small, exec => by
    simp only [List.length_cons] at top small
    have addr : ((Expr.binary Word.u64 BinOp.add (Expr.var pointer) (Expr.lit (BitVec.ofNat 64 offset))).eval
        env).toNat = p + offset := by
      simp only [Expr.eval, Word.apply, BinOp.apply, BitVec.toNat_add, at_, BitVec.toNat_ofNat]
      rw [Nat.mod_eq_of_lt (show offset < 2 ^ 64 by omega), Nat.mod_eq_of_lt (by omega)]
    simp only [strStores]
    refine .seq (.storeWord (by rw [addr]; simp only [MemWidth.bytes]; omega)) ?_
    rw [addr]
    simp only [MemWidth.bytes, Expr.eval]
    refine strStores_exec at_ more (by rw [(Heap.writeLE_top _ _ _ _).1]; omega) (by omega) ?_
    rw [show p + (offset + 4) = p + offset + 4 by omega, writeLE_eq_writeBytes]
    have four : (Semantics.encodeNatLE 4 w.toNat).length = 4 := by simp [Semantics.encodeNatLE]
    have split := Heap.writeBytes_append hp (p + offset) (Semantics.encodeNatLE 4 w.toNat) (wordBytes more)
    rw [four] at split
    rw [← split]
    exact exec

/-- The stores of `strStores`, then a stop. -/
theorem strStores_stops {mp : Program} {d : Nat} {env : Env} {pointer p : Nat} {rest : Stmt} {n : Nat}
    (at_ : (env pointer).toNat = p) :
    ∀ (ws : List (BitVec 64)) {offset : Nat} {hp : Heap}, p + offset + 4 * ws.length ≤ hp.top →
      p + offset + 4 * ws.length < 2 ^ 64 →
      Stops mp d env (hp.writeBytes (p + offset) (wordBytes ws)) rest n →
      Stops mp d env hp (strStores pointer offset ws rest) n
  | [], offset, hp, _, _, stops => stops
  | w :: more, offset, hp, top, small, stops => by
    simp only [List.length_cons] at top small
    have addr : ((Expr.binary Word.u64 BinOp.add (Expr.var pointer) (Expr.lit (BitVec.ofNat 64 offset))).eval
        env).toNat = p + offset := by
      simp only [Expr.eval, Word.apply, BinOp.apply, BitVec.toNat_add, at_, BitVec.toNat_ofNat]
      rw [Nat.mod_eq_of_lt (show offset < 2 ^ 64 by omega), Nat.mod_eq_of_lt (by omega)]
    simp only [strStores]
    refine .seqSecond (.storeWord (by rw [addr]; simp only [MemWidth.bytes]; omega)) ?_
    rw [addr]
    simp only [MemWidth.bytes, Expr.eval]
    refine strStores_stops at_ more (by rw [(Heap.writeLE_top _ _ _ _).1]; omega) (by omega) ?_
    rw [show p + (offset + 4) = p + offset + 4 by omega, writeLE_eq_writeBytes]
    have four : (Semantics.encodeNatLE 4 w.toNat).length = 4 := by simp [Semantics.encodeNatLE]
    have split := Heap.writeBytes_append hp (p + offset) (Semantics.encodeNatLE 4 w.toNat) (wordBytes more)
    rw [four] at split
    rw [← split]
    exact stops

/-! ## The statement -/

section Statements

variable {sp : SrcProgram} {mp : Program} {fuel : Nat} {ret : SrcType} {scope : List Binding}
  {next : Nat} {stmt : Stmt} {frame : Nat → Nat} {base : Nat} {st : State} {env : Env}
  {c : Completion} {st' : State} {hp : Heap}
variable [StaticsOf sp sx]

/-- Entering a `LetStr`'s body: Core mapped the string's storage at `p`; the
mini code before the body (the block, the stores) runs to a heap that
corresponds, the pointer in the let's slot. -/
theorem str_entered {chars : List Nat} (ascii : strAscii chars = true) (nonempty : chars ≠ [])
    (hc : HeapCorr st.heap st.world hp) (fc : FrameCorr sx bud places st hp) {p : Nat} {heap' : Lanius.Memory.Heap}
    (map : st.heap.mapBorrowed (Semantics.stringStorage (strValue chars)) 4 = .allocated p heap')
    (room : heap'.nextAddress ≤ hp.limit) :
    ∃ hp3, (BitVec.ofNat 64 p).toNat = p ∧ HeapCorr heap' st.world hp3 ∧
      FrameCorr sx bud places { st with heap := heap' } hp3 ∧ hp3.limit = hp.limit ∧
      (∀ {rest : Stmt} {d : Nat} {out : Outcome}, Exec mp d (env.set next (BitVec.ofNat 64 p)) hp3 rest out →
        Exec mp d env hp (.seq (.alloc next 2 (.lit (BitVec.ofNat 64 (4 * (strWords chars).length))))
          (strStores next 0 (strWords chars) rest)) out) ∧
      (∀ {rest : Stmt} {d n : Nat}, Stops mp d (env.set next (BitVec.ofNat 64 p)) hp3 rest n →
        Stops mp d env hp (.seq (.alloc next 2 (.lit (BitVec.ofNat 64 (4 * (strWords chars).length))))
          (strStores next 0 (strWords chars) rest)) n) := by
  rw [← strWords_storage ascii] at map
  obtain ⟨pEq, nextEq, hcRoom⟩ := hc.mapView map
  have pos := strWords_pos nonempty
  have maxEq : max (wordBytes (strWords chars)).length 1 = 4 * (strWords chars).length := by
    rw [wordBytes_length]; omega
  rw [maxEq] at nextEq hcRoom
  have tail : p + 4 * (strWords chars).length ≤ hp.limit := nextEq ▸ room
  have small := hc.small
  let hp3 := ({ hp with cursor := p + 4 * (strWords chars).length } : Heap).writeBytes p (wordBytes (strWords chars))
  have hc3 : HeapCorr heap' st.world hp3 := hcRoom tail
  have pBits : (BitVec.ofNat 64 p).toNat = p := Nat.mod_eq_of_lt (by addr_omega)
  have fc3 : FrameCorr sx bud places { st with heap := heap' } hp3 := by
    refine fc.low (fun _ _ => rfl) (fun a above => ?_) ?_ ?_ ?_ (statics := ?_)
    · simp only [hp3, Heap.writeBytes_eq_writeAll, Heap.writeAll, wordBytes_length]
      rw [if_neg (by addr_omega)]
    · simp only [hp3, Heap.writeBytes_eq_writeAll, Heap.writeAll]
    · simp only [hp3, Heap.writeBytes_eq_writeAll, Heap.writeAll]
    · simp only [hp3, Heap.writeBytes_eq_writeAll, Heap.writeAll, Heap.top]
    · constructor <;> simp only [hp3, Heap.writeBytes_eq_writeAll, Heap.writeAll]
  have lit : ((Expr.lit (BitVec.ofNat 64 (4 * (strWords chars).length))).eval env).toNat =
      4 * (strWords chars).length := by
    simp only [Expr.eval, BitVec.toNat_ofNat]
    exact Nat.mod_eq_of_lt (by addr_omega)
  have allocRoom : alignUp hp.cursor 2 + ((Expr.lit (BitVec.ofNat 64 (4 * (strWords chars).length))).eval
      env).toNat ≤ hp.limit := by
    rw [lit, ← pEq]; exact tail
  have ptrAt : ((env.set next (BitVec.ofNat 64 p)) next).toNat = p := by
    simp only [Env.set, if_pos]; exact pBits
  have top2 : p + 0 + 4 * (strWords chars).length ≤ ({ hp with cursor := p +
      ((Expr.lit (BitVec.ofNat 64 (4 * (strWords chars).length))).eval env).toNat } : Heap).top := by
    simp only [Heap.top]; have := hp.limit_le_top; simp only [Heap.top] at this; addr_omega
  have heapEq : ({ hp with cursor := p +
      ((Expr.lit (BitVec.ofNat 64 (4 * (strWords chars).length))).eval env).toNat } : Heap).writeBytes (p + 0)
        (wordBytes (strWords chars)) = hp3 := by
    rw [lit, Nat.add_zero]
  refine ⟨hp3, pBits, hc3, fc3, by simp only [hp3, Heap.writeBytes_eq_writeAll, Heap.writeAll], ?_, ?_⟩
  · intro rest d out exec
    refine .seq (.alloc (target := next) allocRoom) ?_
    rw [← pEq]
    refine strStores_exec (p := p) ptrAt _ (offset := 0) top2 (by addr_omega) ?_
    rw [heapEq]
    exact exec
  · intro rest d n stops
    refine .seqSecond (.alloc (target := next) allocRoom) ?_
    rw [← pEq]
    refine strStores_stops (p := p) ptrAt _ (offset := 0) top2 (by addr_omega) ?_
    rw [heapEq]
    exact stops

theorem stmt_letStr (ih : StmtSound sp mp fuel) {pointer : Nat} {chars : List Nat} {body : SrcStmt}
    (ok : (SrcStmt.letStr pointer chars body).lower (sp.sigsAt bud) sp.decls ret scope next = some stmt)
    (corr : Corr sx places scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell) (hc : HeapCorr st.heap st.world hp) (fc : FrameCorr sx bud places st hp)
    (under : ∀ x ∈ places, x.cell < base)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.letStr pointer chars body).toCore = .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates sx bud places mp hp ret scope frame base st env stmt c st' := by
  obtain ⟨bstmt, nonempty, -, ascii, bodyOk, rfl⟩ := letStr_lower_inv ok
  simp only [SrcStmt.toCore, execStmt] at run
  split at run
  · rename_i v st1 ptrRun
    obtain ⟨p, heap', map, rfl, rfl⟩ := strPtr_run ptrRun
    have room := tail_bound (st1 := { st with heap := heap' }) run bound
    obtain ⟨hp3, pBits, hc3, fc3, limit3, exec', -⟩ := str_entered (mp := mp) (env := env) (next := next)
      ascii nonempty hc fc map room
    obtain ⟨fresh', keeps, d, out, exec, matched⟩ := let_tail ih (ty := .ptr) (st := { st with heap := heap' })
      (v := .pointer p) (env' := env.set next (BitVec.ofNat 64 p)) (hp := hp3) bodyOk
      (corr.sameCells rfl fun _ => rfl) fr ⟨fresh.1, fresh.2.heapOf rfl rfl fun _ o bf => o.mapBorrowed bf map⟩
      le Nat.one_pos (fr.agree fun j below => by simp only [Env.set]; rw [if_neg (by omega)])
      (.ptr (by simp only [SrcType.Holds, Env.set, if_pos, Value.pointer.injEq]; exact pBits.symm))
      hc3 fc3 under run (by rw [limit3]; exact bound)
    exact ⟨fresh', ⟨keeps.cells, keeps.next, keeps.views, keeps.persist, keeps.arrays⟩, d, out, exec' exec, matched⟩
  all_goals simp at run

end Statements

end Lanius.Mini
