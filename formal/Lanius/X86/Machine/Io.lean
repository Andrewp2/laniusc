module

@[expose] public section

namespace Lanius.X86.Machine

/-- One thing a process did to or saw of its environment through the kernel
(roadmap F8; what each `syscall` does is trusted, TRUSTED_BASE.md section 9). -/
inductive Event where
  /-- `write(fd, buffer, count)` wrote these bytes to `fd`. -/
  | write (fd : Nat) (bytes : List UInt8)
deriving DecidableEq, Repr

/-- The process's side of its environment: the trace of events so far. -/
structure Io where
  trace : List Event := []
deriving Repr

/-- The most bytes Linux's `write` transfers in one call (`MAX_RW_COUNT`,
`INT_MAX & PAGE_MASK`). -/
def maxTransfer : Nat := 2147479552

end Lanius.X86.Machine
