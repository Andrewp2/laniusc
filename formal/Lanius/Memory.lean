import Lanius.Core

namespace Lanius.Memory

open Lanius

/-- A raw allocation has stable abstract identity. Its numeric address is not
    intended to prescribe a native allocator layout. -/
structure Block where
  base : Address
  size : Nat
  alignment : Nat
  bytes : List UInt8
  live : Bool := true
  /-- Borrowed blocks are addressable views of language-owned storage. They
      occupy a disjoint abstract address range but are not allocator-owned. -/
  owned : Bool := true
deriving Repr

/-- `remaining = none` represents an unbounded abstract allocator. A finite
    value makes out-of-memory behavior deterministic and testable. -/
structure Heap where
  blocks : List Block := []
  nextAddress : Address := 1
  remaining : Option Nat := none
deriving Repr

inductive AllocationResult where
  | allocated (pointer : Address) (heap : Heap)
  | exhausted (heap : Heap)
  | trapped (reason : Trap) (heap : Heap)
deriving Repr

def null : Address := 0

def validAlignment (alignment : Nat) : Bool :=
  alignment != 0 && 2 ^ alignment.log2 == alignment

def alignUp (address alignment : Nat) : Nat :=
  ((address + alignment - 1) / alignment) * alignment

def Heap.block? (heap : Heap) (base : Address) : Option Block :=
  heap.blocks.find? (fun block => block.base == base)

def Heap.containingBlock? (heap : Heap) (address : Address) : Option Block :=
  heap.blocks.find? fun block =>
    block.live && block.base ≤ address && address < block.base + block.size

def replaceBlock : List Block → Block → List Block
  | [], _ => []
  | block :: rest, replacement =>
      (if block.base == replacement.base then replacement else block) ::
        replaceBlock rest replacement

def consumeBudget (remaining : Option Nat) (size : Nat) : Option (Option Nat) :=
  match remaining with
  | none => some none
  | some available =>
      if size <= available then some (some (available - size)) else none

def refundBudget (remaining : Option Nat) (size : Nat) : Option Nat :=
  remaining.map (fun available => available + size)

def Heap.allocate (heap : Heap) (size alignment : Nat) : AllocationResult :=
  if !validAlignment alignment then
    .trapped .allocatorContract heap
  else
    match consumeBudget heap.remaining size with
    | none => .exhausted heap
    | some remaining =>
        let base := alignUp (max heap.nextAddress 1) alignment
        let block : Block := {
          base
          size
          alignment
          bytes := List.replicate size 0
        }
        .allocated base {
          heap with
          blocks := heap.blocks ++ [block]
          nextAddress := base + max size 1
          remaining
        }

/-- Introduce an addressable view without consuming the raw allocator budget.
    The caller owns synchronization with the language value represented by
    `bytes`; deallocation and reallocation reject this borrowed block. -/
def Heap.mapBorrowed (heap : Heap) (bytes : List UInt8) (alignment : Nat) : AllocationResult :=
  if !validAlignment alignment then
    .trapped .allocatorContract heap
  else
    let base := alignUp (max heap.nextAddress 1) alignment
    let block : Block := {
      base
      size := bytes.length
      alignment
      bytes
      owned := false
    }
    .allocated base {
      heap with
      blocks := heap.blocks ++ [block]
      nextAddress := base + max bytes.length 1
    }

def Heap.deallocate (heap : Heap) (pointer size alignment : Nat) : Except Trap Heap :=
  if pointer == null then
    .ok heap
  else
    match heap.block? pointer with
    | none => .error .invalidPointer
    | some block =>
      if !block.live then
        .error .doubleFree
      else if !block.owned then
        .error .allocatorContract
      else if block.size != size || block.alignment != alignment then
          .error .allocatorContract
        else
          let released := { block with live := false }
          .ok {
            heap with
            blocks := replaceBlock heap.blocks released
            remaining := refundBudget heap.remaining block.size
          }

def setByte : List UInt8 → Nat → UInt8 → List UInt8
  | [], _, _ => []
  | _ :: rest, 0, value => value :: rest
  | first :: rest, index + 1, value => first :: setByte rest index value

def resizeBytes (bytes : List UInt8) (size : Nat) : List UInt8 :=
  bytes.take size ++ List.replicate (size - bytes.length) 0

def Heap.loadByte (heap : Heap) (pointer offset : Nat) : Except Trap UInt8 :=
  let address := pointer + offset
  match heap.containingBlock? address with
  | none =>
      match heap.containingBlock? pointer, heap.block? pointer with
      | some _, _ => .error .rawMemoryBounds
      | none, some block =>
          if block.live then .error .rawMemoryBounds else .error .invalidPointer
      | none, none => .error .invalidPointer
  | some block =>
      match block.bytes[address - block.base]? with
      | none => .error .rawMemoryBounds
      | some value => .ok value

def Heap.storeByte (heap : Heap) (pointer offset : Nat) (value : UInt8) : Except Trap Heap :=
  let address := pointer + offset
  match heap.containingBlock? address with
  | none =>
      match heap.containingBlock? pointer, heap.block? pointer with
      | some _, _ => .error .rawMemoryBounds
      | none, some block =>
          if block.live then .error .rawMemoryBounds else .error .invalidPointer
      | none, none => .error .invalidPointer
  | some block =>
      let updated := {
        block with bytes := setByte block.bytes (address - block.base) value
      }
      .ok { heap with blocks := replaceBlock heap.blocks updated }

def loadBytesFrom (heap : Heap) (pointer offset : Nat) : Nat → Except Trap (List UInt8)
  | 0 => .ok []
  | count + 1 =>
      match heap.loadByte pointer offset with
      | .error reason => .error reason
      | .ok byte =>
          match loadBytesFrom heap pointer (offset + 1) count with
          | .error reason => .error reason
          | .ok rest => .ok (byte :: rest)

def Heap.loadBytes (heap : Heap) (pointer length : Nat) : Except Trap (List UInt8) :=
  loadBytesFrom heap pointer 0 length

def storeBytesFrom
    (heap : Heap) (pointer offset : Nat) : List UInt8 → Except Trap Heap
  | [] => .ok heap
  | byte :: rest =>
      match heap.storeByte pointer offset byte with
      | .error reason => .error reason
      | .ok next => storeBytesFrom next pointer (offset + 1) rest

def Heap.storeBytes (heap : Heap) (pointer : Nat) (bytes : List UInt8) : Except Trap Heap :=
  storeBytesFrom heap pointer 0 bytes

def Heap.reallocate
    (heap : Heap) (pointer oldSize newSize alignment : Nat) : AllocationResult :=
  if pointer == null then
    heap.allocate newSize alignment
  else if newSize == 0 then
    match heap.deallocate pointer oldSize alignment with
    | .error reason => .trapped reason heap
    | .ok released => .allocated null released
  else
    match heap.block? pointer with
    | none => .trapped .invalidPointer heap
    | some oldBlock =>
        if !oldBlock.live then
          .trapped .doubleFree heap
        else if !oldBlock.owned then
          .trapped .allocatorContract heap
        else if oldBlock.size != oldSize || oldBlock.alignment != alignment then
          .trapped .allocatorContract heap
        else
          match heap.deallocate pointer oldSize alignment with
          | .error reason => .trapped reason heap
          | .ok credited =>
              match credited.allocate newSize alignment with
              | .exhausted _ => .exhausted heap
              | .trapped reason _ => .trapped reason heap
              | .allocated replacement allocated =>
                  match allocated.block? replacement with
                  | none => .trapped .invalidPointer heap
                  | some newBlock =>
                      let copied := {
                        newBlock with
                        bytes := resizeBytes oldBlock.bytes newSize
                      }
                      .allocated replacement {
                        allocated with
                        blocks := replaceBlock allocated.blocks copied
                      }

end Lanius.Memory
