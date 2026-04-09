const std = @import("std");
const audio = @import("audio.zig");

const Decoder = audio.Decoder;

pub const c = @cImport({
    @cInclude("chromaprint.h");
});

pub const Error = error{ChromaprintError};
pub const Alogrithm = enum(c_int) {
    test1 = c.CHROMAPRINT_ALGORITHM_TEST1,
    test2 = c.CHROMAPRINT_ALGORITHM_TEST2,
    test3 = c.CHROMAPRINT_ALGORITHM_TEST3,
    test4 = c.CHROMAPRINT_ALGORITHM_TEST4,
    test5 = c.CHROMAPRINT_ALGORITHM_TEST5,

    pub const default: @This() = @enumFromInt(c.CHROMAPRINT_ALGORITHM_DEFAULT);
};

pub const Context = struct {
    ctx: ?*c.ChromaprintContext,

    const Self = @This();
    
    pub fn default() Self {
        return .{
            .ctx = c.chromaprint_new(c.CHROMAPRINT_ALGORITHM_DEFAULT),
        };
    }

    pub fn init(algorithm: c_int) Self {
        return .{ .ctx = c.chromaprint_new(algorithm) };
    }

    pub fn clearFingerprint(self: *Self) Error!void {
        if (c.chromaprint_clear_fingerprint(self.ctx) == 0) return Error.ChromaprintError;
    }

    pub fn feed(self: *Self, data: [*c]const i16, size: c_int) Error!void {
        if (c.chromaprint_feed(self.ctx, data, size) == 0) {
            return Error.ChromaprintError;
        }
    }

    pub fn finish(self: *Self) Error!void {
        if (c.chromaprint_finish(self.ctx) == 0) return Error.ChromaprintError;
    }

    pub fn deinit(self: *Self) void {
        c.chromaprint_free(self.ctx);
    }

    pub fn getAlgorithm(self: *Self) c_int {
        return c.chromaprint_get_algorithm(self.ctx);
    }

    pub fn getDelay(self: *Self) c_int {
        return c.chromaprint_get_delay(self.ctx);
    }

    pub fn getDelayMs(self: *Self) c_int {
        return c.chromaprint_get_delay_ms(self.ctx);
    }

    pub fn getFingerprint(self: *Self, fingerprint: [*c][*c]u8) Error!void {
        if (c.chromaprint_get_fingerprint(self.ctx, fingerprint) == 0) {
            return Error.ChromaprintError;
        }
    }

    pub fn getFingerprintHash(self: *Self, hash: [*c]u32) Error!void {
        return if (c.chromaprint_get_fingerprint_hash(self.ctx, hash)) Error.ChromaprintError;
    }

    pub fn getItemDuration(self: *const Self) c_int {
        return c.chromaprint_get_item_duration(self.ctx);
    }

    pub fn getItemDurationMs(self: *const Self) c_int {
        return c.chromaprint_get_item_duration_ms(self.ctx);
    }

    pub fn getNumChannels(self: *const Self) c_int {
        return c.chromaprint_get_num_channels(self.ctx);
    }

    pub fn getRawFingerprint(self: *Self, fingerprint: [*c][*c]u32, size: [*c]c_int) Error!void {
        return if (c.chromaprint_get_raw_fingerprint(self.ctx, fingerprint, size) == 0)
            Error.ChromaprintError;
    }

    pub fn getRawFingerprintSize(self: *Self, size: [*c]c_int) Error!void {
        return if (c.chromaprint_get_raw_fingerprint_size(self.ctx, size) == 0)
            Error.ChromaprintError;
    }

    pub fn getSampleRate(self: *const Self) c_int {
        return c.chromaprint_get_sample_rate(self.ctx);
    }

    pub fn setOption(self: *Self, name: [*c]const u8, value: c_int) Error!void {
        return if (c.chromaprint_set_option(self.ctx, name, value) == 0)
            Error.ChromaprintError;
    }

    pub fn start(self: *Self, sample_rate: c_int, num_channels: c_int) Error!void {
        return if (c.chromaprint_start(self.ctx, sample_rate, num_channels) == 0)
            Error.ChromaprintError;
    }
};

pub fn getVersion() [*c]const u8 {
    return c.chromaprint_get_version();
}

pub fn hashFingerprint(fp: []const u32, hash: [*c]u32) c_int {
    return c.chromaprint_hash_fingerprint(fp.ptr, fp.len, hash);
}

pub fn dealloc(ptr: ?*anyopaque) void {
    c.chromaprint_dealloc(ptr);
}

pub fn decodeFingerprint(encoded_fp: []const u8, fp: [*c][*c]u32, size: [*c]c_int, algorithm: [*c]c_int, base64: c_int) c_int {
    return c.chromaprint_decode_fingerprint(encoded_fp.ptr, encoded_fp.len, fp, size, algorithm, base64);
}

pub fn encodeFingerprint(fp: []const u32, algorithm: c_int, encoded_fp: []u8, base64: c_int) c_int {
    return c.chromaprint_encode_fingerprint(fp.ptr, fp.len, algorithm, &encoded_fp.ptr, &encoded_fp.len, base64);
}

