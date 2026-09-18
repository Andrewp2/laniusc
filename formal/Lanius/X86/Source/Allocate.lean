import Lanius.X86.Source.Constant

namespace Lanius.X86.Source.Allocate

open Lanius.Core Lanius.Extraction

def parameters : List (VarId × Ty) := [(0, .slice i32), (1, i32)]
def field (id : ConstantId) : Expr := .index (read 0) (.constant id)
def assign (id : ConstantId) (op : AssignOp) (right : Expr) : Stmt :=
  .expression (.assign op (.index (.local 0) (.constant id)) right)
def guard (top : ConstantId) : Expr :=
  .binary .logicalOr (.binary .less (read 1) (number 1))
    (.binary .greater (read 1) (.binary .subtract (number 1048576) (field top)))
def reject (failed : ConstantId) : Stmt :=
  .sequence (assign failed .set (number 1)) (returned (.unary .negate (number 1)))
def watermark (top slots : ConstantId) : Stmt :=
  .ifThenElse (.binary .greater (field top) (field slots))
    (.sequence (assign slots .set (field top)) .skip) .skip
def body (top slots failed : ConstantId) : Stmt :=
  .sequence (.ifThenElse (guard top) (reject failed) .skip)
    (.sequence (assign top .add (read 1))
      (.sequence (watermark top slots) (returned (.binary .subtract (field top) (number 1)))))

structure Checked (program : CoreSynthesis.Program.CheckedProgram artifacts) where
  top : IntegerConstant program.core
  slots : IntegerConstant program.core
  failed : IntegerConstant program.core
  values : top.value = 6 ∧ slots.value = 2 ∧ failed.value = 4
  internal : Extraction.Source.CheckedInternal program ["backend", "frame"] "allocate" parameters i32
    (body top.id slots.id failed.id)

def check? (program : CoreSynthesis.Program.CheckedProgram artifacts) : Option (Checked program) := do
  let source ← CoreSynthesis.Program.checkSourceFunction? program ["backend", "frame"] "allocate"
  let some (.sequence (.ifThenElse _ (.sequence (.expression (.assign _ (.index _ (.constant failedId)) _)) _) _)
    (.sequence (.expression (.assign _ (.index _ (.constant topId)) _))
      (.sequence (.ifThenElse (.binary .greater _ (.index _ (.constant slotsId))) _ _) _))) := source.function.body | none
  let top ← integerConstant? program.core topId
  let slots ← integerConstant? program.core slotsId
  let failed ← integerConstant? program.core failedId
  if values : top.value = 6 ∧ slots.value = 2 ∧ failed.value = 4 then
    let internal ← Extraction.Source.checkInternal? program ["backend", "frame"] "allocate" parameters i32 (body top.id slots.id failed.id)
    pure ⟨top, slots, failed, values, internal⟩
  else none

end Lanius.X86.Source.Allocate
