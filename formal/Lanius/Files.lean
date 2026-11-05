module

@[expose] public section

/-! The file system as Linux's file system calls see it (roadmap F8).

One model serves Core's world (`Lanius.World.State.fs`), the x86 kernel
(`Lanius.X86.Machine.Kernel`, through `Io.files`) and the mini IR's system
calls: laniusc's file externs are its runtime's raw `open(2)`, `read(2)`,
`write(2)` and `close(2)`, each returning the kernel's result, a descriptor, a
count or `-errno` (SEMANTIC_DECISIONS.md, "str values" point 8). The model is
the current directory's subtree, its files and directories named by their
path bytes, and the descriptors from 3 up (0, 1 and 2 are the standard
streams, always open); `none` is where it stops. What is trusted is in
TRUSTED_BASE.md section 8. -/

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

def System.file? (fs : System) (path : List UInt8) : Option Entry :=
  fs.files.find? (fun file => file.path == path)

def System.handle? (fs : System) (id : Int) : Option Handle :=
  fs.handles.find? (fun handle => handle.id == id)

def replaceFile (files : List Entry) (replacement : Entry) : List Entry :=
  files.map fun file => if file.path == replacement.path then replacement else file

def replaceHandle (handles : List Handle) (replacement : Handle) : List Handle :=
  handles.map fun handle => if handle.id == replacement.id then replacement else handle

/-- The longest path a system call takes (Linux's `PATH_MAX` less its NUL). -/
def pathLimit : Nat := 4095

/-- The default limit on open descriptors (`RLIMIT_NOFILE`). -/
def descriptorLimit : Nat := 1024

/-- A path's components: its bytes split at each slash. -/
def pathComponents (path : List UInt8) : List (List UInt8) :=
  path.splitOn 47

/-- A path the model reads: components joined by single slashes, none empty,
`.` or `..` (so not absolute and with no doubled or trailing slash). -/
def simplePath (path : List UInt8) : Bool :=
  (pathComponents path).all fun c => !c.isEmpty && c != [46] && c != [46, 46]

/-- The directories a path's lookup passes through, outermost first. -/
def parentPaths (path : List UInt8) : List (List UInt8) :=
  let cs := pathComponents path
  (List.range (cs.length - 1)).map fun i => [47].intercalate (cs.take (i + 1))

/-- The first failing step of a path's lookup: a missing directory is
`-ENOENT`, a file where a directory should be `-ENOTDIR`. -/
def System.parentError (fs : System) (path : List UInt8) : Option Int :=
  (parentPaths path).findSome? fun parent =>
    if fs.directories.contains parent then none
    else if (fs.file? parent).isSome then some (-20)
    else some (-2)

/-- The lowest number from `n` on that no descriptor in `ids` has (fuel: one
step more than there are ids is always enough). -/
def freeFrom (ids : List Int) : Nat → Nat → Nat
  | 0, n => n
  | fuel + 1, n => if ids.contains (Int.ofNat n) then freeFrom ids fuel (n + 1) else n

/-- The descriptor `open(2)` gives: the lowest number not open (0, 1 and 2
are). -/
def System.lowestFree (fs : System) : Nat :=
  freeFrom (fs.handles.map (·.id)) (fs.handles.length + 1) 3

/-- `open(2)` of a path (its bytes, with no NUL and at most `pathLimit` of
them) for reading (`O_RDONLY`), writing (`O_WRONLY|O_CREAT|O_TRUNC`) or
appending (`O_WRONLY|O_CREAT|O_APPEND`): the descriptor or `-errno` and the
file system after, or `none` where the model stops (a path it does not read,
a directory opened for reading, no free descriptor below `descriptorLimit`). -/
def System.openPath
    (fs : System) (path : List UInt8) (readable writable append : Bool) : Option (Int × System) :=
  if path.isEmpty then some (-2, fs)
  else if fs.lowestFree ≥ descriptorLimit || !simplePath path then none
  else
    match fs.parentError path with
    | some error => some (error, fs)
    | none =>
      if fs.directories.contains path then
        if writable then some (-21, fs) else none
      else
        let existing := fs.file? path
        if readable && existing.isNone then some (-2, fs)
        else
          let files := if writable && !append then
            match existing with
            | some file => replaceFile fs.files { file with bytes := [] }
            | none => fs.files ++ [{ path }]
          else if writable && existing.isNone then
            fs.files ++ [{ path }]
          else
            fs.files
          let id := Int.ofNat fs.lowestFree
          let handle : Handle := { id, path, offset := 0, readable, writable, append }
          some (id, { fs with files, handles := fs.handles ++ [handle] })

/-- The descriptor closed, or `none` when it is not open. -/
def System.closeHandle (fs : System) (id : Int) : Option System :=
  if (fs.handle? id).isSome then
    some { fs with handles := fs.handles.filter (fun handle => handle.id != id) }
  else
    none

/-- At most `capacity` bytes of the descriptor's file from its offset, and the
offset moved past them, or `none` when the descriptor is not open for reading. -/
def System.readBytes (fs : System) (id : Int) (capacity : Nat) : Option (List UInt8 × System) :=
  match fs.handle? id with
  | none => none
  | some handle =>
      if !handle.readable then none
      else
        match fs.file? handle.path with
        | none => none
        | some file =>
            let bytes := (file.bytes.drop handle.offset).take capacity
            let updated := { handle with offset := handle.offset + bytes.length }
            some (bytes, { fs with handles := replaceHandle fs.handles updated })

/-- `bytes` written at the descriptor's offset (at the file's end when it was
opened with `O_APPEND`), past the end filling the gap with zeros, as Linux
does, or `none` when the descriptor is not open for writing. -/
def System.writeBytes (fs : System) (id : Int) (bytes : List UInt8) : Option System :=
  match fs.handle? id with
  | none => none
  | some handle =>
      if !handle.writable then none
      else
        match fs.file? handle.path with
        | none => none
        | some file =>
            let position := if handle.append then file.bytes.length else handle.offset
            let suffix := file.bytes.drop (position + bytes.length)
            let gap := List.replicate (position - file.bytes.length) (0 : UInt8)
            let updatedFile := { file with bytes := file.bytes.take position ++ gap ++ bytes ++ suffix }
            let updatedHandle := { handle with offset := position + bytes.length }
            some { fs with files := replaceFile fs.files updatedFile,
                           handles := replaceHandle fs.handles updatedHandle }

/-! ### The system calls' results -/

/-- `read(2)` of at most `count` bytes from descriptor `fd`: the count, the
bytes and the file system after, or `-EBADF` (-9) and no bytes when `fd` is
not open for reading. -/
def System.read (fs : System) (fd : Int) (count : Nat) : Int × List UInt8 × System :=
  match fs.readBytes fd count with
  | none => (-9, [], fs)
  | some (bytes, next) => (Int.ofNat bytes.length, bytes, next)

/-- `write(2)` of `bytes` to descriptor `fd`: their count and the file system
after, or `-EBADF` when `fd` is not open for writing. -/
def System.write (fs : System) (fd : Int) (bytes : List UInt8) : Int × System :=
  match fs.writeBytes fd bytes with
  | none => (-9, fs)
  | some next => (Int.ofNat bytes.length, next)

/-- `close(2)` of descriptor `fd`: 0 and the file system after, or `-EBADF`
when `fd` is not open. -/
def System.close (fs : System) (fd : Int) : Int × System :=
  match fs.closeHandle fd with
  | none => (-9, fs)
  | some next => (0, next)

/-- What `open(2)`'s flags ask for (readable, writable, append): `O_RDONLY`
(0), `O_WRONLY|O_CREAT|O_TRUNC` (0x241) or `O_WRONLY|O_CREAT|O_APPEND`
(0x441), the three the runtime passes; `none` for any other. -/
def openFlags (flags : Nat) : Option (Bool × Bool × Bool) :=
  if flags = 0 then some (true, false, false)
  else if flags = 0x241 then some (false, true, false)
  else if flags = 0x441 then some (false, true, true)
  else none

/-- `open(2)` of `path` with `flags`. -/
def System.openWith (fs : System) (path : List UInt8) (flags : Nat) : Option (Int × System) :=
  match openFlags flags with
  | none => none
  | some (readable, writable, append) => fs.openPath path readable writable append

/-- A read delivers at most what it asks for. -/
theorem System.read_length (fs : System) (fd : Int) (count : Nat) : (fs.read fd count).2.1.length ≤ count := by
  unfold System.read System.readBytes
  split
  · exact Nat.zero_le _
  · rename_i bytes next found
    split at found
    · cases found
    · split at found
      · cases found
      · split at found
        · cases found
        · cases found
          exact List.length_take_le _ _

end Lanius.Files
