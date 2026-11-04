module

public import Lanius.Memory
public import Lanius.IEEE
public import Lanius.Files
public import Lanius.World.Model
public import Lanius.World.Files

@[expose] public section

namespace Lanius.World

open Lanius
open Lanius.Core
open Lanius.Memory

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
              .returned (i32Result (removeFilePath next path).1) heap (removeFilePath next path).2
      | .createDir, [.pointer pointer, .unsigned .usize length] =>
          match heap.loadBytes pointer length with
          | .error reason => .trapped reason heap next
          | .ok path =>
              .returned (i32Result (createDirPath next path).1) heap (createDirPath next path).2
      | .removeDir, [.pointer pointer, .unsigned .usize length] =>
          match heap.loadBytes pointer length with
          | .error reason => .trapped reason heap next
          | .ok path =>
              .returned (i32Result (removeDirPath next path).1) heap (removeDirPath next path).2
      | .rename, [.pointer fromPointer, .unsigned .usize fromLength,
          .pointer toPointer, .unsigned .usize toLength] =>
          match heap.loadBytes fromPointer fromLength, heap.loadBytes toPointer toLength with
          | .error reason, _ => .trapped reason heap next
          | _, .error reason => .trapped reason heap next
          | .ok sourcePath, .ok destinationPath =>
              .returned (i32Result (renamePath next sourcePath destinationPath).1) heap
                (renamePath next sourcePath destinationPath).2
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
