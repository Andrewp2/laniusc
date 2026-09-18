import Lanius.Core
import Lean

/-! Data quotation for Core programs. Quotation proposes syntax, never proofs
of typing, source correspondence, or execution. -/
open Lean

namespace Lanius.Core

deriving instance ToExpr for Lanius.Capability
deriving instance ToExpr for Lanius.Core.PointerWidth
deriving instance ToExpr for Lanius.Core.Target
deriving instance ToExpr for Lanius.Core.SignedIntTy
deriving instance ToExpr for Lanius.Core.UnsignedIntTy
deriving instance ToExpr for Lanius.Core.ScalarTy
deriving instance ToExpr for Lanius.Core.Ty
deriving instance ToExpr for Lanius.Core.ValueProjection
deriving instance ToExpr for Lanius.Core.Value
deriving instance ToExpr for Lanius.Core.UnaryOp
deriving instance ToExpr for Lanius.Core.BinaryOp
deriving instance ToExpr for Lanius.Core.AssignOp
deriving instance ToExpr for Lanius.Core.HostService
deriving instance ToExpr for Lanius.Core.ExternalBehavior
deriving instance ToExpr for Lanius.Core.Intrinsic
deriving instance ToExpr for Lanius.Core.Pattern, Lanius.Core.Expr, Lanius.Core.Place
deriving instance ToExpr for Lanius.Core.Stmt
deriving instance ToExpr for Lanius.Core.StructDecl
deriving instance ToExpr for Lanius.Core.EnumDecl
deriving instance ToExpr for Lanius.Core.Function
deriving instance ToExpr for Lanius.Core.Constant
deriving instance ToExpr for Lanius.Core.Program

end Lanius.Core
