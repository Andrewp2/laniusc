module

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
(seconds, nanoseconds) of the monotonic and the real-time clock, and the
secure random bytes. -/
structure Io where
  trace : List Event := []
  input : List UInt8 := []
  monotonic : List (Int × Nat) := []
  realtime : List (Int × Nat) := []
  entropy : List UInt8 := []
deriving Repr

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

/-- The most bytes Linux's `write` transfers in one call (`MAX_RW_COUNT`,
`INT_MAX & PAGE_MASK`). -/
def maxTransfer : Nat := 2147479552

end Lanius.X86.Machine
