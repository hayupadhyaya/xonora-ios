// ABOUTME: Audio decoder for FLAC, Opus, and PCM codecs
// ABOUTME: Converts compressed audio to PCM for playback, handles 24-bit unpacking

@preconcurrency import AVFoundation
import Foundation
import Opus
import FLAC

/// Audio decoder protocol
public protocol AudioDecoder {
    func decode(_ data: Data) throws -> Data
}

/// PCM decoder supporting 16-bit and 24-bit formats
public class PCMDecoder: AudioDecoder {
    private let bitDepth: Int
    private let channels: Int

    public init(bitDepth: Int, channels: Int) {
        self.bitDepth = bitDepth
        self.channels = channels
    }

    public func decode(_ data: Data) throws -> Data {
        switch bitDepth {
        case 16:
            // 16-bit PCM - pass through (already correct format)
            return data

        case 24:
            // 24-bit PCM - unpack 3-byte samples to 4-byte Int32
            return try decode24Bit(data)

        case 32:
            // 32-bit PCM - pass through
            return data

        default:
            throw AudioDecoderError.unsupportedBitDepth(bitDepth)
        }
    }

    private func decode24Bit(_ data: Data) throws -> Data {
        let bytesPerSample = 3
        guard data.count % bytesPerSample == 0 else {
            throw AudioDecoderError.invalidDataSize(
                expected: "multiple of 3",
                actual: data.count
            )
        }

        let sampleCount = data.count / bytesPerSample
        let bytes = [UInt8](data)

        // Unpack 24-bit samples to Int32 (4 bytes per sample)
        var samples = [Int32]()
        samples.reserveCapacity(sampleCount)

        for i in 0 ..< sampleCount {
            // Unpack 24-bit sample and shift to fill 32-bit range
            let sample = PCMUtilities.unpack24Bit(bytes, offset: i * bytesPerSample)
            samples.append(sample << 8)
        }

        // Convert Int32 array to Data
        return samples.withUnsafeBytes { Data($0) }
    }
}

/// Opus decoder using libopus via swift-opus package
public class OpusDecoder: AudioDecoder {
    private let decoder: Opus.Decoder
    private let channels: Int

    public init(sampleRate: Int, channels: Int, bitDepth: Int) throws {
        self.channels = channels

        // Create AVAudioFormat for Opus decoder
        // swift-opus accepts standard PCM formats and handles Opus internally
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: AVAudioChannelCount(channels),
            interleaved: true
        ) else {
            throw AudioDecoderError.formatCreationFailed("Failed to create audio format for Opus")
        }

        // Create opus decoder (validates sample rate internally)
        do {
            self.decoder = try Opus.Decoder(format: format)
        } catch {
            throw AudioDecoderError.formatCreationFailed("Opus decoder: \(error.localizedDescription)")
        }
    }

    public func decode(_ data: Data) throws -> Data {
        // Decode Opus packet to AVAudioPCMBuffer
        let pcmBuffer: AVAudioPCMBuffer
        do {
            pcmBuffer = try decoder.decode(data)
        } catch {
            throw AudioDecoderError.conversionFailed("Opus decode failed: \(error.localizedDescription)")
        }

        // swift-opus outputs float32 in AVAudioPCMBuffer
        // Convert float32 → int32 (24-bit left-justified format)
        guard let floatChannelData = pcmBuffer.floatChannelData else {
            throw AudioDecoderError.conversionFailed("No float channel data in decoded buffer")
        }

        let frameLength = Int(pcmBuffer.frameLength)
        let totalSamples = frameLength * channels
        var int32Samples = [Int32](repeating: 0, count: totalSamples)

        // Convert interleaved float32 samples to int32
        // float range [-1.0, 1.0] → int32 range [Int32.min, Int32.max]
        if channels == 1 {
            // Mono: direct conversion
            let floatData = floatChannelData[0]
            for i in 0..<frameLength {
                let floatSample = floatData[i]
                int32Samples[i] = Int32(floatSample * Float(Int32.max))
            }
        } else {
            // Stereo or multi-channel: interleave
            for channel in 0..<channels {
                let floatData = floatChannelData[channel]
                for frame in 0..<frameLength {
                    let floatSample = floatData[frame]
                    let sampleIndex = frame * channels + channel
                    int32Samples[sampleIndex] = Int32(floatSample * Float(Int32.max))
                }
            }
        }

        // Convert [Int32] to Data
        return int32Samples.withUnsafeBytes { Data($0) }
    }
}

/// FLAC decoder using libFLAC via flac-binary-xcframework
public class FLACDecoder: AudioDecoder {
    private var decoder: UnsafeMutablePointer<FLAC__StreamDecoder>?
    private let sampleRate: Int
    private let channels: Int
    private let bitDepth: Int
    private var pendingData: Data = Data()
    private var decodedSamples: [Int32] = []
    private var readOffset: Int = 0
    private var lastError: FLAC__StreamDecoderErrorStatus?

    public init(sampleRate: Int, channels: Int, bitDepth: Int) throws {
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitDepth = bitDepth

        // Create FLAC stream decoder
        guard let flacDecoder = FLAC__stream_decoder_new() else {
            throw AudioDecoderError.formatCreationFailed("Failed to create FLAC stream decoder")
        }
        self.decoder = flacDecoder

        // Initialize decoder with callbacks
        // We need to use Unmanaged to pass self to C callbacks
        let clientData = Unmanaged.passUnretained(self).toOpaque()

        let initStatus = FLAC__stream_decoder_init_stream(
            decoder,
            { decoder, buffer, bytes, clientData -> FLAC__StreamDecoderReadStatus in
                guard let clientData = clientData else {
                    return FLAC__STREAM_DECODER_READ_STATUS_ABORT
                }
                let selfRef = Unmanaged<FLACDecoder>.fromOpaque(clientData).takeUnretainedValue()
                return selfRef.readCallback(buffer: buffer, bytes: bytes)
            },
            nil,  // seek callback (optional)
            nil,  // tell callback (optional)
            nil,  // length callback (optional)
            nil,  // eof callback (optional)
            { decoder, frame, buffer, clientData -> FLAC__StreamDecoderWriteStatus in
                guard let clientData = clientData else {
                    return FLAC__STREAM_DECODER_WRITE_STATUS_ABORT
                }
                let selfRef = Unmanaged<FLACDecoder>.fromOpaque(clientData).takeUnretainedValue()
                return selfRef.writeCallback(frame: frame, buffer: buffer)
            },
            nil,  // metadata callback (optional)
            { decoder, status, clientData in
                // Error callback - store error for later checking
                guard let clientData = clientData else { return }
                let selfRef = Unmanaged<FLACDecoder>.fromOpaque(clientData).takeUnretainedValue()
                selfRef.lastError = status
            },
            clientData
        )

        guard initStatus == FLAC__STREAM_DECODER_INIT_STATUS_OK else {
            FLAC__stream_decoder_delete(flacDecoder)
            throw AudioDecoderError.formatCreationFailed("FLAC decoder init failed: \(initStatus)")
        }
    }

    public func decode(_ data: Data) throws -> Data {
        // Append new data to pending buffer
        pendingData.append(data)
        decodedSamples.removeAll(keepingCapacity: true)
        lastError = nil

        // Process single frame
        guard let decoder = decoder else {
            throw AudioDecoderError.conversionFailed("FLAC decoder not initialized")
        }

        // CRITICAL: readOffset tracks decoder's position in pendingData
        // DON'T reset to 0 - decoder maintains internal state and continues from last position
        // The readCallback will be called and will read from readOffset

        // Process blocks until we get audio samples
        // First block is always STREAMINFO metadata, subsequent blocks are audio frames
        // For complete FLAC files, we need multiple process_single() calls to advance
        // through metadata blocks to reach audio frames
        var iterations = 0
        let startOffset = readOffset
        while decodedSamples.isEmpty {
            iterations += 1
            let success = FLAC__stream_decoder_process_single(decoder)
            let state = FLAC__stream_decoder_get_state(decoder)

            guard success != 0 else {
                throw AudioDecoderError.conversionFailed("FLAC frame processing failed: state=\(state)")
            }

            // Check if we've hit end of stream or processed all available data
            if state == FLAC__STREAM_DECODER_END_OF_STREAM {
                break
            }

            // If readOffset didn't advance, we need more data (for streaming use case)
            if readOffset == startOffset && iterations > 1 {
                break
            }

            // Safety limit to prevent infinite loops
            let maxDecoderIterations = 100
            if iterations > maxDecoderIterations {
                print("[FLACDecoder] Warning: hit max decoder iterations (\(maxDecoderIterations)), breaking")
                break
            }
        }

        // Check for errors reported via error callback
        if let error = lastError {
            throw AudioDecoderError.conversionFailed("FLAC decoder error: \(error)")
        }

        // Remove consumed bytes from pending buffer to prevent memory leak
        // Only remove bytes that were actually read during THIS decode() call
        let bytesConsumed = readOffset - startOffset
        if bytesConsumed > 0 {
            pendingData.removeFirst(bytesConsumed)
            readOffset = startOffset  // Adjust readOffset to account for removed bytes
        }

        // Return decoded samples as Data
        return decodedSamples.withUnsafeBytes { Data($0) }
    }

    private func readCallback(buffer: UnsafeMutablePointer<FLAC__byte>?, bytes: UnsafeMutablePointer<Int>?) -> FLAC__StreamDecoderReadStatus {
        guard let buffer = buffer, let bytes = bytes else {
            return FLAC__STREAM_DECODER_READ_STATUS_ABORT
        }

        let bytesToRead = min(bytes.pointee, pendingData.count - readOffset)

        guard bytesToRead > 0 else {
            bytes.pointee = 0
            return FLAC__STREAM_DECODER_READ_STATUS_END_OF_STREAM
        }

        // Copy data from pending buffer
        pendingData.withUnsafeBytes { srcBytes in
            guard let base = srcBytes.baseAddress else {
                bytes.pointee = 0
                return
            }
            let src = base.advanced(by: readOffset)
            memcpy(buffer, src, bytesToRead)
        }

        readOffset += bytesToRead
        bytes.pointee = bytesToRead

        return FLAC__STREAM_DECODER_READ_STATUS_CONTINUE
    }

    private func writeCallback(frame: UnsafePointer<FLAC__Frame>?, buffer: UnsafePointer<UnsafePointer<FLAC__int32>?>?) -> FLAC__StreamDecoderWriteStatus {
        guard let frame = frame, let buffer = buffer else {
            return FLAC__STREAM_DECODER_WRITE_STATUS_ABORT
        }

        let blocksize = Int(frame.pointee.header.blocksize)

        // FLAC outputs int32 samples per channel
        // Interleave channels if stereo
        for i in 0..<blocksize {
            for channel in 0..<channels {
                guard let channelBuffer = buffer[channel] else {
                    return FLAC__STREAM_DECODER_WRITE_STATUS_ABORT
                }
                let sample = channelBuffer[i]

                // Normalize based on bit depth to full 32-bit range
                // FLAC int32 samples are right-aligned
                // AudioPlayer expects full-scale 32-bit integers
                let normalizedSample: Int32
                if bitDepth == 16 {
                    // 16-bit: shift left 16 bits to fill 32-bit range
                    normalizedSample = sample << 16
                } else if bitDepth == 24 {
                    // 24-bit: shift left 8 bits to fill 32-bit range
                    normalizedSample = sample << 8
                } else {
                    // 32-bit or other: pass through
                    normalizedSample = sample
                }

                decodedSamples.append(normalizedSample)
            }
        }

        return FLAC__STREAM_DECODER_WRITE_STATUS_CONTINUE
    }

    deinit {
        if let decoder = decoder {
            FLAC__stream_decoder_finish(decoder)
            FLAC__stream_decoder_delete(decoder)
        }
    }
}

/// Creates decoder for specified codec
public enum AudioDecoderFactory {
    public static func create(
        codec: AudioCodec,
        sampleRate: Int,
        channels: Int,
        bitDepth: Int,
        header _: Data?
    ) throws -> AudioDecoder {
        switch codec {
        case .pcm:
            return PCMDecoder(bitDepth: bitDepth, channels: channels)
        case .opus:
            return try OpusDecoder(sampleRate: sampleRate, channels: channels, bitDepth: bitDepth)
        case .flac:
            return try FLACDecoder(sampleRate: sampleRate, channels: channels, bitDepth: bitDepth)
        }
    }
}

/// Audio decoder errors
public enum AudioDecoderError: Error {
    case unsupportedBitDepth(Int)
    case invalidDataSize(expected: String, actual: Int)
    case formatCreationFailed(String)
    case converterCreationFailed
    case bufferCreationFailed
    case conversionFailed(String)
}
