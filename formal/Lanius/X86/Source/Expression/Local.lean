import Lanius.X86.Source.Expression.Literal
import Lanius.X86.Source.Lookup
import Lanius.X86.Source.Value.Get

namespace Lanius.X86.Source.Expression.Local

open Lanius.Core Lanius.Extraction

def selected (tag : ConstantId) : Expr := .binary .equal (read 9) (.constant tag)
def kindAddress (header stride : ConstantId) : Expr :=
  .binary .add (.binary .add (.constant header) (Literal.field stride)) (read 15)
def slotAddress (header stride : ConstantId) : Expr :=
  .binary .add (.binary .add (.constant header) (.binary .multiply (Literal.field stride) (number 2))) (read 15)
def rejected : Expr := .binary .less (read 15) (number 0)
def negativeKind : Expr := .binary .less (read 16) (number 0)
def getArguments : List Expr := [read 3, read 4, read 2, read 17, read 16]
def tail (aggregate get : FunctionId) (negativeBranch aggregateBranch : Stmt) : Stmt :=
  .sequence (.ifThenElse negativeKind negativeBranch .skip)
    (.sequence (.expression (.call get getArguments))
      (.sequence (.ifThenElse (.call aggregate [read 16]) aggregateBranch .skip) (returned (read 16))))
def branch (take lookup aggregate get : FunctionId) (header stride : ConstantId)
    (negativeBranch aggregateBranch : Stmt) : Stmt :=
  .letLocal 14 i32 (.call take Literal.takeArguments)
    (.letLocal 15 i32 (.call lookup [read 2, read 5, read 14])
      (.sequence (.ifThenElse rejected (returned negativeOne) .skip)
        (.letLocal 16 i32 (.index (read 2) (kindAddress header stride))
          (.letLocal 17 i32 (.index (read 2) (slotAddress header stride))
            (tail aggregate get negativeBranch aggregateBranch)))))
def rest (tag : ConstantId) (take lookup aggregate get : FunctionId) (header stride : ConstantId)
    (negativeBranch aggregateBranch otherBranches : Stmt) : Stmt :=
  .sequence (.ifThenElse (selected tag) (branch take lookup aggregate get header stride negativeBranch aggregateBranch) .skip)
    otherBranches

/-- The local branch is selected from the already authenticated real
emit_expression body. All other branches retain their source AST; the
initialized scalar case only needs the linked reader, lookup and getter. -/
structure Checked (literal : Literal.Checked emitters) where
  tag : IntegerConstant emitters.pack.program.core
  stride : IntegerConstant emitters.pack.program.core
  values : tag.value = 1 ∧ stride.value = 12
  lookup : Source.Lookup.Checked emitters.pack.program
  memory : Memory.Checked emitters.pack.program emitters.registerValid emitters.widthValid emitters.rex emitters.fits emitters.word
  load : Memory.CheckedMove emitters.pack.program memory true
  offset : Frame.CheckedDisplacement emitters.pack.program
  get : Source.Value.Get.Checked emitters.pack.program literal.layout load offset
  negativeBranch : Stmt
  aggregateBranch : Stmt
  otherBranches : Stmt
  bodyExact : literal.otherBranches = rest tag.id literal.take.internal.source.function.id lookup.internal.source.function.id
    literal.layout.aggregate.source.function.id get.internal.source.function.id lookup.header.id stride.id
    negativeBranch aggregateBranch otherBranches

def check? (literal : Literal.Checked emitters) : Option (Checked literal) := do
  let .sequence (.ifThenElse (.binary .equal _ (.constant tagId)) selectedBranch _) otherBranches := literal.otherBranches | none
  let .letLocal _ _ _ (.letLocal _ _ _ (.sequence _ typed)) := selectedBranch | none
  let .letLocal _ _ (.index _ (.binary .add (.binary .add _ (.index _ (.constant strideId))) _))
    (.letLocal _ _ _ (.sequence (.ifThenElse _ negativeBranch _)
      (.sequence _ (.sequence (.ifThenElse _ aggregateBranch _) _)))) := typed | none
  let program := emitters.pack.program
  let tag ← integerConstant? program.core tagId
  let stride ← integerConstant? program.core strideId
  if values : tag.value = 1 ∧ stride.value = 12 then
    let lookup ← Source.Lookup.check? program
    let memory ← Memory.check? program emitters.registerValid emitters.widthValid emitters.rex emitters.fits emitters.word
    let load ← Memory.checkMove? program memory true
    let offset ← Frame.checkDisplacement? program
    let get ← Source.Value.Get.check? program literal.layout load offset
    let equal ← Core.Equality.statement? literal.otherBranches
      (rest tag.id literal.take.internal.source.function.id lookup.internal.source.function.id literal.layout.aggregate.source.function.id
        get.internal.source.function.id lookup.header.id stride.id negativeBranch aggregateBranch otherBranches)
    pure ⟨tag, stride, values, lookup, memory, load, offset, get, negativeBranch, aggregateBranch, otherBranches, equal.equal⟩
  else none

end Lanius.X86.Source.Expression.Local
