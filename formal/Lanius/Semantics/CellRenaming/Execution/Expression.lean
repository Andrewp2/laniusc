import Lanius.Semantics.CellRenaming.Execution.Call
import Lanius.Semantics.CellRenaming.Execution.Scalars
import Lanius.Semantics.CellRenaming.Execution.Aggregates
import Lanius.Semantics.CellRenaming.Execution.References
import Lanius.Semantics.CellRenaming.Execution.Pointers
import Lanius.Semantics.CellRenaming.Execution.ArrayStorage
import Lanius.Semantics.CellRenaming.Execution.Heap

namespace Lanius.Semantics.CellRenaming.Execution
open Lanius.Core

theorem expression {rename : Permutation boundary} (step : Step fuel rename program)
    (invariant : ProgramInvariant rename.forward program)
    (before : State) (input : Expr) (result : Value) (after : State)
    (ready : boundary ≤ before.nextCell)
    (evaluated : evalExpr (fuel + 1) program before input = .done result after) :
    evalExpr (fuel + 1) program (state rename.forward before) (CellRenaming.expression rename.forward input) =
      .done (value rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  cases input with
  | value entry => cases evaluated; exact ⟨rfl, ready⟩
  | «local» id => exact localExpression rename before id result after ready evaluated
  | cast type input => exact castExpression step before type input result after ready evaluated
  | unary op input => exact unaryExpression step before op input result after ready evaluated
  | binary op left right => exact binaryExpression step before op left right result after ready evaluated
  | array type input => exact arrayExpression step before type input result after ready evaluated
  | arrayToSlice type input => exact arrayToSliceExpression step before type input result after ready evaluated
  | index base index => exact indexExpression step before base index result after ready evaluated
  | structValue id input => exact structExpression step before id input result after ready evaluated
  | field input field => exact fieldExpression step before input field result after ready evaluated
  | enumValue id variant input => exact enumExpression step before id variant input result after ready evaluated
  | matchValue input branches => exact matchExpression step before input branches result after ready evaluated
  | assign op place input => exact assignExpression step before op place input result after ready evaluated
  | borrow type input => exact borrowExpression step before type input result after ready evaluated
  | dereference input => exact dereferenceExpression step before input result after ready evaluated
  | constant id => exact constant invariant before id result after ready evaluated
  | call id arguments => exact call step invariant before id arguments result after ready evaluated
  | intrinsic op input => exact intrinsicExpression step before op input result after ready evaluated
  | i32ArrayDataPtr input => exact arrayPointerExpression step before input result after ready evaluated
  | i32SliceFromRawParts pointer length => exact rawSliceExpression step before pointer length result after ready evaluated
  | i32SliceDataPtr input => exact slicePointerExpression step before input result after ready evaluated
  | stringDataPtr input => exact stringPointerExpression step before input result after ready evaluated
  | alloc size alignment => exact allocExpression step before size alignment result after ready evaluated
  | realloc pointer oldSize newSize alignment => exact reallocExpression step before pointer oldSize newSize alignment result after ready evaluated
  | dealloc pointer size alignment => exact deallocExpression step before pointer size alignment result after ready evaluated
  | loadByte pointer offset => exact loadByteExpression step before pointer offset result after ready evaluated
  | storeByte pointer offset input => exact storeByteExpression step before pointer offset input result after ready evaluated

end Lanius.Semantics.CellRenaming.Execution
