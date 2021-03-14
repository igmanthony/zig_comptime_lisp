const print = @import("std").debug.print;

const parse = @import("parse.zig");
const eval = @import("eval.zig");
const types = @import("types.zig");

pub const script = @embedFile("script.l");
const result = comptime eval.evalProgram(parse.abstract_syntax_tree);

pub fn main() !void {
    print("{s}\n", .{parse.tokens});
    debugList(try result);
}

/// These debug functions are useful for printing out the results
/// of the linked list/nested structure that I'm using
pub fn debugList(res: types.AtomList) void {
    debugNode(res.first.?);
}

pub fn debugNode(node: *types.AtomList.Node) void {
    if (node.next) |next| debugNode(next);
    debugAtom(node.data);
}

pub fn debugAtom(atom: types.Atom) void {
    switch (atom) {
        .number => print("number: {}\n", .{atom.number}),
        .list => debugList(atom.list),
        .function => debugFn(atom),
        .keyword => {},
    }
}

pub fn debugFn(atom: types.Atom) void {
    const func = atom.function;
    debugList(func.args);
    debugList(func.body);
}
