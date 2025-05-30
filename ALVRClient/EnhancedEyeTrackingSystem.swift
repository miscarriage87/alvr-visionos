// ALVRClient/EnhancedEyeTrackingSystem.swift

import Foundation
import CoreGraphics // For CGPoint
import Combine

// This struct will be returned to the optimizer/integration layer
public struct ProcessedGazeData {
    public let centerShiftX: Float // Normalized -1.0 to 1.0
    public let centerShiftY: Float // Normalized -1.0 to 1.0
    public let isTrackingActive: Bool
    public let isStable: Bool // Indicates if gaze is relatively stable based on sensitivity
}

public class EnhancedEyeTrackingSystem {
    private var foveationSettings: EyeTrackedFoveationConfig
    private var worldTracker: WorldTracker // Direct reference for convenience
    
    @Published public private(set) var currentProcessedGaze: ProcessedGazeData
    
    private var updateTimer: Timer?
    private let updateInterval: TimeInterval = 1.0 / 90.0 // Aim for ~90Hz updates, matching typical VR refresh rates
    
    // For gaze stability/sensitivity
    private var lastGazePosition: CGPoint = .zero
    private var gazeMovementBuffer: [CGFloat] = [] // Store recent movement magnitudes
    private let gazeMovementBufferSize = 5 // Number of samples to average for stability
    private var lastSignificantGazeMovementTime: Date = Date()

    public init(settings: EyeTrackedFoveationConfig, worldTracker: WorldTracker = .shared) {
        self.foveationSettings = settings
        self.worldTracker = worldTracker
        self.currentProcessedGaze = ProcessedGazeData(centerShiftX: 0.0, centerShiftY: 0.0, isTrackingActive: false, isStable: true)
        log("EnhancedEyeTrackingSystem initialized with settings.")
    }

    public func start() {
        guard updateTimer == nil else {
            log("Eye tracking system already started.", level: .warning)
            return
        }
        
        // Reset state
        lastGazePosition = .zero
        gazeMovementBuffer.removeAll()
        lastSignificantGazeMovementTime = Date()
        
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.updateGazeData()
        }
        log("EnhancedEyeTrackingSystem started with update interval: \(updateInterval)s")
    }

    public func stop() {
        updateTimer?.invalidate()
        updateTimer = nil
        log("EnhancedEyeTrackingSystem stopped.")
    }

    public func updateFoveationSettings(_ newSettings: EyeTrackedFoveationConfig) {
        self.foveationSettings = newSettings
        log("Foveation settings updated in EnhancedEyeTrackingSystem.")
    }

    private func updateGazeData() {
        let isActive = worldTracker.eyeTrackingActive
        var rawGazeX = worldTracker.eyeX // Expected range: -0.5 to 0.5
        var rawGazeY = worldTracker.eyeY // Expected range: -0.5 to 0.5 (Y might be inverted depending on source)
        
        // Ensure values are within expected raw range if necessary, though WorldTracker should provide normalized data.
        rawGazeX = max(-0.5, min(0.5, rawGazeX))
        rawGazeY = max(-0.5, min(0.5, rawGazeY))

        // Convert to server's expected center_shift range (-1.0 to 1.0)
        // Assuming eyeX: -0.5 (left) to 0.5 (right) -> center_shift_x: -1.0 to 1.0
        // Assuming eyeY: -0.5 (bottom) to 0.5 (top) -> center_shift_y: -1.0 to 1.0
        // The existing WorldTracker calculation: eyeY = ((1.0 - yReg.asFloat) - 0.5)
        // If yReg.asFloat is 0 (top) -> eyeY = 0.5 (top)
        // If yReg.asFloat is 1 (bottom) -> eyeY = -0.5 (bottom)
        // This matches a standard Cartesian coordinate system where +Y is up.
        let currentCenterShiftX = rawGazeX * 2.0
        let currentCenterShiftY = rawGazeY * 2.0
        
        let currentRawGazePoint = CGPoint(x: CGFloat(rawGazeX), y: CGFloat(rawGazeY))
        var isStable = true

        if isActive && foveationSettings.dynamicAdjustmentEnabled && foveationSettings.gazeMovementSensitivity > 0 {
            let movementThreshold = 0.01 + (1.0 - CGFloat(foveationSettings.gazeMovementSensitivity)) * 0.1 // Sensitivity: 1.0 = very sensitive (small threshold), 0.1 = less sensitive (large threshold)
            
            let dx = currentRawGazePoint.x - lastGazePosition.x
            let dy = currentRawGazePoint.y - lastGazePosition.y
            let movementMagnitude = sqrt(dx*dx + dy*dy)
            
            gazeMovementBuffer.append(movementMagnitude)
            if gazeMovementBuffer.count > gazeMovementBufferSize {
                gazeMovementBuffer.removeFirst()
            }
            
            let averageMovement = gazeMovementBuffer.reduce(0, +) / CGFloat(max(1, gazeMovementBuffer.count))
            
            if averageMovement > movementThreshold {
                isStable = false
                lastSignificantGazeMovementTime = Date()
            } else {
                // If gaze has been stable for a short period after movement, consider it stable again
                if Date().timeIntervalSince(lastSignificantGazeMovementTime) > 0.2 { // e.g. 200ms stability window
                     isStable = true
                } else {
                    isStable = false // Still in cooldown from recent movement
                }
            }
            lastGazePosition = currentRawGazePoint
        } else if !isActive {
            // If not active, reset stability indicators
            lastGazePosition = .zero
            gazeMovementBuffer.removeAll()
            isStable = true // Or false, depending on desired default when inactive
        }

        self.currentProcessedGaze = ProcessedGazeData(
            centerShiftX: Float(currentCenterShiftX),
            centerShiftY: Float(currentCenterShiftY),
            isTrackingActive: isActive,
            isStable: isStable
        )
    }
    
    // This method allows the optimizer to get the latest processed gaze data.
    public func getCurrentGazeDataForOptimizer() -> ProcessedGazeData {
        // Ensure thread safety if called from a different thread than the timer's runloop,
        // though @Published property wrapper usually handles this for reads from main thread.
        // For direct calls from optimizer (potentially on another thread), direct access is okay
        // as ProcessedGazeData is a struct (value type).
        return self.currentProcessedGaze
    }

    // MARK: - Logging
    private enum LogLevel { case info, warning, error, debug }
    private func log(_ message: String, level: LogLevel = .debug) {
        let prefix: String
        switch level {
        case .info: prefix = "[INFO] [EnhancedEyeTracking]"
        case .warning: prefix = "[WARN] [EnhancedEyeTracking]"
        case .error: prefix = "[ERROR] [EnhancedEyeTracking]"
        case .debug: prefix = "[DEBUG] [EnhancedEyeTracking]"
        }
        print("\(prefix) \(message)")
    }
}
