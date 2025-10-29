# Zig String (A UTF-8 String Library)

This library is a UTF-8 compatible **string** library for the **Zig** programming language. I copied [JakubSzark's](https://github.com/JakubSzark/zig-string) String implementation and expanded on it.

# Basic Usage

## Managed String

```zig
const std = @import("std");
const String = @import("./stringz.zig").StringManaged;
// ...

// Use your favorite allocator
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();
const allocator = arena.allocator();


// Create your String
var myString = String.init(allocator);
defer myString.deinit();

// Use functions provided
try myString.concat("🔥 Hello!");
_ = myString.pop();
try myString.concat(", World 🔥");

// Success!
std.debug.assert(myString.cmp("🔥 Hello, World 🔥"));

```

## Unmanaged String

```zig
const std = @import("std");
const String = @import("./stringz.zig").StringUnmanaged;
// ...

// Use your favorite allocator
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();
const allocator = arena.allocator();

// Create your String
var myString = String.init();
defer myString.deinit(allocator);

// Use functions provided
try myString.concat(allocator, "🔥 Hello!");
_ = myString.pop();
try myString.concat(allocator, ", World 🔥");

// Success!
std.debug.assert(myString.cmp("🔥 Hello, World 🔥"));

```

## When To Use Which?

If simplicity is what you want and you don't need granular control over memory, then use `StringManaged` (this is fine for most cases). Otherwise you probably want `StringUnmanaged`.

| Feature                         | String | StringUnmanaged            |
| ------------------------------- | ------ | -------------------------- |
| Needs Allocator At Init?        | Yes    | No                         |
| Handles Allocations             | Yes    | No                         |
| Easier To Use?                  | Yes    | Requires memory management |
| Flexible For Custom Allocators? | No     | Yes                        |

# Installation

Add this to your build.zig.zon

```zig
.dependencies = .{
    .string = .{
        .url = "https://github.com/definitepotato/stringz/archive/refs/heads/master.tar.gz",
        // The correct hash will be suggested by zig at build time.
    }
}

```

And add this to you build.zig

```zig
    const string = b.dependency("stringz", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("stringz", string.module("stringz"));

```

You can then import the library into your code like this

```zig
const String = @import("stringz").StringManaged;
```

Or

```zig
const String = @import("stringz").StringUnmanaged;
```

# How to Contribute

1. Fork
2. Clone
3. Add Features (Use Zig FMT)
4. Make a Test
5. Pull Request
6. Success!

# Working Features

If there are any issues with <b>complexity</b> please <b>open an issue</b>
(I'm no expert when it comes to complexity)

| Available in Managed/Unmanaged | Function           | Description                                                              |
| ------------------------------ | ------------------ | ------------------------------------------------------------------------ |
| Both                           | allocate           | Sets the internal buffer size                                            |
| Both                           | capacity           | Returns the capacity of the String                                       |
| Both                           | charAt             | Returns character at index                                               |
| Both                           | clear              | Clears the contents of the String                                        |
| Both                           | clone              | Copies this string to a new one                                          |
| Both                           | cmp                | Compares to string literal                                               |
| Both                           | concat             | Appends a string literal to the end                                      |
| Both                           | deinit             | De-allocates the String                                                  |
| Both                           | find               | Finds first string literal appearance                                    |
| Both                           | rfind              | Finds last string literal appearance                                     |
| Both                           | includesLiteral    | Whether or not the provided literal is in the String                     |
| Both                           | includesString     | Whether or not the provided String is within the String                  |
| Both                           | init               | Creates a String with an Allocator                                       |
| Both                           | init_with_contents | Creates a String with specified contents                                 |
| Both                           | insert             | Inserts a character at an index                                          |
| Both                           | isEmpty            | Checks if length is zero                                                 |
| Both                           | iterator           | Returns a StringIterator over the String                                 |
| Both                           | len                | Returns count of characters stored                                       |
| Both                           | pop                | Removes the last character                                               |
| Both                           | remove             | Removes a character at an index                                          |
| Both                           | removeRange        | Removes a range of characters                                            |
| Both                           | repeat             | Repeats string n times                                                   |
| Both                           | reverse            | Reverses all the characters                                              |
| Both                           | split              | Returns a slice based on delimiters and index                            |
| Both                           | splitAll           | Returns a slice of slices based on delimiters                            |
| Both                           | splitToString      | Returns a String based on delimiters and index                           |
| Both                           | splitAllToStrings  | Returns a slice of Strings based on delimiters                           |
| Both                           | lines              | Returns a slice of Strings split by newlines                             |
| Both                           | str                | Returns the String as a slice                                            |
| Both                           | substr             | Creates a string from a range                                            |
| Both                           | toLowercase        | Converts (ASCII) characters to lowercase                                 |
| Both                           | toOwned            | Creates an owned slice of the String                                     |
| Both                           | toUppercase        | Converts (ASCII) characters to uppercase                                 |
| Both                           | toCapitalized      | Converts the first (ASCII) character of each word to uppercase           |
| Both                           | trim               | Removes whitelist from both ends                                         |
| Both                           | trimEnd            | Remove whitelist from the end                                            |
| Both                           | trimStart          | Remove whitelist from the start                                          |
| Both                           | truncate           | Realloc to the length                                                    |
| Both                           | setStr             | Set's buffer value from string literal                                   |
| Managed Only                   | writer             | Returns a std.Io.Writer for the String                                   |
| Both                           | startsWith         | Determines if the given string begins with the given value               |
| Both                           | endsWith           | Determines if the given string ends with the given value                 |
| Both                           | replace            | Replace all occurrences of the search string with the replacement string |
