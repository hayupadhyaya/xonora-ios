// ABOUTME: Detailed Opus frame analysis and verification
// ABOUTME: Analyzes TOC byte and frame structure for Opus packets

import Foundation

public func analyzeOpusTOC(_ tocByte: UInt8) {
    // Opus TOC byte structure:
    // Bits 0-1: frame count (00=1, 01=2, 10=2 CBR, 11=variable)
    // Bits 2: stereo flag (0=mono, 1=stereo)
    // Bits 3-7: config (mode + bandwidth + frame size)

    let config = tocByte >> 3
    let stereo = (tocByte & 0x04) != 0
    let frameCountCode = tocByte & 0x03

    print("TOC Byte Analysis: 0x\(String(tocByte, radix: 16, uppercase: true))")
    print("  Config: \(config)")
    print("  Stereo: \(stereo)")
    print("  Frame count code: \(frameCountCode)")

    // Decode config
    let frameSize: String
    switch config % 4 {
    case 0: frameSize = "10ms"
    case 1: frameSize = "20ms"
    case 2: frameSize = "40ms"
    case 3: frameSize = "60ms"
    default: frameSize = "unknown"
    }

    let mode: String
    if config < 12 {
        mode = "SILK"
    } else if config < 16 {
        mode = "Hybrid"
    } else {
        mode = "CELT"
    }

    print("  Frame size: \(frameSize)")
    print("  Mode: \(mode)")
}
