/// AudioBufferConverterTests.swift
/// Tests for PCM audio format conversion utilities used by QuinnVoice.
///
/// Covers float↔int16 conversion, RMS level computation, sample rate
/// conversion, and empty/edge-case buffer handling.

import AVFoundation
import XCTest

@testable import QuinnVoice

final class AudioBufferConverterTests: XCTestCase {

    // MARK: - Float-to-Int16 Conversion

    /// Silence (all zeros) should convert to all-zero int16 data.
    func testFloatToInt16_silence() throws {
        let buffer = try makeFloat32Buffer(sampleRate: 16000, samples: [Float](repeating: 0.0, count: 160))
        let data = AudioBufferConverter.bufferToInt16Data(buffer)
        XCTAssertNotNil(data)
        guard let data else { return }

        // Every pair of bytes should be 0
        let samples = data.withUnsafeBytes { $0.bindMemory(to: Int16.self) }
        for sample in samples {
            XCTAssertEqual(sample, 0, "Silence should produce zero int16 samples")
        }
    }

    /// Maximum positive float (+1.0) should map near Int16.max (32767).
    func testFloatToInt16_maxPositive() throws {
        let buffer = try makeFloat32Buffer(sampleRate: 16000, samples: [1.0])
        let data = AudioBufferConverter.bufferToInt16Data(buffer)
        XCTAssertNotNil(data)
        guard let data else { return }

        let sample = data.withUnsafeBytes { $0.load(as: Int16.self) }
        // Allow some tolerance for converter rounding
        XCTAssertGreaterThan(sample, 32000, "Max positive float should map near Int16.max")
    }

    /// Maximum negative float (−1.0) should map near Int16.min (−32768).
    func testFloatToInt16_maxNegative() throws {
        let buffer = try makeFloat32Buffer(sampleRate: 16000, samples: [-1.0])
        let data = AudioBufferConverter.bufferToInt16Data(buffer)
        XCTAssertNotNil(data)
        guard let data else { return }

        let sample = data.withUnsafeBytes { $0.load(as: Int16.self) }
        XCTAssertLessThan(sample, -32000, "Max negative float should map near Int16.min")
    }

    /// Mid-range value (0.5) should map to roughly half of Int16.max.
    func testFloatToInt16_midRange() throws {
        let buffer = try makeFloat32Buffer(sampleRate: 16000, samples: [0.5])
        let data = AudioBufferConverter.bufferToInt16Data(buffer)
        XCTAssertNotNil(data)
        guard let data else { return }

        let sample = data.withUnsafeBytes { $0.load(as: Int16.self) }
        // 0.5 * 32767 ≈ 16383; allow generous tolerance
        XCTAssertGreaterThan(sample, 14000)
        XCTAssertLessThan(sample, 18000)
    }

    // MARK: - Int16-to-Float (Round-Trip)

    /// Converting int16 data to a playback buffer and extracting samples should
    /// produce values proportional to the original int16 values.
    func testInt16ToFloat_roundTrip() throws {
        // Create known int16 data: silence, positive, negative
        let int16Samples: [Int16] = [0, 16384, -16384, 32767, -32768]
        var data = Data(count: int16Samples.count * 2)
        data.withUnsafeMutableBytes { ptr in
            let dst = ptr.bindMemory(to: Int16.self)
            for (i, s) in int16Samples.enumerated() {
                dst[i] = s
            }
        }

        let buffer = AudioBufferConverter.int16DataToPlaybackBuffer(data)
        XCTAssertNotNil(buffer, "Should produce a playback buffer from valid int16 data")
        guard let buffer else { return }

        XCTAssertEqual(buffer.format.commonFormat, .pcmFormatFloat32)
        XCTAssertEqual(buffer.format.sampleRate, 24000, accuracy: 1.0,
                       "Output should be 24kHz for playback")
        // Frame count may differ due to sample-rate conversion (16→24 isn't happening here,
        // the input is already 24kHz int16). Just check we got samples.
        XCTAssertGreaterThan(buffer.frameLength, 0)
    }

    // MARK: - RMS Level

    /// Silence buffer should have RMS level of 0.
    func testRMSLevel_silence() throws {
        let buffer = try makeFloat32Buffer(sampleRate: 24000, samples: [Float](repeating: 0.0, count: 480))
        let level = AudioBufferConverter.rmsLevel(of: buffer)
        XCTAssertEqual(level, 0.0, accuracy: 0.001, "Silence should have RMS of 0")
    }

    /// Full-scale sine should produce an RMS level clamped at 1.0.
    func testRMSLevel_fullScale() throws {
        // Full scale = all samples at ±1.0. RMS of 1.0 * 10 = 10 → clamped to 1.0
        let samples = [Float](repeating: 1.0, count: 480)
        let buffer = try makeFloat32Buffer(sampleRate: 24000, samples: samples)
        let level = AudioBufferConverter.rmsLevel(of: buffer)
        XCTAssertEqual(level, 1.0, accuracy: 0.01, "Full-scale signal should clamp to 1.0")
    }

    /// Known mid-level signal should produce a predictable RMS.
    func testRMSLevel_knownValue() throws {
        // All samples at 0.05 → RMS = 0.05, * 10 = 0.5
        let samples = [Float](repeating: 0.05, count: 480)
        let buffer = try makeFloat32Buffer(sampleRate: 24000, samples: samples)
        let level = AudioBufferConverter.rmsLevel(of: buffer)
        XCTAssertEqual(level, 0.5, accuracy: 0.05, "RMS of 0.05 constant signal * 10 ≈ 0.5")
    }

    /// RMS of a non-float32 buffer should return 0 (guard clause).
    func testRMSLevel_nonFloat32ReturnsZero() throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160)!
        buffer.frameLength = 160
        let level = AudioBufferConverter.rmsLevel(of: buffer)
        XCTAssertEqual(level, 0.0, "Non-float32 buffer should return 0")
    }

    // MARK: - Sample Rate Conversion

    /// Converting a 48kHz buffer to 16kHz should produce a buffer with roughly 1/3 the frames.
    func testSampleRateConversion_48kTo16k() throws {
        let samples = [Float](repeating: 0.5, count: 4800) // 100ms at 48kHz
        let buffer = try makeFloat32Buffer(sampleRate: 48000, samples: samples)
        let target = AudioBufferConverter.inputFormat // 16kHz int16 mono

        let converted = AudioBufferConverter.convert(buffer: buffer, to: target)
        XCTAssertNotNil(converted)
        guard let converted else { return }

        // 4800 samples at 48kHz → ~1600 at 16kHz
        let expectedFrames = AVAudioFrameCount(4800 * 16000 / 48000)
        XCTAssertEqual(converted.frameLength, expectedFrames, "Frame count should scale with sample rate ratio")
    }

    /// Converting between identical formats should preserve frame count.
    func testSampleRateConversion_sameRate() throws {
        let samples = [Float](repeating: 0.25, count: 160)
        let sourceFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: 160)!
        buffer.frameLength = 160
        let ptr = buffer.floatChannelData![0]
        for i in 0..<160 { ptr[i] = samples[i] }

        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let converted = AudioBufferConverter.convert(buffer: buffer, to: targetFormat)
        XCTAssertNotNil(converted)
        XCTAssertEqual(converted?.frameLength, 160)
    }

    // MARK: - Empty Buffer Handling

    /// An empty Data should return nil from int16DataToPlaybackBuffer.
    func testEmptyData_returnsNil() {
        let result = AudioBufferConverter.int16DataToPlaybackBuffer(Data())
        XCTAssertNil(result, "Empty data should return nil")
    }

    /// A single byte (not enough for one int16 sample) should return nil.
    func testSingleByte_returnsNil() {
        let result = AudioBufferConverter.int16DataToPlaybackBuffer(Data([0x42]))
        XCTAssertNil(result, "Single byte is not a valid int16 sample")
    }

    /// Zero-length float32 buffer should return 0 RMS.
    func testZeroLengthBuffer_rmsIsZero() {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 0)!
        buffer.frameLength = 0
        XCTAssertEqual(AudioBufferConverter.rmsLevel(of: buffer), 0.0)
    }

    // MARK: - Int16 Buffer Direct Extraction

    /// bufferToInt16Data on an already-int16 buffer should extract bytes directly.
    func testBufferToInt16Data_alreadyInt16() throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3)!
        buffer.frameLength = 3
        let ptr = buffer.int16ChannelData![0]
        ptr[0] = 1000
        ptr[1] = -2000
        ptr[2] = 32767

        let data = AudioBufferConverter.bufferToInt16Data(buffer)
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.count, 6, "3 int16 samples = 6 bytes")

        if let data {
            let extracted = data.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
            XCTAssertEqual(extracted, [1000, -2000, 32767])
        }
    }

    // MARK: - Helpers

    /// Create a float32 mono non-interleaved AVAudioPCMBuffer with the given samples.
    private func makeFloat32Buffer(sampleRate: Double, samples: [Float]) throws -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let ptr = buffer.floatChannelData![0]
        for (i, sample) in samples.enumerated() {
            ptr[i] = sample
        }
        return buffer
    }
}
