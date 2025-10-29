const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");

/// A managed variable length collection of characters
pub const StringManaged = struct {
    /// The internal character buffer
    buffer: ?[]u8,
    /// The allocator used for managing the buffer
    allocator: std.mem.Allocator,
    /// The total size of the String
    size: usize,

    /// Errors that may occur when using String
    pub const Error = error{
        OutOfMemory,
        InvalidRange,
    };

    /// Creates a String with an Allocator
    /// ### example
    /// ```zig
    /// var str = String.init(allocator);
    /// // don't forget to deallocate
    /// defer _ = str.deinit();
    /// ```
    /// User is responsible for managing the new String
    pub fn init(allocator: std.mem.Allocator) StringManaged {
        // for windows non-ascii characters
        // check if the system is windows
        if (builtin.os.tag == std.Target.Os.Tag.windows) {
            _ = std.os.windows.kernel32.SetConsoleOutputCP(65001);
        }

        return .{
            .buffer = null,
            .allocator = allocator,
            .size = 0,
        };
    }

    pub fn init_with_contents(allocator: std.mem.Allocator, contents: []const u8) Error!StringManaged {
        var string = init(allocator);

        try string.concat(contents);

        return string;
    }

    /// Deallocates the internal buffer
    /// ### usage:
    /// ```zig
    /// var str = String.init(allocator);
    /// // deinit after the closure
    /// defer _ = str.deinit();
    /// ```
    pub fn deinit(self: *StringManaged) void {
        if (self.buffer) |buffer| self.allocator.free(buffer);
    }

    /// Returns the size of the internal buffer
    pub fn capacity(self: StringManaged) usize {
        if (self.buffer) |buffer| return buffer.len;
        return 0;
    }

    /// Allocates space for the internal buffer
    pub fn allocate(self: *StringManaged, bytes: usize) Error!void {
        if (self.buffer) |buffer| {
            if (bytes < self.size) self.size = bytes; // Clamp size to capacity
            self.buffer = self.allocator.realloc(buffer, bytes) catch {
                return Error.OutOfMemory;
            };
        } else {
            self.buffer = self.allocator.alloc(u8, bytes) catch {
                return Error.OutOfMemory;
            };
        }
    }

    /// Reallocates the the internal buffer to size
    pub fn truncate(self: *StringManaged) Error!void {
        try self.allocate(self.size);
    }

    /// Appends a character onto the end of the String
    pub fn concat(self: *StringManaged, char: []const u8) Error!void {
        try self.insert(char, self.len());
    }

    /// Inserts a string literal into the String at an index
    pub fn insert(self: *StringManaged, literal: []const u8, index: usize) Error!void {
        // Make sure buffer has enough space
        if (self.buffer) |buffer| {
            if (self.size + literal.len > buffer.len) {
                try self.allocate((self.size + literal.len) * 2);
            }
        } else {
            try self.allocate((literal.len) * 2);
        }

        const buffer = self.buffer.?;

        // If the index is >= len, then simply push to the end.
        // If not, then copy contents over and insert literal.
        if (index == self.len()) {
            var i: usize = 0;
            while (i < literal.len) : (i += 1) {
                buffer[self.size + i] = literal[i];
            }
        } else {
            if (StringManaged.getIndex(buffer, index, true)) |k| {
                // Move existing contents over
                var i: usize = buffer.len - 1;
                while (i >= k) : (i -= 1) {
                    if (i + literal.len < buffer.len) {
                        buffer[i + literal.len] = buffer[i];
                    }

                    if (i == 0) break;
                }

                i = 0;
                while (i < literal.len) : (i += 1) {
                    buffer[index + i] = literal[i];
                }
            }
        }

        self.size += literal.len;
    }

    /// Removes the last character from the String
    pub fn pop(self: *StringManaged) ?[]const u8 {
        if (self.size == 0) return null;

        if (self.buffer) |buffer| {
            var i: usize = 0;
            while (i < self.size) {
                const size = StringManaged.getUTF8Size(buffer[i]);
                if (i + size >= self.size) break;
                i += size;
            }

            const ret = buffer[i..self.size];
            self.size -= (self.size - i);
            return ret;
        }

        return null;
    }

    /// Compares this String with a string literal
    pub fn cmp(self: StringManaged, literal: []const u8) bool {
        if (self.buffer) |buffer| {
            return std.mem.eql(u8, buffer[0..self.size], literal);
        }
        return false;
    }

    /// Returns the String buffer as a string literal
    /// ### usage:
    ///```zig
    ///var mystr = try String.init_with_contents(allocator, "Test String!");
    ///defer _ = mystr.deinit();
    ///std.debug.print("{s}\n", .{mystr.str()});
    ///```
    pub fn str(self: StringManaged) []const u8 {
        if (self.buffer) |buffer| return buffer[0..self.size];
        return "";
    }

    /// Returns an owned slice of this string
    pub fn toOwned(self: StringManaged) Error!?[]u8 {
        if (self.buffer != null) {
            const string = self.str();
            if (self.allocator.alloc(u8, string.len)) |newStr| {
                std.mem.copyForwards(u8, newStr, string);
                return newStr;
            } else |_| {
                return Error.OutOfMemory;
            }
        }

        return null;
    }

    /// Returns a character at the specified index
    pub fn charAt(self: StringManaged, index: usize) ?[]const u8 {
        if (self.buffer) |buffer| {
            if (StringManaged.getIndex(buffer, index, true)) |i| {
                const size = StringManaged.getUTF8Size(buffer[i]);
                return buffer[i..(i + size)];
            }
        }
        return null;
    }

    /// Returns amount of characters in the String
    pub fn len(self: StringManaged) usize {
        if (self.buffer) |buffer| {
            var length: usize = 0;
            var i: usize = 0;

            while (i < self.size) {
                i += StringManaged.getUTF8Size(buffer[i]);
                length += 1;
            }

            return length;
        } else {
            return 0;
        }
    }

    /// Finds the first occurrence of the string literal
    pub fn find(self: StringManaged, literal: []const u8) ?usize {
        if (self.buffer) |buffer| {
            const index = std.mem.indexOf(u8, buffer[0..self.size], literal);
            if (index) |i| {
                return StringManaged.getIndex(buffer, i, false);
            }
        }

        return null;
    }

    /// Finds the last occurrence of the string literal
    pub fn rfind(self: StringManaged, literal: []const u8) ?usize {
        if (self.buffer) |buffer| {
            const index = std.mem.lastIndexOf(u8, buffer[0..self.size], literal);
            if (index) |i| {
                return StringManaged.getIndex(buffer, i, false);
            }
        }

        return null;
    }

    /// Removes a character at the specified index
    pub fn remove(self: *StringManaged, index: usize) Error!void {
        try self.removeRange(index, index + 1);
    }

    /// Removes a range of character from the String
    /// Start (inclusive) - End (Exclusive)
    pub fn removeRange(self: *StringManaged, start: usize, end: usize) Error!void {
        const length = self.len();
        if (end < start or end > length) return Error.InvalidRange;

        if (self.buffer) |buffer| {
            const rStart = StringManaged.getIndex(buffer, start, true).?;
            const rEnd = StringManaged.getIndex(buffer, end, true).?;
            const difference = rEnd - rStart;

            var i: usize = rEnd;
            while (i < self.size) : (i += 1) {
                buffer[i - difference] = buffer[i];
            }

            self.size -= difference;
        }
    }

    /// Trims all whitelist characters at the start of the String.
    pub fn trimStart(self: *StringManaged, whitelist: []const u8) void {
        if (self.buffer) |buffer| {
            var i: usize = 0;
            while (i < self.size) : (i += 1) {
                const size = StringManaged.getUTF8Size(buffer[i]);
                if (size > 1 or !inWhitelist(buffer[i], whitelist)) break;
            }

            if (StringManaged.getIndex(buffer, i, false)) |k| {
                self.removeRange(0, k) catch {};
            }
        }
    }

    /// Trims all whitelist characters at the end of the String.
    pub fn trimEnd(self: *StringManaged, whitelist: []const u8) void {
        self.reverse();
        self.trimStart(whitelist);
        self.reverse();
    }

    /// Trims all whitelist characters from both ends of the String
    pub fn trim(self: *StringManaged, whitelist: []const u8) void {
        self.trimStart(whitelist);
        self.trimEnd(whitelist);
    }

    /// Copies this String into a new one
    /// User is responsible for managing the new String
    pub fn clone(self: StringManaged) Error!StringManaged {
        var newString = StringManaged.init(self.allocator);
        try newString.concat(self.str());
        return newString;
    }

    /// Reverses the characters in this String
    pub fn reverse(self: *StringManaged) void {
        if (self.buffer) |buffer| {
            var i: usize = 0;
            while (i < self.size) {
                const size = StringManaged.getUTF8Size(buffer[i]);
                if (size > 1) std.mem.reverse(u8, buffer[i..(i + size)]);
                i += size;
            }

            std.mem.reverse(u8, buffer[0..self.size]);
        }
    }

    /// Repeats this String n times
    pub fn repeat(self: *StringManaged, n: usize) Error!void {
        try self.allocate(self.size * (n + 1));
        if (self.buffer) |buffer| {
            for (1..n + 1) |i| {
                std.mem.copyForwards(u8, buffer[self.size * i ..], buffer[0..self.size]);
            }

            self.size *= (n + 1);
        }
    }

    /// Checks the String is empty
    pub inline fn isEmpty(self: StringManaged) bool {
        return self.size == 0;
    }

    /// Splits the String into a slice, based on a delimiter and an index
    pub fn split(self: *const StringManaged, delimiters: []const u8, index: usize) ?[]const u8 {
        if (self.buffer) |buffer| {
            var i: usize = 0;
            var block: usize = 0;
            var start: usize = 0;

            while (i < self.size) {
                const size = StringManaged.getUTF8Size(buffer[i]);
                if (size == delimiters.len) {
                    if (std.mem.eql(u8, delimiters, buffer[i..(i + size)])) {
                        if (block == index) return buffer[start..i];
                        start = i + size;
                        block += 1;
                    }
                }

                i += size;
            }

            if (i >= self.size - 1 and block == index) {
                return buffer[start..self.size];
            }
        }

        return null;
    }

    /// Splits the String into slices, based on a delimiter.
    pub fn splitAll(self: *const StringManaged, delimiters: []const u8) ![][]const u8 {
        var splitArr = std.array_list.Managed([]const u8).init(std.heap.page_allocator);
        defer splitArr.deinit();

        var i: usize = 0;
        while (self.split(delimiters, i)) |slice| : (i += 1) {
            try splitArr.append(slice);
        }

        return try splitArr.toOwnedSlice();
    }

    /// Splits the String into a new string, based on delimiters and an index
    /// The user of this function is in charge of the memory of the new String.
    pub fn splitToString(self: *const StringManaged, delimiters: []const u8, index: usize) Error!?StringManaged {
        if (self.split(delimiters, index)) |block| {
            var string = StringManaged.init(self.allocator);
            try string.concat(block);
            return string;
        }

        return null;
    }

    /// Splits the String into a slice of new Strings, based on delimiters.
    /// The user of this function is in charge of the memory of the new Strings.
    pub fn splitAllToStrings(self: *const StringManaged, delimiters: []const u8) ![]StringManaged {
        var splitArr = std.array_list.Managed(StringManaged).init(std.heap.page_allocator);
        defer splitArr.deinit();

        var i: usize = 0;
        while (try self.splitToString(delimiters, i)) |splitStr| : (i += 1) {
            try splitArr.append(splitStr);
        }

        return try splitArr.toOwnedSlice();
    }

    /// Splits the String into a slice of Strings by new line (\r\n or \n).
    pub fn lines(self: *StringManaged) ![]StringManaged {
        var lineArr = std.array_list.Managed(StringManaged).init(std.heap.page_allocator);
        defer lineArr.deinit();

        var selfClone = try self.clone();
        defer selfClone.deinit();

        _ = try selfClone.replace("\r\n", "\n");

        return try selfClone.splitAllToStrings("\n");
    }

    /// Clears the contents of the String but leaves the capacity
    pub fn clear(self: *StringManaged) void {
        if (self.buffer) |buffer| {
            for (buffer) |*ch| ch.* = 0;
            self.size = 0;
        }
    }

    /// Converts all (ASCII) uppercase letters to lowercase
    pub fn toLowercase(self: *StringManaged) void {
        if (self.buffer) |buffer| {
            var i: usize = 0;
            while (i < self.size) {
                const size = StringManaged.getUTF8Size(buffer[i]);
                if (size == 1) buffer[i] = std.ascii.toLower(buffer[i]);
                i += size;
            }
        }
    }

    /// Converts all (ASCII) uppercase letters to lowercase
    pub fn toUppercase(self: *StringManaged) void {
        if (self.buffer) |buffer| {
            var i: usize = 0;
            while (i < self.size) {
                const size = StringManaged.getUTF8Size(buffer[i]);
                if (size == 1) buffer[i] = std.ascii.toUpper(buffer[i]);
                i += size;
            }
        }
    }

    // Convert the first (ASCII) character of each word to uppercase
    pub fn toCapitalized(self: *StringManaged) void {
        if (self.size == 0) return;

        var buffer = self.buffer.?;
        var i: usize = 0;
        var is_new_word: bool = true;

        while (i < self.size) {
            const char = buffer[i];

            if (std.ascii.isWhitespace(char)) {
                is_new_word = true;
                i += 1;
                continue;
            }

            if (is_new_word) {
                buffer[i] = std.ascii.toUpper(char);
                is_new_word = false;
            }

            i += 1;
        }
    }

    /// Creates a String from a given range
    /// User is responsible for managing the new String
    pub fn substr(self: StringManaged, start: usize, end: usize) Error!StringManaged {
        var result = StringManaged.init(self.allocator);

        if (self.buffer) |buffer| {
            if (StringManaged.getIndex(buffer, start, true)) |rStart| {
                if (StringManaged.getIndex(buffer, end, true)) |rEnd| {
                    if (rEnd < rStart or rEnd > self.size)
                        return Error.InvalidRange;
                    try result.concat(buffer[rStart..rEnd]);
                }
            }
        }

        return result;
    }

    // Writer functionality for the String.
    // pub const Writer = std.io.Writer(*String, Error, appendWrite);
    pub const Writer = struct {
        string: *StringManaged,
        interface: std.Io.Writer,
        err: ?Error = null,

        fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
            _ = splat;
            const a: *@This() = @alignCast(@fieldParentPtr("interface", w));
            const buffered = w.buffered();
            if (buffered.len != 0) return w.consume(a.string.appendWrite(buffered) catch |err| {
                a.err = err;
                return error.WriteFailed;
            });
            return a.string.appendWrite(data[0]) catch |err| {
                a.err = err;
                return error.WriteFailed;
            };
        }
    };

    pub fn writer(self: *StringManaged, buffer: []u8) Writer {
        return .{
            .string = self,
            .interface = .{
                .buffer = buffer,
                .vtable = &.{ .drain = Writer.drain },
            },
        };
    }

    fn appendWrite(self: *StringManaged, m: []const u8) !usize {
        try self.concat(m);
        return m.len;
    }

    // Iterator support
    pub const StringIterator = struct {
        string: *const StringManaged,
        index: usize,

        pub fn next(it: *StringIterator) ?[]const u8 {
            if (it.string.buffer) |buffer| {
                if (it.index == it.string.size) return null;
                const i = it.index;
                it.index += StringManaged.getUTF8Size(buffer[i]);
                return buffer[i..it.index];
            } else {
                return null;
            }
        }
    };

    pub fn iterator(self: *const StringManaged) StringIterator {
        return StringIterator{
            .string = self,
            .index = 0,
        };
    }

    /// Returns whether or not a character is whitelisted
    fn inWhitelist(char: u8, whitelist: []const u8) bool {
        var i: usize = 0;
        while (i < whitelist.len) : (i += 1) {
            if (whitelist[i] == char) return true;
        }

        return false;
    }

    /// Checks if byte is part of UTF-8 character
    inline fn isUTF8Byte(byte: u8) bool {
        return ((byte & 0x80) > 0) and (((byte << 1) & 0x80) == 0);
    }

    /// Returns the real index of a unicode string literal
    fn getIndex(unicode: []const u8, index: usize, real: bool) ?usize {
        var i: usize = 0;
        var j: usize = 0;
        while (i < unicode.len) {
            if (real) {
                if (j == index) return i;
            } else {
                if (i == index) return j;
            }
            i += StringManaged.getUTF8Size(unicode[i]);
            j += 1;
        }

        return null;
    }

    /// Returns the UTF-8 character's size
    inline fn getUTF8Size(char: u8) u3 {
        return std.unicode.utf8ByteSequenceLength(char) catch {
            return 1;
        };
    }

    /// Sets the contents of the String
    pub fn setStr(self: *StringManaged, contents: []const u8) Error!void {
        self.clear();
        try self.concat(contents);
    }

    /// Checks the start of the string against a literal
    pub fn startsWith(self: *StringManaged, literal: []const u8) bool {
        if (self.buffer) |buffer| {
            const index = std.mem.indexOf(u8, buffer[0..self.size], literal);
            return index == 0;
        }
        return false;
    }

    /// Checks the end of the string against a literal
    pub fn endsWith(self: *StringManaged, literal: []const u8) bool {
        if (self.buffer) |buffer| {
            const index = std.mem.lastIndexOf(u8, buffer[0..self.size], literal);
            const i: usize = self.size - literal.len;
            return index == i;
        }
        return false;
    }

    /// Replaces all occurrences of a string literal with another
    pub fn replace(self: *StringManaged, needle: []const u8, replacement: []const u8) !bool {
        if (self.buffer) |buffer| {
            const InputSize = self.size;
            const size = std.mem.replacementSize(u8, buffer[0..InputSize], needle, replacement);
            defer self.allocator.free(buffer);
            self.buffer = self.allocator.alloc(u8, size) catch {
                return Error.OutOfMemory;
            };
            self.size = size;
            const changes = std.mem.replace(u8, buffer[0..InputSize], needle, replacement, self.buffer.?);
            if (changes > 0) {
                return true;
            }
        }
        return false;
    }

    /// Checks if the needle String is within the source String
    pub fn includesString(self: *StringManaged, needle: StringManaged) bool {
        if (self.size == 0 or needle.size == 0) return false;

        if (self.buffer) |buffer| {
            if (needle.buffer) |needle_buffer| {
                const found_index = std.mem.indexOf(u8, buffer[0..self.size], needle_buffer[0..needle.size]);

                if (found_index == null) return false;

                return true;
            }
        }

        return false;
    }

    /// Checks if the needle literal is within the source String
    pub fn includesLiteral(self: *StringManaged, needle: []const u8) bool {
        if (self.size == 0 or needle.len == 0) return false;

        if (self.buffer) |buffer| {
            const found_index = std.mem.indexOf(u8, buffer[0..self.size], needle);

            if (found_index == null) return false;

            return true;
        }

        return false;
    }
};

/// An unmanaged variable length collection of characters
pub const StringUnmanaged = struct {
    /// The internal character buffer
    buffer: ?[]u8,
    /// The total size of the String
    size: usize,

    /// Errors that may occur when using String
    pub const Error = error{
        OutOfMemory,
        InvalidRange,
    };

    /// Creates a String with an Allocator
    /// ### example
    /// ```zig
    /// var str = String.init(allocator);
    /// // don't forget to deallocate
    /// defer _ = str.deinit();
    /// ```
    /// User is responsible for managing the new String
    pub fn init() StringUnmanaged {
        // for windows non-ascii characters
        // check if the system is windows
        if (builtin.os.tag == std.Target.Os.Tag.windows) {
            _ = std.os.windows.kernel32.SetConsoleOutputCP(65001);
        }

        return .{
            .buffer = null,
            .size = 0,
        };
    }

    pub fn init_with_contents(allocator: std.mem.Allocator, contents: []const u8) Error!StringUnmanaged {
        var string = init();

        try string.concat(allocator, contents);

        return string;
    }

    /// Deallocates the external buffer
    /// ### usage:
    /// ```zig
    /// var str = String.init(allocator);
    /// // deinit after the closure
    /// defer _ = str.deinit();
    /// ```
    pub fn deinit(self: *StringUnmanaged, allocator: std.mem.Allocator) void {
        if (self.buffer) |buffer| allocator.free(buffer);
    }

    /// Returns the size of the internal buffer
    pub fn capacity(self: StringUnmanaged) usize {
        if (self.buffer) |buffer| return buffer.len;
        return 0;
    }

    /// Allocates space for the external buffer
    pub fn allocate(self: *StringUnmanaged, allocator: std.mem.Allocator, bytes: usize) Error!void {
        if (self.buffer) |buffer| {
            if (bytes < self.size) self.size = bytes; // Clamp size to capacity
            self.buffer = allocator.realloc(buffer, bytes) catch {
                return Error.OutOfMemory;
            };
        } else {
            self.buffer = allocator.alloc(u8, bytes) catch {
                return Error.OutOfMemory;
            };
        }
    }

    /// Reallocates the the internal buffer to size
    pub fn truncate(self: *StringUnmanaged, allocator: std.mem.Allocator) Error!void {
        try self.allocate(allocator, self.size);
    }

    /// Appends a character onto the end of the String
    pub fn concat(self: *StringUnmanaged, allocator: std.mem.Allocator, char: []const u8) Error!void {
        try self.insert(allocator, char, self.len());
    }

    /// Inserts a string literal into the String at an index
    pub fn insert(self: *StringUnmanaged, allocator: std.mem.Allocator, literal: []const u8, index: usize) Error!void {
        // Make sure buffer has enough space
        if (self.buffer) |buffer| {
            if (self.size + literal.len > buffer.len) {
                try self.allocate(allocator, (self.size + literal.len) * 2);
            }
        } else {
            try self.allocate(allocator, (literal.len) * 2);
        }

        const buffer = self.buffer.?;

        // If the index is >= len, then simply push to the end.
        // If not, then copy contents over and insert literal.
        if (index == self.len()) {
            var i: usize = 0;
            while (i < literal.len) : (i += 1) {
                buffer[self.size + i] = literal[i];
            }
        } else {
            if (StringUnmanaged.getIndex(buffer, index, true)) |k| {
                // Move existing contents over
                var i: usize = buffer.len - 1;
                while (i >= k) : (i -= 1) {
                    if (i + literal.len < buffer.len) {
                        buffer[i + literal.len] = buffer[i];
                    }

                    if (i == 0) break;
                }

                i = 0;
                while (i < literal.len) : (i += 1) {
                    buffer[index + i] = literal[i];
                }
            }
        }

        self.size += literal.len;
    }

    /// Removes the last character from the String
    pub fn pop(self: *StringUnmanaged) ?[]const u8 {
        if (self.size == 0) return null;

        if (self.buffer) |buffer| {
            var i: usize = 0;
            while (i < self.size) {
                const size = StringUnmanaged.getUTF8Size(buffer[i]);
                if (i + size >= self.size) break;
                i += size;
            }

            const ret = buffer[i..self.size];
            self.size -= (self.size - i);
            return ret;
        }

        return null;
    }

    /// Compares this String with a string literal
    pub fn cmp(self: StringUnmanaged, literal: []const u8) bool {
        if (self.buffer) |buffer| {
            return std.mem.eql(u8, buffer[0..self.size], literal);
        }
        return false;
    }

    /// Returns the String buffer as a string literal
    /// ### usage:
    ///```zig
    ///var mystr = try String.init_with_contents(allocator, "Test String!");
    ///defer _ = mystr.deinit();
    ///std.debug.print("{s}\n", .{mystr.str()});
    ///```
    pub fn str(self: StringUnmanaged) []const u8 {
        if (self.buffer) |buffer| return buffer[0..self.size];
        return "";
    }

    /// Returns an owned slice of this string
    pub fn toOwned(self: StringUnmanaged, allocator: std.mem.Allocator) Error!?[]u8 {
        if (self.buffer != null) {
            const string = self.str();
            if (allocator.alloc(u8, string.len)) |newStr| {
                std.mem.copyForwards(u8, newStr, string);
                return newStr;
            } else |_| {
                return Error.OutOfMemory;
            }
        }

        return null;
    }

    /// Returns a character at the specified index
    pub fn charAt(self: StringUnmanaged, index: usize) ?[]const u8 {
        if (self.buffer) |buffer| {
            if (StringUnmanaged.getIndex(buffer, index, true)) |i| {
                const size = StringUnmanaged.getUTF8Size(buffer[i]);
                return buffer[i..(i + size)];
            }
        }
        return null;
    }

    /// Returns amount of characters in the String
    pub fn len(self: StringUnmanaged) usize {
        if (self.buffer) |buffer| {
            var length: usize = 0;
            var i: usize = 0;

            while (i < self.size) {
                i += StringUnmanaged.getUTF8Size(buffer[i]);
                length += 1;
            }

            return length;
        } else {
            return 0;
        }
    }

    /// Finds the first occurrence of the string literal
    pub fn find(self: StringUnmanaged, literal: []const u8) ?usize {
        if (self.buffer) |buffer| {
            const index = std.mem.indexOf(u8, buffer[0..self.size], literal);
            if (index) |i| {
                return StringUnmanaged.getIndex(buffer, i, false);
            }
        }

        return null;
    }

    /// Finds the last occurrence of the string literal
    pub fn rfind(self: StringUnmanaged, literal: []const u8) ?usize {
        if (self.buffer) |buffer| {
            const index = std.mem.lastIndexOf(u8, buffer[0..self.size], literal);
            if (index) |i| {
                return StringUnmanaged.getIndex(buffer, i, false);
            }
        }

        return null;
    }

    /// Removes a character at the specified index
    pub fn remove(self: *StringUnmanaged, index: usize) Error!void {
        try self.removeRange(index, index + 1);
    }

    /// Removes a range of character from the String
    /// Start (inclusive) - End (Exclusive)
    pub fn removeRange(self: *StringUnmanaged, start: usize, end: usize) Error!void {
        const length = self.len();
        if (end < start or end > length) return Error.InvalidRange;

        if (self.buffer) |buffer| {
            const rStart = StringUnmanaged.getIndex(buffer, start, true).?;
            const rEnd = StringUnmanaged.getIndex(buffer, end, true).?;
            const difference = rEnd - rStart;

            var i: usize = rEnd;
            while (i < self.size) : (i += 1) {
                buffer[i - difference] = buffer[i];
            }

            self.size -= difference;
        }
    }

    /// Trims all whitelist characters at the start of the String.
    pub fn trimStart(self: *StringUnmanaged, whitelist: []const u8) void {
        if (self.buffer) |buffer| {
            var i: usize = 0;
            while (i < self.size) : (i += 1) {
                const size = StringUnmanaged.getUTF8Size(buffer[i]);
                if (size > 1 or !inWhitelist(buffer[i], whitelist)) break;
            }

            if (StringUnmanaged.getIndex(buffer, i, false)) |k| {
                self.removeRange(0, k) catch {};
            }
        }
    }

    /// Trims all whitelist characters at the end of the String.
    pub fn trimEnd(self: *StringUnmanaged, whitelist: []const u8) void {
        self.reverse();
        self.trimStart(whitelist);
        self.reverse();
    }

    /// Trims all whitelist characters from both ends of the String
    pub fn trim(self: *StringUnmanaged, whitelist: []const u8) void {
        self.trimStart(whitelist);
        self.trimEnd(whitelist);
    }

    /// Copies this String into a new one
    /// User is responsible for managing the new String
    pub fn clone(self: StringUnmanaged, allocator: std.mem.Allocator) Error!StringUnmanaged {
        var newString = StringUnmanaged.init();
        try newString.concat(allocator, self.str());
        return newString;
    }

    /// Reverses the characters in this String
    pub fn reverse(self: *StringUnmanaged) void {
        if (self.buffer) |buffer| {
            var i: usize = 0;
            while (i < self.size) {
                const size = StringUnmanaged.getUTF8Size(buffer[i]);
                if (size > 1) std.mem.reverse(u8, buffer[i..(i + size)]);
                i += size;
            }

            std.mem.reverse(u8, buffer[0..self.size]);
        }
    }

    /// Repeats this String n times
    pub fn repeat(self: *StringUnmanaged, allocator: std.mem.Allocator, n: usize) Error!void {
        try self.allocate(allocator, self.size * (n + 1));
        if (self.buffer) |buffer| {
            for (1..n + 1) |i| {
                std.mem.copyForwards(u8, buffer[self.size * i ..], buffer[0..self.size]);
            }

            self.size *= (n + 1);
        }
    }

    /// Checks the String is empty
    pub inline fn isEmpty(self: StringUnmanaged) bool {
        return self.size == 0;
    }

    /// Splits the String into a slice, based on a delimiter and an index
    pub fn split(self: *const StringUnmanaged, delimiters: []const u8, index: usize) ?[]const u8 {
        if (self.buffer) |buffer| {
            var i: usize = 0;
            var block: usize = 0;
            var start: usize = 0;

            while (i < self.size) {
                const size = StringUnmanaged.getUTF8Size(buffer[i]);
                if (size == delimiters.len) {
                    if (std.mem.eql(u8, delimiters, buffer[i..(i + size)])) {
                        if (block == index) return buffer[start..i];
                        start = i + size;
                        block += 1;
                    }
                }

                i += size;
            }

            if (i >= self.size - 1 and block == index) {
                return buffer[start..self.size];
            }
        }

        return null;
    }

    /// Splits the String into slices, based on a delimiter.
    pub fn splitAll(self: *const StringUnmanaged, delimiters: []const u8) ![][]const u8 {
        var splitArr = std.array_list.Managed([]const u8).init(std.heap.page_allocator);
        defer splitArr.deinit();

        var i: usize = 0;
        while (self.split(delimiters, i)) |slice| : (i += 1) {
            try splitArr.append(slice);
        }

        return try splitArr.toOwnedSlice();
    }

    /// Splits the String into a new string, based on delimiters and an index
    /// The user of this function is in charge of the memory of the new String.
    pub fn splitToString(self: *const StringUnmanaged, allocator: std.mem.Allocator, delimiters: []const u8, index: usize) Error!?StringUnmanaged {
        if (self.split(delimiters, index)) |block| {
            var string = StringUnmanaged.init();
            try string.concat(allocator, block);
            return string;
        }

        return null;
    }

    /// Splits the String into a slice of new Strings, based on delimiters.
    /// The user of this function is in charge of the memory of the new Strings.
    pub fn splitAllToStrings(self: *const StringUnmanaged, allocator: std.mem.Allocator, delimiters: []const u8) ![]StringUnmanaged {
        var splitArr = std.array_list.Managed(StringUnmanaged).init(std.heap.page_allocator);
        defer splitArr.deinit();

        var i: usize = 0;
        while (try self.splitToString(allocator, delimiters, i)) |splitStr| : (i += 1) {
            try splitArr.append(splitStr);
        }

        return try splitArr.toOwnedSlice();
    }

    /// Splits the String into a slice of Strings by new line (\r\n or \n).
    pub fn lines(self: *StringUnmanaged, allocator: std.mem.Allocator) ![]StringUnmanaged {
        var lineArr = std.array_list.Managed(StringUnmanaged).init(std.heap.page_allocator);
        defer lineArr.deinit();

        var selfClone = try self.clone(allocator);
        defer selfClone.deinit(allocator);

        _ = try selfClone.replace(allocator, "\r\n", "\n");

        return try selfClone.splitAllToStrings(allocator, "\n");
    }

    /// Clears the contents of the String but leaves the capacity
    pub fn clear(self: *StringUnmanaged) void {
        if (self.buffer) |buffer| {
            for (buffer) |*ch| ch.* = 0;
            self.size = 0;
        }
    }

    /// Converts all (ASCII) uppercase letters to lowercase
    pub fn toLowercase(self: *StringUnmanaged) void {
        if (self.buffer) |buffer| {
            var i: usize = 0;
            while (i < self.size) {
                const size = StringUnmanaged.getUTF8Size(buffer[i]);
                if (size == 1) buffer[i] = std.ascii.toLower(buffer[i]);
                i += size;
            }
        }
    }

    /// Converts all (ASCII) uppercase letters to lowercase
    pub fn toUppercase(self: *StringUnmanaged) void {
        if (self.buffer) |buffer| {
            var i: usize = 0;
            while (i < self.size) {
                const size = StringUnmanaged.getUTF8Size(buffer[i]);
                if (size == 1) buffer[i] = std.ascii.toUpper(buffer[i]);
                i += size;
            }
        }
    }

    // Convert the first (ASCII) character of each word to uppercase
    pub fn toCapitalized(self: *StringUnmanaged) void {
        if (self.size == 0) return;

        var buffer = self.buffer.?;
        var i: usize = 0;
        var is_new_word: bool = true;

        while (i < self.size) {
            const char = buffer[i];

            if (std.ascii.isWhitespace(char)) {
                is_new_word = true;
                i += 1;
                continue;
            }

            if (is_new_word) {
                buffer[i] = std.ascii.toUpper(char);
                is_new_word = false;
            }

            i += 1;
        }
    }

    /// Creates a String from a given range
    /// User is responsible for managing the new String
    pub fn substr(self: StringUnmanaged, allocator: std.mem.Allocator, start: usize, end: usize) Error!StringUnmanaged {
        var result = StringUnmanaged.init();

        if (self.buffer) |buffer| {
            if (StringUnmanaged.getIndex(buffer, start, true)) |rStart| {
                if (StringUnmanaged.getIndex(buffer, end, true)) |rEnd| {
                    if (rEnd < rStart or rEnd > self.size)
                        return Error.InvalidRange;
                    try result.concat(allocator, buffer[rStart..rEnd]);
                }
            }
        }

        return result;
    }

    // Writer functionality for the String.
    // pub const Writer = std.io.Writer(*String, Error, appendWrite);
    pub const Writer = struct {
        string: *StringUnmanaged,
        interface: std.Io.Writer,
        err: ?Error = null,

        fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
            _ = splat;
            const a: *@This() = @alignCast(@fieldParentPtr("interface", w));
            const buffered = w.buffered();
            if (buffered.len != 0) return w.consume(a.string.appendWrite(buffered) catch |err| {
                a.err = err;
                return error.WriteFailed;
            });
            return a.string.appendWrite(data[0]) catch |err| {
                a.err = err;
                return error.WriteFailed;
            };
        }
    };

    pub fn writer(self: *StringUnmanaged, buffer: []u8) Writer {
        return .{
            .string = self,
            .interface = .{
                .buffer = buffer,
                .vtable = &.{ .drain = Writer.drain },
            },
        };
    }

    fn appendWrite(self: *StringUnmanaged, m: []const u8) !usize {
        try self.concat(m);
        return m.len;
    }

    // Iterator support
    pub const StringIterator = struct {
        string: *const StringUnmanaged,
        index: usize,

        pub fn next(it: *StringIterator) ?[]const u8 {
            if (it.string.buffer) |buffer| {
                if (it.index == it.string.size) return null;
                const i = it.index;
                it.index += StringUnmanaged.getUTF8Size(buffer[i]);
                return buffer[i..it.index];
            } else {
                return null;
            }
        }
    };

    pub fn iterator(self: *const StringUnmanaged) StringIterator {
        return StringIterator{
            .string = self,
            .index = 0,
        };
    }

    /// Returns whether or not a character is whitelisted
    fn inWhitelist(char: u8, whitelist: []const u8) bool {
        var i: usize = 0;
        while (i < whitelist.len) : (i += 1) {
            if (whitelist[i] == char) return true;
        }

        return false;
    }

    /// Checks if byte is part of UTF-8 character
    inline fn isUTF8Byte(byte: u8) bool {
        return ((byte & 0x80) > 0) and (((byte << 1) & 0x80) == 0);
    }

    /// Returns the real index of a unicode string literal
    fn getIndex(unicode: []const u8, index: usize, real: bool) ?usize {
        var i: usize = 0;
        var j: usize = 0;
        while (i < unicode.len) {
            if (real) {
                if (j == index) return i;
            } else {
                if (i == index) return j;
            }
            i += StringUnmanaged.getUTF8Size(unicode[i]);
            j += 1;
        }

        return null;
    }

    /// Returns the UTF-8 character's size
    inline fn getUTF8Size(char: u8) u3 {
        return std.unicode.utf8ByteSequenceLength(char) catch {
            return 1;
        };
    }

    /// Sets the contents of the String
    pub fn setStr(self: *StringUnmanaged, allocator: std.mem.Allocator, contents: []const u8) Error!void {
        self.clear();
        try self.concat(allocator, contents);
    }

    /// Checks the start of the string against a literal
    pub fn startsWith(self: *StringUnmanaged, literal: []const u8) bool {
        if (self.buffer) |buffer| {
            const index = std.mem.indexOf(u8, buffer[0..self.size], literal);
            return index == 0;
        }
        return false;
    }

    /// Checks the end of the string against a literal
    pub fn endsWith(self: *StringUnmanaged, literal: []const u8) bool {
        if (self.buffer) |buffer| {
            const index = std.mem.lastIndexOf(u8, buffer[0..self.size], literal);
            const i: usize = self.size - literal.len;
            return index == i;
        }
        return false;
    }

    /// Replaces all occurrences of a string literal with another
    pub fn replace(self: *StringUnmanaged, allocator: std.mem.Allocator, needle: []const u8, replacement: []const u8) !bool {
        if (self.buffer) |buffer| {
            const InputSize = self.size;
            const size = std.mem.replacementSize(u8, buffer[0..InputSize], needle, replacement);
            defer allocator.free(buffer);
            self.buffer = allocator.alloc(u8, size) catch {
                return Error.OutOfMemory;
            };
            self.size = size;
            const changes = std.mem.replace(u8, buffer[0..InputSize], needle, replacement, self.buffer.?);
            if (changes > 0) {
                return true;
            }
        }
        return false;
    }

    /// Checks if the needle String is within the source String
    pub fn includesString(self: *StringUnmanaged, needle: StringUnmanaged) bool {
        if (self.size == 0 or needle.size == 0) return false;

        if (self.buffer) |buffer| {
            if (needle.buffer) |needle_buffer| {
                const found_index = std.mem.indexOf(u8, buffer[0..self.size], needle_buffer[0..needle.size]);

                if (found_index == null) return false;

                return true;
            }
        }

        return false;
    }

    /// Checks if the needle literal is within the source String
    pub fn includesLiteral(self: *StringUnmanaged, needle: []const u8) bool {
        if (self.size == 0 or needle.len == 0) return false;

        if (self.buffer) |buffer| {
            const found_index = std.mem.indexOf(u8, buffer[0..self.size], needle);

            if (found_index == null) return false;

            return true;
        }

        return false;
    }
};
