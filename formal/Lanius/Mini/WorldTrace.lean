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
    (err : w'.standardError = outputOf 2 hp'.io.trace) (closed : w'.fileHandles = []) : HeapCorr h w' hp' := by
  obtain ⟨c, pos, unb, small, sized, below, apart, unique, bs, zero, -, -, -⟩ := corr
  refine ⟨cursor.trans c, pos, unb, limit ▸ small, sized, below, apart, unique, ?_, ?_, out, err, closed⟩
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
    (closed : w'.fileHandles = w.fileHandles) : HeapCorr h w' hp' :=
  corr.retrace sameBytes cursor limit (by simp only [out, corr.out, trace, outputOf_append, outs])
    (by simp only [err, corr.err, trace, outputOf_append, outs]) (closed.trans corr.closed)

/-- The record of host calls does not touch the output or the files. -/
theorem HeapCorr.record {h : Memory.Heap} {w : World.State} {hp : Heap} (corr : HeapCorr h w hp)
    (service : Core.HostService) : HeapCorr h (World.record w service) hp :=
  corr.retrace rfl rfl rfl corr.out corr.err corr.closed

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
      H'.io.trace = H.io.trace ++ [Event.write (E slot).toNat [lowByte (E (slot + 1))]] := by
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
    rfl, rfl, rfl, ?_⟩
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
          (.normal E' { H with io := { trace := H.io.trace ++ events } }) ∧
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
      · have : ({ H1 with io := { trace := H1.io.trace ++ events } } : Heap) =
            { H with io := { trace := H.io.trace ++ Event.write fd.toNat (H.slice (E slot).toNat c) :: events } } := by
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
    ∃ E' events, Exec mp d E H (hostWriteCode fd slot) (.normal E' { H with io := { trace := H.io.trace ++ events } }) ∧
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

end Lanius.Mini
