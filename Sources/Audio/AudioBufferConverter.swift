import AVFoundation
import Foundation

/// Utilities for converting audio between formats needed by Gemini Live API.
enum AudioBufferConverter {

    /// Standard format for mic capture → Gemini input: 16-bit PCM, 16kHz, mono.
    static let inputFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16000,
        channels: 1,
        interleaved: true
    )!

    /// Standard format for Gemini output → speaker playback: 16-bit PCM, 24kHz, mono.
    static let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24000,
        channels: 1,
        interleaved: true
    )!

    /// Float32 version of output format for AVAudioPlayerNode.
    static let outputFloatFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 24000,
        channels: 1,
        interleaved: false
    )!

    /// Convert an AVAudioPCMBuffer to a different format using an AVAudioConverter.
    static func convert(buffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else {
            return nil
        }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
            return nil
        }

        var error: NSError?
        var allConsumed = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if allConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            allConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error {
            print("[AudioBufferConverter] Conversion error: \(error)")
            return nil
        }

        return outputBuffer
    }

    /// Convert an AVAudioPCMBuffer (float or int) to raw 16-bit PCM Data for sending over WebSocket.
    static func bufferToInt16Data(_ buffer: AVAudioPCMBuffer) -> Data? {
        // If already int16, extract directly
        if buffer.format.commonFormat == .pcmFormatInt16 {
            let int16Ptr = buffer.int16ChannelData!
            let count = Int(buffer.frameLength)
            return Data(bytes: int16Ptr[0], count: count * 2)
        }

        // Convert float32 → int16
        guard let int16Buffer = convert(buffer: buffer, to: AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: buffer.format.sampleRate,
            channels: buffer.format.channelCount,
            interleaved: true
        )!) else {
            return nil
        }

        let count = Int(int16Buffer.frameLength)
        return Data(bytes: int16Buffer.int16ChannelData![0], count: count * 2)
    }

    /// Convert raw 16-bit PCM data (from Gemini) into an AVAudioPCMBuffer for playback.
    /// Returns a float32 buffer at 24kHz mono, ready for AVAudioPlayerNode.
    static func int16DataToPlaybackBuffer(_ data: Data) -> AVAudioPCMBuffer? {
        let sampleCount = data.count / 2
        guard sampleCount > 0 else { return nil }

        // Create int16 buffer
        guard let int16Buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(sampleCount)) else {
            return nil
        }
        int16Buffer.frameLength = AVAudioFrameCount(sampleCount)

        data.withUnsafeBytes { rawPtr in
            let src = rawPtr.bindMemory(to: Int16.self)
            let dst = int16Buffer.int16ChannelData![0]
            for i in 0..<sampleCount {
                dst[i] = src[i]
            }
        }

        // Convert to float32 for AVAudioPlayerNode
        return convert(buffer: int16Buffer, to: outputFloatFormat)
    }

    /// Compute RMS level (0…1) from a float32 buffer.
    static func rmsLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard buffer.format.commonFormat == .pcmFormatFloat32,
              let channelData = buffer.floatChannelData else { return 0 }

        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }

        var sum: Float = 0
        let ptr = channelData[0]
        for i in 0..<count {
            let sample = ptr[i]
            sum += sample * sample
        }

        let rms = sqrtf(sum / Float(count))
        // Normalize to roughly 0…1 range (typical speech RMS ~0.01–0.1)
        return min(rms * 10.0, 1.0)
    }
}
