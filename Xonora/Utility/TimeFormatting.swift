import Foundation

func formatTime(_ time: TimeInterval) -> String {
    guard time.isFinite && !time.isNaN else { return "0:00" }
    let minutes = Int(time) / 60
    let seconds = Int(time) % 60
    return String(format: "%d:%02d", minutes, seconds)
}
