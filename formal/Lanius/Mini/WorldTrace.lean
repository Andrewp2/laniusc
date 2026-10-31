import Lanius.World
import Lanius.X86.Machine.Io
import Lanius.Mini.HeapCorr

/-! Core's host world and the process's write trace (roadmap F8).

Core keeps what a program wrote as two byte lists in its world,
`standardOutput` and `standardError`; the x86 model and the mini IR keep one
trace of `write` events (`Lanius.X86.Machine.Io`). `WorldOut w₀ w io` says
that the world `w` is `w₀` with exactly the trace's writes to fd 1 appended
to its standard output and its writes to fd 2 to its standard error.

These are Core's host specifications for the output services the verified
compiler lowers to `Syscall.write`: `write_byte` to handle 1 or 2 returns 1
and appends its byte (`callSimple_writeByte`), and `write_stdout` /
`write_stderr` return the length and append the bytes they load
(`call_writeStdout`, `call_writeStderr`); each such call, matched by one
`write` event with the same bytes, keeps `WorldOut` (`writeBytes_out`,
`worldOut_write`). On the mini side, the bytes Core loads are the mini
heap's slice (`HeapCorr.loadBytes_slice`), and `Syscall.write` appends that
slice as one event (`Syscall.run_write`). -/

namespace Lanius.Mini

open Lanius.X86.Machine (Event Io)
open Lanius.World
open Lanius.Core (Value HostService)

/-- The bytes a trace wrote to `fd`, in order. -/
def outputOf (fd : Nat) : List Event → List UInt8
  | [] => []
  | .write target bytes :: rest =>
      (if target = fd then bytes else []) ++ outputOf fd rest

theorem outputOf_append (fd : Nat) (first second : List Event) :
    outputOf fd (first ++ second) = outputOf fd first ++ outputOf fd second := by
  induction first with
  | nil => rfl
  | cons event rest ih =>
      cases event with
      | write target bytes =>
          simp only [List.cons_append, outputOf, ih, List.append_assoc]

theorem outputOf_write (fd target : Nat) (bytes : List UInt8) :
    outputOf fd [.write target bytes] = if target = fd then bytes else [] := by
  simp only [outputOf, List.append_nil]

/-- The world `w` is `w₀` with the trace's output appended. -/
structure WorldOut (w₀ w : State) (io : Io) : Prop where
  out : w.standardOutput = w₀.standardOutput ++ outputOf 1 io.trace
  err : w.standardError = w₀.standardError ++ outputOf 2 io.trace

theorem worldOut_start (w : State) : WorldOut w w {} :=
  ⟨by simp [outputOf], by simp [outputOf]⟩

/-- A world change that appends `bytes` to the output of `fd` keeps
`WorldOut` when the trace gains `.write fd bytes`. -/
theorem worldOut_write {w₀ w w' : State} {io : Io} {fd : Nat} {bytes : List UInt8}
    (corr : WorldOut w₀ w io) (which : fd = 1 ∨ fd = 2)
    (out : w'.standardOutput = w.standardOutput ++ (if fd = 1 then bytes else []))
    (err : w'.standardError = w.standardError ++ (if fd = 2 then bytes else [])) :
    WorldOut w₀ w' { io with trace := io.trace ++ [.write fd bytes] } := by
  refine ⟨?_, ?_⟩
  · simp only [out, corr.out, outputOf_append, outputOf_write, List.append_assoc]
  · simp only [err, corr.err, outputOf_append, outputOf_write, List.append_assoc]

/-- The record of host calls does not touch the output. -/
theorem worldOut_record {w₀ w : State} {io : Io} (service : HostService)
    (corr : WorldOut w₀ w io) : WorldOut w₀ (record w service) io :=
  ⟨corr.out, corr.err⟩

/-- Core's `writeBytes` to handle 1 or 2 always succeeds and keeps
`WorldOut` with one `write` event of the same bytes. -/
theorem writeBytes_out {w₀ w : State} {io : Io} {handle : Int} {bytes : List UInt8}
    (corr : WorldOut w₀ w io) (which : handle = 1 ∨ handle = 2) :
    ∃ w', writeBytes w handle bytes = some w' ∧
      WorldOut w₀ w' { io with trace := io.trace ++ [.write handle.toNat bytes] } := by
  rcases which with one | two
  · subst one
    exact ⟨{ w with standardOutput := w.standardOutput ++ bytes }, rfl,
      worldOut_write corr (Or.inl rfl) (by simp) (by simp)⟩
  · subst two
    exact ⟨{ w with standardError := w.standardError ++ bytes }, by simp [writeBytes],
      worldOut_write corr (Or.inr rfl) (by simp) (by simp)⟩

/-- The byte `write_byte` writes for an `i32` value: its low byte. -/
def hostByte (value : Int) : UInt8 := UInt8.ofNat (Int.toNat (value % 256))

/-- Core's host specification of `write_byte(handle, value)` for handle 1
or 2: it returns `1` and its world has one more `write` event, the low byte
of `value`. -/
theorem callSimple_writeByte {w₀ w : State} {io : Io} {handle value : Int}
    (corr : WorldOut w₀ w io) (which : handle = 1 ∨ handle = 2) :
    ∃ w', callSimple w .writeByte [.signed .i32 handle, .signed .i32 value] =
        .returned (i32Result 1) w' ∧
      WorldOut w₀ w' { io with trace := io.trace ++ [.write handle.toNat [hostByte value]] } := by
  obtain ⟨w', written, out⟩ :=
    writeBytes_out (bytes := [hostByte value]) (worldOut_record .writeByte corr) which
  refine ⟨w', ?_, out⟩
  simp only [callSimple]
  unfold hostByte at written
  rw [written]

/-- Core's host specification of `write_stdout(pointer, length)` when the
bytes load: it returns their count and appends them to standard output. -/
theorem call_writeStdout {w₀ w : State} {io : Io} {heap : Lanius.Memory.Heap}
    {pointer length : Nat} {bytes : List UInt8}
    (corr : WorldOut w₀ w io) (loads : heap.loadBytes pointer length = .ok bytes) :
    ∃ w', call heap w .writeStdout [.pointer pointer, .unsigned .usize length] =
        .returned (i32Result bytes.length) heap w' ∧
      WorldOut w₀ w' { io with trace := io.trace ++ [.write 1 bytes] } := by
  refine ⟨{ record w .writeStdout with
      standardOutput := (record w .writeStdout).standardOutput ++ bytes }, ?_,
    worldOut_write (worldOut_record .writeStdout corr) (Or.inl rfl) (by simp) (by simp)⟩
  simp [call, callSimple, loads]

/-- The same for `write_stderr` and standard error. -/
theorem call_writeStderr {w₀ w : State} {io : Io} {heap : Lanius.Memory.Heap}
    {pointer length : Nat} {bytes : List UInt8}
    (corr : WorldOut w₀ w io) (loads : heap.loadBytes pointer length = .ok bytes) :
    ∃ w', call heap w .writeStderr [.pointer pointer, .unsigned .usize length] =
        .returned (i32Result bytes.length) heap w' ∧
      WorldOut w₀ w' { io with trace := io.trace ++ [.write 2 bytes] } := by
  refine ⟨{ record w .writeStderr with
      standardError := (record w .writeStderr).standardError ++ bytes }, ?_,
    worldOut_write (worldOut_record .writeStderr corr) (Or.inr rfl) (by simp) (by simp)⟩
  simp [call, callSimple, loads]

/-- The bytes Core loads from a range are the mini heap's bytes there, below
Core's cursor. -/
theorem HeapCorr.loadBytesFrom_slice {h : Memory.Heap} {hp : Heap} (corr : HeapCorr h hp) {p : Nat} :
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

theorem HeapCorr.loadBytes_slice {h : Memory.Heap} {hp : Heap} (corr : HeapCorr h hp)
    {p count : Nat} {bytes : List UInt8} (ok : h.loadBytes p count = .ok bytes) :
    bytes = hp.slice p count ∧ (0 < count → p + count ≤ h.nextAddress) :=
  corr.loadBytesFrom_slice count 0 ok

/-- `Syscall.write` within its bounds returns the count and appends the
heap's slice to the trace. -/
theorem Syscall.run_write {heap : Heap} {fd address count : BitVec 64}
    (which : fd = 1 ∨ fd = 2) (small : count.toNat ≤ Lanius.X86.Machine.maxTransfer)
    (inside : address.toNat + count.toNat ≤ heap.limit) :
    Syscall.run .write [fd, address, count] heap =
      some (count, { heap with io := { heap.io with trace := heap.io.trace ++
        [.write fd.toNat (heap.slice address.toNat count.toNat)] } }) := by
  rw [Syscall.run, if_pos ⟨which, small, inside⟩]

end Lanius.Mini
