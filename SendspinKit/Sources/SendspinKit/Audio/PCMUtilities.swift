// ABOUTME: PCM sample conversion utilities for multi-bit-depth audio
// ABOUTME: Handles 24-bit unpacking/packing and 16-bit to 24-bit conversion

import Foundation
import Accelerate

/// PCM sample conversion utilities
public enum PCMUtilities {
    /// 24-bit sample range constants
    public static let max24Bit: Int32 = 8_388_607 // 2^23 - 1
    public static let min24Bit: Int32 = -8_388_608 // -2^23

    /// Apply volume scaling using vDSP (Accelerate)
    /// - Parameters:
    ///   - data: PCM data (Int16)
    ///   - volume: Volume scale factor (0.0 to 1.0)
    /// - Returns: Scaled PCM data
    public static func applyVolume(_ data: Data, volume: Float) -> Data {
        guard volume < 1.0 else { return data }
        
        let count = data.count / 2
        var samples = [Int16](repeating: 0, count: count)
        _ = samples.withUnsafeMutableBytes { ptr in
            data.copyBytes(to: ptr)
        }
        
        // Convert to Float for processing
        var floatSamples = [Float](repeating: 0, count: count)
        vDSP_vflt16(samples, 1, &floatSamples, 1, vDSP_Length(count))
        
        // Apply volume
        var vol = volume
        vDSP_vsmul(floatSamples, 1, &vol, &floatSamples, 1, vDSP_Length(count))
        
        // Convert back to Int16
        vDSP_vfix16(floatSamples, 1, &samples, 1, vDSP_Length(count))
        
        return Data(bytes: samples, count: data.count)
    }

    /// Unpack 3-byte little-endian to Int32 with sign extension
    /// - Parameters:
    ///   - bytes: Source byte array
    ///   - offset: Starting offset in bytes array
    /// - Returns: Signed 24-bit value as Int32
    public static func unpack24Bit(_ bytes: [UInt8], offset: Int) -> Int32 {
        let b0 = Int32(bytes[offset])
        let b1 = Int32(bytes[offset + 1])
        let b2 = Int32(bytes[offset + 2])

        var value = b0 | (b1 << 8) | (b2 << 16)

        // Sign extend if negative (bit 23 set)
        if value & 0x80_0000 != 0 {
            value |= ~0xFF_FFFF
        }

        return value
    }

    /// Pack Int32 to 3-byte little-endian
    /// - Parameter sample: Signed 24-bit value as Int32
    /// - Returns: 3-byte array (little-endian)
    public static func pack24Bit(_ sample: Int32) -> [UInt8] {
        return [
            UInt8(sample & 0xFF),
            UInt8((sample >> 8) & 0xFF),
            UInt8((sample >> 16) & 0xFF)
        ]
    }

    /// Convert int32 sample to 16-bit (right-shift 8 bits)
    /// Used when downconverting 24-bit to 16-bit
    /// - Parameter sample: 24-bit sample as Int32
    /// - Returns: 16-bit sample
    public static func convertTo16Bit(_ sample: Int32) -> Int16 {
        return Int16(sample >> 8)
    }

    /// Convert int16 sample to 24-bit range (left-shift 8 bits)
    /// Used when upconverting 16-bit to 24-bit
    /// - Parameter sample: 16-bit sample
    /// - Returns: 24-bit sample as Int32
    public static func convertFrom16Bit(_ sample: Int16) -> Int32 {
        return Int32(sample) << 8
    }

    /// Clamp Int32 value to 24-bit range
    /// - Parameter sample: Unclamped sample value
    /// - Returns: Clamped value within 24-bit range
    public static func clamp24Bit(_ sample: Int32) -> Int32 {
        if sample > max24Bit {
            return max24Bit
        } else if sample < min24Bit {
            return min24Bit
        }
        return sample
    }
}
