const std = @import("std");
const eval = @import("eval.zig");
const Env = eval.Env;

const SinglyLinkedList = std.SinglyLinkedList;
pub const AtomList = SinglyLinkedList(Atom);
pub const VarList = SinglyLinkedList(Variable);

pub const SpecialForms = enum {
    def,
    @"if",
    @"fn",
};

// errors rock with comptime... partly because print debugging isn't very helpful :)
pub const SyntaxErrors = error{
    InvalidParseToken,
    FoundRParensInParse,
    EndOfTokenList,
    ParsingUnreachable,
    NoFunctionFound,
    CannotApplyFunction,
    IndexEqualTokenCount,
    CannotFindKeyInEnvs,
    UserFunctionParameterArgumentLengthMismatch,
    InvalidFunctionArgsOrBody,
    NoDefKeyword,
    NoDefinedValue,
    NoFunctionShouldBeHere,
    SomethingFellThroughTheEvalCracks,
    KeyDisappearedAfterFinding,
};

pub const Variable = struct {
    name: []const u8,
    value: Value,
};

pub const Value = union(enum) {
    atom: Atom,
    func: Func,
};

/// this is a bad name for what it represents... I'm just not sure what's better... "Type" seems
/// worse. This is the "basetype" (too long of a name) for this toy language
pub const Atom = union(enum) {
    number: f64,
    list: AtomList,
    keyword: []const u8,
    function: *const Function,
};

/// Union of function pointer types with different numbers of input parameters. Not sure of a better
/// way to do this -> I took inspiration from the MAL implementation on:
/// github.com/kanaka/mal/tree/master/impls/zig
/// also, func can't be an atom, as it would depend on atom
pub const Func = union(enum) {
    funcZero: *const fn () Atom,
    funcOne: *const fn (first: Atom) Atom,
    funcTwo: *const fn (first: Atom, second: Atom) Atom,
    funcUser: *const Function,
};

pub const Function = struct {
    args: AtomList,
    body: AtomList,
    env: *Env,
};
