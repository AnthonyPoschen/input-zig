const std = @import("std");

pub const has_threaded_io = @hasDecl(std.Io, "Threaded");

pub const Runtime = if (has_threaded_io) OldRuntime else NewRuntime;
pub const File = if (has_threaded_io) std.Io.File else std.fs.File;
pub const Writer = if (has_threaded_io)
    std.Io.File.Writer
else
    std.fs.File.Writer;

/// Bridge CLI file I/O across changing stdlib APIs.
const OldRuntime = struct {
    threaded: std.Io.Threaded,

    /// Initialize the legacy std.Io runtime.
    pub fn init() OldRuntime {
        return .{
            .threaded = std.Io.Threaded.init(
                std.heap.page_allocator,
                .{},
            ),
        };
    }

    /// Release any runtime resources owned by the CLI.
    pub fn deinit(self: *OldRuntime) void {
        self.threaded.deinit();
    }

    /// Create a buffered stdout writer.
    pub fn stdoutWriter(self: *OldRuntime, buffer: []u8) Writer {
        return std.Io.File.stdout().writer(self.io(), buffer);
    }

    /// Create a buffered stderr writer.
    pub fn stderrWriter(self: *OldRuntime, buffer: []u8) Writer {
        return std.Io.File.stderr().writer(self.io(), buffer);
    }

    /// Create a buffered writer for an opened file.
    pub fn fileWriter(self: *OldRuntime, file: File, buffer: []u8) Writer {
        return file.writer(self.io(), buffer);
    }

    /// Open a file for rewriting from the current directory.
    pub fn createFile(self: *OldRuntime, path: []const u8) !File {
        return std.Io.Dir.cwd().createFile(self.io(), path, .{
            .truncate = true,
        });
    }

    /// Read an entire file from the current directory.
    pub fn readFileAlloc(
        self: *OldRuntime,
        allocator: std.mem.Allocator,
        path: []const u8,
        max_bytes: usize,
    ) ![]u8 {
        return std.Io.Dir.cwd().readFileAlloc(
            self.io(),
            path,
            allocator,
            .limited(max_bytes),
        );
    }

    /// Close a file opened through this runtime.
    pub fn closeFile(self: *OldRuntime, file: File) void {
        file.close(self.io());
    }

    /// Sleep for a fixed number of nanoseconds.
    pub fn sleep(self: *OldRuntime, nanoseconds: u64) !void {
        try self.io().sleep(
            std.Io.Duration.fromNanoseconds(@intCast(nanoseconds)),
            .awake,
        );
    }

    /// Expose the legacy std.Io handle internally.
    fn io(self: *OldRuntime) std.Io {
        return self.threaded.io();
    }
};

/// Bridge CLI file I/O for std.fs-based builds.
const NewRuntime = struct {
    /// Initialize the fs-backed runtime.
    pub fn init() NewRuntime {
        return .{};
    }

    /// Release any runtime resources owned by the CLI.
    pub fn deinit(_: *NewRuntime) void {}

    /// Create a buffered stdout writer.
    pub fn stdoutWriter(_: *NewRuntime, buffer: []u8) Writer {
        return std.fs.File.stdout().writer(buffer);
    }

    /// Create a buffered stderr writer.
    pub fn stderrWriter(_: *NewRuntime, buffer: []u8) Writer {
        return std.fs.File.stderr().writer(buffer);
    }

    /// Create a buffered writer for an opened file.
    pub fn fileWriter(_: *NewRuntime, file: File, buffer: []u8) Writer {
        return file.writer(buffer);
    }

    /// Open a file for rewriting from the current directory.
    pub fn createFile(_: *NewRuntime, path: []const u8) !File {
        return std.fs.cwd().createFile(path, .{ .truncate = true });
    }

    /// Read an entire file from the current directory.
    pub fn readFileAlloc(
        _: *NewRuntime,
        allocator: std.mem.Allocator,
        path: []const u8,
        max_bytes: usize,
    ) ![]u8 {
        return std.fs.cwd().readFileAlloc(allocator, path, max_bytes);
    }

    /// Close a file opened through this runtime.
    pub fn closeFile(_: *NewRuntime, file: File) void {
        file.close();
    }

    /// Sleep for a fixed number of nanoseconds.
    pub fn sleep(_: *NewRuntime, nanoseconds: u64) !void {
        std.Thread.sleep(nanoseconds);
    }
};
