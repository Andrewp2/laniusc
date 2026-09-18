import Lanius.Extraction.CompactOutput.Nodes.Read

namespace Lanius.Extraction.CompactOutput.Nodes

open Lanius.Core Lanius.Semantics Lanius.Properties

def payloadGuard : Expr := binary .lessEqual (read 16) negativeOne
def dispatch (tokenTag : Lanius.ConstantId) : Expr := binary .equal (read 15) (.constant tokenTag)
def tokenGuard : Expr := binary .greaterEqual (read 16) (read 4)
def nodeGuard (stateTag : Lanius.ConstantId) : Expr :=
  binary .logicalOr (binary .notEqual (read 15) (.constant stateTag))
    (binary .greaterEqual (read 16) (read 9))
def validationBranch (tokenTag stateTag : Lanius.ConstantId) : Stmt :=
  .ifThenElse (dispatch tokenTag)
    (.sequence (.ifThenElse tokenGuard (returned negativeOne) .skip) .skip)
    (.sequence (.ifThenElse (nodeGuard stateTag) (returned negativeOne) .skip) .skip)
def validateThen (tokenTag stateTag : Lanius.ConstantId) (continuation : Stmt) : Stmt :=
  .sequence (.ifThenElse payloadGuard (returned negativeOne) .skip)
    (.sequence (validationBranch tokenTag stateTag) continuation)

theorem nonnegative_payload (program : Program) (payload : Nat)
    (found : before.local? 16 = some (.signed .i32 payload)) :
    Evaluates program before payloadGuard (.boolean false) before := by
  core_eval []

/-- The source's token branch accepts precisely the supplied in-range token
reference, with no writes or local changes. -/
theorem validate_token (program : Program) (payload count : Nat)
    (tokenConstant : ParserTreeSource.constantValue program tokenTag 1)
    (tag : before.local? 15 = some (.signed .i32 1))
    (value : before.local? 16 = some (.signed .i32 payload))
    (countRead : before.local? 4 = some (.signed .i32 count))
    (bound : payload < count)
    (tailRun : Executes program before continuation completion after) :
    Executes program before (validateThen tokenTag stateTag continuation) completion after := by
  core_exec []

/-- State references must point backward, not to the current or a future node. -/
theorem validate_node (program : Program) (payload node : Nat)
    (tokenConstant : ParserTreeSource.constantValue program tokenTag 1)
    (stateConstant : ParserTreeSource.constantValue program stateTag 2)
    (tag : before.local? 15 = some (.signed .i32 2))
    (value : before.local? 16 = some (.signed .i32 payload))
    (nodeRead : before.local? 9 = some (.signed .i32 node))
    (bound : payload < node)
    (tailRun : Executes program before continuation completion after) :
    Executes program before (validateThen tokenTag stateTag continuation) completion after := by
  core_exec []

open Lanius.Compiler.Parser ParserTreeLayout Lanius.Extraction.SemanticTokens

/-- Reuse the frontend's backward-reference relation, and the token bound
already established by collection, to select the real validation branch. -/
theorem validate_child (program : Program) (child : ChildVisit) (count node : Nat)
    (tokenConstant : ParserTreeSource.constantValue program tokenTag 1)
    (stateConstant : ParserTreeSource.constantValue program stateTag 2)
    (tag : before.local? 15 = some (.signed .i32 (childTag child.reference)))
    (value : before.local? 16 = some (.signed .i32 (childPayload child.reference)))
    (countRead : before.local? 4 = some (.signed .i32 count))
    (nodeRead : before.local? 9 = some (.signed .i32 node))
    (linked : child.Linked 0 records node)
    (tokenBound : ∀ use, child = .token use → use.token < count)
    (tailRun : Executes program before continuation completion after) :
    Executes program before (validateThen tokenTag stateTag continuation) completion after := by
  cases child with
  | token use =>
    exact validate_token program use.token count tokenConstant tag value countRead (tokenBound use rfl) tailRun
  | node id start finish =>
    exact validate_node program id node tokenConstant stateConstant tag value nodeRead linked.2.1 tailRun

end Lanius.Extraction.CompactOutput.Nodes
