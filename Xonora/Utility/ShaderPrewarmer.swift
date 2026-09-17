import SwiftUI
import UIKit

/// Utility to pre-warm Metal shaders used by SwiftUI effects
/// This prevents stuttering when blur/visual effects are first rendered
final class ShaderPrewarmer {
    static let shared = ShaderPrewarmer()
    
    private var hasPrewarmed = false
    private let lock = NSLock()
    
    private init() {}
    
    /// Call this on app launch to pre-warm shaders in the background
    func prewarm() {
        lock.lock()
        guard !hasPrewarmed else {
            lock.unlock()
            return
        }
        hasPrewarmed = true
        lock.unlock()
        
        // Run pre-warming on a background thread
        DispatchQueue.global(qos: .utility).async {
            self.prewarmShaders()
        }
    }
    
    private func prewarmShaders() {
        // Create an offscreen UIView with blur effect to trigger shader compilation
        // This ensures the Metal shaders are compiled before user sees any UI
        
        DispatchQueue.main.async {
            // Create a small offscreen window to render effects
            let window = UIWindow(frame: CGRect(x: -100, y: -100, width: 50, height: 50))
            window.isHidden = false
            window.alpha = 0.01 // Nearly invisible
            
            // Add views with effects that use shaders
            let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
            blurView.frame = window.bounds
            window.addSubview(blurView)
            
            // Add a view with vibrancy
            let vibrancyView = UIVisualEffectView(effect: UIVibrancyEffect(blurEffect: UIBlurEffect(style: .systemMaterial)))
            vibrancyView.frame = blurView.bounds
            blurView.contentView.addSubview(vibrancyView)
            
            // Create a gradient layer to warm up gradient shaders
            let gradientLayer = CAGradientLayer()
            gradientLayer.frame = CGRect(x: 0, y: 0, width: 50, height: 50)
            gradientLayer.colors = [UIColor.black.cgColor, UIColor.white.cgColor]
            window.layer.addSublayer(gradientLayer)
            
            // Force a render pass
            window.layoutIfNeeded()
            
            // Clean up after a short delay (shaders should be compiled by then)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                window.isHidden = true
                window.removeFromSuperview()
            }
        }
    }
}
