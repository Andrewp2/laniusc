# Geometry

`ext::geometry` provides exact planar topology for **every `i32` coordinate**, bounded owning convex hulls, and separately defined finite `f64` vector and affine arithmetic. Production code is Lanius. There are no host geometry calls.

## Exact planar API

`Point { x: i32, y: i32 }` is a plain value. `Bounds { min: Point, max: Point }` is closed and axis aligned.

| Function | Contract |
| --- | --- |
| `orientation(a,b,c)` | `-1` clockwise, `0` collinear, `1` counterclockwise. Exact, allocation free. |
| `equal(a,b)` | Exact coordinate equality. |
| `segment_bounds(a,b)` | Inclusive extrema of the endpoints. |
| `bounds_valid(box)` | Both minimum coordinates are at most their maximum. |
| `bounds_contains(box,p)` | Inclusive containment; invalid bounds return false. |
| `bounds_intersect(a,b)` | Inclusive intersection, including edge/corner contact; invalid bounds return false. |
| `on_segment(a,b,p)` | Inclusive exact membership, including a zero-length segment. |
| `classify_segments(a,b,c,d)` | `Disjoint`, `Touch` (one shared point involving an endpoint), `Proper` (crossing in both interiors), or `Overlap` (positive-length collinear intersection). Endpoints may coincide. |
| `bounding_box(points,limits)` | `Ok(None)` for empty input; otherwise inclusive extrema. |
| `signed_area2(points,limits)` | Exact signed twice-area if representable in `i64`; otherwise `Overflow`. Counterclockwise simple rings are positive. |
| `locate_in_ring(points,p,limits)` | `Outside`, `Boundary`, or `Inside` using even-odd fill. |
| `convex_hull(points,limits)` | An independently owned `Hull` in deterministic order. |
| `hull_work_bound(count)` | Conservative `count * (12 + 2*ceil(log2(count)))` work units; zero for empty input. Negative count is `InvalidView`. |

A ring closes implicitly from its last point to its first. An explicit repeated closing vertex is also accepted. Area is the algebraic shoelace sum for self-intersecting rings, whereas containment follows the even-odd rule. Neither function validates simplicity or interprets holes. Empty rings have zero area and no boundary/interior. One-point and two-point rings have zero area and their exact point/segment as boundary.

Orientation forms signed differences in `i64`, each with magnitude at most `2^32-1`. Each product magnitude fits `u64`. It compares the two signed products without constructing their potentially 65-bit difference. Thus near-collinearity and values beyond the `i64` product range require no epsilon or allocation. Shoelace terms individually fit `i64`; a signed two-word accumulator holds their exact sum (less than 96 bits for an `i32` count), and only the final conversion can overflow. Cancellation, translation, reversal and cyclic rotation do not introduce intermediate overflow errors.

The hull uses iterative mergesort, duplicate filtering, and the Graham–Andrew lower/upper scans with strict counterclockwise turns. It returns each extreme vertex once, counterclockwise, starting at the lexicographically smallest `(x,y)`. It excludes points in straight hull edges. Empty input gives no vertices, equal input gives one vertex, and collinear input gives its two lexicographic endpoints. Input order, duplicates, and explicit ring closure do not change the result. Time is `O(n log n)` and temporary/output memory is `O(n)`.

## Limits, errors and ownership

`Limits { max_points: i32, max_work: u64 }` defaults to 1,048,576 points and 100,000,000 work units. Negative point limits return `InvalidLimits`. Negative/overflowing view metadata returns `InvalidView`; counts over the caller's limit return `PointLimit`; insufficient work returns `WorkLimit`. Linear queries require one unit per point. Hulls require `hull_work_bound(n)` and reject counts above 134,217,727 with `Overflow` before reading or allocating, to keep every point buffer within the vector allocator's signed byte capacity. Limits are per operation.

All sequence functions take `core::slice::View<Point>`. Metadata checks cover nonnegative start/length and the sum fitting `i32`. **The caller must ensure the underlying physical slice covers `start + length`, and keep it alive and unchanged for the entire call.** The language cannot project physical slice length. Prefer `Vec.as_view()` or views constructed from known arrays. No function may make forged or dangling views safe.

Only hull construction allocates. It preserves the borrowed input and releases every temporary on failure, returning `AllocationFailed` for allocator failures. `Hull.view()` borrows its output; `get(index)` returns `Option<Point>`; `len()` returns its vertex count. `Hull.destroy()` releases the owner. Lanius copies owning structs shallowly: keep one active owner, borrow it through `Hull.borrow()` for helpers, and destroy it once. Do not destroy, mutate, or copy an owning vector handle while its view is in use.

## Finite approximate coordinates

`Vec2 { x,y }`, `Vec3 { x,y,z }` and `Affine2 { xx,xy,yx,yy,tx,ty }` contain `f64` values. `add2/3`, `sub2/3`, `scale2/3`, `dot2/3`, `cross2/3`, `length2/3`, and `normalize2/3` return `Result`. Nonfinite inputs return `NonFinite`; nonfinite computed results return `NumericalFailure`. Zero normalization returns `ZeroLength`. Ordinary binary64 rounding and underflow apply; these arithmetic results have no exact topology guarantee.

Lengths scale by the largest magnitude before summing squares, avoiding avoidable squaring overflow/underflow. Normalization divides by that scale before computing a unit vector, so it can succeed even when the original length is unrepresentable. Subnormal one-axis vectors normalize correctly. Dot/cross products and affine sums use ordinary binary64 operations; overflow or invalid intermediates are errors even when a differently ordered mathematical expression could cancel them.

`identity2()` returns the identity affine map. `transform2(a,v)` computes `(xx*x+xy*y+tx, yx*x+yy*y+ty)`. `compose2(a,b)` applies `b` first, then `a`. These maps provide approximate coordinates, never orientation, boundary, or intersection decisions.

## Sources and verification

The algorithm contracts were checked against the [CGAL 2D hull manual](https://doc.cgal.org/latest/Convex_hull_2/index.html) and its [Graham–Andrew implementation](https://github.com/CGAL/cgal/blob/master/Convex_hull_2/include/CGAL/Convex_hull_2/ch_graham_andrew_impl.h), plus JTS's [ray crossing counter](https://github.com/locationtech/jts/blob/master/modules/core/src/main/java/org/locationtech/jts/algorithm/RayCrossingCounter.java) and [robust line intersector](https://github.com/locationtech/jts/blob/master/modules/core/src/main/java/org/locationtech/jts/algorithm/RobustLineIntersector.java). The implementation uses exact bounded integer products rather than JTS's floating point orientation. It classifies intersections without constructing rounded intersection coordinates.

`tests/extended_geometry_execution.rs` runs native Lanius against seeded Python integer/Fraction models, including full-range near-collinearity, degenerate segments/rings, signed-area cancellation, hull permutations/duplicates and resource/failure paths. `shape_hull` is the real CSV consumer described in [extended-shape-hull.md](extended-shape-hull.md).
