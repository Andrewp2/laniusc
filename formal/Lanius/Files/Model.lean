module

@[expose] public section

/-! The file system's data (roadmap F8): the files, directories and
descriptors that `Lanius.Files` gives Linux's file system calls on. Only
types and constants are here, so a change to what the calls do
(`Lanius.Files`, whose bodies are not exposed) rebuilds only the proofs that
`import all` it. -/

namespace Lanius.Files

/-- A regular file: its path from the current directory and its bytes. -/
structure Entry where
  path : List UInt8
  bytes : List UInt8 := []
deriving Repr

/-- An open descriptor (3 or more): the file it names, its offset, and how it
was opened. -/
structure Handle where
  id : Int
  path : List UInt8
  offset : Nat := 0
  readable : Bool := false
  writable : Bool := false
  /-- opened with `O_APPEND`: each write goes to the file's end -/
  append : Bool := false
deriving Repr

/-- The files and directories under the current directory, and the open
descriptors besides the standard streams. -/
structure System where
  files : List Entry := []
  directories : List (List UInt8) := []
  handles : List Handle := []
deriving Repr

/-- The longest path a system call takes (Linux's `PATH_MAX` less its NUL). -/
def pathLimit : Nat := 4095

/-- The default limit on open descriptors (`RLIMIT_NOFILE`). -/
def descriptorLimit : Nat := 1024

end Lanius.Files
