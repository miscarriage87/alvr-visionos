// ALVRClient/ALVRShadowPCIntegration.swift

import Foundation
import Combine
import SwiftUI // For ObservableObject

// Ensure ALVRClientCore is properly bridged if any C functions were to be called directly.
// However, for this simplified version, we rely on EventHandler for core ALVR interactions.

public enum ALVRIntegrationSimplifiedStatus: String {
    case idle = "Idle"
    case initialized = "Initialized (Ready)"
    case streamingActive = "Streaming (Performance Active)" // Set by external trigger if needed
    case error = "Error"
}

public class ALVRShadowPCIntegration: ObservableObject {
    public static let shared = ALVRShadowPCIntegration()

    @ObservedObject private var settingsStore: GlobalSettingsStore
    private var optimizer: ShadowPCOptimizer
    private var eyeTrackingSystem: EnhancedEyeTrackingSystem // Keep for settings propagation

    @Published public var currentStatusMessage: String = "Waiting to initialize."
    
    // Simplified Performance Metrics
    @Published public var currentFPS: Float = 0.0
    @Published public var detectedNetworkLatencyMs: Int = 0 // Based on settings
    @Published public var effectiveBitrateMbps: Float = 0.0 // Target bitrate from optimizer
    @Published public var foveationDebugInfo: String = "Foveation: N/A"
    @Published public var halfLifeAlyxModeActive: Bool = false

    private var performanceUpdateTimer: Timer?
    private var lastFrameTime: Date = Date()
    private var frameCountForFPS: Int = 0
    
    private var cancellables = Set<AnyCancellable>()

    private init(settingsStore: GlobalSettingsStore = .shared) {
        self.settingsStore = settingsStore
        // Initialize optimizer and eye tracking system with current settings from the store
        self.optimizer = ShadowPCOptimizer(settings: settingsStore.settings.shadowPCOptimizationSettings)
        self.eyeTrackingSystem = EnhancedEyeTrackingSystem(settings: settingsStore.settings.shadowPCOptimizationSettings.foveationConfig)
        
        log("ALVRShadowPCIntegration initialized.", level: .info)

        // Observe changes in GlobalSettingsStore to reconfigure
        settingsStore.$settings
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main) // Debounce to avoid rapid updates during UI interaction
            .sink { [weak self] newSettings in
                guard let self = self else { return }
                self.log("Global settings changed. Reconfiguring integration.", level: .info)
                self.handleGlobalSettingsChange(newSettings)
            }
            .store(in: &cancellables)
    }

    public func initialize() {
        currentStatusMessage = "Initializing ALVR integration systems..."
        log("Initializing ALVRShadowPCIntegration systems...", level: .info)

        // Apply initial settings from the store
        handleGlobalSettingsChange(settingsStore.settings)

        // Start performance monitoring (basic FPS)
        setupTimers()
        
        currentStatusMessage = "Initialized. Server config generated."
        log("ALVRShadowPCIntegration initialization complete. Waiting for ALVR connection via EventHandler.", level: .info)
    }
    
    private func setupTimers() {
        performanceUpdateTimer?.invalidate()
        performanceUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updatePerformanceMetricsDisplay()
        }
        log("Basic performance display timer started.", level: .info)
    }

    private func handleGlobalSettingsChange(_ newSettings: GlobalSettings) {
        // Update internal optimizer and eye tracking system with new settings
        self.optimizer.settings = newSettings.shadowPCOptimizationSettings
        self.eyeTrackingSystem.updateFoveationSettings(newSettings.shadowPCOptimizationSettings.foveationConfig) // Propagate settings
        
        // Perform dynamic adjustments within the optimizer based on new settings
        // This updates internal state like effectiveTargetBitrateMbps
        self.optimizer.performDynamicAdjustments()
        
        // Update published properties for the UI
        DispatchQueue.main.async {
            self.halfLifeAlyxModeActive = newSettings.shadowPCOptimizationSettings.halfLifeAlyxConfig.enabled &&
                                          newSettings.currentVisualQualityPreset == .maximumQualityHLAlyx
            self.effectiveBitrateMbps = self.optimizer.effectiveTargetBitrateMbps
            self.detectedNetworkLatencyMs = self.optimizer.settings.networkConfig.cloudStreamingExtraLatencyMs
            
            if self.optimizer.settings.foveationConfig.enabled {
                let centerLayerQuality = self.optimizer.settings.foveationConfig.foveationLayers.first?.qualityFactor ?? 0.0
                let dynamicMultiplier = self.optimizer.currentFoveationStrengthMultiplier
                self.foveationDebugInfo = String(format: "Foveation: On (Center Qual: %.2f, Strength: %.2f)",
                                                 centerLayerQuality, dynamicMultiplier)
            } else {
                self.foveationDebugInfo = "Foveation: Off"
            }
        }
        
        // Regenerate and log the server session parameters JSON
        // This is the primary output of this integration layer for server configuration
        configureALVRServerSession()
        
        log("Applied new global settings to integration layer. Server JSON re-generated.", level: .info)
    }

    public func configureALVRServerSession() {
        guard let serverJsonConfig = optimizer.getServerSessionParametersAsJson() else {
            log("Failed to generate server session JSON.", level: .error)
            DispatchQueue.main.async {
                self.currentStatusMessage = "Error: Failed to generate server config."
            }
            return
        }

        log("Successfully generated ALVR Server Session JSON.", level: .info)
        // Output the JSON for the user to manually apply to their ALVR server's session.json
        print("\n--------------------------------------------------------------------------------")
        print("🚀 ALVR SERVER CONFIGURATION FOR APPLE VISION PRO + SHADOW PC 🚀")
        print("--------------------------------------------------------------------------------")
        print("👉 Action Required: Copy the JSON below and paste it into your ALVR server's")
        print("   'session.json' file. This file is usually located in the ALVR installation")
        print("   directory on your Shadow PC (e.g., C:\\Program Files\\ALVR).")
        print("   Restart the ALVR server on your Shadow PC after updating the file.")
        print("--------------------------------------------------------------------------------\n")
        print(serverJsonConfig)
        print("\n--------------------------------------------------------------------------------")
        print("✅ Server configuration generated and logged to console.")
        print("--------------------------------------------------------------------------------\n")
        
        DispatchQueue.main.async {
            self.currentStatusMessage = "Server config generated. Apply to ALVR server."
        }
    }
    
    // Called by the rendering loop (e.g., from RealityKitClientSystem or MetalClientSystem)
    public func incrementCompositedFrameCount() {
        frameCountForFPS += 1
    }

    private func updatePerformanceMetricsDisplay() {
        // FPS Calculation
        let timeSinceLastFPSUpdate = Date().timeIntervalSince(lastFrameTime)
        if timeSinceLastFPSUpdate >= 1.0 { // Update FPS display every second
            let calculatedFPS = Float(frameCountForFPS) / Float(timeSinceLastFPSUpdate)
            DispatchQueue.main.async {
                self.currentFPS = calculatedFPS
            }
            frameCountForFPS = 0
            lastFrameTime = Date()
            
            // Update optimizer's internal FPS metric
            optimizer.currentFPS = calculatedFPS
            // Trigger dynamic adjustments in optimizer which might depend on FPS
            optimizer.performDynamicAdjustments()
            // Update UI-bound effective bitrate after optimizer adjustments
            DispatchQueue.main.async {
                 self.effectiveBitrateMbps = self.optimizer.effectiveTargetBitrateMbps
                 // Also update foveation debug info as strength might change
                if self.optimizer.settings.foveationConfig.enabled {
                    let centerLayerQuality = self.optimizer.settings.foveationConfig.foveationLayers.first?.qualityFactor ?? 0.0
                    let dynamicMultiplier = self.optimizer.currentFoveationStrengthMultiplier
                    self.foveationDebugInfo = String(format: "Foveation: On (Center Qual: %.2f, Strength: %.2f)",
                                                     centerLayerQuality, dynamicMultiplier)
                }
            }
        }
    }

    public func shutdown() {
        log("Shutting down ALVRShadowPCIntegration...", level: .info)
        performanceUpdateTimer?.invalidate()
        performanceUpdateTimer = nil
        
        eyeTrackingSystem.stop() // Stop eye tracking updates

        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        
        DispatchQueue.main.async {
            self.currentStatusMessage = "Shutdown complete."
            self.currentFPS = 0.0
        }
        log("ALVRShadowPCIntegration shutdown complete.", level: .info)
    }

    // MARK: - Logging
    public enum LogLevel { case info, warning, error, debug }
    public func log(_ message: String, level: LogLevel = .debug) {
        let prefix: String
        switch level {
        case .info: prefix = "[INFO] [ALVRIntegration]"
        case .warning: prefix = "[WARN] [ALVRIntegration]"
        case .error: prefix = "[ERROR] [ALVRIntegration]"
        case .debug: prefix = "[DEBUG] [ALVRIntegration]"
        }
        print("\(prefix) \(message)")
    }
}
