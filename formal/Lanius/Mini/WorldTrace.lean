import Lanius.World
import Lanius.X86.Machine.Io
import Lanius.Mini.HeapCorr

/-! Core's host world and the process's write trace (roadmap F8).

Core keeps what a program wrote as two byte lists in its world,
`standardOutput` and `standardError`; the x86 model and the mini IR keep one
trace of `write` events (`Lanius.X86.Machine.Io`). `HeapCorr h w hp` says that
the world's output is what the mini heap's trace wrote to fds 1 and 2
(`outputOf`), and that no file is open.

The host functions the verified compiler lowers (`hostFuncs`) are Core's
`write_byte`, `write_stdout` and `write_stderr`, with Core's own meaning
(`World.call`, inverted by `call_writeByte_inv` and `call_writeOut_inv`). Their
code (`hostByteCode`, `hostWriteCode`) is system calls:

- `write_byte(handle, value)` to handle 1 or 2 writes the value's low byte
  through the heap's byte 0, which is in no block (Core's addresses start at
  1), and puts the byte back (`hostByte_exec`); any other handle returns -1,
  as Core's does with no file open (`hostByte_other`).
- `write_stdout`/`write_stderr(pointer, count)` writes in chunks of at most
  `maxTransfer` bytes until none are left (`writeLoop`); the chunks' bytes are
  the heap's slice that Core loads (`HeapCorr.loadBytes_slice`). -/

namespace Lanius.Mini

open Lanius.X86.Machine (Event Io maxTransfer)
open Lanius.Core (Value)

/-! ## The world and the trace -/

/-- The byte `write_byte` writes for an `i32` value: its low byte. -/
def hostByte (value : Int) : UInt8 := UInt8.ofNat (Int.toNat (value % 256))

/-- The low byte of an `i32` value's bits is the byte Core writes. -/
theorem hostByte_low (x : BitVec 32) : hostByte x.toInt = lowByte (widen x) := by
  unfold hostByte lowByte widen
  congr 1
  rw [BitVec.toNat_setWidth, BitVec.toNat_setWidth, BitVec.toInt_eq_toNat_cond]
  have := x.isLt
  split <;> omega

/-- `HeapCorr` for another world and a mini heap with the same bytes,
cursor and limit, whose trace the world's output is. -/
theorem HeapCorr.retrace {h : Memory.Heap} {w : World.State} {hp : Heap} (corr : HeapCorr h w hp)
    {w' : World.State} {hp' : Heap} (bytes : hp'.bytes = hp.bytes) (cursor : hp'.cursor = hp.cursor)
    (limit : hp'.limit = hp.limit) (out : w'.standardOutput = outputOf 1 hp'.io.trace)
    (err : w'.standardError = outputOf 2 hp'.io.trace) (closed : w'.fileHandles = [])
    (input : w'.standardInput = hp'.io.input) : HeapCorr h w' hp' := by
  obtain ⟨c, pos, unb, small, sized, below, apart, unique, bs, zero, -, -, -, -⟩ := corr
  refine ⟨cursor.trans c, pos, unb, limit ▸ small, sized, below, apart, unique, ?_, ?_, out, err, closed, input⟩
  · intro b mem live i lt
    rw [bytes]
    exact bs b mem live i lt
  · intro a ge
    rw [bytes]
    exact zero a ge

/-- A world whose output grew by `bytes` on `fd` and a mini heap with the
same bytes, cursor and limit whose trace grew by events writing exactly those
bytes keep `HeapCorr`. -/
theorem HeapCorr.wrote {h : Memory.Heap} {w : World.State} {hp : Heap} (corr : HeapCorr h w hp)
    {w' : World.State} {hp' : Heap} {fd : Nat} {bytes : List UInt8} {events : List Event}
    (sameBytes : hp'.bytes = hp.bytes) (cursor : hp'.cursor = hp.cursor) (limit : hp'.limit = hp.limit)
    (trace : hp'.io.trace = hp.io.trace ++ events)
    (outs : ∀ k, outputOf k events = if fd = k then bytes else [])
    (out : w'.standardOutput = w.standardOutput ++ (if fd = 1 then bytes else []))
    (err : w'.standardError = w.standardError ++ (if fd = 2 then bytes else []))
    (closed : w'.fileHandles = w.fileHandles) (input : w'.standardInput = hp'.io.input) : HeapCorr h w' hp' :=
  corr.retrace sameBytes cursor limit (by simp only [out, corr.out, trace, outputOf_append, outs])
    (by simp only [err, corr.err, trace, outputOf_append, outs]) (closed.trans corr.closed) input

/-- The record of host calls does not touch the output or the files. -/
theorem HeapCorr.record {h : Memory.Heap} {w : World.State} {hp : Heap} (corr : HeapCorr h w hp)
    (service : Core.HostService) : HeapCorr h (World.record w service) hp :=
  corr.retrace rfl rfl rfl corr.out corr.err corr.closed corr.input

/-- With no file open, a write to a file handle has nowhere to go. -/
theorem writeFileBytes_closed {w : World.State} (closed : w.fileHandles = []) (handle : Int)
    (bytes : List UInt8) : World.writeFileBytes w handle bytes = none := by
  simp [World.writeFileBytes, World.State.handle?, closed]

/-- The bytes Core loads from a range are the mini heap's bytes there, below
Core's cursor. -/
theorem HeapCorr.loadBytesFrom_slice {h : Memory.Heap} {w : World.State} {hp : Heap} (corr : HeapCorr h w hp)
    {p : Nat} :
    ∀ (count o : Nat) {bytes : List UInt8}, Memory.loadBytesFrom h p o count = .ok bytes →
      bytes = hp.slice (p + o) count ∧ (0 < count → p + o + count ≤ h.nextAddress)
  | 0, o, bytes, ok => by
    simp only [Memory.loadBytesFrom, Except.ok.injEq] at ok
    subst ok
    exact ⟨rfl, fun lt => absurd lt (Nat.lt_irrefl 0)⟩
  | count + 1, o, bytes, ok => by
    simp only [Memory.loadBytesFrom] at ok
    split at ok
    · simp at ok
    · rename_i b loaded
      split at ok
      · simp at ok
      · rename_i rest restOk
        simp only [Except.ok.injEq] at ok
        subst ok
        obtain ⟨at_, below⟩ := corr.load loaded
        obtain ⟨sliced, restBelow⟩ := corr.loadBytesFrom_slice count (o + 1) restOk
        refine ⟨?_, fun _ => ?_⟩
        · simp only [Heap.slice, at_, sliced, Nat.add_assoc]
        · rcases Nat.eq_zero_or_pos count with zero | pos
          · subst zero; omega
          · have := restBelow pos; omega

theorem HeapCorr.loadBytes_slice {h : Memory.Heap} {w : World.State} {hp : Heap} (corr : HeapCorr h w hp)
    {p count : Nat} {bytes : List UInt8} (ok : h.loadBytes p count = .ok bytes) :
    bytes = hp.slice p count ∧ (0 < count → p + count ≤ h.nextAddress) :=
  corr.loadBytesFrom_slice count 0 ok

theorem Heap.slice_length (hp : Heap) : ∀ (address count : Nat), (hp.slice address count).length = count
  | _, 0 => rfl
  | address, count + 1 => by simp [Heap.slice, Heap.slice_length hp (address + 1) count]

theorem Heap.slice_io (hp : Heap) (io : Io) : ∀ (address count : Nat),
    ({ hp with io } : Heap).slice address count = hp.slice address count
  | _, 0 => rfl
  | address, count + 1 => by simp [Heap.slice, Heap.slice_io hp io (address + 1) count]

theorem Heap.slice_append (hp : Heap) : ∀ (address first second : Nat),
    hp.slice address first ++ hp.slice (address + first) second = hp.slice address (first + second)
  | _, 0, _ => by simp [Heap.slice]
  | address, first + 1, second => by
    have := Heap.slice_append hp (address + 1) first second
    rw [show address + (first + 1) = address + 1 + first by omega]
    rw [show first + 1 + second = (first + second) + 1 by omega]
    simp only [Heap.slice, List.cons_append, this]

/-- `Syscall.write` within its bounds returns the count and appends the
heap's slice to the trace. -/
theorem Syscall.run_write {heap : Heap} {fd address count : BitVec 64}
    (which : fd = 1 ∨ fd = 2) (small : count.toNat ≤ maxTransfer)
    (inside : address.toNat + count.toNat ≤ heap.top) :
    Syscall.run .write [fd, address, count] heap =
      some (count, { heap with io := { heap.io with trace := heap.io.trace ++
        [.write fd.toNat (heap.slice address.toNat count.toNat)] } }) := by
  rw [Syscall.run, if_pos ⟨which, small, inside⟩]

theorem wrapI32_eq (x : Int) : World.wrapI32 x = Semantics.wrapSigned .x86_64 .i32 x := rfl

/-- Core's `i32` result of a count. -/
theorem i32Result_nat (n : Nat) : World.i32Result n = .signed .i32 (BitVec.ofNat 32 n).toInt := by
  simp only [World.i32Result, wrapI32_eq]
  exact congrArg _ (wrap_nat n)

/-! ## The code of `write_byte` -/

theorem set_get (E : Env) (j v : Nat) (x : BitVec 64) : E.set j x v = if v = j then x else E v := rfl

/-- `write_byte` to handle 1 or 2: one event with the value's low byte, the
heap's bytes as they were, and 1 in `slot`. -/
theorem hostByte_exec {mp : Program} {d : Nat} {E : Env} {H : Heap} (slot : Nat) (pos : 0 < H.top)
    (which : E slot = 1 ∨ E slot = 2) :
    ∃ E' H', Exec mp d E H (hostByteCode slot) (.normal E' H') ∧ (∀ j < slot, E' j = E j) ∧ E' slot = 1 ∧
      H'.bytes = H.bytes ∧ H'.cursor = H.cursor ∧ H'.limit = H.limit ∧ H'.top = H.top ∧
      H'.io.trace = H.io.trace ++ [Event.write (E slot).toNat [lowByte (E (slot + 1))]] ∧ H'.io.input = H.io.input := by
  have cond : (Expr.binary .u64 .or (.compare .u64 .eq (.var slot) (.lit 1))
      (.compare .u64 .eq (.var slot) (.lit 2))).eval E ≠ 0 := by
    rcases which with one | two
    · simp [Expr.eval, Word.apply, Word.holds, BinOp.apply, CmpOp.holdsU, one]
    · simp [Expr.eval, Word.apply, Word.holds, BinOp.apply, CmpOp.holdsU, two]
  have inside : ((Expr.lit 0).eval E).toNat < H.top := by simpa [Expr.eval] using pos
  let E1 := E.set (slot + 2) (BitVec.ofNat 64 (H.bytes ((Expr.lit 0).eval E).toNat).toNat)
  have s1 : Exec mp d E H (.loadByte (slot + 2) (.lit 0)) (.normal E1 H) := .loadByte inside
  let H1 := H.write ((Expr.lit 0).eval E1).toNat (lowByte ((Expr.var (slot + 1)).eval E1))
  have s2 : Exec mp d E1 H (.storeByte (.lit 0) (.var (slot + 1))) (.normal E1 H1) :=
    .storeByte (by simpa [Expr.eval] using pos)
  have fd : E1 slot = E slot := by simp [E1, set_get]
  have arg : E1 (slot + 1) = E (slot + 1) := by simp [E1, set_get]
  let H2 : Heap := { H1 with io := { H1.io with trace := H1.io.trace ++
    [Event.write (E1 slot).toNat (H1.slice (0 : BitVec 64).toNat (1 : BitVec 64).toNat)] } }
  have ran : Syscall.run .write (Expr.evalAll E1 [.var slot, .lit 0, .lit 1]) H1 = some (1, H2) :=
    Syscall.run_write (by simpa [Expr.eval, fd] using which) (by simp [Expr.eval, maxTransfer])
      (by simp [Expr.eval, H1, Heap.write, Heap.top] at pos ⊢; omega)
  have s3 : Exec mp d E1 H1 (.sys .write (slot + 3) [.var slot, .lit 0, .lit 1]) (.normal (E1.set (slot + 3) 1) H2) :=
    .sys ran
  let E2 := E1.set (slot + 3) 1
  let H3 := H2.write ((Expr.lit 0).eval E2).toNat (lowByte ((Expr.var (slot + 2)).eval E2))
  have s4 : Exec mp d E2 H2 (.storeByte (.lit 0) (.var (slot + 2))) (.normal E2 H3) :=
    .storeByte (by simpa [Expr.eval, H2, H1, Heap.write, Heap.top] using pos)
  have s5 : Exec mp d E2 H3 (.assign slot (.lit 1)) (.normal (E2.set slot ((Expr.lit 1).eval E2)) H3) := .assign
  have saved : E2 (slot + 2) = BitVec.ofNat 64 (H.bytes 0).toNat := by simp [E2, E1, set_get, Expr.eval]
  refine ⟨_, _, .ifTrue cond (.seq s1 (.seq s2 (.seq s3 (.seq s4 s5)))), ?_, by simp [set_get, Expr.eval], ?_,
    rfl, rfl, rfl, ?_, rfl⟩
  · intro j lt
    simp only [E2, E1, set_get]
    rw [if_neg (by omega), if_neg (by omega), if_neg (by omega)]
  · funext a
    simp only [H3, H2, H1, Heap.write, Expr.eval, saved]
    by_cases at0 : a = 0
    · subst at0
      simp only [BitVec.toNat_zero, if_true, lowByte]
      apply UInt8.toNat.inj
      simp
    · simp [at0]
  · simp [H3, H2, H1, Heap.write, Heap.slice, Expr.eval, fd, arg]

/-- `write_byte` to any other handle: -1 in `slot`, nothing else. -/
theorem hostByte_other {mp : Program} {d : Nat} {E : Env} {H : Heap} (slot : Nat) (other : E slot ≠ 1 ∧ E slot ≠ 2) :
    Exec mp d E H (hostByteCode slot) (.normal (E.set slot 4294967295) H) := by
  refine .ifFalse ?_ .assign
  simpa [Expr.eval, Word.apply, Word.holds, BinOp.apply, CmpOp.holdsU] using other

/-! ## The code of `write_stdout` and `write_stderr` -/

/-- The write loop's condition: some bytes are left. -/
def writeCond (slot : Nat) : Expr := .compare .u64 .ne (.var (slot + 1)) (.lit 0)

/-- One turn: a chunk of at most `maxTransfer` bytes, written, and the
pointer and count moved past it. -/
def writeBody (fd : BitVec 64) (slot : Nat) : Stmt :=
  .seq (.ite (.compare .u64 .lt (.var (slot + 1)) (.lit 2147479552)) (.assign (slot + 3) (.var (slot + 1)))
      (.assign (slot + 3) (.lit 2147479552)))
    (.seq (.sys .write (slot + 4) [.lit fd, .var slot, .var (slot + 3)])
      (.seq (.assign slot (.binary .u64 .add (.var slot) (.var (slot + 3))))
        (.assign (slot + 1) (.binary .u64 .sub (.var (slot + 1)) (.var (slot + 3))))))

theorem hostWriteCode_eq (fd : BitVec 64) (slot : Nat) :
    hostWriteCode fd slot = .seq (.assign (slot + 2) (.var (slot + 1)))
      (.seq (.loop (writeCond slot) (writeBody fd slot))
        (.assign slot (.binary .s32 .add (.var (slot + 2)) (.lit 0)))) := rfl

theorem eval_pick (E : Env) (slot : Nat) :
    (if Word.holds .u64 .lt ((Expr.var (slot + 1)).eval E) ((Expr.lit 2147479552).eval E) then (1 : BitVec 64) else 0)
      ≠ 0 ↔ (E (slot + 1)).toNat < maxTransfer := by
  simp [Expr.eval, Word.holds, CmpOp.holdsU, BitVec.ult, maxTransfer]

/-- The loop writes the `count` bytes from the pointer, in chunks, and keeps
the slots below `slot` and `slot + 2`. -/
theorem writeLoop {mp : Program} {d : Nat} (fd : BitVec 64) (which : fd = 1 ∨ fd = 2) (slot : Nat) :
    ∀ (n : Nat) (E : Env) (H : Heap), (E (slot + 1)).toNat = n →
      (0 < n → (E slot).toNat + n ≤ H.limit) → H.limit < 2 ^ 62 → H.limit ≤ H.top →
      ∃ E' events, Exec mp d E H (.loop (writeCond slot) (writeBody fd slot))
          (.normal E' { H with io := { H.io with trace := H.io.trace ++ events } }) ∧
        (∀ j, j < slot ∨ j = slot + 2 → E' j = E j) ∧
        ∀ k, outputOf k events = if fd.toNat = k then H.slice (E slot).toNat n else [] := by
  intro n
  induction n using Nat.strongRecOn with
  | ind n ih =>
    intro E H count inside small topped
    rcases Nat.eq_zero_or_pos n with zero | pos
    · subst zero
      have done : (writeCond slot).eval E = 0 := by
        have : E (slot + 1) = 0 := BitVec.eq_of_toNat_eq (by simpa using count)
        simp [writeCond, Expr.eval, Word.holds, CmpOp.holdsU, this]
      refine ⟨E, [], ?_, fun _ _ => rfl, fun k => by simp [outputOf, Heap.slice]⟩
      rw [List.append_nil]
      exact .loopDone done
    · have going : (writeCond slot).eval E ≠ 0 := by
        have : E (slot + 1) ≠ 0 := fun h => by rw [h] at count; simp at count; omega
        simpa [writeCond, Expr.eval, Word.holds, CmpOp.holdsU] using this
      have p_lt := inside pos
      -- the chunk: the count, or `maxTransfer` when more are left
      obtain ⟨cbits, c, picked, cnat, cpos, cle, cmax⟩ : ∃ (cbits : BitVec 64) (c : Nat),
          Exec mp d E H (.ite (.compare .u64 .lt (.var (slot + 1)) (.lit 2147479552))
            (.assign (slot + 3) (.var (slot + 1))) (.assign (slot + 3) (.lit 2147479552)))
            (.normal (E.set (slot + 3) cbits) H) ∧ cbits.toNat = c ∧ 0 < c ∧ c ≤ n ∧ c ≤ maxTransfer := by
        by_cases lt : (E (slot + 1)).toNat < maxTransfer
        · exact ⟨E (slot + 1), n, .ifTrue ((eval_pick E slot).mpr lt) .assign, count, pos, Nat.le_refl _,
            by omega⟩
        · refine ⟨2147479552, maxTransfer, .ifFalse ?_ .assign, by simp [maxTransfer], by simp [maxTransfer],
            by omega, Nat.le_refl _⟩
          exact Classical.byContradiction fun h => lt ((eval_pick E slot).mp h)
      -- the write
      let E1 := E.set (slot + 3) cbits
      have e1p : E1 slot = E slot := by simp [E1, set_get]
      have e1c : E1 (slot + 3) = cbits := by simp [E1, set_get]
      let H1 : Heap := { H with io := { H.io with trace := H.io.trace ++
        [Event.write fd.toNat (H.slice (E1 slot).toNat (E1 (slot + 3)).toNat)] } }
      have ran : Syscall.run .write (Expr.evalAll E1 [.lit fd, .var slot, .var (slot + 3)]) H = some (E1 (slot + 3), H1) :=
        Syscall.run_write which (by show (E1 (slot + 3)).toNat ≤ _; rw [e1c, cnat]; exact cmax)
          (by show (E1 slot).toNat + (E1 (slot + 3)).toNat ≤ _; rw [e1c, e1p, cnat]; omega)
      let E2 := E1.set (slot + 4) (E1 (slot + 3))
      let E3 := E2.set slot ((Expr.binary .u64 .add (.var slot) (.var (slot + 3))).eval E2)
      let E4 := E3.set (slot + 1) ((Expr.binary .u64 .sub (.var (slot + 1)) (.var (slot + 3))).eval E3)
      have body : Exec mp d E H (writeBody fd slot) (.normal E4 H1) :=
        .seq picked (.seq (.sys ran) (.seq .assign .assign))
      have e4p : (E4 slot).toNat = (E slot).toNat + c := by
        have : E4 slot = E slot + cbits := by simp [E4, E3, E2, E1, set_get, Expr.eval, Word.apply, BinOp.apply]
        rw [this, BitVec.toNat_add, cnat, Nat.mod_eq_of_lt (by omega)]
      have e4n : (E4 (slot + 1)).toNat = n - c := by
        have : E4 (slot + 1) = E (slot + 1) - cbits := by
          simp [E4, E3, E2, E1, set_get, Expr.eval, Word.apply, BinOp.apply]
        rw [this, BitVec.toNat_sub_of_le (by rw [BitVec.le_def, cnat, count]; exact cle), cnat, count]
      obtain ⟨E', events, loop, keep, outs⟩ := ih (n - c) (by omega) E4 H1 e4n
        (fun _ => by rw [e4p]; simp only [H1]; omega) small topped
      refine ⟨E', Event.write fd.toNat (H.slice (E slot).toNat c) :: events, ?_, ?_, ?_⟩
      · have : ({ H1 with io := { H1.io with trace := H1.io.trace ++ events } } : Heap) =
            { H with io := { H.io with trace := H.io.trace ++ Event.write fd.toNat (H.slice (E slot).toNat c) :: events } } := by
          simp [H1, e1p, e1c, cnat]
        rw [← this]
        exact .loopNext going body loop
      · intro j which'
        rw [keep j which']
        simp only [E4, E3, E2, E1, set_get]
        rcases which' with lt | eq
        · rw [if_neg (by omega), if_neg (by omega), if_neg (by omega), if_neg (by omega)]
        · subst eq
          rw [if_neg (by omega), if_neg (by omega), if_neg (by omega), if_neg (by omega)]
      · intro k
        have first : outputOf k [Event.write fd.toNat (H.slice (E slot).toNat c)] =
            if fd.toNat = k then H.slice (E slot).toNat c else [] := outputOf_write _ _ _
        rw [show (Event.write fd.toNat (H.slice (E slot).toNat c) :: events) =
          [Event.write fd.toNat (H.slice (E slot).toNat c)] ++ events from rfl, outputOf_append, first, outs k, e4p]
        have whole := H.slice_append (E slot).toNat c (n - c)
        rw [Nat.add_sub_cancel' cle] at whole
        by_cases same : fd.toNat = k
        · simp only [same, if_true, H1, Heap.slice_io]
          exact whole
        · simp [same]

/-- `write_stdout` / `write_stderr` to `fd`: the events write the `count`
bytes from the pointer, and `slot` holds the count as `i32`. -/
theorem hostWrite_exec {mp : Program} {d : Nat} (fd : BitVec 64) (which : fd = 1 ∨ fd = 2) {E : Env} {H : Heap}
    (slot : Nat) (inside : 0 < (E (slot + 1)).toNat → (E slot).toNat + (E (slot + 1)).toNat ≤ H.limit)
    (small : H.limit < 2 ^ 62) (topped : H.limit ≤ H.top) :
    ∃ E' events, Exec mp d E H (hostWriteCode fd slot) (.normal E' { H with io := { H.io with trace := H.io.trace ++ events } }) ∧
      (∀ j < slot, E' j = E j) ∧ E' slot = widen (low (E (slot + 1))) ∧
      ∀ k, outputOf k events = if fd.toNat = k then H.slice (E slot).toNat (E (slot + 1)).toNat else [] := by
  let E0 := E.set (slot + 2) ((Expr.var (slot + 1)).eval E)
  have e0p : E0 slot = E slot := by simp [E0, set_get]
  have e0n : E0 (slot + 1) = E (slot + 1) := by simp [E0, set_get]
  obtain ⟨E', events, loop, keep, outs⟩ := writeLoop (mp := mp) (d := d) fd which slot (E (slot + 1)).toNat E0 H
    (by rw [e0n]) (by rw [e0p]; exact inside) small topped
  refine ⟨E'.set slot ((Expr.binary .s32 .add (.var (slot + 2)) (.lit 0)).eval E'), events, ?_, ?_, ?_, ?_⟩
  · rw [hostWriteCode_eq]
    exact .seq (.assign (env := E)) (.seq loop .assign)
  · intro j lt
    simp only [set_get]
    rw [if_neg (by omega), keep j (.inl lt)]
    simp only [E0, set_get]
    rw [if_neg (by omega)]
  · simp only [set_get, if_true, Expr.eval]
    rw [keep (slot + 2) (.inr rfl)]
    simp [E0, set_get, Word.apply, BinOp.apply, Expr.eval]
  · intro k
    rw [outs k, e0p]

/-! ## The code of `read_stdin` -/

/-- The heap after reading `n` bytes, or all that are left, of its input to
offset `p`. -/
def readHeap (H : Heap) (p n : Nat) : Heap :=
  { H.writeAll p (H.io.input.take n) with io := { H.io with input := H.io.input.drop n } }

theorem getD_append_left' (xs ys : List UInt8) (i : Nat) (h : i < xs.length) :
    (xs ++ ys).getD i 0 = xs.getD i 0 := by
  simp only [List.getD_eq_getElem?_getD, List.getElem?_append_left h]

theorem getD_append_right' (xs ys : List UInt8) (i : Nat) (h : xs.length ≤ i) :
    (xs ++ ys).getD i 0 = ys.getD (i - xs.length) 0 := by
  simp only [List.getD_eq_getElem?_getD, List.getElem?_append_right h]

theorem Heap.writeAll_append (H : Heap) (a : Nat) (xs ys : List UInt8) :
    (H.writeAll a xs).writeAll (a + xs.length) ys = H.writeAll a (xs ++ ys) := by
  simp only [Heap.writeAll]
  congr 1
  funext o
  by_cases lo : a ≤ o
  · by_cases inX : o - a < xs.length
    · rw [if_neg (by omega), if_pos ⟨lo, inX⟩, if_pos ⟨lo, by simp; omega⟩, getD_append_left' xs ys _ inX]
    · by_cases inY : o - (a + xs.length) < ys.length
      · rw [if_pos ⟨by omega, inY⟩, if_pos ⟨lo, by simp; omega⟩, getD_append_right' xs ys _ (by omega)]
        congr 1
        omega
      · rw [if_neg (by omega), if_neg (by omega), if_neg (by simp; omega)]
  · rw [if_neg (by omega), if_neg (by omega), if_neg (by omega)]

theorem Heap.write_writeAll (H : Heap) (a : Nat) (b : UInt8) (rest : List UInt8) :
    (H.write a b).writeAll (a + 1) rest = H.writeAll a (b :: rest) := by
  simp only [Heap.writeAll, Heap.write]
  congr 1
  funext o
  by_cases lo : a ≤ o
  · by_cases at_ : o = a
    · subst at_
      rw [if_neg (by omega), if_pos rfl, if_pos ⟨lo, by simp⟩]
      simp
    · by_cases inR : o - (a + 1) < rest.length
      · rw [if_pos ⟨by omega, inR⟩, if_pos ⟨lo, by simp; omega⟩,
          show o - a = (o - (a + 1)) + 1 by omega, List.getD_cons_succ]
      · rw [if_neg (by omega), if_neg at_, if_neg (by simp; omega)]
  · rw [if_neg (by omega), if_neg (by omega), if_neg (by omega)]

/-- A full read of `c` bytes, then of the next `n - c`, is a read of `n`. -/
theorem readHeap_split (H : Heap) (p : Nat) {c n : Nat} (le : c ≤ n) (full : (H.io.input.take c).length = c) :
    readHeap (readHeap H p c) (p + c) (n - c) = readHeap H p n := by
  simp only [readHeap]
  have whole : H.io.input.take c ++ (H.io.input.drop c).take (n - c) = H.io.input.take n := by
    rw [← List.take_add, Nat.add_sub_cancel' le]
  have bytes := Heap.writeAll_append H p (H.io.input.take c) ((H.io.input.drop c).take (n - c))
  rw [full, whole] at bytes
  rw [show ({ H.writeAll p (H.io.input.take c) with io := { H.io with input := H.io.input.drop c } } : Heap).writeAll
      (p + c) ((H.io.input.drop c).take (n - c)) =
    { (H.writeAll p (H.io.input.take c)).writeAll (p + c) ((H.io.input.drop c).take (n - c)) with
      io := { H.io with input := H.io.input.drop c } } from rfl, bytes, List.drop_drop, Nat.add_sub_cancel' le]

/-- A short read of `c` bytes used the input up: it is a read of any `n` past it. -/
theorem readHeap_short (H : Heap) (p : Nat) {c n : Nat} (le : c ≤ n) (short : (H.io.input.take c).length < c) :
    readHeap H p c = readHeap H p n := by
  have len : H.io.input.length < c := by simp at short; omega
  simp only [readHeap, List.take_of_length_le (Nat.le_of_lt len), List.take_of_length_le (by omega : H.io.input.length ≤ n),
    List.drop_eq_nil_of_le (Nat.le_of_lt len), List.drop_eq_nil_of_le (by omega : H.io.input.length ≤ n)]

/-- `Syscall.read` from fd 0 within its bounds. -/
theorem Syscall.run_read {heap : Heap} {address count : BitVec 64} (small : count.toNat ≤ maxTransfer)
    (inside : heap.io.input.take count.toNat = [] ∨
      address.toNat + (heap.io.input.take count.toNat).length ≤ heap.limit) :
    Syscall.run .read [0, address, count] heap =
      some (BitVec.ofNat 64 (heap.io.input.take count.toNat).length, readHeap heap address.toNat count.toNat) := by
  rw [Syscall.run, if_pos ⟨rfl, small, inside.imp id fun h => Nat.le_trans h heap.limit_le_top⟩]
  rfl

/-- One turn: a chunk of at most `maxTransfer` bytes asked for, read, the
pointer, count and total moved past what came, and the count zeroed when
fewer came than were asked for. -/
def readBody (slot : Nat) : Stmt :=
  .seq (.ite (.compare .u64 .lt (.var (slot + 1)) (.lit 2147479552)) (.assign (slot + 3) (.var (slot + 1)))
      (.assign (slot + 3) (.lit 2147479552)))
    (.seq (.sys .read (slot + 4) [.lit 0, .var slot, .var (slot + 3)])
      (.seq (.assign slot (.binary .u64 .add (.var slot) (.var (slot + 4))))
        (.seq (.assign (slot + 1) (.binary .u64 .sub (.var (slot + 1)) (.var (slot + 4))))
          (.seq (.assign (slot + 2) (.binary .u64 .add (.var (slot + 2)) (.var (slot + 4))))
            (.ite (.compare .u64 .ne (.var (slot + 4)) (.var (slot + 3))) (.assign (slot + 1) (.lit 0)) .skip)))))

theorem hostReadCode_eq (slot : Nat) :
    hostReadCode slot = .seq (.assign (slot + 2) (.lit 0))
      (.seq (.loop (writeCond slot) (readBody slot))
        (.assign slot (.binary .s32 .add (.var (slot + 2)) (.lit 0)))) := rfl

/-- The loop reads the next `count` bytes of the input, or all that are left,
to the pointer, adds how many to the total, and keeps the slots below `slot`. -/
theorem readLoop {mp : Program} {d : Nat} (slot : Nat) :
    ∀ (n : Nat) (E : Env) (H : Heap), (E (slot + 1)).toNat = n →
      (H.io.input.take n = [] ∨ (E slot).toNat + (H.io.input.take n).length ≤ H.limit) → H.limit < 2 ^ 62 →
      (E (slot + 2)).toNat + n < 2 ^ 64 →
      ∃ E', Exec mp d E H (.loop (writeCond slot) (readBody slot)) (.normal E' (readHeap H (E slot).toNat n)) ∧
        (∀ j < slot, E' j = E j) ∧
        (E' (slot + 2)).toNat = (E (slot + 2)).toNat + (H.io.input.take n).length := by
  intro n
  induction n using Nat.strongRecOn with
  | ind n ih =>
    intro E H count inside small total
    rcases Nat.eq_zero_or_pos n with zero | pos
    · subst zero
      have done : (writeCond slot).eval E = 0 := by
        have : E (slot + 1) = 0 := BitVec.eq_of_toNat_eq (by simpa using count)
        simp [writeCond, Expr.eval, Word.holds, CmpOp.holdsU, this]
      refine ⟨E, ?_, fun _ _ => rfl, by simp⟩
      have same : readHeap H (E slot).toNat 0 = H := by
        simp only [readHeap, List.take_zero, List.drop_zero, Heap.writeAll]
        cases H
        simp
      rw [same]
      exact .loopDone done
    · have going : (writeCond slot).eval E ≠ 0 := by
        have : E (slot + 1) ≠ 0 := fun h => by rw [h] at count; simp at count; omega
        simpa [writeCond, Expr.eval, Word.holds, CmpOp.holdsU] using this
      -- the chunk: the count, or `maxTransfer` when more are left
      obtain ⟨cbits, c, picked, cnat, cpos, cle, cmax⟩ : ∃ (cbits : BitVec 64) (c : Nat),
          Exec mp d E H (.ite (.compare .u64 .lt (.var (slot + 1)) (.lit 2147479552))
            (.assign (slot + 3) (.var (slot + 1))) (.assign (slot + 3) (.lit 2147479552)))
            (.normal (E.set (slot + 3) cbits) H) ∧ cbits.toNat = c ∧ 0 < c ∧ c ≤ n ∧ c ≤ maxTransfer := by
        by_cases lt : (E (slot + 1)).toNat < maxTransfer
        · exact ⟨E (slot + 1), n, .ifTrue ((eval_pick E slot).mpr lt) .assign, count, pos, Nat.le_refl _,
            by omega⟩
        · refine ⟨2147479552, maxTransfer, .ifFalse ?_ .assign, by simp [maxTransfer], by simp [maxTransfer],
            by omega, Nat.le_refl _⟩
          exact Classical.byContradiction fun h => lt ((eval_pick E slot).mp h)
      obtain ⟨g, gdef⟩ : ∃ g, (H.io.input.take c).length = g := ⟨_, rfl⟩
      have gmin : g = min c H.io.input.length := by rw [← gdef, List.length_take]
      have nmin : (H.io.input.take n).length = min n H.io.input.length := List.length_take
      have gle : g ≤ c := by omega
      have emptyAll : H.io.input.take n = [] → H.io.input = [] := fun empty => by
        rcases List.take_eq_nil_iff.mp empty with z | e
        · exact absurd z (by omega)
        · exact e
      have fitC : H.io.input.take c = [] ∨ (E slot).toNat + g ≤ H.limit := by
        rcases inside with empty | fit
        · left
          rw [emptyAll empty]
          simp
        · right
          omega
      have pg : (E slot).toNat + g < 2 ^ 64 := by
        rcases fitC with empty | fit
        · have : g = 0 := by rw [← gdef, empty]; rfl
          have := (E slot).isLt
          omega
        · omega
      let E1 := E.set (slot + 3) cbits
      have e1p : E1 slot = E slot := by simp [E1, set_get]
      have e1c : E1 (slot + 3) = cbits := by simp [E1, set_get]
      let gbits : BitVec 64 := BitVec.ofNat 64 g
      have gnat : gbits.toNat = g := by
        simp only [gbits, BitVec.toNat_ofNat]
        exact Nat.mod_eq_of_lt (by simp [maxTransfer] at cmax; omega)
      let H1 := readHeap H (E slot).toNat c
      have ran : Syscall.run .read (Expr.evalAll E1 [.lit 0, .var slot, .var (slot + 3)]) H = some (gbits, H1) := by
        have := Syscall.run_read (heap := H) (address := E1 slot) (count := E1 (slot + 3))
          (by rw [e1c, cnat]; exact cmax) (by rw [e1c, cnat, e1p, gdef]; exact fitC)
        show Syscall.run .read [0, E1 slot, E1 (slot + 3)] H = _
        rw [this, e1c, cnat, e1p, gdef]
      let E2 := E1.set (slot + 4) gbits
      let E3 := E2.set slot ((Expr.binary .u64 .add (.var slot) (.var (slot + 4))).eval E2)
      let E4 := E3.set (slot + 1) ((Expr.binary .u64 .sub (.var (slot + 1)) (.var (slot + 4))).eval E3)
      let E5 := E4.set (slot + 2) ((Expr.binary .u64 .add (.var (slot + 2)) (.var (slot + 4))).eval E4)
      have e5p : (E5 slot).toNat = (E slot).toNat + g := by
        have : E5 slot = E slot + gbits := by simp [E5, E4, E3, E2, E1, set_get, Expr.eval, Word.apply, BinOp.apply]
        rw [this, BitVec.toNat_add, gnat, Nat.mod_eq_of_lt pg]
      have e5n : (E5 (slot + 1)).toNat = n - g := by
        have : E5 (slot + 1) = E (slot + 1) - gbits := by
          simp [E5, E4, E3, E2, E1, set_get, Expr.eval, Word.apply, BinOp.apply]
        rw [this, BitVec.toNat_sub_of_le (by rw [BitVec.le_def, gnat, count]; omega), gnat, count]
      have e5t : (E5 (slot + 2)).toNat = (E (slot + 2)).toNat + g := by
        have : E5 (slot + 2) = E (slot + 2) + gbits := by
          simp [E5, E4, E3, E2, E1, set_get, Expr.eval, Word.apply, BinOp.apply]
        rw [this, BitVec.toNat_add, gnat, Nat.mod_eq_of_lt (by omega)]
      have e5g : E5 (slot + 4) = gbits := by simp [E5, E4, E3, E2, set_get]
      have e5c : E5 (slot + 3) = cbits := by simp [E5, E4, E3, E2, E1, set_get]
      have e5keep : ∀ j < slot, E5 j = E j := by
        intro j lt
        simp only [E5, E4, E3, E2, E1, set_get]
        rw [if_neg (by omega), if_neg (by omega), if_neg (by omega), if_neg (by omega), if_neg (by omega)]
      have stopEval : (Expr.compare .u64 .ne (.var (slot + 4)) (.var (slot + 3))).eval E5 ≠ 0 ↔ g ≠ c := by
        rw [show (Expr.compare .u64 .ne (.var (slot + 4)) (.var (slot + 3))).eval E5 =
          (if Word.holds .u64 .ne (E5 (slot + 4)) (E5 (slot + 3)) then 1 else 0) from rfl, e5g, e5c]
        constructor
        · intro h same
          apply h
          have : gbits = cbits := BitVec.eq_of_toNat_eq (by rw [gnat, cnat, same])
          simp [Word.holds, CmpOp.holdsU, this]
        · intro h
          have : gbits ≠ cbits := fun e => h (by rw [← gnat, ← cnat, e])
          simp [Word.holds, CmpOp.holdsU, this]
      by_cases full : g = c
      · -- a full chunk: go on with the rest
        have stay : Exec mp d E5 H1 (.ite (.compare .u64 .ne (.var (slot + 4)) (.var (slot + 3)))
            (.assign (slot + 1) (.lit 0)) .skip) (.normal E5 H1) :=
          .ifFalse (Classical.byContradiction fun h => (stopEval.mp h) full) .skip
        have body : Exec mp d E H (readBody slot) (.normal E5 H1) :=
          .seq picked (.seq (.sys ran) (.seq .assign (.seq .assign (.seq .assign stay))))
        have h1in : H1.io.input = H.io.input.drop c := rfl
        have h1lim : H1.limit = H.limit := rfl
        obtain ⟨E', loop, keep, tot⟩ := ih (n - c) (by omega) E5 H1 (by rw [e5n, full])
          (by
            rw [e5p, h1in, h1lim]
            rcases inside with empty | fit
            · left
              rw [emptyAll empty]
              simp
            · right
              simp only [List.length_take, List.length_drop]
              omega)
          small (by rw [e5t, full]; omega)
        refine ⟨E', ?_, fun j lt => (keep j lt).trans (e5keep j lt), ?_⟩
        · have split := readHeap_split H (E slot).toNat cle (by rw [gdef, full])
          rw [← split]
          have at5 : (E5 slot).toNat = (E slot).toNat + c := by rw [e5p, full]
          rw [at5] at loop
          exact .loopNext going body loop
        · rw [tot, e5t, h1in]
          simp only [List.length_take, List.length_drop]
          omega
      · -- a short chunk: the input is used up, and the loop ends
        have short : g < c := by omega
        let E6 := E5.set (slot + 1) ((Expr.lit 0).eval E5)
        have stop : Exec mp d E5 H1 (.ite (.compare .u64 .ne (.var (slot + 4)) (.var (slot + 3)))
            (.assign (slot + 1) (.lit 0)) .skip) (.normal E6 H1) :=
          .ifTrue (stopEval.mpr full) .assign
        have body : Exec mp d E H (readBody slot) (.normal E6 H1) :=
          .seq picked (.seq (.sys ran) (.seq .assign (.seq .assign (.seq .assign stop))))
        have ended : (writeCond slot).eval E6 = 0 := by
          simp [writeCond, E6, set_get, Expr.eval, Word.holds, CmpOp.holdsU]
        refine ⟨E6, ?_, fun j lt => ?_, ?_⟩
        · rw [← readHeap_short H (E slot).toNat cle (by rw [gdef]; exact short)]
          exact .loopNext going body (.loopDone ended)
        · simp only [E6, set_get]
          rw [if_neg (by omega)]
          exact e5keep j lt
        · have : E6 (slot + 2) = E5 (slot + 2) := by simp [E6, set_get]
          rw [this, e5t, nmin]
          omega

/-- `read_stdin`: the next `count` bytes of the input, or all that are left,
stored from the pointer, and how many as `i32` in `slot`. -/
theorem hostRead_exec {mp : Program} {d : Nat} {E : Env} {H : Heap} (slot : Nat)
    (inside : H.io.input.take (E (slot + 1)).toNat = [] ∨
      (E slot).toNat + (H.io.input.take (E (slot + 1)).toNat).length ≤ H.limit)
    (small : H.limit < 2 ^ 62) :
    ∃ E', Exec mp d E H (hostReadCode slot) (.normal E' (readHeap H (E slot).toNat (E (slot + 1)).toNat)) ∧
      (∀ j < slot, E' j = E j) ∧
      E' slot = widen (BitVec.ofNat 32 (H.io.input.take (E (slot + 1)).toNat).length) := by
  let E0 := E.set (slot + 2) ((Expr.lit 0).eval E)
  have e0p : E0 slot = E slot := by simp [E0, set_get]
  have e0n : E0 (slot + 1) = E (slot + 1) := by simp [E0, set_get]
  have e0t : (E0 (slot + 2)).toNat = 0 := by simp [E0, set_get, Expr.eval]
  obtain ⟨E', loop, keep, tot⟩ := readLoop (mp := mp) (d := d) slot (E (slot + 1)).toNat E0 H
    (by rw [e0n]) (by rw [e0p]; exact inside) small (by rw [e0t]; have := (E (slot + 1)).isLt; omega)
  rw [e0p] at loop
  refine ⟨E'.set slot ((Expr.binary .s32 .add (.var (slot + 2)) (.lit 0)).eval E'), ?_, ?_, ?_⟩
  · rw [hostReadCode_eq]
    exact .seq (.assign (env := E)) (.seq loop .assign)
  · intro j lt
    simp only [set_get]
    rw [if_neg (by omega), keep j lt]
    simp only [E0, set_get]
    rw [if_neg (by omega)]
  · rw [e0t, Nat.zero_add] at tot
    have low_eq : low (E' (slot + 2)) = BitVec.ofNat 32 (H.io.input.take (E (slot + 1)).toNat).length := by
      apply BitVec.eq_of_toNat_eq
      simp only [low, BitVec.toNat_setWidth, BitVec.toNat_ofNat, tot]
    simp only [set_get, if_true]
    rw [← low_eq]
    simp [Expr.eval, Word.apply, BinOp.apply]

/-- The byte-by-byte write is the whole-run write. -/
theorem Heap.writeBytes_eq_writeAll : ∀ (hp : Heap) (a : Nat) (bytes : List UInt8),
    hp.writeBytes a bytes = hp.writeAll a bytes
  | hp, a, [] => by
    simp only [Heap.writeBytes, Heap.writeAll, List.length_nil]
    cases hp
    simp
  | hp, a, b :: rest => by
    rw [Heap.writeBytes, Heap.writeBytes_eq_writeAll _ (a + 1) rest, Heap.write_writeAll]

/-- Core's store of a run of bytes is the mini heap's `writeAll` there, below
Core's cursor. -/
theorem HeapCorr.storeBytesAll {h : Memory.Heap} {w : World.State} {hp : Heap} (corr : HeapCorr h w hp)
    {p : Nat} {bytes : List UInt8} {h' : Memory.Heap} (ok : h.storeBytes p bytes = .ok h') :
    HeapCorr h' w (hp.writeAll p bytes) ∧ (bytes ≠ [] → p + bytes.length ≤ h.nextAddress) := by
  have := HeapCorr.storeBytesFrom bytes 0 corr ok
  rwa [Nat.add_zero, Heap.writeBytes_eq_writeAll] at this

end Lanius.Mini
