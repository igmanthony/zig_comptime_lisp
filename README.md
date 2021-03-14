# Zig comptime lisp

This is a toy lisp following in the steps of a ["Make A Lisp"](https://github.com/kanaka/mal) or "MAL". However, unlike other "Make A Lisps" this one is implemented entirely in compiletime Zig code. This makes it much less useful (no I/O other than compiletime loading of strings or embedded files and output to the Zig language). However, it does generate executables! :D

"script.l" is a file with the toy lisp language that gets pulled, parsed, and evaluated at compiletime through Zig's @embedFile command. Recursion, loops, most arithematic, comments, and most anything useful isn't implemented, but you can use "if" and define functions and variables and do some basic arithmatic.

I likely won't ever touch this repository again, as it's a fun toy but I wanted to see if I could get the proof-of-concept of a MAL working, which I think I have. This is working with Zig version zig-windows-x86_64-0.8.0-dev.1369+45d220cac.

