import Lanius.X86.Source.Expression.Indexed
import Lanius.X86.Source.Immediate
import Lanius.X86.Frame.Take

namespace Lanius.X86.Source.Expression.Literal

open Lanius.Core Lanius.Extraction

def widthGuard (signed boolean : ConstantId) : Expr := .binary .logicalOr
  (.binary .equal (read 0) (.constant signed)) (.binary .equal (read 0) (.constant boolean))
def widthBody (signed boolean : ConstantId) : Stmt :=
  .sequence (.ifThenElse (widthGuard signed boolean) (returned (number 32)) .skip) (returned (number 64))
def aggregateBody (slice string record : ConstantId) : Stmt := returned
  (.binary .logicalOr (.binary .logicalOr (.binary .equal (read 0) (.constant slice))
    (.binary .equal (read 0) (.constant string))) (.binary .greaterEqual (read 0) (.constant record)))

structure Layout (program : CoreSynthesis.Program.CheckedProgram artifacts) where
  signed : IntegerConstant program.core
  boolean : IntegerConstant program.core
  slice : IntegerConstant program.core
  string : IntegerConstant program.core
  record : IntegerConstant program.core
  values : signed.value = 1 ∧ boolean.value = 2 ∧ slice.value = 6 ∧ string.value = 5 ∧ record.value = 16
  width : Extraction.Source.CheckedInternal program ["backend", "layout"] "width" [(0, i32)] i32
    (widthBody signed.id boolean.id)
  aggregate : Extraction.Source.CheckedInternal program ["backend", "layout"] "aggregate" [(0, i32)] (.scalar .bool)
    (aggregateBody slice.id string.id record.id)

def layout? (program : CoreSynthesis.Program.CheckedProgram artifacts) : Option (Layout program) := do
  let width ← CoreSynthesis.Program.checkSourceFunction? program ["backend", "layout"] "width"
  let some (.sequence (.ifThenElse (.binary .logicalOr (.binary .equal _ (.constant signedId))
    (.binary .equal _ (.constant booleanId))) _ _) _) := width.function.body | none
  let aggregate ← CoreSynthesis.Program.checkSourceFunction? program ["backend", "layout"] "aggregate"
  let some (.sequence (.returnValue (some (.binary .logicalOr
    (.binary .logicalOr (.binary .equal _ (.constant sliceId)) (.binary .equal _ (.constant stringId)))
    (.binary .greaterEqual _ (.constant recordId))))) _) := aggregate.function.body | none
  let signed ← integerConstant? program.core signedId
  let boolean ← integerConstant? program.core booleanId
  let slice ← integerConstant? program.core sliceId
  let string ← integerConstant? program.core stringId
  let record ← integerConstant? program.core recordId
  if values : signed.value = 1 ∧ boolean.value = 2 ∧ slice.value = 6 ∧ string.value = 5 ∧ record.value = 16 then
    let width ← Extraction.Source.checkInternal? program ["backend", "layout"] "width" [(0, i32)] i32
      (widthBody signed.id boolean.id)
    let aggregate ← Extraction.Source.checkInternal? program ["backend", "layout"] "aggregate" [(0, i32)] (.scalar .bool)
      (aggregateBody slice.id string.id record.id)
    pure ⟨signed, boolean, slice, string, record, values, width, aggregate⟩
  else none

structure Constants (program : Program) where
  maxDepth : IntegerConstant program
  failed : IntegerConstant program
  code : IntegerConstant program
  value : IntegerConstant program
  pointer : IntegerConstant program
  rax : IntegerConstant program
  top : IntegerConstant program
  values : maxDepth.value = 512 ∧ failed.value = 4 ∧ code.value = 1 ∧ value.value = 0 ∧
    pointer.value = 4 ∧ rax.value = 0 ∧ top.value = 6

def field (id : ConstantId) : Expr := .index (read 2) (.constant id)
def assign (id : ConstantId) (right : Expr) : Stmt :=
  .expression (.assign .set (.index (.local 2) (.constant id)) right)
def entryGuard (constants : Constants program) : Expr := .binary .logicalOr
  (.binary .logicalOr (.binary .greaterEqual (read 6) (.constant constants.maxDepth.id))
    (.binary .notEqual (field constants.failed.id) (number 0)))
  (.binary .less (field constants.code.id) (number 0))
def takeArguments : List Expr := [read 0, read 1, read 2]
def invalidKind (layout : Layout program) (constants : Constants program.core) : Expr := .binary .logicalOr
  (.binary .logicalOr (.binary .less (read 10) (.constant layout.signed.id))
    (.binary .greater (read 10) (.constant constants.pointer.id)))
  (.binary .logicalAnd (.binary .logicalAnd (.binary .equal (read 10) (.constant layout.boolean.id))
    (.binary .notEqual (read 11) (number 0))) (.binary .notEqual (read 11) (number 1)))
def literalTail (layout : Layout program) (constants : Constants program.core) (take immediate : FunctionId) : Stmt :=
  .letLocal 13 i32 (number 0)
    (.sequence (.ifThenElse (.binary .equal (.call layout.width.source.function.id [read 10]) (number 64))
      (.sequence (.expression (.assign .set (.local 13) (.call take takeArguments))) .skip) .skip)
      (.sequence (assign constants.code.id (.call immediate [read 3, read 4, field constants.code.id,
        .call layout.width.source.function.id [read 10], .constant constants.rax.id, read 11, read 13]))
        (returned (read 10))))
def literalBody (layout : Layout program) (constants : Constants program.core) (take immediate : FunctionId)
    (stringBranch : Stmt) : Stmt :=
  .letLocal 10 i32 (.call take takeArguments) (.letLocal 11 i32 (.call take takeArguments)
    (.sequence (.ifThenElse (.binary .equal (read 10) (.constant layout.string.id)) stringBranch .skip)
      (.sequence (.ifThenElse (invalidKind layout constants) (returned negativeOne) .skip)
        (literalTail layout constants take immediate))))
def emitBody (layout : Layout program) (constants : Constants program.core) (take immediate : FunctionId)
    (stringBranch otherBranches : Stmt) : Stmt :=
  .sequence (.ifThenElse (entryGuard constants) (returned negativeOne) .skip)
    (.letLocal 9 i32 (.call take takeArguments)
      (.sequence (.ifThenElse (.binary .equal (read 9) (.constant constants.value.id))
        (literalBody layout constants take immediate stringBranch) .skip) otherBranches))
def body (layout : Layout program) (constants : Constants program.core) (emit : FunctionId) : Stmt :=
  .letLocal 9 i32 (field constants.top.id)
    (.letLocal 10 i32 (.call emit Indexed.recurseArguments)
      (.sequence (.ifThenElse (.unary .logicalNot (.call layout.aggregate.source.function.id [read 10]))
        (.sequence (assign constants.top.id (read 9)) .skip) .skip) (returned (read 10))))

/-- The complete real wrapper and its literal dispatch prefix are linked to
one source pack. Untaken string and nonliteral branches remain the original
AST, not copies of the rest of the recursive compiler. -/
structure Checked (emitters : CheckedBuffer encoded sources) where
  layout : Layout emitters.pack.program
  constants : Constants emitters.pack.program.core
  take : Source.Take.Checked emitters.pack.program
  immediate : Immediate.Checked emitters.pack.program emitters.registerValid emitters.widthValid emitters.rex emitters.fits emitters.word
  stringBranch : Stmt
  otherBranches : Stmt
  emitter : Extraction.Source.CheckedInternal emitters.pack.program ["backend", "compile"] "emit_expression" Indexed.parameters i32
    (emitBody layout constants take.internal.source.function.id immediate.source.function.id stringBranch otherBranches)
  wrapper : Extraction.Source.CheckedInternal emitters.pack.program ["backend", "compile"] "expression" Indexed.parameters i32
    (body layout constants emitter.source.function.id)

def check? (emitters : CheckedBuffer encoded sources) : Option (Checked emitters) := do
  let program := emitters.pack.program
  let layout ← layout? program
  let take ← Source.Take.check? program
  let immediate ← Immediate.check? program emitters.registerValid emitters.widthValid emitters.rex emitters.fits emitters.word
  let wrapper ← CoreSynthesis.Program.checkSourceFunction? program ["backend", "compile"] "expression"
  let some (.letLocal _ _ (.index _ (.constant topId)) _) := wrapper.function.body | none
  let emitter ← CoreSynthesis.Program.checkSourceFunction? program ["backend", "compile"] "emit_expression"
  let some (.sequence (.ifThenElse guard _ _) (.letLocal _ _ _
    (.sequence (.ifThenElse (.binary .equal _ (.constant valueId)) literal _) otherBranches))) := emitter.function.body | none
  let .binary .logicalOr (.binary .logicalOr (.binary .greaterEqual _ (.constant maxDepthId))
    (.binary .notEqual (.index _ (.constant failedId)) _)) (.binary .less (.index _ (.constant codeId)) _) := guard | none
  let .letLocal _ _ _ (.letLocal _ _ _ (.sequence (.ifThenElse _ stringBranch _) rest)) := literal | none
  let .sequence (.ifThenElse (.binary .logicalOr (.binary .logicalOr _ (.binary .greater _ (.constant pointerId))) _) _ _)
    (.letLocal _ _ _ (.sequence _ (.sequence (.expression (.assign _ _
      (.call _ [_, _, _, _, .constant raxId, _, _]))) _))) := rest | none
  let maxDepth ← integerConstant? program.core maxDepthId
  let failed ← integerConstant? program.core failedId
  let code ← integerConstant? program.core codeId
  let value ← integerConstant? program.core valueId
  let pointer ← integerConstant? program.core pointerId
  let rax ← integerConstant? program.core raxId
  let top ← integerConstant? program.core topId
  if values : maxDepth.value = 512 ∧ failed.value = 4 ∧ code.value = 1 ∧ value.value = 0 ∧
      pointer.value = 4 ∧ rax.value = 0 ∧ top.value = 6 then
    let constants := Constants.mk maxDepth failed code value pointer rax top values
    let emitter ← Extraction.Source.checkInternal? program ["backend", "compile"] "emit_expression" Indexed.parameters i32
      (emitBody layout constants take.internal.source.function.id immediate.source.function.id stringBranch otherBranches)
    let wrapper ← Extraction.Source.checkInternal? program ["backend", "compile"] "expression" Indexed.parameters i32
      (body layout constants emitter.source.function.id)
    pure ⟨layout, constants, take, immediate, stringBranch, otherBranches, emitter, wrapper⟩
  else none

end Lanius.X86.Source.Expression.Literal
