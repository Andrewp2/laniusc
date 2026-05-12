This compiler is intended to be ran entirely on the GPU end-to-end. Do not add any CPU fallback or any pass on the CPU.
That means lexing, parsing, type checking, intermediate representations, optimizations, register allocation, and binary emission should all occur on the GPU.

When testing, run the shortest timeout that catches the problem. This compiler is expected to compile 100kloc in less than a single second, and GPU setup 
only takes a couple of seconds, so you should try to keep your timeouts below 10 seconds.

Building a compiler that runs on the GPU is very hard. You will not be able to invent the methods that are used to make it work from scratch. Instead, you should defer to the papers - the papers are in /docs , they are the pdfs, there are also markdown versions of them.
