/// AudioBufferConverterTests.swift — Comprehensive tests for audio format conversion.

import AVFoundation
import XCTest

@testable import QuinnVoice

final class AudioBufferConverterTests: XCTestCase {

    // MARK: - Float-to-Int16 Conversion

    func testFloatToInt16_silence() throws {
        let buffer = try makeFloat32Buffer(sampleRate: 16000, samples: [Float](repeating: 0.0, count: 160))
        let data = AudioBufferConverter.bufferToInt16Data(buffer)
        XCTAssertNotNil(data)
        guard let data else { return }

        let samples = data.withUnsafeBytes { $0.bindMemory(to: Int16.self) }
        for sample in samples {
            XCTAssertEqual(sample, 0, "Silence should produce zero int16 samples")
        }
    }

    func testFloatToInt16_maxPositive() throws {
        let buffer = try makeFloat32Buffer(sampleRate: 16000, samples: [1.0])
        let data = AudioBufferConverter.bufferToInt16Data(buffer)
        XCTAssertNotNil(data)
        guard let data else { return }

        let sample = data.withUnsafeBytes { $0.load(as: Int16.self) }
        XCTAssertGreaterThan(sample, 32000, "Max positive float should map near Int16.max (32767)")
    }

    func testFloatToInt16_maxNegative() throws {
        let buffer = try makeFloat32Buffer(sampleRate: 16000, samples: [-1.0])
        let data = AudioBufferConverter.bufferToInt16Data(buffer)
        XCTAssertNotNil(data)
        guard let data else { return }

        let sample = data.withUnsafeBytes { $0.load(as: Int16.self) }
        XCTAssertLessThan(sample, -32000, "Max negative float should map near Int16.min (-32768)")
    }

    func testFloatToInt16_midRange() throws {
        let buffer = try makeFloat32Buffer(sampleRate: 16000, samples: [0.5])
        let data = AudioBufferConverter.bufferToInt16Data(buffer)
        XCTAssertNotNil(data)
        guard let data else { return }

        let sample = data.withUnsafeBytes { $0.load(as: Int16.self) }
        XCTAssertGreaterThan(sample, 14000)
        XCTAssertLessThan(sample, 18000)
    }

    func testFloatToInt16_negativeMidRange() throws {
        let buffer = try makeFloat32Buffer(sampleRate: 16000, samples: [-0.5])
        let data = AudioBufferConverter.bufferToInt16Data(buffer)
        XCTAssertNotNil(data)
        guard let data else { return }

        let sample = data.withUnsafeBytes { $0.load(as: Int16.self) }
        XCTAssertLessThan(sample, -14000)
        XCTAssertGreaterThan(sample, -18000)
    }

    func testFloatToInt16_smallValue() throws {
        let buffer = try makeFloat32Buffer(sampleRate: 16000, samples: [0.01])
        let data = AudioBufferConverter.bufferToInt16Data(buffer)
        XCTAssertNotNil(data)
        guard let data else { return }

        let sample = data.withUnsafeBytes { $0.load(as: Int16.self) }
        XCTAssertGreaterThan(sample, 200)
        XCTAssertLessThan(sample, 500)
    }

    // MARK: - Int16-to-Float (Round-Trip)

    func testInt16ToFloat_roundTrip() throws {
        let int16Samples: [Int16] = [0, 16384, -16384, 32767, -32768]
        var data = Data(count: int16Samples.count * 2)
        data.withUnsafeMutableBytes { ptr in
            let dst = ptr.bindMemory(to: Int16.self)
            for (i, s) in int16Samples.enumerated() {
                dst[i] = s
            }
        }

        let buffer = AudioBufferConverter.int16DataToPlaybackBuffer(data)
        XCTAssertNotNil(buffer)
        guard let buffer else { return }

        XCTAssertEqual(buffer.format.commonFormat, .pcmFormatFloat32)
        XCTAssertEqual(buffer.format.sampleRate, 24000, accuracy: 1.0)
        XCTAssertGreaterThan(buffer.frameLength, 0)
    }

    func testInt16ToFloat_singleSample() throws {
        var data = Data(count: 2)
        data.withUnsafeMutableBytes { ptr in
            ptr.bindMemory(to: Int16.self)[0] = 16384
        }

        let buffer = AudioBufferConverter.int16DataToPlaybackBuffer(data)
        XCTAssertNotNil(buffer)
    }

    // MARK: - RMS Level

    func testRMSLevel_silence() throws {
        let buffer = try makeFloat32Buffer(sampleRate: 24000, samples: [Float](repeating: 0.0, count: 480))
        let level = AudioBufferConverter.rmsLevel(of: buffer)
        XCTAssertEqual(level, 0.0, accuracy: 0.001)
    }

    func testRMSLevel_fullScale() throws {
        let samples = [Float](repeating: 1.0, count: 480)
        let buffer = try makeFloat32Buffer(sampleRate: 24000, samples: samples)
        let level = AudioBufferConverter.rmsLevel(of: buffer)
        XCTAssertEqual(level, 1.0, accuracy: 0.01, "Full-scale signal should clamp to 1.0")
    }

    func testRMSLevel_knownValue() throws {
        // All samples at 0.05 → RMS = 0.05, * 10 = 0.5
        let samples = [Float](repeating: 0.05, count: 480)
        let buffer = try makeFloat32Buffer(sampleRate: 24000, samples: samples)
        let level = AudioBufferConverter.rmsLevel(of: buffer)
        XCTAssertEqual(level, 0.5, accuracy: 0.05)
    }

    func testRMSLevel_sineWave() throws {
        // Sine wave at full amplitude: RMS ≈ 1/√2 ≈ 0.707, * 10 → clamped to 1.0
        var samples = [Float](repeating: 0, count: 1000)
        for i in 0..<1000 {
            samples[i] = sin(Float(i) * 2.0 * .pi / 100.0)
        }
        let buffer = try makeFloat32Buffer(sampleRate: 24000, samples: samples)
        let level = AudioBufferConverter.rmsLevel(of: buffer)
        XCTAssertEqual(level, 1.0, accuracy: 0.05, "Full-amplitude sine wave RMS*10 should clamp to 1.0")
    }

    func testRMSLevel_quietSineWave() throws {
        // Sine wave at amplitude 0.01: RMS ≈ 0.00707, * 10 ≈ 0.0707
        var samples = [Float](repeating: 0, count: 1000)
        for i in 0..<1000 {
            samples[i] = 0.01 * sin(Float(i) * 2.0 * .pi / 100.0)
        }
        let buffer = try makeFloat32Buffer(sampleRate: 24000, samples: samples)
        let level = AudioBufferConverter.rmsLevel(of: buffer)
        XCTAssertGreaterThan(level, 0.01)
        XCTAssertLessThan(level, 0.15)
    }

    func testRMSLevel_nonFloat32ReturnsZero() throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160)!
        buffer.frameLength = 160
        XCTAssertEqual(AudioBufferConverter.rmsLevel(of: buffer), 0.0)
    }

    // MARK: - Empty Buffer Handling

    func testEmptyData_returnsNil() {
        XCTAssertNil(AudioBufferConverter.int16DataToPlaybackBuffer(Data()))
    }

    func testSingleByte_returnsNil() {
        XCTAssertNil(AudioBufferConverter.int16DataToPlaybackBuffer(Data([0x42])))
    }

    func testZeroLengthBuffer_rmsIsZero() {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 0)!
        buffer.frameLength = 0
        XCTAssertEqual(AudioBufferConverter.rmsLevel(of: buffer), 0.0)
    }

    // MARK: - Odd Size Buffers

    func testOddSampleCount_floatToInt16() throws {
        let buffer = try makeFloat32Buffer(sampleRate: 16000, samples: [0.1, 0.2, 0.3])
        let data = AudioBufferConverter.bufferToInt16Data(buffer)
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.count, 6, "3 int16 samples = 6 bytes")
    }

    func testSingleSample_floatToInt16() throws {
        let buffer = try makeFloat32Buffer(sampleRate: 16000, samples: [0.5])
        let data = AudioBufferConverter.bufferToInt16Data(buffer)
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.count, 2, "1 int16 sample = 2 bytes")
    }

    // MARK: - Clipping Behavior

    func testClipping_aboveOne() throws {
        // Values > 1.0 should clip at Int16.max
        let buffer = try makeFloat32Buffer(sampleRate: 16000, samples: [1.5])
        let data = AudioBufferConverter.bufferToInt16Data(buffer)
        XCTAssertNotNil(data)
        guard let data else { return }

        let sample = data.withUnsafeBytes { $0.load(as: Int16.self) }
        // Should be clamped at or near Int16.max
        XCTAssertEqual(sample, 32767, "Values > 1.0 should clip to Int16.max")
    }

    func testClipping_belowNegativeOne() throws {
        let buffer = try makeFloat32Buffer(sampleRate: 16000, samples: [-1.5])
        let data = AudioBufferConverter.bufferToInt16Data(buffer)
        XCTAssertNotNil(data)
        guard let data else { return }

        let sample = data.withUnsafeBytes { $0.load(as: Int16.self) }
        XCTAssertEqual(sample, -32768, "Values < -1.0 should clip to Int16.min")
    }

    // MARK: - Int16 Buffer Direct Extraction

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
        XCTAssertEqual(data?.count, 6)

        if let data {
            let extracted = data.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
            XCTAssertEqual(extracted, [1000, -2000, 32767])
        }
    }

    // MARK: - Sample Rate Conversion

    func testSampleRateConversion_48kTo16k() throws {
        let samples = [Float](repeating: 0.5, count: 4800)
        let buffer = try makeFloat32Buffer(sampleRate: 48000, samples: samples)
        let target = AudioBufferConverter.inputFormat

        let converted = AudioBufferConverter.convert(buffer: buffer, to: target)
        XCTAssertNotNil(converted)
        guard let converted else { return }

        // After downsampling from 48kHz to 16kHz, frame count should be roughly 1/3
        // Allow some tolerance for the converter implementation
        XCTAssertGreaterThan(converted.frameLength, 1000)
        XCTAssertLessThan(converted.frameLength, 2000)
    }

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

    // MARK: - Static Format Properties

    func testInputFormat_is16kHzInt16Mono() {
        let fmt = AudioBufferConverter.inputFormat
        XCTAssertEqual(fmt.commonFormat, .pcmFormatInt16)
        XCTAssertEqual(fmt.sampleRate, 16000)
        XCTAssertEqual(fmt.channelCount, 1)
    }

    func testOutputFormat_is24kHzInt16Mono() {
        let fmt = AudioBufferConverter.outputFormat
        XCTAssertEqual(fmt.commonFormat, .pcmFormatInt16)
        XCTAssertEqual(fmt.sampleRate, 24000)
        XCTAssertEqual(fmt.channelCount, 1)
    }

    func testOutputFloatFormat_is24kHzFloat32Mono() {
        let fmt = AudioBufferConverter.outputFloatFormat
        XCTAssertEqual(fmt.commonFormat, .pcmFormatFloat32)
        XCTAssertEqual(fmt.sampleRate, 24000)
        XCTAssertEqual(fmt.channelCount, 1)
    }

    // MARK: - Helpers

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
