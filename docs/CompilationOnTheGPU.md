                         Compilation On The GPU? A Feasibility Study
                 Robin F. Voetter                                          Marcel Huijben                                  Kristian F. D. Rietveld
             LIACS, Leiden University                                 LIACS, Leiden University                             LIACS, Leiden University
             Leiden, The Netherlands                                  Leiden, The Netherlands                               Leiden, The Netherlands
                 robin@voetter.nl                                        marcelhuij@live.nl                            k.f.d.rietveld@liacs.leidenuniv.nl
ABSTRACT                                                                                         We are in particular interested in the feasibility of performing the
The emergence of highly parallel architectures has led to a renewed                           entire compilation process on Graphics Processing Units (GPUs),
interest in parallel compilation. In particular, the widespread avail-                        which are now widely available. This might pave the way to ac-
ability of GPU architectures raises the question whether compi-                               celerate the compilation process by taking advantage of features
lation on the GPU is feasible. In this paper, we describe the first                           introduced in hardware in the last years, such as SIMD units and
design and implementation of a parallel compiler from a simple                                GPUs, or to offload compilation to GPUs contrary to preparing
imperative programming language to RISC-V machine code, that is                               executable GPU code on the CPU beforehand.
fully executed on a GPU. To accomplish this, all stages from parsing                             In this paper, we present a feasibility study on implementing and
to machine code generation were redesigned to exploit fine-grained                            executing the full compilation chain on the GPU. More specifically,
parallelism. Experimental evaluation of the implemented proto-                                we describe the first design and implementation of a parallel com-
type demonstrates our proposed parallel techniques to be effective                            piler from a simple imperative programming language to RISC-V
and implementation of compilation on the GPU to be feasible. Fi-                              machine code. We have devised our own simple programming lan-
nally, we propose a number of avenues for future work and hope to                             guage due to the limitations of current parallel parsers and the scope
revitalize research into parallel compilation conducted in the 1980s.                         of this study. This language serves as a demonstrator that implemen-
                                                                                              tation of a fully parallel compiler, by redesigning all compilation
CCS CONCEPTS                                                                                  stages to exploit fine-grained parallelization, is feasible. To the best
                                                                                              of our knowledge, our implementation is the first to perform all
• Software and its engineering → Compilers; • Theory of
                                                                                              of these steps in parallel on single translation units. We extend
computation → Parallel algorithms.
                                                                                              and adapt prior work on parallel lexing and parsing [7, 15, 20] and
                                                                                              describe our implementation of parallel semantic analysis and code
KEYWORDS                                                                                      generation, including register allocation.
Parallel Compilation, GPUs, Compiler Construction, Parsing, Code                                 Subsequently, we perform an experimental evaluation to see
Generation                                                                                    whether compilation on the GPU is advantageous from a perfor-
ACM Reference Format:                                                                         mance perspective. Experiments conducted on a modern GPU ar-
Robin F. Voetter, Marcel Huijben, and Kristian F. D. Rietveld. 2022. Compila-                 chitecture show a sub-linear scaling of the execution time against
tion On The GPU? A Feasibility Study. In 19th ACM International Conference                    a linear increase in the size of the source file for the majority of
on Computing Frontiers (CF’22), May 17–19, 2022, Torino, Italy. ACM, New                      the compiler stages. This shows our proposed parallel techniques
York, NY, USA, 7 pages. https://doi.org/10.1145/3528416.3530249                               to be effective. In fact, for large input files better scaling compared
                                                                                              to traditional CPU-based compilers is already seen, showing the
1     INTRODUCTION                                                                            potential of GPU-based compilation. Based on these initial results,
                                                                                              we identify a number of avenues for future work, in particular to
In the 1980’s and 1990’s parallel compilation was an active area of
                                                                                              improve the register allocation stage which is shown to be a bottle-
research [7, 15, 16]. Despite these efforts, a fully parallel compiler
                                                                                              neck. By doing so, there is the potential to lower the bound on the
has never been realized. Currently, parallelization of the compi-
                                                                                              input file size for GPU compilation to be profitable. Furthermore,
lation process is typically achieved at a coarse-grained level by
                                                                                              due to the portable nature of our implementation, the study can be
processing different source files (translation units) at the same time,
                                                                                              extended to many-core SIMD CPU architectures in the future.
or by performing analysis on compilation units in parallel. With
the stagnation of the increase in single-core performance [18] and                               Contributions. Our work makes the following contributions:
the emergence of highly parallel architectures, compiler design
warrants to be reconsidered. In fact, there is a renewed interest                                 • We describe an implementation of a compiler running com-
in parallel compilation by taking the parallelization to an even                                    pletely on the GPU, which is capable of taking a program
finer-grained level [3, 10, 19].                                                                    written in a custom designed imperative programming lan-
                                                                                                    guage and compiling it into RISC-V instructions.
                                                                                                  • We evaluate the effectiveness of the design and give an indica-
                                                                                                    tion of the performance compared to traditional compilation
                                                                                                    with a number of experiments.
This work is licensed under a Creative Commons Attribution International 4.0 License.             • Based on these results, we identify avenues for future work
CF’22, May 17–19, 2022, Torino, Italy                                                               to revitalize research into parallel compilation techniques.
© 2022 Copyright held by the owner/author(s).
ACM ISBN 978-1-4503-9338-6/22/05.
                                                                                                  • We have released the compiler as open source, available at
https://doi.org/10.1145/3528416.3530249                                                             https://github.com/Snektron/pareas.




                                                                                        230
CF’22, May 17–19, 2022, Torino, Italy                                                            Robin F. Voetter, Marcel Huijben, and Kristian F. D. Rietveld

                                                                                                                              Optimization



      Source       Lexical                       Parsing            Parse       Semantic                  Intermediate Code    Intermediate    Machine Code     RISC-V
                                   Tokens                                                         AST
       code        Analysis                                         Tree        Analysis                      Generation      Representation    Generation    Instructions




                        Figure 1: Schematic overview of the compiler passes that are considered in this paper.


This paper is organized as follows. Section 2 describes the design of                         The parallel operations are implementing using parallel array
our parallel compiler and Section 3 its implementation on modern                           primitives. This allows for a reduced development time compared
GPUs. Section 4 presents an evaluation of the compiler’s parallel                          to writing the various GPU kernels by hand and results in a portable
performance. Section 5 describes future work. Section 6 discusses                          code base as efficient implementations of these primitives exist for
related work in parallel compilation. Section 7 concludes the paper.                       different architectures. A pure functional programming language,
                                                                                           in our case Futhark [6], is used to compose these primitives into
2    DESIGN                                                                                programs. In such languages no expression may have side effects
In this paper, we consider the compilation passes from parsing                             and this makes it easier to reason about optimizing high-level con-
of the source code of a program until the generation of machine                            structs into parallel primitives. Many of the primitives that are used
code, summarized in Figure 1. To parallelize a compiler there are                          in the implementation, such as parallel map, reduction, scan and
two approaches: run many, possibly different, passes in parallel,                          prefix sum were first described by Hillis and Steele [9].
or parallelize each pass individually. Given the SIMD nature of
GPU architectures, the latter is the more suitable choice, and we de-                      2.1    Lexical Analysis
scribe the individual parallelization of each pass. Another important                      The first stage performs lexical analysis according to a lexical gram-
property of GPU architecture is the reliance on streaming memory                           mar to partition the input into a sequence of tokens. The main
access and that codes involving frequent branching and irregular                           problem of parallel lexical analysis presents itself when grammars
memory access (e.g., due to indirection arrays or pointer-linked                           with more complicated tokens are introduced, such as comments
data structures) are ill suited. In fact, traditional compilers are for                    and quoted strings. In such a case processors that are parsing sec-
the most part centered around the manipulation of pointer-linked                           tions of the input in parallel may need to look back to the start of
trees using recursive functions that involve heavy branching. There-                       the input to determine the current state, which is detrimental to
fore, in our design an inverted tree data structure is used instead of                     the performance. We address this by representing the grammar as a
pointer-linked trees. The inverted tree is array-based and can be                          single deterministic finite automaton that is run once for each token
manipulated in a straightforward manner using parallel operations.                         in the input. Subsequently, we employ the algorithm proposed by
   Figure 2 illustrates the differences between these. The inverted                        Hillis & Steele [9] to evaluate this automaton on all characters of the
tree was recently proposed for the implementation of compiler                              input string in parallel. This can be implemented in terms of lookup
transformations on the GPU by Hsu, et al. [10]. We use a variant of                        tables generated ahead of the lexical analysis, see Section 3.1.
the inverted tree and store the parse tree in pre-order and Abstract
Syntax Tree (AST) in post-order. Additionally, we use different                            2.2    Parsing
algorithms to manipulate the inverted tree. Whereas pointer-linked                         In the parsing stage the syntactic structure of the input is validated
trees are manipulated using recursive operations, we use iterative,                        according to the language’s syntactic grammar and a parse tree
loop-based array accesses which are easier to parallelize. The basic                       is built. This is usually performed using a push-down automaton,
inverted tree data structure is augmented with additional fields and                       which requires the current state of the stack to be known to parse
node types as the compilation progresses.                                                  a section of the input. This causes subsequent sections to be depen-
                                                                                           dent on each other, refraining these from being parsed in parallel.
                                                                                           We break this dependence chain by making it possible to determine
                 *4                                                                        the top of the stack from the previous few input symbols, relative to
                                   index      type         parent      depth
                                                                                           the current input position, instead of maintaining an actual stack.
                                     0       deref           2              2              Sections of the input are now processed in parallel by deriving the
                                     1       deref           2              2              initial contents of the stack from preceding input symbols, parsing
         +2                   63
                                     2        add            4              1              each section using a regular predictive LL parser and recording the
                                     3      constant         4              1              push and pop operations. The recorded operations (stack configura-
                                     4        mul           -1              0              tion changes) are concatenated to validate the input and to produce
                                                                                           the final parse. From the final parse the parse tree is constructed.
a0               b1
                                                                                              The foundation of a parallel parsing algorithm that takes this
                                                                                           approach, and that we have implemented, is described in [20]. This
Figure 2: Left: illustration of regular tree for expression                                algorithm is capable of deterministically parsing languages of the
(a+b) * 6, subscript indicates node index. Right: the cor-                                 newly defined LLP(q, k) grammar class in O(log n) parallel time,
responding inverted tree data structure in post-order.                                     where n is the number of tokens to parse. Within this definition,




                                                                                 231
Compilation On The GPU? A Feasibility Study                                                                      CF’22, May 17–19, 2022, Torino, Italy

               fn fib[x: int]: int {
                   if x < 2 {                                                    of the fixed-width instructions and the regularity of the instruction
                       return x;                                                 encoding. Part of the generation of instructions is the selection
                   } else {                                                      of free registers. Because this is highly dependent on neighboring
                       return fib[x - 1] + fib[x - 2];
                   }                                                             instructions, this would severely restrict the degree of parallelism
               }                                                                 that can be achieved. To counter this, we postpone register allo-
               fn main[a: int, b: float]: void {
                                                                                 cation and first compile to an intermediate representation which
                   while (a + 2) < int(-b * 3.0) {                               uses virtual registers and that is similar to a static single assign-
                       a = fib[a];                                               ment representation of RISC-V. Section 3.5 explains the allocation
                   }
               }                                                                 of physical registers. We allow each register to be written once
                                                                                 and read multiple times, but do not allow a register to be written
Figure 3: Example program in our programming language.                           in between writes. The output register number is computed from
                                                                                 the instruction location, already satisfying the requirement that
                                                                                 each register can only be written once. The actual generation of
q and k denote the number of lookbehind symbols and lookahead                    the instructions is parallelized by processing all nodes at the same
symbols respectively. For this study, we have opted to implement                 depth in the tree simultaneously.
an LLP(1, 1) parser, in which case the stack configuration changes
corresponding to a pair of lookbehind and lookahead symbols can                  2.5    Optimization
be stored in a pre-computed two-dimensional table. In this case, the             Optimizations can be performed on the intermediate representa-
grammar must allow constructs to be deduced from two consecutive                 tion that do not require information about the physical registers.
input symbols. This puts restrictions on the grammar which in                    Optimizations modify the instruction buffer and parallelization is
turn leads to a limitation in the languages that can be parsed. One              done at the level of instructions instead of nodes. Many of the fea-
could modify the grammar to conform to these restrictions, but                   sible optimizations at this stage involve the removal of instructions
the result is a language with inconvenient and unorthodox syntax.                (e.g., dead code removal or constant folding). However, repeatedly
Alternatively, one can modify the grammar to accept a super set of               removing instructions from an array-based instruction buffer is an
the desired syntax and verify full correctness during the semantic               expensive operation, as remaining instructions need to be scattered
analysis stage that follows the parsing stage.                                   to new locations and function locations and jump targets need to
   For the purpose of this initial feasibility study, we have designed           be updated. Therefore, we employ an instruction mask indicating
a custom imperative and procedural programming language with a                   whether an instruction in the program is enabled, which later stages
static type system, bearing resemblance to existing programming                  can use to determine whether an instruction will be optimized away.
languages. As such, the operations performed in our parallel com-                The actual removal of instructions and correction of data structures
piler relate to existing compilers. A super set of our language can be           is delayed until the final step of the machine code generation.
parsed using a LLP(1, 1) parser and full correctness is verified in dur-
ing semantic analysis. An example program is shown in Figure 3. As
                                                                                 2.6    Machine Code Generation
can be seen, we have had to make a number of compromises such as
always enforcing curly braces around compound statements, using                  At this stage, the intermediate representation is transformed into
square brackets for function applications, parsing else and elif                 the final RISC-V machine code. First, register allocation will map
parts of if-statements as separate statements and verifying the                  the infinite set of virtual registers onto the finite set of physical reg-
relative order of these later, and limiting the number of supported              isters. If insufficient registers are available, registers will be flagged
data types. More work is necessary to strike a balance between                   for spilling and the necessary stack space will be allocated. In tra-
parsing programming languages with traditional syntax and the                    ditional compilers a graph coloring algorithm is typically used to
degree of parallelism that can be achieved.                                      perform register allocation. While the graph coloring algorithm
                                                                                 itself can be run efficiently on a parallel architecture like a GPU
                                                                                 [5], the fact that each iteration may insert spill instructions would
2.3    Semantic Analysis
                                                                                 impose a significant overhead due to the array reallocation that
This stage has three major tasks: (1) validate and correct the parse             is required. Therefore, we opt to implement a greedy algorithm
tree for the fact that a super set of the desired grammar was accepted           to allocate registers. Although this does not result in mappings as
by the parser, (2) analyze the parse tree to determine whether it                optimal as those produced by a graph coloring approach, a reason-
fits the semantic rules of the language, (3) transform the parse tree            able mapping is still produced for most applications given the large
to an AST. All of these tasks are implemented as a series of passes.             amount of registers present on the RISC-V target architecture.
A pass processes the parse tree and may add, replace or remove                      Additionally, the actual insertion of spill instructions is post-
nodes. Each pass is designed such that it performs small, node-local             poned until register allocation has completed. By doing so, all spill
operations that can be executed for all nodes of the tree in parallel,           instructions can be inserted in one go and this can be combined
or by parallelizing large, tree-wide operations in a clever way.                 with the removal of instructions according to the instruction mask.
                                                                                 This results in the final instruction buffer. After post-processing the
2.4    Intermediate Code Generation                                              jump instructions and computing the final function offset table, the
At this point, the AST is transformed into machine code. For this                compilation process has finished and the results can be transferred
study, we have selected the RISC-V architecture as target because                from GPU to CPU memory.




                                                                           232
CF’22, May 17–19, 2022, Torino, Italy                                                Robin F. Voetter, Marcel Huijben, and Kristian F. D. Rietveld


3     IMPLEMENTATION                                                           and a set of arrays is created where each array stores a particular
We have implemented a prototype of the described parallel compiler             node property (e.g., data type, parent index, depth of the node in
in a mix of C++ and Futhark [6] code. The former is used for the               the AST, literals). So, all information regarding a node is now easily
pre-processing tools to generate the pre-computed tables required              reachable without tree walks, which simplifies the implementation
for the lexical analyzer and parser, and for the compiler’s driver             of the subsequent code generation stages.
code. The driver code loads these tables onto the GPU at runtime,
along with the source code to compile in verbatim, after which it              3.3     Intermediate Code Generation
launches the compilation passes. All of the compilation passes are             First, the number of instructions to be generated is computed1 and
written in the Futhark functional programming language.                        an instruction buffer is allocated. Second, a mapping is computed
                                                                               from nodes in the tree to instruction locations in the buffer. Both
3.1    Lexical Analyzer & Parser                                               rely on a parallel map to map each node type to the number of
                                                                               instructions required to encode it. Small adjustments are made
The pre-processing for the lexical analyzer and parser is combined
                                                                               for special cases (e.g., branch nodes) and a function offset table,
into a single tool, which generates the appropriate data structures
                                                                               containing start and size of each function, is computed. To generate
during the build process of the compiler. For the lexical analyzer, a
                                                                               the actual instructions, child nodes must be processed before parent
single deterministic finite automaton that is run once for the entire
                                                                               nodes. As such, a bottom-up tree walk is performed which will
input is constructed from a lexical grammar provided as text file. It
                                                                               process all nodes at the same depth in parallel. By assuming each
is encoded into three (table) data structures to support simulation
                                                                               node will yield at most four instructions, we spawn four threads for
of the automaton using the algorithm of Hillis & Steele. To reduce
                                                                               each AST node. Each of these threads will determine instruction
the memory space required, we compute all reachable compositions
                                                                               opcode, registers and branch target according to the node type.
of unary transition functions ahead of time and assign an (integer)
identifier to each one of them.
   To generate the parser, a syntactical grammar must be supplied in
                                                                               3.4     Optimization
the form of a text file containing a number of productions. This input         Simple optimizations can be implemented that amend instructions
is processed into a total of three data structures. The generation             in the intermediate representation or mark instructions for removal
algorithm that is employed is a straightforward implementation of              in the instruction mask. As an example, consider dead expression
the method discussed in [20]. As our compiler is designed around               removal, which removes any expression of which the result is not
a LLP(1, 1) grammar, we can pre-compute the stack configuration                used. To do so, we repeatedly update a table that maps virtual
changes for every possible pair of token types and store this in a             register numbers to a boolean indicating whether that register is
two-dimensional lookup table.                                                  used, using parallel map and scatter operations. For instructions
   At runtime, the lexical analyzer automaton is evaluated using               of which the destination register is not used, the booleans for the
the algorithm of Hillis & Steele, implemented using parallel map for           source registers are set to false. Because of the correspondence
table lookups and a parallel prefix scan to deduce all token types             between virtual register numbers and instruction location, we can
that have been emitted during the evaluation. This sequence of                 directly update the instruction mask from this table to indicate the
token types is the final token stream, from which the parser will              instructions that can be optimized away. Instructions that induce
build the parse tree. The parallel parsing algorithm that we consider          side-effects are never removed.
first maps each subsequent pair of symbols to stack configuration
changes using the lookup table and a parallel string extraction                3.5     Machine Code Generation
algorithm. Secondly, the validity of the input is determined by                First, the physical register numbers to be encoded into the instruc-
verifying that the concatenated stack configuration changes are                tions must be determined. This register allocation starts with a
balanced using a parallel bracket matching algorithm [1]. Finally,             lifetime analysis to determine which registers are in use at which
the final parse can be computed in a similar fashion, but using a              point of the program. This analysis is performed in parallel for each
different lookup table and superstring. This is converted to a parse           function (and cannot be parallelized at the level of instructions).
tree using a variant of depth-first traversal implemented using                Each instruction of a function is visited sequentially and a lifetime
parallel primitives.                                                           mask, which contains a bit indicating availability of every physical
                                                                               register, is updated according to the operands. Physical registers
3.2    Semantic Analysis                                                       are greedily assigned by finding a free register in the lifetime mask.
                                                                               If no free register is available, a register will be selected from a
This stage is implemented as a series of passes that analyze and
                                                                               statically defined set of suitable scratch registers and marked as
manipulate the parse tree. This consists of passes such as extracting
                                                                               a spilled register. The assignment of virtual to physical registers
lexemes to literals, variable resolution, function resolution and type
                                                                               is stored in the virtual register table together with a swap bit that
analysis. The implementation of these passes is facilitated by a
                                                                               identifies if that register needs to be spilled at any point.
set of common operations on the inverted tree data structure. For
                                                                                   After lifetime analysis has completed, stack space is allocated
example, a typical operation is to find the root of certain subtrees.
                                                                               by computing a stack offset table that maps virtual registers to
This operation can be implemented in parallel by applying the
                                                                               integer stack offsets. This computation is performed for all func-
algorithm by Hillis & Steele [9] to find the end of a linked list on
                                                                               tions in parallel using the swap bits from the virtual register table.
each of the nodes simultaneously. When the tree is converted to
an AST, the inverted tree is converted from pre-order to post-order            1 Note that a single node in the AST may result in more than one instruction.




                                                                         233
Compilation On The GPU? A Feasibility Study                                                                     CF’22, May 17–19, 2022, Torino, Italy

       Table 1: Properties of the generated input files.                         Semantic Analysis we observe a factor 6.4 increase in runtime for
                                                                                 a 100x increase in input size. From the sixth input file onwards
          File#       Size     Lines   Functions   AST Nodes                     this nears linear scaling, with a 4.7x increase in runtime for a 4.8x
          1        5.1 KB        121           5         1 211                   increase in input size.
          2        11 KB         209           9         3 211                      The results for the code generation stages are shown in Figure 4b.
          3        99 KB       1 992          80        26 946
                                                                                 Recall that the register allocation and instruction removal stages
          4       500 KB      10 328         412       134 564
          5       1.1 MB      21 939         895       289 082
                                                                                 were merged. The majority of the stages show a scaling similar
          6       9.8 MB     204 649        8387     2 675 153                   to the stages in Figure 4a, but a notable exception is the register
          7        47 MB     971 014      40112     12 872 847                   allocation stage. As discussed in Section 3.5, lifetime analysis must
                                                                                 be performed in parallel for each function, resulting in less paral-
                                                                                 lelism being available to exploit, leading to a significant overhead
Additionally, based on the lifetime mask a table is created that                 compared to the other stages.
contains the number of instructions to be generated for each in-                    In Figure 5 the total runtime of the compiler is shown, excluding
termediate instruction including spill instructions. Subsequently,               data transfer to/from the GPU. The total runtime is dominated by
instructions are removed according to the instruction mask and                   the register allocation stage. Still, a sub-linear scaling is seen, for
spill instructions are inserted. These operations are combined for               instance from the fifth to seventh input file we observe an increase
the sake of performance. New instruction locations are computed                  in runtime of 11.3x against a 44.5x increase in input size. This
and all generated instructions are copied to the final locations in the          signifies that the parallelization of the different stages is effective.
instruction buffer using a parallel scatter. Afterwards, any required               A detailed performance comparison to other approaches is hard
spill instructions are inserted obtaining the stack offsets from the             at this moment. On the one hand, given that we have presented the
stack offset table. With all instructions in place, the virtual register         first compiler fully hosted on the GPU, there is no GPU baseline
numbers in each instruction are resolved to physical registers using             to compare to. A comparison to our compiler generated for the
the virtual register table. As the final step, the function offset table         CPU would not yield a fair comparison as Futhark only generates
is recomputed to account for the removed and inserted instructions,              multi-threaded CPU code, without using SIMD, causing not all
and the target addresses for all jump instructions are corrected. The            available resources to be used. Moreover, all stages were designed
separate buffers containing per-instruction information are merged               with the high memory bandwidth available on GPUs in mind. On
to construct the final instruction buffer.                                       the other hand, a direct comparison to traditional CPU-based com-
                                                                                 pilers would not be fair, as our compiler does not fully handle a
4    EVALUATION                                                                  programming language like C and does not implement all optimiza-
For the purpose of this feasibility study, we are interested in the ef-          tions and instruction selection techniques. For a factual comparison
fectiveness of the parallel algorithms and an indication of the perfor-          the feature set of the GPU compiler must be up to par and also the
mance of the parallel compiler compared to traditional CPU-based                 quality of the produced code must be included in the comparison.
compilation. To investigate the effectiveness, we have performed                    Still, we would like to obtain an initial performance comparison
a number of experiments to determine the scaling characteristics                 to see whether this development is worthwhile. To do so, we have
under increasing input sizes. Given that a custom programming                    translated the custom source files from the above experiments to
language is used in this study, there is no source code available                C source files and measured the runtime of invoking cc -w -c
that represents real-world use cases and translation of real-world               on these files. The experiments were performed on an Intel Core
source code to this language is complicated. Therefore, we have                  i7-8700, using gcc 10.2.0 and Clang 8, and were repeated 10 times.
randomly generated seven source code files that we believe will                  The results are included as dashed lines in Figure 5. The C files are
yield results indicative of the performance on real-world source                 between 19.1% to 21.6% larger compared to the original files. As can
code. The properties of these files are shown in Table 1, all files are          be seen, the CPU-based compilers perform better for small input
syntactically and semantically correct.                                          sizes, because of the overhead encountered by the GPU implemen-
   The experiments were conducted on an NVIDIA GeForce RTX3090                   tation. Once the input sizes get larger, the GPU implementation
GPU, hosted in a machine equipped with dual Intel Xeon Silver                    clearly shows better scaling compared to the CPU compilers. This
4214R processors. The software configuration consists of CentOS 7,               shows that compilation on the GPU can be feasible with reasonable
Linux kernel 5.4.126, Futhark 0.20, CUDA 11.2 and gcc 10.2.0 in re-              performance and that there is the potential to GPU-accelerate the
lease mode (-O3). All runtime measurements are obtained using the                compilation of large input files. Note that there is the potential to
C++ chrono::high_resolution_clock. Care is taken that GPU                        lower the bound on the input file size for GPU compilation to be
and CPU work is synchronized before a timestamp is collected. To                 profitable when register allocation is further optimized.
reduce noise, we repeat every individual experiment 30 times.
   Figure 4a depicts a breakdown of the runtime from parsing up to
the creation of the AST. Almost all stages show similar characteris-             5    DISCUSSION AND FUTURE WORK
tics. Initially, the scaling appears flat, as a relatively large amount          There are many avenues for further work. Most importantly, the
of time is spent launching the kernels and combining the results                 identified performance bottlenecks need to be addressed to further
of the individual shader processors, making the actual processing                increase the potential of GPU compilation. The large overhead
time almost negligible compared to the overhead. From the third                  of register allocation can possibly be alleviated by a redesign to
to the sixth input file we see a sub-linear scaling, for example for             operate on the level of expressions instead of functions. For the




                                                                           234
CF’22, May 17–19, 2022, Torino, Italy                                                                                                                 Robin F. Voetter, Marcel Huijben, and Kristian F. D. Rietveld

                            Lexing                      Parsing                                     Preprocessing       Instr. Count     Instr. Gen
                            Building parse tree         Restructuring                               Optimization        Regalloc         Jump Fix                                    GPU RTX3090
                            Semantic Analysis           Translate AST                               Postprocessing                                                                   gcc 10.2.0 on Core i7-8700
                103                                                                           103                                                                                    clang 8 on Core i7-8700
                                                                                                                                                                              104

                102                                                                           102




                                                                                                                                                               Runtime (ms)
                                                                                              101                                                                             103




                                                                              Runtime (ms)
Runtime (ms)




                101

                                                                                              100
                100
                                                                                                                                                                              102
                                                                                             10−1
               10−1
                                                                                             10−2
                                                                                                                                                                              101
                      104         105             106        107        108                         104       105         106          107        108                               104        105         106        107   108
                                    Input size (bytes)                                                          Input size (bytes)
                                                                                                                                                                                                 Input size (bytes)

                (a) Parsing to semantic analysis.                                                   (b) Code generation.
                                                                                                                                                             Figure 5: Total runtime of the GPU compiler and
Figure 4: Scaling characteristics of the compiler stages for increasing in-                                                                                  an indication of the runtime of traditional CPU
put size.                                                                                                                                                    compilers on similarly sized inputs.


code generation algorithms, only nodes at the same depth may be                                                                          run function-local analysis and optimization stages on multiple
processed in parallel, limiting the degree of parallelism. By splitting                                                                  CPU cores. Although a reasonable speedup is achieved, this only
the assignment of virtual registers out of the instruction generation                                                                    concerns a small part of the overall compilation process and the
step, it will become possible to execute nodes at different levels of                                                                    remainder is still single-threaded. CuLi is capable of executing a
the tree. These improvements will lead to a lower bound on the                                                                           runtime environment for the Lisp programming language on GPUs
input size for GPU compilation to be profitable.                                                                                         by recursively evaluating the AST [17]. Contrary to our work, stages
   Besides performance improvements, work is needed on feature                                                                           other than evaluation, such as parsing, are performed on the CPU.
completeness. More research into parallel parsing techniques is                                                                             Hsu describes the implementation of an APL to C++ compiler,
required to shrink the number of restrictions posed on input gram-                                                                       which is completely hosted on the GPU, focusing on tree transfor-
mars, to efficiently support the syntax of traditional languages. Also                                                                   mations performed by a compiler after parsing and before code
more complicated type systems should be supported. With regard                                                                           generation [10]. This can be compared to the semantic analysis
to code generation, work is to be done on basic block detection,                                                                         stage of our work. The inverted tree data structure follows a similar
implementation of different optimizations and an evaluation of the                                                                       approach, but in our case a post-order storage is used and the tree
quality of the produced code. Finally, we would like to evaluate our                                                                     traversal routines are partly based on [9]. Furthermore, contrary to
approach on many-core SIMD CPUs to determine whether this is                                                                             Hsu, we present a full compiler hosted on the GPU and we describe
worthwhile and what changes would be required for instance due                                                                           solutions for the challenges of parallel parsing and parallel code
to the limited memory bandwidth that is available.                                                                                       generation, including register allocation.
                                                                                                                                            Our prototype was developed in Futhark and differs from prior
6               RELATED WORK                                                                                                             work on writing compilers in functional programming languages [4,
                                                                                                                                         12]. Earlier work involves the use of language constructs, such as
Parallel compilation received considerable interest in the 1980’s and
                                                                                                                                         conditional branches, and data structures, such as lists into which
1990’s, due to the development of parallel architectures such as the
                                                                                                                                         elements are inserted repeatedly, that perform poorly on GPU ar-
Connection Machine [8]. A good overview of the state-of-the-art
                                                                                                                                         chitectures. Instead, we make extensive use of array-based data
in parallel compilation at that time, with a focus on parallel lexical
                                                                                                                                         structures and parallel primitives.
and syntactical analysis, is given in [16]. In [11] an implementation
of a parallel assembler is described, but this paper does not consider
the transformation of an AST into assembly code. To the best of
our knowledge, a fully parallel compiler, as described in our paper,                                                                         7   CONCLUSIONS
was not realized at that time.                                                                                                           We have described the first design and implementation of a parallel
   During the same time, parallel lexical analysis and parsing was                                                                       compiler that is fully executed on a GPU, demonstrating that it is
investigated [7, 9, 15], where the focus was on the application of                                                                       feasible to implement all stages in a fine-grained parallel manner.
parallel prefix sum to simulate deterministic finite state machines.                                                                     The experimental evaluation showed the parallelization of all stages
More recent work considered an implementation of SIMD hard-                                                                              to be effective, although the total runtime is dominated by the reg-
ware [13], CPU multicores [2] and methods to reduce the memory                                                                           ister allocation stage. Compilation on the GPU can be done with
overhead [14]. A deterministic parallel parsing algorithm and the                                                                        reasonable performance, and in fact for large input files better scal-
LLP(q, k) grammar class was proposed by Vagner & Melcihar [20],                                                                          ing compared to traditional CPU-based compilers is already seen.
which we have implemented as part of our compiler.                                                                                       We argue that compilation on the GPU is feasible and potentially
   More recently, parallel compilation received renewed interest.                                                                        worthwhile, and have proposed a number of avenues for future
The Parallel GCC project [3] modifies the GNU C Compiler to                                                                              work hoping to further revitalize research into parallel compilation.




                                                                                                                                 235
Compilation On The GPU? A Feasibility Study                                                                                        CF’22, May 17–19, 2022, Torino, Italy


REFERENCES                                                                                   [11] Howard P. Katseff. 1988. Using Data Partitioning to Implement a Parallel Assem-
 [1] Ilan Bar-On and Uzi Vishkin. 1985. Optimal parallel generation of a computation              bler. SIGPLAN Not. 23, 9 (Jan. 1988), 66–76. https://doi.org/10.1145/62116.62123
     tree form. ACM Transactions on Programming Languages and Systems (TOPLAS)               [12] Andrew W. Keep and R. Kent Dybvig. 2013. A Nanopass Framework for Com-
     7, 2 (1985), 348–357.                                                                        mercial Compiler Development. SIGPLAN Not. 48, 9 (Sept. 2013), 343–350.
 [2] Alessandro Barenghi, Stefano Crespi Reghizzi, Dino Mandrioli, Federica Panella,              https://doi.org/10.1145/2544174.2500618
     and Matteo Pradella. 2015. Parallel parsing made practical. Science of Computer         [13] Todd Mytkowicz, Madanlal Musuvathi, and Wolfram Schulte. 2014. Data-parallel
     Programming 112 (2015), 195–226.                                                             finite-state machines. In Proceedings of the 19th international conference on Archi-
 [3] GNU Contributors. 2019. ParallelGcc. https://gcc.gnu.org/wiki/ParallelGcc                    tectural support for programming languages and operating systems. 529–542.
 [4] Abdulaziz Ghuloum. 2006. An incremental approach to compiler construction. In           [14] Ryoma Sinya, Kiminori Matsuzaki, and Masataka Sassa. 2013. Simultaneous finite
     Proceedings of the 2006 Scheme and Functional Programming Workshop, Portland,                automata: An efficient data-parallel model for regular expression matching. In
     OR. Citeseer. Citeseer.                                                                      2013 42nd International Conference on Parallel Processing. IEEE, 220–229.
 [5] Andre Vincent Pascal Grosset, Peihong Zhu, Shusen Liu, Suresh Venkatasubra-             [15] David B Skillicorn and David T Barnard. 1989. Parallel parsing on the connection
     manian, and Mary Hall. 2011. Evaluating graph coloring on GPUs. In Proceedings               machine. Inform. Process. Lett. 31, 3 (1989), 111–117.
     of the 16th ACM symposium on Principles and practice of parallel programming.           [16] David B. Skillicorn and David T. Barnard. 1993. Compiling in parallel. J. Parallel
     297–298.                                                                                     and Distrib. Comput. 17, 4 (1993), 337–352.
 [6] Troels Henriksen, Niels GW Serup, Martin Elsman, Fritz Henglein, and Cosmin E           [17] Tim Süß, Nils Döring, André Brinkmann, and Lars Nagel. 2018. And now for
     Oancea. 2017. Futhark: purely functional GPU-programming with nested par-                    something completely different: running Lisp on GPUs. In 2018 IEEE International
     allelism and in-place array updates. In Proceedings of the 38th ACM SIGPLAN                  Conference on Cluster Computing (CLUSTER). IEEE, 434–444.
     Conference on Programming Language Design and Implementation. 556–571.                  [18] Herb Sutter and James Larus. 2005. Software and the Concurrency Revolution:
 [7] Jonathan MD Hill. 1992. Parallel lexical analysis and parsing on the AMT dis-                Leveraging the full power of multicore processors demands new tools and new
     tributed array processor. Parallel computing 18, 6 (1992), 699–714.                          thinking from the software industry. Queue 3, 7 (2005), 54–62.
 [8] W Daniel Hillis. 1989. The connection machine. MIT press.                               [19] Rui Ueyama. 2021. mold: A Modern Linker. https://github.com/rui314/mold/
 [9] W Daniel Hillis and Guy L Steele Jr. 1986. Data parallel algorithms. Commun.                 blob/main/README.md
     ACM 29, 12 (1986), 1170–1183.                                                           [20] Ladislav Vagner and Bořivoj Melichar. 2007. Parallel LL parsing. Acta informatica
[10] Aaron Wen-yao Hsu. 2019. A data parallel compiler hosted on the gpu. Ph.D.                   44, 1 (2007), 1–21.
     Dissertation. Indiana University.




                                                                                       236
