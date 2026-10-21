import Lanius.Mini.Compile
import Lanius.Mini.Frame

/-! Assembly: each abstract instruction is a fixed byte sequence from the
existing encoders. A function image is the frame prologue followed by its
instructions; `ret` is the frame epilogue. -/

namespace Lanius.Mini
open Lanius.X86.Machine

def BinOp.alu : BinOp → Alu
  | .add => .add
  | .sub => .subtract
  | .mul => .add
  | .and => .and
  | .or => .or
  | .xor => .xor

def epilogueBytes : List UInt8 :=
  moveBytes .w64 rspRegister rbpRegister ++ popBytes rbpRegister ++ returnBytes

def Instr.encode : Instr → List UInt8
  | .imm value => immediateBytes .w32 0 value 0
  | .load slot => frameLoadBytes slot
  | .store slot => frameStoreBytes slot
  | .neg => negateBytes .w32 0
  | .op .mul slot => frameMultiplyBytes slot
  | .op operation slot => frameAluBytes slot operation.alu
  | .ret => epilogueBytes

def encodeAll : List Instr → List UInt8
  | [] => []
  | i :: rest => i.encode ++ encodeAll rest

def Code.image (code : Code) : List UInt8 :=
  framePrologueBytes code.slots ++ encodeAll code.instrs

end Lanius.Mini
