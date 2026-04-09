//! Reimplementation of 
//! https://github.com/acoustid/chromaprint/blob/master/src/audio/ffmpeg_audio_reader.h

const std = @import("std");
const mem = std.mem;

const mod = @import("../root.zig");
// const av = mod.av;
const c = mod.c;

const log = std.log.scoped(.audio_reader);

const Processor = @import("Processor.zig");

const Self = @This();

// #include <libavutil/opt.h>
// #include <libavutil/channel_layout.h>

// std::unique_ptr<FFmpegAudioProcessor> m_converter;
converter: ?Processor = null,
// uint8_t *m_convert_buffer[1] = { nullptr };
convert_buffer: [1]?*u8 = .{null},
// int m_convert_buffer_nb_samples = 0;
convert_buffer_nb_samples: c_int = 0,

// const AVInputFormat *m_input_fmt = nullptr;
// input_fmt: ?*av.InputFormat = null,
input_fmt: ?*const c.AVInputFormat = null,
// AVDictionary *m_input_opts = nullptr;
// input_opts: ?*av.Dictionary.Mutable = null,
input_opts: ?*c.AVDictionary = null,

// AVFormatContext *m_format_ctx = nullptr;
// format_ctx: ?*av.FormatContext = null,
format_ctx: ?*c.AVFormatContext = null,
// AVCodecContext *m_codec_ctx = nullptr;
// codec_ctx: ?*av.Codec.Context = null,
codec_ctx: ?*c.AVCodecContext = null,
// int m_stream_index = -1;
stream_index: c_int = -1,
// std::string m_error;
error_msg: ?[]const u8 = null,
// int m_error_code = 0;
error_code: c_int = 0,
// bool m_opened = false;
opened: bool = false,
// bool m_has_more_packets = true;
has_more_packets: bool = true,
// bool m_has_more_frames = true;
has_more_frames: bool = true,
// AVPacket *m_packet = nullptr;
// packet: ?*av.Packet = null,
packet: ?*c.AVPacket = null,
// AVFrame *m_frame = nullptr;
// frame: ?*av.Frame = null,
frame: ?*c.AVFrame = null,

// int m_output_sample_rate = 0;
output_sample_rate: c_int = 0,
// int m_output_channels = 0;
output_channels: c_int = 0,

// uint64_t m_nb_packets = 0;
nb_packets: u64 = 0,
// int m_decode_error = 0;
decoder_error: c_int = 0,

inline fn setError(self: *Self, format: []const u8, errnum: c_int) void {
    self.error_msg = format;
	if (errnum < 0) {
		// char buf[AV_ERROR_MAX_STRING_SIZE];
		// if (av_strerror(errnum, buf, AV_ERROR_MAX_STRING_SIZE) == 0) {
		//  m_error += " (";
		//  m_error += buf;
		//  m_error += ")";
		// }
	}
    self.error_code = errnum;
}

pub fn logError(self: *const Self) void {
    log.err("{?s} ({d})", .{self.error_msg, self.error_code});
}

pub fn setOutputSampleRate(self: *Self, sample_rate: c_int) void {
    self.output_sample_rate = sample_rate;
}
pub fn setOutputChannels(self: *Self, channels: c_int) void {
    self.output_channels = channels;
}

pub fn isOpen(self: *const Self) bool {
    return self.opened;
}
pub fn isFinished(self: *const Self) bool {
    return !self.has_more_packets and !self.has_more_frames;
}

pub fn getError(self: *const Self) ?[]const u8 {
    return self.error_msg;
}
pub fn getErrorCode(self: *const Self) c_int {
    return self.error_code;
}

// inline FFmpegAudioReader::FFmpegAudioReader() {
//  av_log_set_level(AV_LOG_QUIET);
// }
pub fn init() Self {
    c.av_log_set_level(c.AV_LOG_QUIET);
    return .{ 
        // .converter = Processor.init() 
    };
}

// inline FFmpegAudioReader::~FFmpegAudioReader() {
//  Close();
//  av_dict_free(&m_input_opts);
//  av_freep(&m_convert_buffer[0]);
// }
pub fn deinit(self: *Self) void {
    self.close();
    // if (self.input_opts) |opts| opts.free();
    if (self.input_opts != null) c.av_dict_free(&self.input_opts);
    if (self.converter) |*conv| conv.deinit();
    // av.free(@ptrCast(self.convert_buffer[0]));
    if (self.convert_buffer[0] != null) c.av_freep(@ptrCast(&self.convert_buffer[0]));
}

// inline bool FFmpegAudioReader::SetInputFormat(const char *name) {
//  m_input_fmt = av_find_input_format(name);
//  return m_input_fmt;
// }
pub fn setInputFormat(self: *Self, name: [:0]const u8) bool {
    self.input_fmt = c.av_find_input_format(name);
    return self.input_fmt != null;
}

// inline bool FFmpegAudioReader::SetInputSampleRate(int sample_rate) {
//  char buf[64];
//  sprintf(buf, "%d", sample_rate);
//  return av_dict_set(&m_input_opts, "sample_rate", buf, 0) >= 0;
// }
pub fn setInputSampleRate(self: *Self, sample_rate: c_int) bool {
    // if (self.input_opts) |input_opts| {
    //     try input_opts.set_int("sample_rate", @intCast(sample_rate), .{});
    //     return true;
    // }
    // return false;
     var buf: [64]u8 = undefined;
     const b = std.fmt.bufPrintSentinel(&buf, "{d}", .{sample_rate}, 0) catch unreachable;
     return c.av_dict_set(&self.input_opts, "sample_rate", b.ptr, 0) >= 0;
}

// inline bool FFmpegAudioReader::SetInputChannels(int channels) {
//     char buf[64];
//     sprintf(buf, "%d", channels);
//     return av_dict_set(&m_input_opts, "channels", buf, 0) >= 0;
// }
pub fn setInputChannels(self: *Self, channels: c_int) bool {
    // if (self.input_opts) |input_opts| {
    //     try input_opts.set_int("channels", @intCast(channels), .{});
    //     return true;
    // }
    // return false;
    var buf: [64]u8 = undefined;
    const b = std.fmt.bufPrintSentinel(&buf, "{d}", .{channels}, 0) catch unreachable;
    return c.av_dict_set(&self.input_opts, "channels", b.ptr, 0) >= 0;
}

pub fn open(self: *Self, file_name: [:0]const u8) error{OutOfMemory,SetOptError}!bool {
    var ret: c_int = undefined;

    self.close();

    // self.packet = try av.Packet.alloc();
    self.packet = c.av_packet_alloc();
	if (self.packet == null) {
        return error.OutOfMemory;
		// return error.PackAllocFailed;
	}

    // ret = av.avformat_open_input(&self.format_ctx, file_name, self.input_fmt, self.input_opts);
    ret = c.avformat_open_input(&self.format_ctx, file_name, self.input_fmt, &self.input_opts);
	if (ret < 0) {
		self.setError("Could not open the input file", ret);
		return false;
	}

    // ret = av.avformat_find_stream_info(self.format_ctx.?, null);
    ret = c.avformat_find_stream_info(self.format_ctx, null);
	if (ret < 0) {
		self.setError("Coud not find stream information in the file", ret);
		return false;
	}

    // var codec: ?*const av.Codec = null;
    var codec: [*c]const c.AVCodec = null;
    // ret = av.av_find_best_stream(self.format_ctx.?, .AUDIO, -1, -1, &codec, 0);
    ret = c.av_find_best_stream(self.format_ctx, c.AVMEDIA_TYPE_AUDIO, -1, -1, &codec, 0);
	if (ret < 0) {
		self.setError("Could not find any audio stream in the file", ret);
		return false;
	}
    self.stream_index = ret;
    // const stream: *av.Stream = self.format_ctx.?.streams[@intCast(self.stream_index)];
    const stream = self.format_ctx.?.streams[@intCast(self.stream_index)];

    self.codec_ctx = c.avcodec_alloc_context3(codec.?);
    // self.codec_ctx.?.request_sample_fmt = .S16;
    self.codec_ctx.?.request_sample_fmt = c.AV_SAMPLE_FMT_S16;

    // ret = av.avcodec_parameters_to_context(self.codec_ctx.?, stream.codecpar);
    ret = c.avcodec_parameters_to_context(self.codec_ctx, @as(?*c.AVStream, @ptrCast(stream)).?.codecpar);
	if (ret < 0) {
		self.setError("Could not copy the stream parameters", ret);
		return false;
	}

    // ret = av.avcodec_open2(self.codec_ctx.?, codec.?, null);
    ret = c.avcodec_open2(self.codec_ctx, codec, null);
	if (ret < 0) {
		self.setError("Could not open the codec", ret);
		return false;
	}

	// av_dump_format(m_format_ctx, 0, "foo", 0);
    // av.av_dump_format(self.format_ctx.?, 0, "foo", .input);
    // TODO: c.av_dump_format(self.format_ctx, 0, "ogg", 0);

    // self.frame = av.av_frame_alloc();
    self.frame = c.av_frame_alloc();
	if (self.frame == null) {
		// return false;
		return error.OutOfMemory;
	}

	if (self.output_sample_rate == 0) {
        self.output_sample_rate = self.codec_ctx.?.sample_rate;
	}

    // var output_channel_layout: av.ChannelLayout = undefined;
    var output_channel_layout: c.AVChannelLayout = undefined;
	if (self.output_channels != 0) {
		// av_channel_layout_default(&output_channel_layout, m_output_channels);
        c.av_channel_layout_default(&output_channel_layout, self.output_channels);
	} else {
		// m_output_channels = m_codec_ctx->ch_layout.nb_channels;
        self.output_channels = self.codec_ctx.?.ch_layout.nb_channels;
		// av_channel_layout_default(&output_channel_layout, m_output_channels);
        c.av_channel_layout_default(&output_channel_layout, self.output_channels);
	}

	// if (m_codec_ctx->sample_fmt != AV_SAMPLE_FMT_S16 || m_codec_ctx->ch_layout.nb_channels != m_output_channels || m_codec_ctx->sample_rate != m_output_sample_rate) {
    if (
        self.codec_ctx.?.sample_fmt != c.AV_SAMPLE_FMT_S16 
        or self.codec_ctx.?.ch_layout.nb_channels != self.output_channels 
        or self.codec_ctx.?.sample_rate != self.output_sample_rate
    ) {
		// m_converter.reset(new FFmpegAudioProcessor());
        if (self.converter) |*conv| conv.deinit();
        self.converter = .init();

        if (self.converter) |*converter| {
            ret = blk: {
                if (converter.swr_ctx != null) {
                    // m_converter->SetCompatibleMode();
                    try converter.setCompatibleMode();
                    // m_converter->SetInputSampleFormat(m_codec_ctx->sample_fmt);
                    try converter.setInputSampleFormat(self.codec_ctx.?.sample_fmt);
                    // m_converter->SetInputSampleRate(m_codec_ctx->sample_rate);
                    try converter.setInputSampleRate(self.codec_ctx.?.sample_rate);
                    // m_converter->SetInputChannelLayout(&(m_codec_ctx->ch_layout));
                    try converter.setInputChannelLayout(self.codec_ctx.?.ch_layout);
                    // m_converter->SetOutputSampleFormat(AV_SAMPLE_FMT_S16);
                    try converter.setOutputSampleFormat(c.AV_SAMPLE_FMT_S16);
                    // m_converter->SetOutputSampleRate(m_output_sample_rate);
                    try converter.setOutputSampleRate(self.output_sample_rate);
                    // m_converter->SetOutputChannelLayout(&output_channel_layout);
                    try converter.setOutputChannelLayout(output_channel_layout);
                    // auto ret = m_converter->Init();
                    break :blk converter.swrInit();
                } 
                break :blk c.AVERROR_UNKNOWN;
            };
            if (ret != 0) {
                self.setError("Could not create an audio converter instance", ret);
                return false;
            }
        }
    }

	// av_channel_layout_uninit(&output_channel_layout);
    // av.av_channel_layout_uninit(&output_channel_layout);
    c.av_channel_layout_uninit(&output_channel_layout);

    self.opened = true;
    self.has_more_frames = true;
    self.has_more_packets = true;
    self.decoder_error = 0;

	return true;
}

pub fn close(self: *Self) void {
    c.av_frame_free(&self.frame);
    c.av_packet_free(&self.packet);

    self.stream_index = -1;

    // avcodec_close(m_codec_ctx);
    // m_codec_ctx = nullptr;
    // _ = c.avcodec_close(@ptrCast(self.codec_ctx));
    if (self.codec_ctx) |*codec_ctx| c.avcodec_free_context(@ptrCast(codec_ctx));

	// avformat_close_input(&m_format_ctx);
    c.avformat_close_input(&self.format_ctx);
}

/// Get the sample rate in the audio stream.
/// @return sample rate in Hz, -1 on error
pub fn getSampleRate(self: *const Self) c_int {
    return self.output_sample_rate;
}

/// Get the number of channels in the audio stream.
/// @return number of channels, -1 on error
pub fn getChannels(self: *const Self) c_int {
    return self.output_channels;
}

/// Get the estimated audio stream duration.
/// @return stream duration in milliseconds, -1 on error
pub fn getDuration(self: *const Self) i64 {
    if (self.format_ctx != null and self.stream_index >= 0) {
        // const stream: *av.Stream = fmt_ctx.streams[self.stream_index];
        const stream: [*c]c.AVStream = self.format_ctx.?.streams[self.stream_index];
        // if (stream.duration != av.NOPTS_VALUE) {
        if (stream.duration != c.AV_NOPTS_VALUE) {
            return 1000 * @as(i64, @intCast(stream.time_base.num)) * stream.duration / @as(i64, @intCast(stream.time_base.den));
        // } else if (fmt_ctx.duration != c.NOPTS_VALUE) {
        } else if (self.format_ctx.?.duration != c.AV_NOPTS_VALUE) {
            return 1000 * self.format_ctx.?.duration / @as(i64, @intCast(c.AV_TIME_BASE));
        }
    }
	return -1;
}

// bool Read(const int16_t **data, size_t *size);
pub fn read(self: *Self, data: *[*c]i16, size: *c_int) bool {
    if (!self.isOpen() or self.isFinished()) {
		return false;
	}

    data.* = null;
    size.* = 0;

    var ret: c_int = undefined;
    var needs_packet: bool = false;
	while (true) {
		while (needs_packet and self.packet.?.size == 0) {
            // ret = av.av_read_frame(self.format_ctx.?, self.packet.?);
            ret = c.av_read_frame(self.format_ctx, self.packet);
			if (ret < 0) {
                // if (ret == @as(c_int, av.ERROR.EOF)) {
                if (ret == c.AVERROR_EOF) {
					needs_packet = false;
					self.has_more_packets = false;
					break;
				}
				self.setError("Error reading from the audio source", ret);
				return false;
			}
            if (self.packet.?.stream_index == self.stream_index) {
				needs_packet = false;
			} else {
				// av_packet_unref(m_packet);
                // self.packet.?.unref();
                c.av_packet_unref(self.packet);
			}
		}

        if (self.packet.?.size != 0) {
            // ret = av.avcodec_send_packet(self.codec_ctx, self.packet);
            ret = c.avcodec_send_packet(self.codec_ctx, self.packet);
			if (ret < 0) {
			    if (ret != c.AVERROR(c.EAGAIN)) {
			        self.setError("Error reading from the audio source", ret);
			        return false;
			    }
			} else {
			    c.av_packet_unref(self.packet);
			}
			//
            // if (self.codec_ctx.?.send_packet(self.packet)) {
            //     av.av_packet_unref(self.packet);
            // } else |err| {
            //     switch (err) {
            //         av.Error.WouldBlock => {
            //             std.debug.print("would block\n", .{});
            //         },
            //         av.Error.EndOfFile => {
            //             std.debug.print("end of file\n", .{});
            //         },
            //         else => {
            //             self.setError("Error reading from the audio source", ret);
            //             return false;
            //         }
            //     }
            // }
		}

        // ret = av.avcodec_receive_frame(self.codec_ctx, self.frame);
        ret = c.avcodec_receive_frame(self.codec_ctx, self.frame);
        if (ret < 0) {
            if (ret == c.AVERROR_EOF) {
                self.has_more_frames = false;
            } else if (ret == c.AVERROR(c.EAGAIN)) {
                if (self.has_more_packets) {
                    needs_packet = true;
                    continue;
                } else {
                    self.has_more_frames = false;
                }
            } else {
                self.setError("Error decoding the audio source", ret);
                return false;
            }
        }
        //     self.codec_ctx.?.receive_frame(self.frame) catch |err| switch (err) {
        //         av.Error.EndOfFile => self.has_more_frames = false,
        //         av.Error.WouldBlock => {
        //             if (self.has_more_packets) {
        //                 needs_packet = true;
        //                 continue;
        //             } else {
        //                 self.has_more_frames = false;
        //             }
        //         },
        //         else => {
        // self.setError("Error decoding the audio source", ret);
        // return false;
        //         }
        //     };

        if (self.frame.?.nb_samples > 0) {
            if (self.converter) |*converter| {
				if (self.frame.?.nb_samples > self.convert_buffer_nb_samples) {
					var linsize: c_int = undefined;
                    // av_freep(&m_convert_buffer[0]);
					c.av_freep(@ptrCast(&self.convert_buffer[0]));
                    // av.free(&self.convert_buffer[0]);
                    self.convert_buffer_nb_samples = @max(1024 * 8, self.frame.?.nb_samples);
					ret = c.av_samples_alloc(@ptrCast(&self.convert_buffer), &linsize, self.codec_ctx.?.ch_layout.nb_channels, self.convert_buffer_nb_samples, c.AV_SAMPLE_FMT_S16, 1);
                    // ret = c.av_samples_alloc(self.convert_buffer, &linsize, self.codec_ctx.?.ch_layout.nb_channels, self.convert_buffer_nb_sample, av.SampleFormat.S16, 1);
					if (ret < 0) {
					    self.setError("Couldn't allocate audio converter buffer", ret);
					    return false;
					}
				}
				// auto nb_samples = m_converter->Convert(m_convert_buffer, m_convert_buffer_nb_samples, (const uint8_t **) m_frame->data, m_frame->nb_samples);
                const nb_samples = converter.convert(@ptrCast(&self.convert_buffer), self.convert_buffer_nb_samples, @ptrCast(self.frame.?.data[0..]), self.frame.?.nb_samples);
				if (nb_samples < 0) {
					self.setError("Couldn't convert audio", ret);
					return false;
				}
				// *data = (const int16_t *) m_convert_buffer[0];
                data.* = @ptrCast(@alignCast(self.convert_buffer[0]));
				// *size = nb_samples;
                size.* = nb_samples;
			} else {
				// *data = (const int16_t *) m_frame->data[0];
                data.* = @ptrCast(@alignCast(self.frame.?.data[0]));
				// *size = m_frame->nb_samples;
                size.* = self.frame.?.nb_samples;
			}
		} else {
			if (self.converter) |*converter| {
				if (self.isFinished()) {
					// auto nb_samples = m_converter->Flush(m_convert_buffer, m_convert_buffer_nb_samples);
                    const nb_samples = converter.flush(@ptrCast(&self.convert_buffer), self.convert_buffer_nb_samples);
					if (nb_samples < 0) {
						self.setError("Couldn't convert audio", nb_samples);
						return false;
					} else if (nb_samples > 0) {
						// *data = (const int16_t *) m_convert_buffer[0];
                        data.* = @ptrCast(@alignCast(self.convert_buffer[0]));
						// *size = nb_samples;
                        size.* = nb_samples;
					}
				}
			}
		}

		return true;
	}
}

