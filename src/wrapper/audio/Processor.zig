//! Reimplementation of https://github.com/acoustid/chromaprint/blob/master/src/audio/ffmpeg_audio_processor.h

const c = @import("../root.zig").c;

swr_ctx: ?*c.SwrContext = null,

const Self = @This();

pub fn init() Self {
    return .{
        .swr_ctx = c.swr_alloc(),
    };
}

pub fn deinit(self: *Self) void {
    if (self.swr_ctx != null) c.swr_free(&self.swr_ctx);
}

pub fn setCompatibleMode(self: *Self) error{SetOptError}!void {
    if (c.av_opt_set_int(self.swr_ctx, "resampler", c.SWR_ENGINE_SWR, 0) != 0) 
        return error.SetOptError;
    if (c.av_opt_set_int(self.swr_ctx, "filter_size", 16, 0) != 0) 
        return error.SetOptError;
    if (c.av_opt_set_int(self.swr_ctx, "phase_shift", 8, 0) != 0) 
        return error.SetOptError;
    if (c.av_opt_set_int(self.swr_ctx, "linear_interp", 1, 0) != 0) 
        return error.SetOptError;
    if (c.av_opt_set_double(self.swr_ctx, "cutoff", 0.8, 0) != 0) 
        return error.SetOptError;
}

pub fn setInputChannelLayout(self: *Self, channel_layout: c.AVChannelLayout) error{SetOptError}!void {
    if (c.av_opt_set_chlayout(@ptrCast(self.swr_ctx), "in_chlayout", &channel_layout, 0) != 0) 
        return error.SetOptError;
}

pub fn setInputSampleFormat(self: *Self, sample_format: c.AVSampleFormat) error{SetOptError}!void {
    // av_opt_set_sample_fmt(m_swr_ctx, "in_sample_fmt", sample_format, 0);
    if (c.av_opt_set_sample_fmt(@ptrCast(self.swr_ctx), "in_sample_fmt", sample_format, 0) != 0) {
        return error.SetOptError;
    }
}

pub fn setInputSampleRate(self: *Self, sample_rate: c_int) error{SetOptError}!void {
    if (c.av_opt_set_int(@ptrCast(self.swr_ctx), "in_sample_rate", sample_rate, 0) != 0) 
        return error.SetOptError;
}

pub fn setOutputChannelLayout(self: *Self, channel_layout: c.AVChannelLayout) error{SetOptError}!void {
    if (c.av_opt_set_chlayout(@ptrCast(self.swr_ctx), "out_chlayout", &channel_layout, 0) != 0) 
        return error.SetOptError;
}

pub fn setOutputSampleFormat(self: *Self, sample_format: c.AVSampleFormat) error{SetOptError}!void {
    if (c.av_opt_set_sample_fmt(@ptrCast(self.swr_ctx), "out_sample_fmt", sample_format, 0) != 0) 
        return error.SetOptError;
}

pub fn setOutputSampleRate(self: *Self, sample_rate: c_int) error{SetOptError}!void {
    if (c.av_opt_set_int(@ptrCast(self.swr_ctx), "out_sample_rate", sample_rate, 0) != 0) 
        return error.SetOptError;
}

pub fn swrInit(self: *Self) c_int {
    return c.swr_init(self.swr_ctx);
}

pub fn convert(self: *Self, out: [*c]const [*c]u8, out_count: c_int, in: [*c]const [*c]const u8, in_count: c_int) c_int {
    return c.swr_convert(self.swr_ctx, out, out_count, in, in_count);
}

pub fn flush(self: *Self, out: [*c]const [*c]u8, out_count: c_int) c_int {
    return c.swr_convert(self.swr_ctx, out, out_count, null, 0);
}

