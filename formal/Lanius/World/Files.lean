module

public import Lanius.World.Model
public import Lanius.Files
import all Lanius.Files

public section

/-! Core's file services on the world's file system (`State.fs`, the model
of `Lanius.Files`, SEMANTIC_DECISIONS.md "str values" point 8): the
runtime's path copy and `open(2)`, `close(2)`, `read(2)` and `write(2)` as
`World.call` uses them, the directory services, and `read_i32`. Their bodies
are not exposed: a proof that unfolds one `import all`s this module, and a
change to one rebuilds only those. -/

namespace Lanius.World

open Lanius
open Lanius.Core
open Lanius.Files (replaceFile replaceHandle pathLimit)

def State.file? (world : State) (path : List UInt8) : Option FileEntry :=
  world.fs.file? path

def State.handle? (world : State) (id : Int) : Option FileHandle :=
  world.fs.handle? id

def bytesPrefix : List UInt8 → List UInt8 → Bool
  | [], _ => true
  | _, [] => false
  | first :: prefixes, byte :: bytes => first == byte && bytesPrefix prefixes bytes

def directoryPrefix (path : List UInt8) : List UInt8 :=
  if path.getLast? == some 47 then path else path ++ [47]

def descendantPath (parent candidate : List UInt8) : Bool :=
  bytesPrefix (directoryPrefix parent) candidate

def replacePathPrefix
    (source destination path : List UInt8) : List UInt8 :=
  if path == source then
    destination
  else if descendantPath source path then
    directoryPrefix destination ++ path.drop (directoryPrefix source).length
  else
    path

def State.pathOccupied (world : State) (path : List UInt8) : Bool :=
  (world.file? path).isSome || world.fs.directories.contains path

/-! ### Files as Linux's system calls see them

laniusc's file externs are its runtime's raw Linux system calls (`open(2)`
behind a copy of the path to a NUL-terminated buffer, `read(2)`, `write(2)`,
`close(2)`), each returning the kernel's result: a descriptor, a count or
`-errno` (SEMANTIC_DECISIONS.md, "str values" point 8). The file system and
the calls are `Lanius.Files`'s, which the x86 kernel's model shares; `none` is
where the model stops (`unavailable`). -/

/-- The runtime's path copy: a path longer than `pathLimit` is
`-ENAMETOOLONG`, one with a NUL byte `-EINVAL`. -/
def pathCopyError (path : List UInt8) : Option Int :=
  if path.length > pathLimit then some (-36)
  else if path.contains 0 then some (-22)
  else none

/-- `open(2)` of a path for reading (`O_RDONLY`), writing
(`O_WRONLY|O_CREAT|O_TRUNC`) or appending (`O_WRONLY|O_CREAT|O_APPEND`),
after the runtime's path copy (`Files.System.openPath`). -/
def openFile
    (world : State) (path : List UInt8) (readable writable append : Bool) : Option (Int × State) :=
  match pathCopyError path with
  | some error => some (error, world)
  | none => (world.fs.openPath path readable writable append).map fun (id, fs) => (id, { world with fs })

def closeHandle (world : State) (id : Int) : Option State :=
  (world.fs.closeHandle id).map fun fs => { world with fs }

def readFileBytes
    (world : State) (id : Int) (capacity : Nat) : Option (List UInt8 × State) :=
  (world.fs.readBytes id capacity).map fun (bytes, fs) => (bytes, { world with fs })

def writeFileBytes
    (world : State) (id : Int) (bytes : List UInt8) : Option State :=
  (world.fs.writeBytes id bytes).map fun fs => { world with fs }

def isAsciiDigit (byte : UInt8) : Bool :=
  byte.toNat >= 48 && byte.toNat <= 57

def parseI32Prefix (bytes : List UInt8) : Option (Int × Nat) :=
  let trimmed := bytes.dropWhile (fun byte => byte.toNat <= 32)
  let leading := bytes.length - trimmed.length
  let (negative, signWidth, digits) := match trimmed with
    | first :: rest =>
        if first.toNat == 45 then (true, 1, rest)
        else if first.toNat == 43 then (false, 1, rest)
        else (false, 0, trimmed)
    | [] => (false, 0, [])
  let digits := digits.takeWhile isAsciiDigit
  if digits.isEmpty then none
  else
    let magnitude := digits.foldl
      (fun value digit => value * 10 + (digit.toNat - 48)) 0
    let value := if negative then -Int.ofNat magnitude else Int.ofNat magnitude
    let modulus : Int := 2 ^ 32
    let bits := value % modulus
    let value := if bits >= 2 ^ 31 then bits - modulus else bits
    some (value, leading + signWidth + digits.length)

def readFileI32 (world : State) (id fallback : Int) : Int × State :=
  match world.handle? id with
  | none => (fallback, world)
  | some handle =>
      if !handle.readable then (fallback, world)
      else
        match world.file? handle.path with
        | none => (fallback, world)
        | some file =>
            match parseI32Prefix (file.bytes.drop handle.offset) with
            | none => (fallback, world)
            | some (value, consumed) =>
                let updated := { handle with offset := handle.offset + consumed }
                (value, {
                  world with fs := { world.fs with handles := replaceHandle world.fs.handles updated }
                })

/-- `remove_file`: -1 for a path that names no file, else the file gone. -/
def removeFilePath (world : State) (path : List UInt8) : Int × State :=
  if (world.file? path).isNone then (-1, world)
  else (0, { world with fs := { world.fs with files := world.fs.files.filter (fun file => file.path != path) } })

/-- `create_dir`: -1 for a path in use, else the directory added. -/
def createDirPath (world : State) (path : List UInt8) : Int × State :=
  if world.fs.directories.contains path || (world.file? path).isSome then (-1, world)
  else (0, { world with fs := { world.fs with directories := world.fs.directories ++ [path] } })

/-- `remove_dir`: -1 for a path that names no directory or a non-empty one,
else the directory gone. -/
def removeDirPath (world : State) (path : List UInt8) : Int × State :=
  let nonempty := world.fs.files.any (fun file => descendantPath path file.path) ||
    world.fs.directories.any (fun directory => descendantPath path directory)
  if !world.fs.directories.contains path || nonempty then (-1, world)
  else (0, { world with fs := { world.fs with directories := world.fs.directories.filter (fun entry => entry != path) } })

/-- `rename`: -1 when the source is missing or the destination in use (or
inside the source directory), else the file or the directory's subtree, and
the descriptors on them, renamed. -/
def renamePath (world : State) (sourcePath destinationPath : List UInt8) : Int × State :=
  let next := world
    if sourcePath == destinationPath then
      if next.pathOccupied sourcePath then
        (0, next)
      else
        ((-1), next)
    else if next.pathOccupied destinationPath then
      ((-1), next)
    else
      match next.file? sourcePath with
      | some file =>
          let renamed := { file with path := destinationPath }
          (0, {
            next with fs := {
              next.fs with
              files := next.fs.files.filter
                (fun entry => entry.path != sourcePath) ++ [renamed]
              handles := next.fs.handles.map fun handle =>
                if handle.path == sourcePath then
                  { handle with path := destinationPath }
                else handle }
          })
      | none =>
          if !next.fs.directories.contains sourcePath ||
              descendantPath sourcePath destinationPath then
            ((-1), next)
          else
            (0, {
              next with fs := {
                files := next.fs.files.map fun file => {
                  file with path := (replacePathPrefix
                    sourcePath destinationPath file.path)
                }
                directories := next.fs.directories.map
                  (replacePathPrefix sourcePath destinationPath)
                handles := next.fs.handles.map fun handle => {
                  handle with path := (replacePathPrefix
                    sourcePath destinationPath handle.path)
                } }
            })

/-! ### Equations the proofs use in place of the bodies -/

/-- With no descriptor open, a write to a file has nowhere to go. -/
theorem writeFileBytes_closed {world : State} (closed : world.fs.handles = []) (handle : Int)
    (bytes : List UInt8) : writeFileBytes world handle bytes = none := by
  simp [writeFileBytes, Files.System.writeBytes, Files.System.handle?, closed]

/-- A file read delivers at most what it asks for. -/
theorem readFileBytes_length {world after : State} {handle : Int} {count : Nat} {bytes : List UInt8}
    (read : readFileBytes world handle count = some (bytes, after)) : bytes.length ≤ count := by
  unfold readFileBytes at read
  cases h : world.fs.readBytes handle count with
  | none => simp [h] at read
  | some r =>
    obtain ⟨b, fs⟩ := r
    simp only [h, Option.map_some, Option.some.injEq, Prod.mk.injEq] at read
    rw [← read.1]
    have := world.fs.read_length handle count
    simp only [Files.System.read, h] at this
    exact this

end Lanius.World
