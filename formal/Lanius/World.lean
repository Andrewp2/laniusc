import Lanius.Memory

namespace Lanius.World

open Lanius
open Lanius.Core
open Lanius.Memory

structure FileEntry where
  path : List UInt8
  bytes : List UInt8 := []
deriving Repr

structure FileHandle where
  id : Int
  path : List UInt8
  offset : Nat := 0
  readable : Bool := false
  writable : Bool := false
deriving Repr

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
  monotonicSeconds : Int := 0
  monotonicNanoseconds : Nat := 0
  systemSeconds : Int := 0
  systemNanoseconds : Nat := 0
  secureU32Stream : List Nat := []
  secureByteStream : List UInt8 := []
  files : List FileEntry := []
  directories : List (List UInt8) := []
  fileHandles : List FileHandle := []
  nextFileHandle : Nat := 3
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

def advanceClock (seconds : Int) (nanoseconds milliseconds : Nat) : Int × Nat :=
  let totalNanoseconds := nanoseconds + milliseconds * 1_000_000
  (seconds + Int.ofNat (totalNanoseconds / 1_000_000_000),
    totalNanoseconds % 1_000_000_000)

def State.afterSleepMs (world : State) (milliseconds : Nat) : State :=
  let monotonic := advanceClock world.monotonicSeconds world.monotonicNanoseconds milliseconds
  let system := advanceClock world.systemSeconds world.systemNanoseconds milliseconds
  {
    world with
    unixTimeSeconds := world.unixTimeSeconds + Int.ofNat (milliseconds / 1000)
    monotonicSeconds := monotonic.1
    monotonicNanoseconds := monotonic.2
    systemSeconds := system.1
    systemNanoseconds := system.2
  }

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
  world.files.find? (fun file => file.path == path)

def State.handle? (world : State) (id : Int) : Option FileHandle :=
  world.fileHandles.find? (fun handle => handle.id == id)

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
  (world.file? path).isSome || world.directories.contains path

def replaceFile (files : List FileEntry) (replacement : FileEntry) : List FileEntry :=
  files.map fun file => if file.path == replacement.path then replacement else file

def replaceHandle
    (handles : List FileHandle) (replacement : FileHandle) : List FileHandle :=
  handles.map fun handle => if handle.id == replacement.id then replacement else handle

def openFile
    (world : State) (path : List UInt8) (readable writable append : Bool) : Int × State :=
  let existing := world.file? path
  if readable && existing.isNone then
    (-1, world)
  else
    let files := if writable && !append then
      match existing with
      | some file => replaceFile world.files { file with bytes := [] }
      | none => world.files ++ [{ path }]
    else if writable && existing.isNone then
      world.files ++ [{ path }]
    else
      world.files
    let offset := if append then (existing.map (fun file => file.bytes.length)).getD 0 else 0
    let id := Int.ofNat world.nextFileHandle
    let handle : FileHandle := { id, path, offset, readable, writable }
    (id, {
      world with
      files
      fileHandles := world.fileHandles ++ [handle]
      nextFileHandle := world.nextFileHandle + 1
    })

def closeHandle (world : State) (id : Int) : Option State :=
  if (world.handle? id).isSome then
    some { world with fileHandles := world.fileHandles.filter (fun handle => handle.id != id) }
  else
    none

def readFileBytes
    (world : State) (id : Int) (capacity : Nat) : Option (List UInt8 × State) :=
  match world.handle? id with
  | none => none
  | some handle =>
      if !handle.readable then none
      else
        match world.file? handle.path with
        | none => none
        | some file =>
            let bytes := (file.bytes.drop handle.offset).take capacity
            let updated := { handle with offset := handle.offset + bytes.length }
            some (bytes, {
              world with fileHandles := replaceHandle world.fileHandles updated
            })

def writeFileBytes
    (world : State) (id : Int) (bytes : List UInt8) : Option State :=
  match world.handle? id with
  | none => none
  | some handle =>
      if !handle.writable then none
      else
        match world.file? handle.path with
        | none => none
        | some file =>
            let suffix := file.bytes.drop (handle.offset + bytes.length)
            let updatedFile := {
              file with bytes := file.bytes.take handle.offset ++ bytes ++ suffix
            }
            let updatedHandle := { handle with offset := handle.offset + bytes.length }
            some {
              world with
              files := replaceFile world.files updatedFile
              fileHandles := replaceHandle world.fileHandles updatedHandle
            }

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
                  world with fileHandles := replaceHandle world.fileHandles updated
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
      .returned (.f32Bits (Float32.ofInt value).toBits) world
  | .sleepMsI32, [.signed .i32 milliseconds] =>
      if milliseconds < 0 then .returned (i32Result (-1)) world
      else .returned (i32Result 0) (world.afterSleepMs milliseconds.toNat)
  | .writeText, [.signed .i32 handle, .string text] =>
      match writeBytes world handle (utf8Bytes text) with
      | some written => .returned (i32Result 0) written
      | none => .unavailable service world
  | .writeI32, [.signed .i32 handle, .signed .i32 value] =>
      match writeBytes world handle (utf8Bytes (toString value)) with
      | some written => .returned (i32Result 0) written
      | none => .unavailable service world
  | .writeByte, [.signed .i32 handle, .signed .i32 value] =>
      match writeBytes world handle [UInt8.ofNat (Int.toNat (value % 256))] with
      | some written => .returned (i32Result 0) written
      | none => .unavailable service world
  | .writeNewline, [.signed .i32 handle] =>
      match writeBytes world handle [10] with
      | some written => .returned (i32Result 0) written
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
          let (handle, opened) := openFile next (utf8Bytes path) true false false
          .returned (i32Result handle) heap opened
      | .openWritePath, [.string path] =>
          let (handle, opened) := openFile next (utf8Bytes path) false true false
          .returned (i32Result handle) heap opened
      | .readI32, [.signed .i32 handle, .signed .i32 fallback] =>
          let (value, read) := readFileI32 next handle fallback
          .returned (i32Result value) heap read
      | .writeText, [.signed .i32 handle, .string text] =>
          match writeFileBytes next handle (utf8Bytes text) with
          | some written => .returned (i32Result 0) heap written
          | none => .returned (i32Result (-1)) heap next
      | .writeI32, [.signed .i32 handle, .signed .i32 value] =>
          match writeFileBytes next handle (utf8Bytes (toString value)) with
          | some written => .returned (i32Result 0) heap written
          | none => .returned (i32Result (-1)) heap next
      | .writeByte, [.signed .i32 handle, .signed .i32 value] =>
          match writeFileBytes next handle [UInt8.ofNat (Int.toNat (value % 256))] with
          | some written => .returned (i32Result 0) heap written
          | none => .returned (i32Result (-1)) heap next
      | .writeNewline, [.signed .i32 handle] =>
          match writeFileBytes next handle [10] with
          | some written => .returned (i32Result 0) heap written
          | none => .returned (i32Result (-1)) heap next
      | .closeFile, [.signed .i32 handle]
      | .close, [.signed .i32 handle] =>
          match closeHandle next handle with
          | some closed => .returned (i32Result 0) heap closed
          | none => .returned (i32Result (-1)) heap next
      | .openRead, [.pointer pointer, .unsigned .usize length]
      | .openWrite, [.pointer pointer, .unsigned .usize length]
      | .openAppend, [.pointer pointer, .unsigned .usize length] =>
          match heap.loadBytes pointer length with
          | .error reason => .trapped reason heap next
          | .ok path =>
              let readable := service == .openRead
              let writable := service != .openRead
              let append := service == .openAppend
              let (handle, opened) := openFile next path readable writable append
              .returned (i32Result handle) heap opened
      | .read, [.signed .i32 handle, .pointer pointer, .unsigned .usize length] =>
          match readFileBytes next handle length with
          | none => .returned (i32Result (-1)) heap next
          | some (bytes, read) =>
              match heap.storeBytes pointer bytes with
              | .error reason => .trapped reason heap next
              | .ok copied => .returned (i32Result bytes.length) copied read
      | .write, [.signed .i32 handle, .pointer pointer, .unsigned .usize length] =>
          match heap.loadBytes pointer length with
          | .error reason => .trapped reason heap next
          | .ok bytes =>
              match writeFileBytes next handle bytes with
              | none => .returned (i32Result (-1)) heap next
              | some written => .returned (i32Result bytes.length) heap written
      | .removeFile, [.pointer pointer, .unsigned .usize length] =>
          match heap.loadBytes pointer length with
          | .error reason => .trapped reason heap next
          | .ok path =>
              if (next.file? path).isNone then .returned (i32Result (-1)) heap next
              else .returned (i32Result 0) heap {
                next with files := next.files.filter (fun file => file.path != path)
              }
      | .createDir, [.pointer pointer, .unsigned .usize length] =>
          match heap.loadBytes pointer length with
          | .error reason => .trapped reason heap next
          | .ok path =>
              if next.directories.contains path || (next.file? path).isSome then
                .returned (i32Result (-1)) heap next
              else .returned (i32Result 0) heap {
                next with directories := next.directories ++ [path]
              }
      | .removeDir, [.pointer pointer, .unsigned .usize length] =>
          match heap.loadBytes pointer length with
          | .error reason => .trapped reason heap next
          | .ok path =>
              let nonempty := next.files.any (fun file => descendantPath path file.path) ||
                next.directories.any (fun directory => descendantPath path directory)
              if !next.directories.contains path || nonempty then
                .returned (i32Result (-1)) heap next
              else
                .returned (i32Result 0) heap {
                  next with directories := next.directories.filter (fun entry => entry != path)
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
                      next with
                      files := next.files.filter
                        (fun entry => entry.path != sourcePath) ++ [renamed]
                      fileHandles := next.fileHandles.map fun handle =>
                        if handle.path == sourcePath then
                          { handle with path := destinationPath }
                        else handle
                    }
                | none =>
                    if !next.directories.contains sourcePath ||
                        descendantPath sourcePath destinationPath then
                      .returned (i32Result (-1)) heap next
                    else
                      .returned (i32Result 0) heap {
                        next with
                        files := next.files.map fun file => {
                          file with path := (replacePathPrefix
                            sourcePath destinationPath file.path)
                        }
                        directories := next.directories.map
                          (replacePathPrefix sourcePath destinationPath)
                        fileHandles := next.fileHandles.map fun handle => {
                          handle with path := (replacePathPrefix
                            sourcePath destinationPath handle.path)
                        }
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
            match heap.storeBytes pointer
                (timespecBytes next.monotonicSeconds next.monotonicNanoseconds) with
            | .error reason => .trapped reason heap next
            | .ok copied => .returned (i32Result 0) copied next
      | .systemRead, [.pointer pointer, .unsigned .usize length] =>
          if length < 16 then .returned (i32Result (-1)) heap next
          else
            match heap.storeBytes pointer
                (timespecBytes next.systemSeconds next.systemNanoseconds) with
            | .error reason => .trapped reason heap next
            | .ok copied => .returned (i32Result 0) copied next
      | service, _ => .unavailable service heap next

end Lanius.World
