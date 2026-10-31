import Lanius.Faithful.SafeDriver
import Lanius.Mini.SourceOutcome

/-! # The self-built verified compiler (roadmap step V7)

`prog` is the self program: the verified compiler's own Lanius source with
the driver `w(input, words, output, room)`. A binary `B` with
`compileSource prog = some B` is the self-built verified compiler.
`selfCompiler_outcome` is about its machine code for `w`, entered with the
words of source files at `selfInput` and `room` output words after them
(`selfStart`, `selfHeap`): it faults (every run that stops, stops at a fault:
out of stack or heap, or a checked trap), or it returns, deterministically,
-1 when `compileText` rejects the files, and otherwise the length of the
words of `compileText`'s binary, with those words in the output view. The
theorem joins `driver_files` (V1, V5) with `compileSource_outcome_from` (V2),
and `driver_safe` (V7b) rules out the run of `w` Core traps undefinedly in.

What this leaves to trust about the native self-built compiler: that its
bytes are `compileSource prog`, which `lake exe runAll` computes (Lean's
compiled code, not the kernel), and which the fixpoint test confirms
byte for byte. -/

namespace Lanius.Faithful.SelfCompiler

open Lanius.Mini
open Lanius.X86.Machine
open Lanius.Core (Value)
open Lanius.Faithful
open Lanius.Faithful.Self
open Lanius.Faithful.SelfDriver

/-! ## The input and output views -/

/-- Byte `a` of the words `W`, little-endian. -/
def wordByte (W : List (BitVec 32)) (a : Nat) : UInt8 :=
  UInt8.ofNat ((W.getD (a / 4) 0).toNat / 256 ^ (a % 4) % 256)

/-- The input view's address. -/
def selfInput : Nat := 4

/-- The output view's address: after the input words. -/
def selfOutput (W : List (BitVec 32)) : Nat := selfInput + 4 * W.length

/-- Core's next free address: after the output view. -/
def selfNext (W : List (BitVec 32)) (room : Nat) : Nat := selfOutput W + 4 * room + 4

def inputBlock (W : List (BitVec 32)) : Memory.Block :=
  { base := selfInput, size := 4 * W.length, alignment := 4, bytes := (List.range (4 * W.length)).map (wordByte W) }

def outputBlock (W : List (BitVec 32)) (room : Nat) : Memory.Block :=
  { base := selfOutput W, size := 4 * room, alignment := 4, bytes := List.replicate (4 * room) 0 }

/-- The Core state `w` starts in: the input words and `room` zero words. -/
def selfStart (W : List (BitVec 32)) (room : Nat) : Semantics.State :=
  { heap := { blocks := [inputBlock W, outputBlock W room], nextAddress := selfNext W room } }

/-- The x86 heap that represents it, with limit `limit`. -/
def selfHeap (W : List (BitVec 32)) (room limit : Nat) : Heap :=
  { bytes := fun a => if selfInput ≤ a ∧ a < selfOutput W then wordByte W (a - selfInput) else 0
    cursor := selfNext W room
    limit := limit }

/-- `w`'s arguments as Core values. -/
def selfArgs (W : List (BitVec 32)) (room : Nat) : List Value :=
  [.pointer selfInput, .signed .i32 W.length, .pointer (selfOutput W), .signed .i32 room]

/-- `w`'s arguments as slots. -/
def selfBits (W : List (BitVec 32)) (room : Nat) : List (BitVec 64) :=
  [BitVec.ofNat 64 selfInput, widen (BitVec.ofNat 32 W.length), BitVec.ofNat 64 (selfOutput W),
    widen (BitVec.ofNat 32 room)]

/-- `omega` through the layout's names and `Address`. -/
macro "self_omega" : tactic =>
  `(tactic| ((try simp only [Lanius.Address, selfInput, selfOutput, selfNext] at *) <;> omega))

section
variable {W : List (BitVec 32)} {room : Nat}

theorem containing_input {a : Nat} (lo : selfInput ≤ a) (hi : a < selfOutput W) :
    (selfStart W room).heap.containingBlock? a = some (inputBlock W) := by
  unfold Memory.Heap.containingBlock?
  rw [show (selfStart W room).heap.blocks = [inputBlock W, outputBlock W room] from rfl, List.find?_cons_of_pos]
  simp only [selfOutput, selfInput] at lo hi
  simp [inputBlock, selfInput, lo, hi]

theorem containing_output {a : Nat} (lo : selfOutput W ≤ a) (hi : a < selfOutput W + 4 * room) :
    (selfStart W room).heap.containingBlock? a = some (outputBlock W room) := by
  unfold Memory.Heap.containingBlock?
  rw [show (selfStart W room).heap.blocks = [inputBlock W, outputBlock W room] from rfl, List.find?_cons_of_neg,
    List.find?_cons_of_pos]
  · simp [outputBlock, lo, hi]
  · have no : ¬a < 4 + 4 * W.length := by simp only [selfOutput, selfInput] at lo; omega
    simp [inputBlock, selfInput, no]

theorem loadByte_input {p o : Nat} (lo : selfInput ≤ p + o) (hi : p + o < selfOutput W) :
    (selfStart W room).heap.loadByte p o = .ok (wordByte W (p + o - selfInput)) := by
  have lt : p + o - selfInput < 4 * W.length := by simp only [selfOutput] at hi; self_omega
  simp only [Memory.Heap.loadByte, containing_input lo hi]
  simp [inputBlock, List.getElem?_map, List.getElem?_range lt]

theorem loadByte_output {p o : Nat} (lo : selfOutput W ≤ p + o) (hi : p + o < selfOutput W + 4 * room) :
    (selfStart W room).heap.loadByte p o = .ok 0 := by
  have lt : p + o - selfOutput W < 4 * room := by self_omega
  simp only [Memory.Heap.loadByte, containing_output lo hi]
  simp [outputBlock, lt]

theorem decode_word (x : BitVec 32) :
    Semantics.decodeNatLE [UInt8.ofNat (x.toNat / 256 ^ 0 % 256), UInt8.ofNat (x.toNat / 256 ^ 1 % 256),
      UInt8.ofNat (x.toNat / 256 ^ 2 % 256), UInt8.ofNat (x.toNat / 256 ^ 3 % 256)] = x.toNat := by
  have := x.isLt
  simp [Semantics.decodeNatLE]
  self_omega

theorem signed_word (x : BitVec 32) :
    (if x.toNat ≥ 2 ^ 31 then Int.ofNat x.toNat - 2 ^ 32 else Int.ofNat x.toNat) = x.toInt := by
  rw [BitVec.toInt_eq_toNat_cond]
  have := x.isLt
  simp only [Int.ofNat_eq_natCast]
  split <;> split <;> self_omega

/-- The input view reads `W`. -/
theorem start_reads (len : W.length < 2 ^ 31) : Reads (selfStart W room) selfInput W := by
  intro i lt
  have b : ∀ j, j < 4 → (selfStart W room).heap.loadByte (selfInput + i * 4) j =
      .ok (UInt8.ofNat ((W[i]).toNat / 256 ^ j % 256)) := by
    intro j lj
    rw [loadByte_input (by self_omega) (by simp only [selfOutput]; self_omega)]
    simp only [wordByte, show (selfInput + i * 4 + j - selfInput) / 4 = i by self_omega,
      show (selfInput + i * 4 + j - selfInput) % 4 = j by self_omega, List.getD_eq_getElem?_getD,
      List.getElem?_eq_getElem lt, Option.getD_some]
  simp only [Semantics.readRawSliceIndex, show ¬i ≥ W.length by self_omega, if_false, Semantics.rawSliceElementAddress?,
    NativeLayout.maxDepth, Semantics.readNativeValue, Semantics.loadNatLE, Memory.Heap.loadBytes,
    Memory.loadBytesFrom, b 0 (by self_omega), b 1 (by self_omega), b 2 (by self_omega), b 3 (by self_omega), bind, Except.bind, pure,
    Except.pure, decode_word, signed_word]

/-- The output view's bytes are readable. -/
theorem start_readable : (selfStart W room).heap.Readable (selfOutput W) (room * 4) := by
  intro index lt
  exact ⟨0, loadByte_output (by self_omega) (by self_omega)⟩

theorem start_inv (nonempty : 0 < W.length) : Inv (selfStart W room) where
  views := rfl
  fresh := fun _ mem => by simp [selfStart] at mem
  below := by
    intro b mem
    simp only [selfStart, List.mem_cons, List.mem_nil_iff, or_false] at mem
    rcases mem with rfl | rfl <;> simp [inputBlock, outputBlock, selfStart, selfNext, selfOutput, selfInput, Nat.max_def] <;>
      split <;> addr_omega
  unique := by
    intro l ml r mr same
    simp only [selfStart, List.mem_cons, List.mem_nil_iff, or_false] at ml mr
    rcases ml with rfl | rfl <;> rcases mr with rfl | rfl <;>
      first | rfl | (simp [inputBlock, outputBlock, selfOutput, selfInput] at same; self_omega)

theorem start_range_input (pos : 0 < W.length) :
    (selfStart W room).heap.checkRange selfInput (W.length * 4) 4 = .ok () := by
  simp only [Memory.Heap.checkRange, containing_input (W := W) (room := room) (Nat.le_refl _)
    (by simp only [selfOutput]; omega)]
  simp [inputBlock, Memory.validAlignment, selfInput]
  rw [if_neg (by rw [show Nat.log2 4 = 2 by decide]; omega), if_neg (by omega)]

theorem start_range_output (pos : 0 < room) :
    (selfStart W room).heap.checkRange (selfOutput W) (room * 4) 4 = .ok () := by
  simp only [Memory.Heap.checkRange, containing_output (W := W) (room := room) (Nat.le_refl _) (by omega)]
  simp [outputBlock, Memory.validAlignment, selfOutput, selfInput]
  rw [if_neg (by rw [show Nat.log2 4 = 2 by decide]; omega), if_neg (by omega)]

theorem start_fresh : (selfStart W room).Fresh := ⟨fun _ mem => by simp [selfStart] at mem, rfl⟩

theorem start_corr (nonempty : 0 < W.length) {limit : Nat} (small : limit < 2 ^ 62) :
    HeapCorr (selfStart W room).heap (selfStart W room).world (selfHeap W room limit) where
  cursor := rfl
  pos := by simp [selfStart, selfNext]
  unbounded := rfl
  small := small
  sized := by
    intro b mem
    simp only [selfStart, List.mem_cons, List.mem_nil_iff, or_false] at mem
    rcases mem with rfl | rfl <;> simp [inputBlock, outputBlock]
  below := by
    intro b mem
    simp only [selfStart, List.mem_cons, List.mem_nil_iff, or_false] at mem
    rcases mem with rfl | rfl <;> simp [inputBlock, outputBlock, selfStart, selfNext, selfOutput, selfInput, Nat.max_def] <;>
      split <;> addr_omega
  apart := by
    intro l ml r mr less
    simp only [selfStart, List.mem_cons, List.mem_nil_iff, or_false] at ml mr
    rcases ml with rfl | rfl <;> rcases mr with rfl | rfl <;>
      simp [inputBlock, outputBlock, selfOutput, selfInput] at less ⊢ <;> self_omega
  unique := by
    intro l ml r mr same
    simp only [selfStart, List.mem_cons, List.mem_nil_iff, or_false] at ml mr
    rcases ml with rfl | rfl <;> rcases mr with rfl | rfl <;>
      first | rfl | (simp [inputBlock, outputBlock, selfOutput, selfInput] at same; self_omega)
  bytes := by
    intro b mem _ i lt
    simp only [selfStart, List.mem_cons, List.mem_nil_iff, or_false] at mem
    rcases mem with rfl | rfl
    · simp only [inputBlock, List.length_map, List.length_range] at lt
      simp [selfHeap, inputBlock, selfOutput, selfInput, lt]
    · simp [outputBlock] at lt
      simp only [selfHeap, outputBlock]
      rw [if_neg (by simp only [selfOutput, selfInput]; omega)]
      simp
  zero := by
    intro a ge _
    apply if_neg
    intro h
    simp only [selfStart, selfNext, selfOutput, selfInput] at ge h
    addr_omega
  out := rfl
  err := rfl
  closed := rfl
  input := rfl

theorem args_hold (wordsLt : W.length < 2 ^ 31) (roomLt : room < 2 ^ 31) :
    FieldsHold (paramTypes (src_app_main_w 1 2 5 6 7 8).params) (selfArgs W room) (Func.entry (selfBits W room)) 0 := by
  have i32 : ∀ n : Nat, n < 2 ^ 31 → SrcType.i32.Holds (.signed .i32 n) (widen (BitVec.ofNat 32 n)) := by
    intro n lt
    have lw : low (widen (BitVec.ofNat 32 n)) = BitVec.ofNat 32 n := by
      simp [low, widen, BitVec.setWidth_setWidth_of_le]
    refine ⟨?_, by rw [lw]⟩
    rw [lw, BitVec.toInt_eq_toNat_cond]
    simp only [BitVec.toNat_ofNat, Nat.mod_eq_of_lt (show n < 2 ^ 32 by omega)]
    congr 1
    split <;> omega
  exact .cons (.ptr (by simp [SrcType.Holds, Func.entry, selfBits, selfInput]))
    (.cons (.i32 (i32 _ wordsLt))
    (.cons (.ptr (by
      simp [SrcType.Holds, SrcType.size, Func.entry, selfBits, selfOutput, selfInput]; exact (Nat.mod_eq_of_lt (by omega)).symm))
    (.cons (.i32 (i32 _ roomLt)) .nil)))

end

/-! ## The output, in x86 memory -/

/-- An output word Core's final state reads is the x86 memory's
little-endian word at the same heap offset. -/
theorem written_memory {st : Semantics.State} {after : Heap} {memory : Memory} {base : BitVec 64}
    {outp room : Nat} {ws : List (BitVec 32)} (written : Written st outp room 0 ws)
    (corr : HeapCorr st.heap st.world after) (within : st.heap.nextAddress ≤ after.limit)
    (agree : ∀ a, a < after.limit → memory (base + BitVec.ofNat 64 a) = after.bytes a) :
    ∀ i (lt : i < ws.length), memLE memory (base + BitVec.ofNat 64 (outp + 4 * i)) 4 = (ws[i]).toNat := by
  intro i lt
  have read := written i lt
  rw [Nat.zero_add] at read
  simp only [Semantics.readRawSliceIndex, Semantics.rawSliceElementAddress?, NativeLayout.maxDepth,
    Semantics.readNativeValue, bind, Except.bind, pure, Except.pure] at read
  split at read
  · cases read
  · cases h : Semantics.loadNatLE st.heap (outp + i * 4) 4 with
    | error e => rw [h] at read; cases read
    | ok n =>
      rw [h] at read
      simp only [Except.ok.injEq, Value.signed.injEq, true_and] at read
      obtain ⟨eq, fits⟩ := corr.loadNatLE h
      have nLt : n < 2 ^ 32 := by rw [eq]; exact Heap.readLE_lt _ _ _
      have same : BitVec.ofNat 32 n = ws[i] := by
        rw [← BitVec.toInt_inj, ← signed_word, BitVec.toNat_ofNat, Nat.mod_eq_of_lt nLt]
        exact read
      rw [memLE_heap memory base after (outp + 4 * i) 4 (fun k lk => agree _ (by have := fits (by omega); addr_omega)),
        show outp + 4 * i = outp + i * 4 by omega, ← eq, ← same, BitVec.toNat_ofNat, Nat.mod_eq_of_lt nLt]

/-- What the self-built verified compiler's `w` returned in `s'`, entered
in `s`: rax's low 32 bits are -1 when `compileText` rejects the files, and
otherwise the number of words of its binary, which are in the output view. -/
def SelfOutput (binary : Option Binary) (W : List (BitVec 32)) (s s' : State) : Prop :=
  match binaryWords binary with
  | none => (low (s'.registers 0)).toInt = -1
  | some ws => (low (s'.registers 0)).toInt = ws.length ∧
      ∀ i (lt : i < ws.length),
        memLE s'.memory (s.registers heapBaseRegister + BitVec.ofNat 64 (selfOutput W + 4 * i)) 4 = (ws[i]).toNat

/-! ## The self-built verified compiler -/

theorem filesWords_pos (files : List SourceFile) : 0 < (filesWords files).length := by
  simp [filesWords]

/-- **The self-built verified compiler** (CakeML style). Let `B` be the
binary the verified compiler makes of its own source (`prog`), and enter its
code for `w` by a near call with the words of source `files` in the input
view and `room` words of output view after them (`selfHeap`, `selfBits`),
any stack window and any heap limit past them. Then the run faults (every
run of it that stops, stops at a fault), or it returns, deterministically,
with `compileText files`'s answer (`SelfOutput`). -/
theorem selfCompiler_outcome {B : Binary} (compiled : compileSource prog = some B) {files : List SourceFile}
    (fit : FilesFit files) (wordsLt : (filesWords files).length < 2 ^ 31) {room limit : Nat} (roomLt : room < 2 ^ 31)
    (enough : selfNext (filesWords files) room ≤ limit) (small : limit < 2 ^ 62)
    (s : State) (imageBase : BitVec 64) (window : Nat) (bounded : window ≤ 2 ^ 62)
    (loaded : CodeAt s.memory imageBase B.image)
    (apart : ∀ index, index < B.image.length →
      ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index))
    (imageHeap : ∀ index, index < B.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index))
    (entry : s.rip = imageBase + BitVec.ofNat 64 (B.entries.getD 0 0))
    (params : ∀ k (bound : k < (selfBits (filesWords files) room).length),
      read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = (selfBits (filesWords files) room)[k])
    (heapAt : HeapAt window s (selfHeap (filesWords files) room limit)) (stack : StackAt B.guard window s) :
    Faults s ∨
    ∃ n s' results after, Steps n s s' ∧ Det n s s' ∧ Returned window s s' results after ∧
      SelfOutput (compileText files) (filesWords files) s s' := by
  have nonempty := filesWords_pos files
  rcases compileSource_outcome_from compiled fn_w (args_hold wordsLt roomLt) rfl start_fresh
      (start_corr nonempty small) enough s imageBase window bounded loaded apart imageHeap entry params heapAt stack with
    faults | ⟨fuel, v, final, runs, fits, results, after, holds, len, corr, n, s', run, det, ret⟩ | undefined
  · exact .inl faults
  · refine .inr ⟨n, s', results, after, run, det, ret, ?_⟩
    have result := driver_files fit (start_inv nonempty) (by have := small; simp only [selfHeap] at fits; addr_omega)
      wordsLt roomLt (start_reads wordsLt) start_readable runs
    obtain ⟨r, rfl⟩ : ∃ r, results = [r] := by
      match results, len with
      | [r], _ => exact ⟨r, rfl⟩
    have rax : s'.registers 0 = r := ret.value r rfl
    have value : v = .signed .i32 (low r).toInt := by
      cases holds with
      | i32 h => exact h.1
    have agree : ∀ a, a < after.limit → s'.memory (s.registers heapBaseRegister + BitVec.ofNat 64 a) = after.bytes a :=
      ret.heap
    have within : final.heap.nextAddress ≤ after.limit := by
      rw [ret.limit, ← heapAt.limit]; exact fits
    unfold SelfOutput
    unfold Result at result
    split at result
    · rename_i none
      rw [none, rax]
      rw [value] at result
      simp only [Value.signed.injEq, true_and] at result
      exact result
    · rename_i ws some
      rw [some, rax]
      rw [value] at result
      simp only [Value.signed.injEq, true_and] at result
      exact ⟨result.1, written_memory result.2 corr within agree⟩
  · -- Core's run of `w` traps only definedly (`driver_safe`, V7b).
    obtain ⟨fuel, r, st', trapped, bad, within⟩ := undefined
    have safe := driver_safe (st := selfStart (filesWords files) room) (start_inv nonempty) wordsLt roomLt
      (start_reads wordsLt) start_readable (.inr (start_range_input nonempty))
      (if h : room = 0 then .inl h else .inr (start_range_output (Nat.pos_of_ne_zero h)))
    rw [safe fuel r st' trapped (Nat.le_trans (by simpa only [selfHeap] using within) (by omega))] at bad
    cases bad

end Lanius.Faithful.SelfCompiler
