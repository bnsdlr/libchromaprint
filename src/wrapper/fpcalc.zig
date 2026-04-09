const std = @import("std");
const Io = std.Io;
const mem = std.mem;

const chromaprint = @import("chromaprint.zig");
const ChromaprintContext = chromaprint.Context;

const audio = @import("audio.zig");
const Reader = audio.Reader;

pub const log = std.log.scoped(.fpcalc);

pub const FingerprintCalcOpts = struct {
    input_format: ?[:0]const u8 = null,
    input_channels: c_int = 0,
    input_sample_rate: c_int = 0,
    max_duration: f64 = 120,
    max_chunk_duration: f64 = 0,
    overlap: bool = false,
    algorithm: chromaprint.Alogrithm = .default,
};

pub const FingerprintCalcError = error{
    SetOptError,
    WriteFailed,
    InvalidInputFormat,
    OutOfMemory,
    InvalidNumberOfChannels,
    InvalidSampleRate,
    PackAllocFailed,
    ReaderError,
    ChromaprintError,
    NotEnoughAudioData,
    EmptyFingerprint,
    ReaderFailed,
    DidNotGetResults,
};

/// The returned slice needs to be freed with `chromaprint.dealloc`.
pub fn calcFingerprint(
    file_name: [:0]const u8,
    opts: FingerprintCalcOpts
) FingerprintCalcError!?[]const u8 {
    var reader: Reader = .init();
    defer reader.deinit();
    if (opts.input_format) |input_format| {
        if (!reader.setInputFormat(input_format)) {
            return error.InvalidInputFormat;
        }
    }
    if (opts.input_channels != 0) {
        if (!reader.setInputChannels(opts.input_channels)) {
            return error.InvalidNumberOfChannels;
        }
    }
    if (opts.input_sample_rate != 0) {
        if (!reader.setInputSampleRate(opts.input_sample_rate)) {
            return error.InvalidSampleRate;
        }
    }

    // ChromaprintContext *chromaprint_ctx = chromaprint_new(g_algorithm);
    var chromaprint_ctx: ChromaprintContext = .init(@intFromEnum(opts.algorithm));
    defer chromaprint_ctx.deinit();

    // reader.SetOutputChannels(chromaprint_get_num_channels(chromaprint_ctx));
    reader.setOutputChannels(chromaprint_ctx.getNumChannels());
    // reader.SetOutputSampleRate(chromaprint_get_sample_rate(chromaprint_ctx));
    reader.setOutputSampleRate(chromaprint_ctx.getSampleRate());

    return processFile(&chromaprint_ctx, &reader, file_name, opts) catch |err| switch (err) {
        error.ReaderError => {
            reader.logError();
            return err;
        },
        else => return err,
    };
}

/// If `error.ReaderError` is returned, a message can be printed by calling `Reader.printError`.
/// The returned slice needs to be freed with `chromaprint.dealloc`.
pub fn processFile(
    ctx: *ChromaprintContext,
    reader: *Reader,
    ofile_name: [:0]const u8,
    opts: FingerprintCalcOpts,
) FingerprintCalcError!?[]const u8 {
    var file_name: [:0]const u8 = ofile_name;

    if (mem.eql(u8, file_name, "-")) {
        file_name = "pipe:0";
    }

    if (!try reader.open(file_name)) {
        return error.ReaderError;
    }

    ctx.start(reader.getSampleRate(), reader.getChannels()) catch |err| {
        log.err("Could not initialize the fingerprinting process\n", .{});
        return err;
    };

    var stream_size: usize = 0;
    const stream_limit: usize = @intFromFloat(opts.max_duration * @as(f64, @floatFromInt(reader.getSampleRate())));

    var chunk_size: usize = 0;
    const chunk_limit: usize = @intFromFloat(opts.max_chunk_duration * @as(f64, @floatFromInt(reader.getSampleRate())));

    var extra_chunk_limit: usize = 0;
    var overlap: f64 = 0;
    if (chunk_limit > 0 and opts.overlap) {
        extra_chunk_limit = @intCast(ctx.getDelay());
        overlap = @as(f64, @floatFromInt(ctx.getDelayMs())) / 1000.0;
    }

    var first_chunk: bool = true;
    var read_failed: bool = false;
    var got_results: bool = false;

    while (!reader.isFinished()) {
        // const int16_t *frame_data = nullptr;
        var frame_data: [*c]i16 = null;
        var frame_size: c_int = 0;
        if (!reader.read(&frame_data, &frame_size)) {
            read_failed = true;
            break;
        }

        var stream_done: bool = false;
        if (stream_limit > 0) {

            const remaining: c_int = @intCast(stream_limit -| stream_size);
            if (frame_size > remaining) {
                frame_size = remaining;
                stream_done = true;
            }
        }
        stream_size += @intCast(frame_size);

        if (frame_size == 0) {
            if (stream_done) {
                break;
            } else {
                continue;
            }
        }

        var chunk_done: bool = false;
        var first_part_size: c_int = frame_size;
        if (chunk_limit > 0) {
            // const auto remaining = chunk_limit + extra_chunk_limit - chunk_size;
            const remaining: c_int = @intCast(chunk_limit + extra_chunk_limit -| chunk_size);
            if (first_part_size > remaining) {
                first_part_size = remaining;
                chunk_done = true;
            }
        }

        ctx.feed(frame_data, @as(c_int, @intCast(first_part_size)) * reader.getChannels()) catch |err| {
            log.err("Could not process audio data\n", .{});
            return err;
        };

        chunk_size += @intCast(first_part_size);

        if (chunk_done) {
            ctx.finish() catch |err| {
                log.err("Could not finish the fingerprinting process\n", .{});
                return err;
            };

            // const auto chunk_duration = (chunk_size - extra_chunk_limit) * 1.0 / reader.GetSampleRate() + overlap;
            // const chunk_duration = @as(f64, @floatFromInt(chunk_size - extra_chunk_limit)) / @as(f64, @floatFromInt(reader.getSampleRate())) + overlap;
            // display results
            // return try getResult(writer, ctx, first_chunk);
            got_results = true;

            if (opts.overlap) {
                ctx.clearFingerprint() catch |err| {
                    log.err("Could not initialize the fingerprinting process\n", .{});
                    return err;
                };
            } else {
                ctx.start(reader.getSampleRate(), reader.getChannels()) catch |err| {
                    log.err("Could not initialize the fingerprinting process\n", .{});
                    return err;
                };
            }

            if (first_chunk) {
                extra_chunk_limit = 0;
                first_chunk = false;
            }

            chunk_size = 0;
        }

        frame_data += @intCast(first_part_size * reader.getChannels());
        frame_size -= first_part_size;

        if (frame_size > 0) {
            ctx.feed(frame_data, @as(c_int, @intCast(frame_size)) * reader.getChannels()) catch |err| {
                log.err("Could not process audio data\n", .{});
                return err;
            };
        }

        chunk_size += @intCast(frame_size);

        if (stream_done) {
            break;
        }
    }

    ctx.finish() catch |err| {
        log.err("Could not finish the fingerprinting process\n", .{});
        return err;
    };

    if (chunk_size > 0) {
        // display results
        got_results = true;
    } else if (first_chunk) {
        log.err("Not enough audio data\n", .{});
        return error.NotEnoughAudioData;
    }

    if (read_failed) {
        if (got_results) {
            return error.ReaderFailed;
        } else {
            return error.DidNotGetResults;
        }
    }

    return getResult(ctx, first_chunk);
}

/// The returned slice needs to be freed with `chromaprint.dealloc`.
pub fn getResult(ctx: *ChromaprintContext, first: bool) FingerprintCalcError!?[]const u8 {
    var fp: [*c]u8 = null;
    var size: c_int = -1;
    ctx.getRawFingerprintSize(&size) catch |err| {
        log.err("Could not get the fingerprinting size\n", .{});
        return err;
    };

    if (size <= 0) {
        if (first) {
            log.err("Empty fingerprint\n", .{});
            return error.EmptyFingerprint;
        }
        return null;
    }

    ctx.getFingerprint(&fp) catch |err| {
        log.err("Could not get the fingerprinting\n", .{});
        return err;
    };

    return mem.sliceTo(fp, 0);
}

