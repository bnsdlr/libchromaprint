pub const c = @cImport({
    @cInclude("libavcodec/avcodec.h");
    @cInclude("libavformat/avformat.h");
    @cInclude("libavutil/opt.h");
    @cInclude("libavutil/samplefmt.h");
    @cInclude("libswresample/swresample.h");
});

pub const audio = @import("audio.zig");
pub const AudioReader = audio.Reader;

pub const chromaprint = @import("chromaprint.zig");
pub const chromaprintDealloc = chromaprint.dealloc;
pub const ChromaprintContext = chromaprint.Context;
pub const ChromaprintAlgorithm = chromaprint.Alogrithm;
pub const ChromaprintError = chromaprint.Error;

pub const fpcalc = @import("fpcalc.zig");
pub const calcFingerprint = fpcalc.calcFingerprint;
pub const FingerprintCalcError = fpcalc.FingerprintCalcError;
pub const FingerprintCalcOpts = fpcalc.FingerprintCalcOpts;

