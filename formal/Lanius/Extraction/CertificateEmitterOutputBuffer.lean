import Lanius.Extraction.CertificateRoundTrip
import Lanius.Extraction.CertificateEmitterFrame

namespace Lanius.Extraction.CertificateEmitterOutputBuffer

open Lanius Lanius.Core Lanius.Extraction Lanius.Semantics
open Lanius.Extraction.CertificateEmitterFrame

export Lanius.Extraction.CertificateEmitterFrame
  (WriteFrame WriteFrame.trans WriteFrame.trans_bindLocal
    WriteFrame.cellIdFound WriteFrame.localFound_of_ne
    StableExpr.assignSetLocal StableExpr.assignSubtractI32)

/-! The source-independent model of the certificate emitter's mutable byte
buffer. Execution witnesses live in `CertificateEmitterHexWordExecution`;
this module intentionally contains no quoted or generated program artifact. -/

def outputSliceValue (root : CellId) (length : Nat) : Value :=
  .slice (.scalar (.signed .i32)) root [] 0 length

def outputByteValues (root : CellId) (length capacity position value : Nat) :
    List Value :=
  [outputSliceValue root length, .signed .i32 (Int.ofNat capacity),
    .signed .i32 (Int.ofNat position), .signed .i32 (Int.ofNat value)]

def outputByteBindings (root : CellId) (length capacity position value : Nat) :
    List (VarId × Value) :=
  [(0, outputSliceValue root length),
   (1, .signed .i32 (Int.ofNat capacity)),
   (2, .signed .i32 (Int.ofNat position)),
   (3, .signed .i32 (Int.ofNat value))]

structure OutputBuffer (caller : State) (root : CellId) (elements : List Value)
    (capacity position value : Nat) : Prop where
  formed : caller.CellsWellFormed
  backing : caller.cellEntry? root = some
    { id := root, value := some (.array elements) }
  inBounds : position < elements.length
  positionBound : position < capacity
  valueBound : value < 256
  positionAddBound : position + 1 < 2 ^ 31

theorem OutputBuffer.rootBound
    {caller : State} {root : CellId} {elements : List Value}
    {capacity position value : Nat}
    (buffer : OutputBuffer caller root elements capacity position value) :
    root < caller.nextCell := by
  have backing := buffer.backing
  unfold State.cellEntry? at backing
  exact buffer.formed _ (List.mem_of_find?_eq_some backing)

def hexByteHighValue (value : Nat) : Nat :=
  (CertificateRoundTrip.hexDigit (value / 16)).toNat

def hexByteLowValue (value : Nat) : Nat :=
  (CertificateRoundTrip.hexDigit (value % 16)).toNat

def hexByteElements (elements : List Value) (position value : Nat) : List Value :=
  setValue (setValue elements position
    (.signed .i32 (Int.ofNat (hexByteHighValue value)))) (position + 1)
    (.signed .i32 (Int.ofNat (hexByteLowValue value)))

end Lanius.Extraction.CertificateEmitterOutputBuffer
