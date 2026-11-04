module

public import Lanius.Memory
public import Lanius.IEEE
public import Lanius.Files

@[expose] public section

namespace Lanius.World

open Lanius
open Lanius.Core
open Lanius.Memory

open Lanius.Files (replaceFile replaceHandle pathLimit)

abbrev FileEntry := Files.Entry

abbrev FileHandle := Files.Handle

/-- A user-defined external function is outside the closed Lanius world. Its
    result is therefore supplied as part of the initial semantic environment,
    just like process arguments, clocks, and entropy. Responses are ordered so
    replay remains deterministic, and carry semantic values so aggregate
    returns do not depend on a target calling convention. -/
inductive OpaqueOutcome where
  | returned (value : Value)
  | trapped (reason : Trap)
deriving Repr

structure OpaqueResponse where
  external : ExternId
  outcome : OpaqueOutcome
deriving Repr

structure OpaqueCall where
  external : ExternId
  arguments : List Value
deriving Repr

/-- External inputs are part of the initial semantic state. Randomness and
    clocks are explicit streams/values, which makes a run reproducible without
    pretending that these services are pure. -/
structure State where
  arguments : List String := []
  environment : List (String × String) := []
  currentDirectory : String := "."
  standardInput : List UInt8 := []
  standardOutput : List UInt8 := []
  standardError : List UInt8 := []
  unixTimeSeconds : Int := 0
  /-- The readings (seconds, nanoseconds) the monotonic clock gives, one a
  read, in turn: a stream fixed before the run, as the kernel's clock is
  outside the program (SEMANTIC_DECISIONS.md, "Clock readings and secure
  bytes"). -/
  monotonicReadings : List (Int × Nat) := []
  /-- The readings the system (real-time) clock gives, one a read. -/
  systemReadings : List (Int × Nat) := []
  secureU32Stream : List Nat := []
  secureByteStream : List UInt8 := []
  /-- The files and directories under the current directory, and the open
  file descriptors besides 0, 1 and 2 (the standard streams, always open:
  closing one is not modeled), as Linux's file system calls see them
  (`Lanius.Files`, which the x86 kernel's model shares). -/
  fs : Files.System := {}
  calls : List HostService := []
  opaqueResponses : List OpaqueResponse := []
  opaqueCalls : List OpaqueCall := []
deriving Repr

inductive OpaqueCallResult where
  | returned (value : Value) (world : State)
  | trapped (reason : Trap) (world : State)
  | unmodeled (world : State)

/-- Consume exactly the next response for an opaque external call. An absent
    or out-of-order response is observably unmodeled; it is never guessed from
    the external's name or from the shape of its arguments. -/
def State.callOpaque
    (world : State) (external : ExternId) (arguments : List Value) :
    OpaqueCallResult :=
  let called := {
    world with opaqueCalls := world.opaqueCalls ++ [{ external, arguments }]
  }
  match world.opaqueResponses with
  | response :: rest =>
      if response.external = external then
        let next := { called with opaqueResponses := rest }
        match response.outcome with
        | .returned value => .returned value next
        | .trapped reason => .trapped reason next
      else
        .unmodeled called
  | [] => .unmodeled called

inductive CallResult where
  | returned (value : Value) (world : State)
  | exited (code : Int) (world : State)
  | unavailable (service : HostService) (world : State)
  | trapped (reason : Trap) (world : State)
  | typeMismatch (world : State)

inductive EffectResult where
  | returned (value : Value) (heap : Heap) (world : State)
  | exited (code : Int) (heap : Heap) (world : State)
  | unavailable (service : HostService) (heap : Heap) (world : State)
  | trapped (reason : Trap) (heap : Heap) (world : State)
  | typeMismatch (heap : Heap) (world : State)

def utf8Bytes (text : String) : List UInt8 :=
  text.toUTF8.data.toList

def State.afterPrintI32 (world : State) (value : Int) : State :=
  { world with standardOutput := world.standardOutput ++ utf8Bytes (toString value) ++ [10] }

def record (world : State) (service : HostService) : State :=
  { world with calls := world.calls ++ [service] }

/-- A sleep advances the whole-second compatibility clock; the monotonic and
system clocks are streams of readings, which a sleep does not change. -/
def State.afterSleepMs (world : State) (milliseconds : Nat) : State :=
  { world with unixTimeSeconds := world.unixTimeSeconds + Int.ofNat (milliseconds / 1000) }

/-- Host APIs returning `i32` use the same two's-complement wrapping rule as
    ordinary resolved integer operations. Host inputs such as timestamps and
    byte counts are mathematical integers in the model and are not assumed to
    fit merely because a native ABI would already have truncated them. -/
def wrapI32 (value : Int) : Int :=
  let bits := value % (2 ^ 32)
  if bits >= 2 ^ 31 then bits - 2 ^ 32 else bits

def i32Result (value : Int) : Value :=
  .signed .i32 (wrapI32 value)

def copyToHeap
    (heap : Heap) (pointer capacity : Nat) (bytes : List UInt8) : Except Trap (Nat × Heap) :=
  let count := min capacity bytes.length
  match heap.storeBytes pointer (bytes.take count) with
  | .error reason => .error reason
  | .ok next => .ok (count, next)

def environmentValue? (world : State) (key : List UInt8) : Option String :=
  (world.environment.find? (fun entry => utf8Bytes entry.1 == key)).map Prod.snd

def littleEndian64 (value : Int) : List UInt8 :=
  let bits := Int.toNat (value % (2 ^ 64))
  (List.range 8).map fun index => UInt8.ofNat ((bits / (2 ^ (8 * index))) % 256)

def timespecBytes (seconds : Int) (nanoseconds : Nat) : List UInt8 :=
  littleEndian64 seconds ++ littleEndian64 (Int.ofNat nanoseconds)

def writeBytes (world : State) (handle : Int) (bytes : List UInt8) : Option State :=
  if handle == 1 then
    some { world with standardOutput := world.standardOutput ++ bytes }
  else if handle == 2 then
    some { world with standardError := world.standardError ++ bytes }
  else
    none

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

/-- The most bytes one `read(2)` or `write(2)` transfers (Linux's `MAX_RW_COUNT`). -/
def transferLimit : Nat := 0x7ffff000

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

/-- Services that do not dereference raw memory or manipulate filesystem
    handles. Pointer-bearing services are handled by the heap-aware layer in
    `Lanius.Semantics`; an explicit `unavailable` result prevents an omitted
    service from silently acquiring arbitrary behavior. -/
def callSimple (world : State) (service : HostService) (arguments : List Value) : CallResult :=
  let world := record world service
  match service, arguments with
  | .argc, [] => .returned (i32Result world.arguments.length) world
  | .argLen, [.signed .i32 index] =>
      if index < 0 then .returned (i32Result (-1)) world
      else
        match world.arguments[index.toNat]? with
        | none => .returned (i32Result (-1)) world
        | some value => .returned (i32Result value.toUTF8.size) world
  | .unixSeconds, [] => .returned (i32Result world.unixTimeSeconds) world
  | .secureU32, [] =>
      match world.secureU32Stream with
      | [] => .trapped .entropyExhausted world
      | value :: rest =>
          .returned (.unsigned .u32 (value % (2 ^ 32)))
            { world with secureU32Stream := rest }
  | .i32ToF32, [.signed .i32 value] =>
      .returned (.f32Bits (IEEE.F32.ofInt value)) world
  | .sleepMsI32, [.signed .i32 milliseconds] =>
      if milliseconds < 0 then .returned (i32Result (-1)) world
      else .returned (i32Result 0) (world.afterSleepMs milliseconds.toNat)
  | .writeText, [.signed .i32 handle, .string text] =>
      match writeBytes world handle (utf8Bytes text) with
      | some written => .returned (i32Result (utf8Bytes text).length) written
      | none => .unavailable service world
  | .writeI32, [.signed .i32 handle, .signed .i32 value] =>
      match writeBytes world handle (utf8Bytes (toString value)) with
      | some written => .returned (i32Result 0) written
      | none => .unavailable service world
  | .writeByte, [.signed .i32 handle, .signed .i32 value] =>
      match writeBytes world handle [UInt8.ofNat (Int.toNat (value % 256))] with
      | some written => .returned (i32Result 1) written
      | none => .unavailable service world
  | .writeNewline, [.signed .i32 handle] =>
      match writeBytes world handle [10] with
      | some written => .returned (i32Result 1) written
      | none => .unavailable service world
  | .exit, [.signed .i32 code] => .exited code world
  | .argc, _ => .typeMismatch world
  | .unixSeconds, _ => .typeMismatch world
  | .secureU32, _ => .typeMismatch world
  | .argLen, _ => .typeMismatch world
  | .i32ToF32, _ => .typeMismatch world
  | .sleepMsI32, _ => .typeMismatch world
  | .writeText, _ => .typeMismatch world
  | .writeI32, _ => .typeMismatch world
  | .writeByte, _ => .typeMismatch world
  | .writeNewline, _ => .typeMismatch world
  | .exit, _ => .typeMismatch world
  | service, _ => .unavailable service world

/-- Heap-aware host execution. A zero-length copy performs no pointer access;
    nonempty invalid ranges trap through the abstract heap rather than invoking
    undefined host behavior. -/
def call (heap : Heap) (world : State) (service : HostService)
    (arguments : List Value) : EffectResult :=
  match callSimple world service arguments with
  | .returned value next => .returned value heap next
  | .exited code next => .exited code heap next
  | .trapped reason next => .trapped reason heap next
  | .typeMismatch next => .typeMismatch heap next
  | .unavailable _ next =>
      match service, arguments with
      | .openReadPath, [.string path] =>
          match openFile next (utf8Bytes path) true false false with
          | some (handle, opened) => .returned (i32Result handle) heap opened
          | none => .unavailable service heap next
      | .openWritePath, [.string path] =>
          match openFile next (utf8Bytes path) false true false with
          | some (handle, opened) => .returned (i32Result handle) heap opened
          | none => .unavailable service heap next
      | .readI32, [.signed .i32 handle, .signed .i32 fallback] =>
          let (value, read) := readFileI32 next handle fallback
          .returned (i32Result value) heap read
      | .writeText, [.signed .i32 handle, .string text] =>
          match writeFileBytes next handle (utf8Bytes text) with
          | some written => .returned (i32Result (utf8Bytes text).length) heap written
          | none => .returned (i32Result (-1)) heap next
      | .writeI32, [.signed .i32 handle, .signed .i32 value] =>
          match writeFileBytes next handle (utf8Bytes (toString value)) with
          | some written => .returned (i32Result 0) heap written
          | none => .returned (i32Result (-1)) heap next
      | .writeByte, [.signed .i32 handle, .signed .i32 value] =>
          match writeFileBytes next handle [UInt8.ofNat (Int.toNat (value % 256))] with
          | some written => .returned (i32Result 1) heap written
          | none => .returned (i32Result (-1)) heap next
      | .writeNewline, [.signed .i32 handle] =>
          match writeFileBytes next handle [10] with
          | some written => .returned (i32Result 1) heap written
          | none => .returned (i32Result (-1)) heap next
      | .closeFile, [.signed .i32 handle]
      | .close, [.signed .i32 handle] =>
          if 0 ≤ handle && handle ≤ 2 then .unavailable service heap next
          else
            match closeHandle next handle with
            | some closed => .returned (i32Result 0) heap closed
            | none => .returned (i32Result (-9)) heap next
      | .openRead, [.pointer pointer, .unsigned .usize length]
      | .openWrite, [.pointer pointer, .unsigned .usize length]
      | .openAppend, [.pointer pointer, .unsigned .usize length] =>
          match heap.loadBytes pointer length with
          | .error reason => .trapped reason heap next
          | .ok path =>
              let readable := service == .openRead
              let writable := service != .openRead
              let append := service == .openAppend
              match openFile next path readable writable append with
              | some (handle, opened) => .returned (i32Result handle) heap opened
              | none => .unavailable service heap next
      | .read, [.signed .i32 handle, .pointer pointer, .unsigned .usize length] =>
          if handle == 1 || handle == 2 || length > transferLimit then .unavailable service heap next
          -- the whole buffer is checked before the call, as the lowering
          -- checks it before the system call; then the call is Linux's
          else match heap.storeBytes pointer (List.replicate length (0 : UInt8)) with
          | .error reason => .trapped reason heap next
          | .ok _ =>
          if handle == 0 then
            let bytes := next.standardInput.take length
            match heap.storeBytes pointer bytes with
            | .error reason => .trapped reason heap next
            | .ok copied => .returned (i32Result bytes.length) copied
                { next with standardInput := next.standardInput.drop bytes.length }
          else
            -- not open, or not opened for reading: -EBADF
            match readFileBytes next handle length with
            | none => .returned (i32Result (-9)) heap next
            | some (bytes, read) =>
                match heap.storeBytes pointer bytes with
                | .error reason => .trapped reason heap next
                | .ok copied => .returned (i32Result bytes.length) copied read
      | .write, [.signed .i32 handle, .pointer pointer, .unsigned .usize length] =>
          if handle == 0 || length > transferLimit then .unavailable service heap next
          else
            match heap.loadBytes pointer length with
            | .error reason => .trapped reason heap next
            | .ok bytes =>
                if handle == 1 || handle == 2 then
                  match writeBytes next handle bytes with
                  | some written => .returned (i32Result bytes.length) heap written
                  | none => .unavailable service heap next
                else
                  -- not open, or not opened for writing: -EBADF
                  match writeFileBytes next handle bytes with
                  | none => .returned (i32Result (-9)) heap next
                  | some written => .returned (i32Result bytes.length) heap written
      | .removeFile, [.pointer pointer, .unsigned .usize length] =>
          match heap.loadBytes pointer length with
          | .error reason => .trapped reason heap next
          | .ok path =>
              if (next.file? path).isNone then .returned (i32Result (-1)) heap next
              else .returned (i32Result 0) heap {
                next with fs := { next.fs with files := next.fs.files.filter (fun file => file.path != path) }
              }
      | .createDir, [.pointer pointer, .unsigned .usize length] =>
          match heap.loadBytes pointer length with
          | .error reason => .trapped reason heap next
          | .ok path =>
              if next.fs.directories.contains path || (next.file? path).isSome then
                .returned (i32Result (-1)) heap next
              else .returned (i32Result 0) heap {
                next with fs := { next.fs with directories := next.fs.directories ++ [path] }
              }
      | .removeDir, [.pointer pointer, .unsigned .usize length] =>
          match heap.loadBytes pointer length with
          | .error reason => .trapped reason heap next
          | .ok path =>
              let nonempty := next.fs.files.any (fun file => descendantPath path file.path) ||
                next.fs.directories.any (fun directory => descendantPath path directory)
              if !next.fs.directories.contains path || nonempty then
                .returned (i32Result (-1)) heap next
              else
                .returned (i32Result 0) heap {
                  next with fs := { next.fs with directories := next.fs.directories.filter (fun entry => entry != path) }
                }
      | .rename, [.pointer fromPointer, .unsigned .usize fromLength,
          .pointer toPointer, .unsigned .usize toLength] =>
          match heap.loadBytes fromPointer fromLength, heap.loadBytes toPointer toLength with
          | .error reason, _ => .trapped reason heap next
          | _, .error reason => .trapped reason heap next
          | .ok sourcePath, .ok destinationPath =>
              if sourcePath == destinationPath then
                if next.pathOccupied sourcePath then
                  .returned (i32Result 0) heap next
                else
                  .returned (i32Result (-1)) heap next
              else if next.pathOccupied destinationPath then
                .returned (i32Result (-1)) heap next
              else
                match next.file? sourcePath with
                | some file =>
                    let renamed := { file with path := destinationPath }
                    .returned (i32Result 0) heap {
                      next with fs := {
                        next.fs with
                        files := next.fs.files.filter
                          (fun entry => entry.path != sourcePath) ++ [renamed]
                        handles := next.fs.handles.map fun handle =>
                          if handle.path == sourcePath then
                            { handle with path := destinationPath }
                          else handle }
                    }
                | none =>
                    if !next.fs.directories.contains sourcePath ||
                        descendantPath sourcePath destinationPath then
                      .returned (i32Result (-1)) heap next
                    else
                      .returned (i32Result 0) heap {
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
                      }
      | .alloc, [.unsigned .usize size, .unsigned .usize alignment] =>
          match heap.allocate size alignment with
          | .allocated pointer allocated => .returned (.pointer pointer) allocated next
          | .exhausted exhausted => .returned (.pointer null) exhausted next
          | .trapped reason trapped => .trapped reason trapped next
      | .realloc, [.pointer pointer, .unsigned .usize oldSize,
          .unsigned .usize newSize, .unsigned .usize alignment] =>
          match heap.reallocate pointer oldSize newSize alignment with
          | .allocated replacement allocated => .returned (.pointer replacement) allocated next
          | .exhausted exhausted => .returned (.pointer null) exhausted next
          | .trapped reason trapped => .trapped reason trapped next
      | .dealloc, [.pointer pointer, .unsigned .usize size, .unsigned .usize alignment] =>
          match heap.deallocate pointer size alignment with
          | .ok released => .returned .unit released next
          | .error reason => .trapped reason heap next
      | .allocFailed, [.unsigned .usize _, .unsigned .usize _] =>
          .trapped .allocationFailure heap next
      | .argRead, [.signed .i32 index, .pointer pointer, .unsigned .usize length] =>
          if index < 0 then .returned (i32Result (-1)) heap next
          else
            match next.arguments[index.toNat]? with
            | none => .returned (i32Result (-1)) heap next
            | some argument =>
                match copyToHeap heap pointer length (utf8Bytes argument) with
                | .error reason => .trapped reason heap next
                | .ok (count, copied) => .returned (i32Result count) copied next
      | .currentDirRead, [.pointer pointer, .unsigned .usize length] =>
          match copyToHeap heap pointer length (utf8Bytes next.currentDirectory) with
          | .error reason => .trapped reason heap next
          | .ok (count, copied) => .returned (i32Result count) copied next
      | .varCount, [] => .returned (i32Result next.environment.length) heap next
      | .varKeyLen, [.signed .i32 index] =>
          if index < 0 then .returned (i32Result (-1)) heap next
          else
            match next.environment[index.toNat]? with
            | none => .returned (i32Result (-1)) heap next
            | some entry => .returned (i32Result entry.1.toUTF8.size) heap next
      | .varKeyRead, [.signed .i32 index, .pointer pointer, .unsigned .usize length] =>
          if index < 0 then .returned (i32Result (-1)) heap next
          else
            match next.environment[index.toNat]? with
            | none => .returned (i32Result (-1)) heap next
            | some entry =>
                match copyToHeap heap pointer length (utf8Bytes entry.1) with
                | .error reason => .trapped reason heap next
                | .ok (count, copied) => .returned (i32Result count) copied next
      | .varLen, [.pointer keyPointer, .unsigned .usize keyLength] =>
          match heap.loadBytes keyPointer keyLength with
          | .error reason => .trapped reason heap next
          | .ok key =>
              match environmentValue? next key with
              | none => .returned (i32Result (-1)) heap next
              | some value => .returned (i32Result value.toUTF8.size) heap next
      | .varRead, [.pointer keyPointer, .unsigned .usize keyLength,
          .pointer valuePointer, .unsigned .usize valueLength] =>
          match heap.loadBytes keyPointer keyLength with
          | .error reason => .trapped reason heap next
          | .ok key =>
              match environmentValue? next key with
              | none => .returned (i32Result (-1)) heap next
              | some value =>
                  match copyToHeap heap valuePointer valueLength (utf8Bytes value) with
                  | .error reason => .trapped reason heap next
                  | .ok (count, copied) => .returned (i32Result count) copied next
      | .writeStdout, [.pointer pointer, .unsigned .usize length]
      | .writeStderr, [.pointer pointer, .unsigned .usize length] =>
          match heap.loadBytes pointer length with
          | .error reason => .trapped reason heap next
          | .ok bytes =>
              let written := if service == .writeStdout then
                { next with standardOutput := next.standardOutput ++ bytes }
              else
                { next with standardError := next.standardError ++ bytes }
              .returned (i32Result bytes.length) heap written
      | .readStdin, [.pointer pointer, .unsigned .usize length] =>
          let bytes := next.standardInput.take length
          match heap.storeBytes pointer bytes with
          | .error reason => .trapped reason heap next
          | .ok copied => .returned (i32Result bytes.length) copied
              { next with standardInput := next.standardInput.drop bytes.length }
      | .fillSecureBytes, [.pointer pointer, .unsigned .usize length] =>
          if next.secureByteStream.length < length then
            .trapped .entropyExhausted heap next
          else
            let bytes := next.secureByteStream.take length
            match heap.storeBytes pointer bytes with
            | .error reason => .trapped reason heap next
            | .ok copied => .returned (i32Result length) copied
                { next with secureByteStream := next.secureByteStream.drop length }
      | .monotonicRead, [.pointer pointer, .unsigned .usize length] =>
          if length < 16 then .returned (i32Result (-1)) heap next
          else
            match next.monotonicReadings with
            | [] => .trapped .clockExhausted heap next
            | reading :: rest =>
                match heap.storeBytes pointer (timespecBytes reading.1 reading.2) with
                | .error reason => .trapped reason heap next
                | .ok copied => .returned (i32Result 0) copied { next with monotonicReadings := rest }
      | .systemRead, [.pointer pointer, .unsigned .usize length] =>
          if length < 16 then .returned (i32Result (-1)) heap next
          else
            match next.systemReadings with
            | [] => .trapped .clockExhausted heap next
            | reading :: rest =>
                match heap.storeBytes pointer (timespecBytes reading.1 reading.2) with
                | .error reason => .trapped reason heap next
                | .ok copied => .returned (i32Result 0) copied { next with systemReadings := rest }
      | service, _ => .unavailable service heap next

end Lanius.World
