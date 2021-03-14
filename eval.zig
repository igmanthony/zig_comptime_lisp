const std = @import("std");
// const // print = std.debug.// print;
const memEql = std.mem.eql;
const stringToEnum = std.meta.stringToEnum;
const types = @import("types.zig");
const parse = @import("parse.zig");
const Atom = types.Atom;
const AtomList = types.AtomList;
const Variable = types.Variable;
const VarList = types.VarList;
const Value = types.Value;
const SpecialForms = types.SpecialForms;
const Func = types.Func;
const Function = types.Function;
const SyntaxErrors = types.SyntaxErrors;

/// Addition; some dummy functions to play with -> add takes 2 params (order independant)
pub fn add(l: Atom, r: Atom) Atom {
    return Atom{ .number = l.number + r.number };
}

/// Division; order dependant
pub fn sub(l: Atom, r: Atom) Atom {
    return Atom{ .number = l.number - r.number };
}

/// Negation; neg takes 1 param
pub fn neg(l: Atom) Atom {
    return Atom{ .number = -l.number };
}

pub fn less(l: Atom, r: Atom) Atom {
    return Atom{ .number = if (l.number < r.number) 1.0 else 0 };
}

pub const Env = struct {
    outer: ?*Env,
    varlist: VarList,

    pub fn copy(self: *const Env) Env {
        return Env{ .outer = self.outer, .varlist = self.varlist };
    }

    pub fn push(self: *Env, symbol: []const u8, value: Value) void {
        var node = VarList.Node{ .data = Variable{ .name = symbol, .value = value } };
        self.varlist.prepend(&node);
    }

    pub fn find(self: *const Env, symbol: []const u8) ?*const Env {
        var it = self.varlist.first;
        while (it) |node| : (it = node.next) {
            if (memEql(u8, node.data.name, symbol)) return self;
        }
        return if (self.outer) |outer_node| outer_node.find(symbol) else null;
    }

    pub fn get(self: *const Env, symbol: []const u8) !Value {
        if (self.find(symbol)) |env| {
            var it = env.varlist.first;
            while (it) |node| : (it = node.next) {
                if (memEql(u8, node.data.name, symbol)) return node.data.value;
            }
            return error.KeyDisappearedAfterFinding;
        } else {
            return error.CannotFindKeyInEnvs;
        }
    }

    pub fn addArgs(self: *Env, names: AtomList, values: AtomList) SyntaxErrors!void {
        if (names.len() != values.len()) return error.UserFunctionParameterArgumentLengthMismatch;
        comptime var i = 0;
        var name = names.first;
        var value = values.first;
        while (name) |nameNode| : (name = nameNode.next) {
            if (value) |valueNode| {
                self.push(nameNode.data.keyword, Value{ .atom = valueNode.data });
                value = valueNode.next; // the same as name = nameNode.next on continuation
            }
        }
    }
};

pub fn evalProgram(comptime ast: AtomList) SyntaxErrors!AtomList {
    var corelist = VarList{};
    const functions = [_]Variable{
        Variable{ .name = "add", .value = Value{ .func = Func{ .funcTwo = &add } } },
        Variable{ .name = "sub", .value = Value{ .func = Func{ .funcTwo = &sub } } },
        Variable{ .name = "less", .value = Value{ .func = Func{ .funcTwo = &less } } },
    };

    for (functions) |function| {
        var func = VarList.Node{ .data = function };
        corelist.prepend(&func);
    }
    var global_env = Env{ .outer = null, .varlist = corelist };

    var results = AtomList{};
    var it = ast.first;
    while (it) |node| : (it = node.next) {
        const evaluation = try comptime eval(node.data, &global_env);
        var new_node = AtomList.Node{ .data = evaluation };
        if (results.len() >= 1) {
            results.first.?.findLast().insertAfter(&new_node); // front to back growth
        } else {
            results.prepend(&new_node);
        }
    }
    return results;
}

pub fn eval(x: Atom, env: *Env) SyntaxErrors!Atom {
    @setEvalBranchQuota(1_000_000);
    return switch (x) {
        .number => x, // number evaluates to itself
        .keyword => (try env.get(x.keyword)).atom, // non function keywords
        .function => error.NoFunctionShouldBeHere, // we shouldn't see a bare function
        .list => blk: {
            if (x.list.len() == 0) break :blk x; // list is empty, return emptylist
            const node = comptime x.list.first.?;
            const data = comptime node.data;
            const next = comptime node.next;
            if (data != .keyword) break :blk eval(comptime data, comptime env); // evaluate it if not a kwd
            if (next == null) break :blk (try env.get(data.keyword)).atom; // if its termina, find it (variable)
            if (stringToEnum(comptime SpecialForms, data.keyword)) |special_form| { // special form
                break :blk switch (special_form) {
                    .def => handleDefSpecialForm(next.?, env),
                    .@"if" => handleIfSpecialForm(next.?, env),
                    .@"fn" => handleFnSpecialForm(next.?, env),
                };
            } else { // function that's not a special form
                break :blk handleFunction(node, env);
            }
        },
    };
}

/// No bool values, like the cool kids
pub fn handleIfSpecialForm(conditional: *types.AtomList.Node, env: *Env) SyntaxErrors!Atom {
    const evaluated_condition = try eval(conditional.data, env);
    const is_true = switch (evaluated_condition) {
        .number => if (evaluated_condition.number == 0.0) false else true, // only 0.0 is false!
        else => true,
    };
    const first = conditional.next.?.data; // first branch if true
    const second = conditional.next.?.next.?.data; // take second branch if false
    return if (is_true) try eval(first, env) else try eval(second, env);
}

/// Define variables and functions
pub fn handleDefSpecialForm(variable_name_node: *types.AtomList.Node, env: *Env) SyntaxErrors!Atom {
    const value_node = variable_name_node.next orelse return error.NoDefinedValue;
    const atom = try eval(value_node.data, env);
    const value = switch (atom) {
        .function => Value{ .func = Func{ .funcUser = atom.function } },
        else => Value{ .atom = atom },
    };
    env.push(variable_name_node.data.keyword, value);
    return atom;
}

// build arg and body lists for function
pub fn handleFnSpecialForm(args: *types.AtomList.Node, env: *Env) SyntaxErrors!Atom {
    var arg = AtomList{};
    var argnode = AtomList.Node{ .data = args.data };
    arg.prepend(&argnode);
    var bod = AtomList{};
    if (args.next) |body| bod.prepend(body);
    var new_env = env.copy();
    var func_data = Function{ .args = arg, .body = bod, .env = &new_env };
    return Atom{ .function = &func_data };
}

pub fn handleFunction(topnode: *types.AtomList.Node, env: *Env) SyntaxErrors!Atom {
    const next = topnode.next.?;
    var copy = AtomList.Node{ .data = try eval(next.data, env) };
    var args = AtomList{};
    args.prepend(&copy);
    var it = next.next;
    while (it) |node| : (it = node.next) { // traverse any other args
        var new_node = AtomList.Node{ .data = try eval(node.data, env) };
        copy.insertAfter(&new_node); // append
    }
    const val = (try env.get(topnode.data.keyword));
    switch (val) {
        .func => return try applyFunction(val.func, args),
        .atom => return val.atom,
    }
    return (try env.get(topnode.data.keyword)).atom;
}

pub fn applyFunction(func: Func, args: AtomList) !Atom {
    return switch (func) {
        .funcZero => func.funcZero.*(),
        .funcOne => func.funcOne.*(args.first.?.data),
        .funcTwo => func.funcTwo.*(args.first.?.data, args.first.?.next.?.data),
        .funcUser => blk: {
            const n = func.funcUser.args.first.?.data;
            var new_env = Env{ .outer = func.funcUser.env, .varlist = VarList{} };
            switch (func.funcUser.args.first.?.data) {
                .list => {
                    const names = Atom{ .list = n.list };
                    try new_env.addArgs(names.list, args);
                },
                .keyword => {
                    const names = Atom{ .keyword = n.keyword };
                    var list = AtomList{};
                    var node = AtomList.Node{ .data = names };
                    list.prepend(&node);
                    try new_env.addArgs(list, args);
                },
                else => return error.SomethingFellThroughTheEvalCracks,
            }
            break :blk try eval(Atom{ .list = func.funcUser.body }, &new_env);
        },
    };
}
