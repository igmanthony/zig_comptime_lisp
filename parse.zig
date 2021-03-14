const script = @import("main.zig").script;

const types = @import("types.zig");
const Atom = types.Atom;
const AtomList = types.AtomList;
const SyntaxErrors = types.SyntaxErrors;

const parseFloat = @import("std").fmt.parseFloat;

// I'd prefer this all to be in a function, but I couldn't figure out how to give the tokenize
// function the size of the needed token-array without having an external/global variable for it
// I guess I should do a double-pass? - read to count then make?
pub const token_count = comptime countTokens(script);
pub const tokens = comptime tokenize(script, token_count);
pub const abstract_syntax_tree = try comptime parse();

pub fn countTokens(comptime buf: []const u8) usize {
    var num = 0;
    var last = ' ';
    for (buf) |char| {
        num += switch (char) {
            '(', ')' => 1,
            ' ', '\n' => 0,
            else => if (isSplitByte(last)) 1 else 0,
        };
        last = char;
    }
    return num;
}

pub fn tokenize(comptime buf: []const u8, size: usize) [size][]const u8 {
    var token_array: [size][]const u8 = undefined;
    var index: usize = 0;
    var token_iter = TokenIterator{ .index = 0, .buf = buf };
    while (token_iter.next()) |token| : (index += 1) {
        token_array[index] = token;
    }
    return token_array;
}

const TokenIterator = struct {
    buf: []const u8,
    index: usize,
    pub fn next(self: *TokenIterator) ?[]const u8 {
        // move to beginning of token
        while (self.index < self.buf.len and isSkipByte(self.buf[self.index])) : (self.index += 1) {}
        const start = self.index;
        if (start == self.buf.len) return null;
        if (self.buf[start] == '(' or self.buf[start] == ')') {
            self.index += 1;
            return self.buf[start .. start + 1];
        }

        // move to end of token
        while (self.index < self.buf.len and !isSplitByte(self.buf[self.index])) : (self.index += 1) {}
        const end = self.index;
        return self.buf[start..end];
    }
};

fn isSkipByte(byte: u8) bool {
    return byte == ' ' or byte == '\n';
}

fn isSplitByte(byte: u8) bool {
    @setEvalBranchQuota(1_000_000); // use this as needed to stop compiler quitting on the job!
    return byte == ' ' or byte == ')' or byte == '(' or byte == '\n';
}

/// takes in the current index and accesses the globals 'token_count' and 'tokens'; ideally these
/// would be in a struct or something.. but I wasn't sure how to do that with the recursion
/// neither of these globals are (or probably can be) modified/altered
fn parse() SyntaxErrors!AtomList {
    comptime var list = AtomList{};
    comptime var index: comptime_int = 0;
    while (index < token_count) {
        comptime var atom_index = try comptime nextBlock(index);
        comptime var node = AtomList.Node{ .data = atom_index.atom };
        if (index == 0) {
            list.prepend(&node);
        } else {
            list.first.?.findLast().insertAfter(&node);
        }
        index = atom_index.index;
    }
    return list;
}

fn nextBlock(comptime current_index: comptime_int) SyntaxErrors!AtomIndex {
    @setEvalBranchQuota(1_000_000);
    var index = current_index;
    if (index == token_count) return error.IndexEqualTokenCount;
    if (popToken(index)) |token_index| { // poptoken just increments a counter and returns a char
        const token = token_index.token;
        index = token_index.index;
        if (token[0] == '(') { // we're starting a new expression
            var list = AtomList{};
            while (popToken(index)) |next_token_index| {
                const next_token = next_token_index.token; // extract the token
                index = next_token_index.index; // update the index
                if (next_token[0] == ')') break; // we've reached the end of a 'list'

                // index - 1 fixes an off-by-one error (I can't figure out why exactly)
                var next_atom_index = try nextBlock(index - 1); // recurse in case of other expressions
                index = next_atom_index.index; // update the index yet again after recursion
                var list_node = AtomList.Node{ .data = next_atom_index.atom };
                if (list.len() >= 1) {
                    list.first.?.findLast().insertAfter(&list_node); // front to back growth
                } else {
                    list.prepend(&list_node); // if it's the first in the list we'll just add it
                }
            }
            return AtomIndex{ .atom = Atom{ .list = list }, .index = index }; // we got the expression
        } else if (token[0] == ')') {
            return error.FoundRParensInParse; // mismatched parens
        } else {
            return AtomIndex{ .atom = atomize(token), .index = index };
        }
    } else {
        return error.EndOfTokenList; // we shouldn't reach end of tokens here
    }
    return error.ParsingUnreachable; // makes the comptime happy
}

/// somewhat eagerly increments counters
fn popToken(index: usize) ?TokenIndex {
    return if (token_count == index) null else TokenIndex{ .index = index + 1, .token = tokens[index] };
}

pub fn atomize(token: []const u8) Atom {
    return if (parseNumber(token)) |t| t else Atom{ .keyword = token };
}

fn parseNumber(token: []const u8) ?Atom {
    return if (parseFloat(f64, token)) |t| Atom{ .number = t } else |err| null;
}

/// these seem like silly things - but I can't figure out how to return the index without them...
pub const AtomIndex = struct {
    atom: Atom,
    index: comptime_int,
};

pub const TokenIndex = struct {
    token: []const u8,
    index: comptime_int,
};
