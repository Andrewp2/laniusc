module

public import Lanius.Files

@[expose] public section

namespace Lanius.X86.Machine

/-- One thing a process did to or saw of its environment through the kernel
(roadmap F8; what each `syscall` does is trusted, TRUSTED_BASE.md section 8). -/
inductive Event where
  /-- `write(fd, buffer, count)` wrote these bytes to `fd`. -/
  | write (fd : Nat) (bytes : List UInt8)
deriving DecidableEq, Repr

/-- The process's side of its environment: the trace of events so far, and
what the kernel has still to deliver, streams fixed when the process starts
(TRUSTED_BASE.md section 8): the bytes of standard input, the readings
(seconds, nanoseconds) of the monotonic and the real-time clock, the secure
random bytes, and how many bytes each read of standard input delivers. -/
structure Io where
  trace : List Event := []
  input : List UInt8 := []
  monotonic : List (Int × Nat) := []
  realtime : List (Int × Nat) := []
  entropy : List UInt8 := []
  /-- The most bytes each `read` delivers, less one, in turn: a pipe or a
  terminal may deliver fewer bytes than were asked for, but at least one while
  any are left. A read past the end of the list delivers all it asks for. -/
  readLimits : List Nat := []
  /-- The files and directories under the current directory and the open
  descriptors besides the standard streams (`Lanius.Files`, Core's world's
  model too). -/
  files : Lanius.Files.System := {}
deriving Repr

/-- How many bytes of the input the next `read` asking for `count` takes: the
count, or the next limit plus one when that is smaller. -/
def Io.readCap (io : Io) (count : Nat) : Nat :=
  match io.readLimits with
  | [] => count
  | limit :: _ => min count (limit + 1)

/-- The bytes the next `read` asking for `count` delivers. -/
def Io.readBytes (io : Io) (count : Nat) : List UInt8 :=
  io.input.take (io.readCap count)

/-- `io` after a `read` asking for `count`: its bytes taken, and its limit. -/
def Io.afterRead (io : Io) (count : Nat) : Io :=
  { io with input := io.input.drop (io.readCap count), readLimits := io.readLimits.tail }

theorem Io.readCap_le (io : Io) (count : Nat) : io.readCap count ≤ count := by
  unfold Io.readCap
  split <;> omega

theorem Io.readCap_pos (io : Io) {count : Nat} (pos : 0 < count) : 0 < io.readCap count := by
  unfold Io.readCap
  split <;> omega

/-- A read delivers at most what it asks for, and none only when it asks for
none or the input is used up. -/
theorem Io.readBytes_length (io : Io) (count : Nat) :
    (io.readBytes count).length ≤ count ∧ (io.readBytes count).length ≤ io.input.length ∧
      ((io.readBytes count).length = 0 → count = 0 ∨ io.input = []) := by
  have le := io.readCap_le count
  have pos : 0 < count → 0 < io.readCap count := io.readCap_pos
  simp only [Io.readBytes, List.length_take]
  refine ⟨by omega, by omega, fun zero => ?_⟩
  rcases Nat.eq_zero_or_pos count with z | p
  · exact .inl z
  · exact .inr (List.length_eq_zero_iff.mp (by have := pos p; omega))

/-- Every length a read may deliver, from one to what it asks for or what is
left, is the length some schedule of limits delivers. -/
theorem Io.readBytes_any (io : Io) {count k : Nat} (pos : 0 < k) (le : k ≤ count) (left : k ≤ io.input.length)
    (rest : List Nat) : ({ io with readLimits := (k - 1) :: rest }.readBytes count).length = k := by
  simp only [Io.readBytes, Io.readCap, List.length_take]
  omega

/-- The readings left of the clock `clock_gettime` names: `CLOCK_MONOTONIC`
(1) or, for any other, `CLOCK_REALTIME` (0). -/
def Io.readings (io : Io) (clock : BitVec 64) : List (Int × Nat) :=
  if clock = 1 then io.monotonic else io.realtime

/-- `io` with the clock's next reading taken. -/
def Io.afterReading (io : Io) (clock : BitVec 64) : Io :=
  if clock = 1 then { io with monotonic := io.monotonic.tail } else { io with realtime := io.realtime.tail }

/-- The 8 little-endian bytes of `value` modulo 2^64 (as Core's
`World.littleEndian64`). -/
def le64Bytes (value : Int) : List UInt8 :=
  let bits := Int.toNat (value % (2 ^ 64))
  (List.range 8).map fun index => UInt8.ofNat ((bits / (2 ^ (8 * index))) % 256)

/-- A `struct timespec` of a reading (seconds, nanoseconds): two 64-bit
little-endian fields, as Linux's `clock_gettime` stores it on x86-64. -/
def timespecLE (reading : Int × Nat) : List UInt8 :=
  le64Bytes reading.1 ++ le64Bytes (Int.ofNat reading.2)

theorem timespecLE_length (reading : Int × Nat) : (timespecLE reading).length = 16 := by
  simp [timespecLE, le64Bytes]

/-- The descriptor a system call's `unsigned int fd` argument names: its
register's low 32 bits. -/
def descriptor (register : BitVec 64) : Int := Int.ofNat (register.setWidth 32).toNat

/-- The most bytes Linux's `write` transfers in one call (`MAX_RW_COUNT`,
`INT_MAX & PAGE_MASK`). -/
def maxTransfer : Nat := 2147479552

end Lanius.X86.Machine

end

/-! The kernel's file calls on `Io.files`, whose bodies (`Lanius.Files`'s
calls) are not exposed: the x86 model names them, and the proofs use the
lemmas here. -/

public section

namespace Lanius.X86.Machine

/-- `read(2)` of at most `count` bytes from a file descriptor (3 or more): the
result, the bytes delivered, and `io` after. -/
def Io.readFile (io : Io) (fd : Int) (count : Nat) : Int × List UInt8 × Io :=
  ((io.files.read fd count).1, (io.files.read fd count).2.1, { io with files := (io.files.read fd count).2.2 })

/-- `write(2)` of `bytes` to a file descriptor (3 or more): the result and `io` after. -/
def Io.writeFile (io : Io) (fd : Int) (bytes : List UInt8) : Int × Io :=
  ((io.files.write fd bytes).1, { io with files := (io.files.write fd bytes).2 })

/-- `close(2)` of a file descriptor (3 or more): the result and `io` after. -/
def Io.closeFile (io : Io) (fd : Int) : Int × Io :=
  ((io.files.close fd).1, { io with files := (io.files.close fd).2 })

/-- `open(2)` of `path` with `flags`: the descriptor or `-errno` and `io`
after, or `none` where the model stops. -/
def Io.openFile (io : Io) (path : List UInt8) (flags : Nat) : Option (Int × Io) :=
  (io.files.openWith path flags).map fun (result, files) => (result, { io with files })

/-- A file read delivers at most what it asks for. -/
theorem Io.readFile_length (io : Io) (fd : Int) (count : Nat) : (io.readFile fd count).2.1.length ≤ count :=
  io.files.read_length fd count

end Lanius.X86.Machine
