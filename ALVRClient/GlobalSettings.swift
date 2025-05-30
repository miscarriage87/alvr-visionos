//
//  GlobalSettings.swift
//
// Client-side settings and defaults
//

import Foundation
import SwiftUI

// MARK: - Minimal Visual Quality Preset Enum
public enum VisualQualityPreset: String, Codable, CaseIterable, Identifiable {
    case maximumQualityHLAlyx = "Maximum Quality (Half-Life Alyx)"
    case balanced = "Balanced"
    // case lowLatency = "Low Latency" // Can be added back if needed
    case custom = "Custom"
    
    public var id: String { self.rawValue }
}

// MARK: - GlobalSettings Struct
struct GlobalSettings: Codable {
    // Existing settings
    var keepSteamVRCenter: Bool = true
    var showHandsOverlaid: Bool = false
    var disablePersistentSystemOverlays: Bool = true
    var streamFPS: String = "90"
    var experimental40ppd: Bool = false
    var chromaKeyEnabled: Bool = false
    var chromaKeyDistRangeMin: Float = 0.35
    var chromaKeyDistRangeMax: Float = 0.7
    var chromaKeyColorR: Float = 16.0 / 255.0
    var chromaKeyColorG: Float = 124.0 / 255.0
    var chromaKeyColorB: Float = 16.0 / 255.0
    var dismissWindowOnEnter: Bool = true
    var emulatedPinchInteractions: Bool = false
    var dontShowAWDLAlertAgain: Bool = false
    var fovRenderScale: Float = 1.0
    var forceMipmapEyeTracking: Bool = false
    var targetHandsAtRoundtripLatency: Bool = false
    var lastUsedAppVersion: String = "never launched"

    // New minimal settings for Shadow PC optimization
    var currentVisualQualityPreset: VisualQualityPreset
    var shadowPCOptimizationSettings: ShadowPCOptimizationSettings

    enum CodingKeys: String, CodingKey {
        // Existing keys
        case keepSteamVRCenter, showHandsOverlaid, disablePersistentSystemOverlays, streamFPS, experimental40ppd
        case chromaKeyEnabled, chromaKeyDistRangeMin, chromaKeyDistRangeMax, chromaKeyColorR, chromaKeyColorG, chromaKeyColorB
        case dismissWindowOnEnter, emulatedPinchInteractions, dontShowAWDLAlertAgain
        case fovRenderScale, forceMipmapEyeTracking, targetHandsAtRoundtripLatency, lastUsedAppVersion
        // New keys
        case currentVisualQualityPreset, shadowPCOptimizationSettings
    }
    
    init() {
        // Default initialization for all properties
        self.keepSteamVRCenter = true
        self.showHandsOverlaid = false
        self.disablePersistentSystemOverlays = true
        self.streamFPS = "90"
        self.experimental40ppd = false
        self.chromaKeyEnabled = false
        self.chromaKeyDistRangeMin = 0.35
        self.chromaKeyDistRangeMax = 0.7
        self.chromaKeyColorR = 16.0 / 255.0
        self.chromaKeyColorG = 124.0 / 255.0
        self.chromaKeyColorB = 16.0 / 255.0
        self.dismissWindowOnEnter = true
        self.emulatedPinchInteractions = false
        self.dontShowAWDLAlertAgain = false
        self.fovRenderScale = 1.0
        self.forceMipmapEyeTracking = false
        self.targetHandsAtRoundtripLatency = false
        self.lastUsedAppVersion = "never launched"
        
        // Initialize new properties with defaults
        self.currentVisualQualityPreset = .balanced // Default preset
        self.shadowPCOptimizationSettings = .defaultSettings // Default detailed settings
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode existing properties with their original defaults if not present
        self.keepSteamVRCenter = try container.decodeIfPresent(Bool.self, forKey: .keepSteamVRCenter) ?? true
        self.showHandsOverlaid = try container.decodeIfPresent(Bool.self, forKey: .showHandsOverlaid) ?? false
        self.disablePersistentSystemOverlays = try container.decodeIfPresent(Bool.self, forKey: .disablePersistentSystemOverlays) ?? true
        self.streamFPS = try container.decodeIfPresent(String.self, forKey: .streamFPS) ?? "90"
        self.experimental40ppd = try container.decodeIfPresent(Bool.self, forKey: .experimental40ppd) ?? false
        self.chromaKeyEnabled = try container.decodeIfPresent(Bool.self, forKey: .chromaKeyEnabled) ?? false
        self.chromaKeyDistRangeMin = try container.decodeIfPresent(Float.self, forKey: .chromaKeyDistRangeMin) ?? 0.35
        self.chromaKeyDistRangeMax = try container.decodeIfPresent(Float.self, forKey: .chromaKeyDistRangeMax) ?? 0.7
        self.chromaKeyColorR = try container.decodeIfPresent(Float.self, forKey: .chromaKeyColorR) ?? (16.0 / 255.0)
        self.chromaKeyColorG = try container.decodeIfPresent(Float.self, forKey: .chromaKeyColorG) ?? (124.0 / 255.0)
        self.chromaKeyColorB = try container.decodeIfPresent(Float.self, forKey: .chromaKeyColorB) ?? (16.0 / 255.0)
        self.dismissWindowOnEnter = try container.decodeIfPresent(Bool.self, forKey: .dismissWindowOnEnter) ?? true
        self.emulatedPinchInteractions = try container.decodeIfPresent(Bool.self, forKey: .emulatedPinchInteractions) ?? false
        self.dontShowAWDLAlertAgain = try container.decodeIfPresent(Bool.self, forKey: .dontShowAWDLAlertAgain) ?? false
        self.fovRenderScale = try container.decodeIfPresent(Float.self, forKey: .fovRenderScale) ?? 1.0
        self.forceMipmapEyeTracking = try container.decodeIfPresent(Bool.self, forKey: .forceMipmapEyeTracking) ?? false
        self.targetHandsAtRoundtripLatency = try container.decodeIfPresent(Bool.self, forKey: .targetHandsAtRoundtripLatency) ?? false
        self.lastUsedAppVersion = try container.decodeIfPresent(String.self, forKey: .lastUsedAppVersion) ?? "never launched"

        // Decode new properties, falling back to defaults if not present (for backward compatibility)
        self.currentVisualQualityPreset = try container.decodeIfPresent(VisualQualityPreset.self, forKey: .currentVisualQualityPreset) ?? .balanced
        self.shadowPCOptimizationSettings = try container.decodeIfPresent(ShadowPCOptimizationSettings.self, forKey: .shadowPCOptimizationSettings) ?? .defaultSettings
    }
}

// MARK: - GlobalSettingsStore
extension GlobalSettingsStore {
    static let sampleData: GlobalSettingsStore = GlobalSettingsStore()
}

class GlobalSettingsStore: ObservableObject {
    @Published var settings: GlobalSettings = GlobalSettings()
    
    private static func fileURL() throws -> URL {
        try FileManager.default.url(for: .documentDirectory,
                                    in: .userDomainMask,
                                    appropriateFor: nil,
                                    create: true)
        .appendingPathComponent("globalsettings.data")
    }
    
    func load() throws {
        let fileURL = try Self.fileURL()
        guard let data = try? Data(contentsOf: fileURL) else {
            // If no saved data, initialize with defaults and apply the default preset's detailed settings
            self.settings = GlobalSettings() // This initializes with .balanced and .defaultSettings
            self.applyPreset(self.settings.currentVisualQualityPreset, forceApplyDetailedSettings: true) // Ensure detailed settings match
            return
        }
        let decodedSettings = try JSONDecoder().decode(GlobalSettings.self, from: data)
        self.settings = decodedSettings
        // After loading, ensure the shadowPCOptimizationSettings are consistent with the loaded preset,
        // unless the preset is .custom.
        if self.settings.currentVisualQualityPreset != .custom {
            self.applyPreset(self.settings.currentVisualQualityPreset, forceApplyDetailedSettings: true)
        }
    }
    
    func save(settings: GlobalSettings) throws {
        let data = try JSONEncoder().encode(settings)
        let outfile = try Self.fileURL()
        try data.write(to: outfile)
    }

    // Function to apply a visual quality preset
    // This will change the currentVisualQualityPreset and update shadowPCOptimizationSettings accordingly.
    func applyPreset(_ preset: VisualQualityPreset, forceApplyDetailedSettings: Bool = true) {
        objectWillChange.send() // Manually notify observers before changing properties
        
        settings.currentVisualQualityPreset = preset
        
        if forceApplyDetailedSettings || preset != .custom {
            switch preset {
            case .maximumQualityHLAlyx:
                settings.shadowPCOptimizationSettings = ShadowPCOptimizationSettings(
                    videoConfig: VideoOptimizationConfig(
                        codec: .h265,
                        use10BitEncodingServer: true,
                        targetMaxBitrateMbps: 70,
                        nvencPreset: .p7_slowest, // Max quality on RTX A4500
                        nvencTuningPreset: .highQuality,
                        nvencMultiPass: .fullRes,
                        rateControlMode: .vbr,
                        adaptiveQuantizationMode: .spatial,
                        dynamicBitrate: VideoOptimizationConfig.DynamicBitrateConfig(
                            enabled: true, baseBitrateMbps: 55, maxBoostBitrateMbps: 70,
                            sceneComplexityMinThreshold: 0.2, sceneComplexityMaxThreshold: 0.7,
                            bitrateAdjustmentSpeedFactor: 0.3
                        ),
                        sharpeningStrength: 0.3,
                        encodingGamma: 2.2,
                        enableHDRServer: true,
                        targetEyeWidth: 2880, targetEyeHeight: 2880, targetRefreshRate: 90.0
                    ),
                    foveationConfig: EyeTrackedFoveationConfig(
                        enabled: true,
                        foveationLayers: [
                            EyeTrackedFoveationConfig.FoveationLayer(qualityFactor: 1.0, radiusDegrees: 25.0, transitionDegrees: 10.0),
                            EyeTrackedFoveationConfig.FoveationLayer(qualityFactor: 0.7, radiusDegrees: 45.0, transitionDegrees: 10.0),
                            EyeTrackedFoveationConfig.FoveationLayer(qualityFactor: 0.3, radiusDegrees: 0.0, transitionDegrees: 0.0)
                        ],
                        dynamicAdjustmentEnabled: true, gazeMovementSensitivity: 0.6,
                        performanceTargetFps: 88, edgeSmoothingLevel: .high
                    ),
                    halfLifeAlyxConfig: .defaultOptimized, // Enable all HL:A specific tweaks
                    networkConfig: NetworkOptimizationConfig( // Customize for max quality
                        cloudStreamingExtraLatencyMs: 20, prioritizeVideoData: true,
                        packetLossRecoveryMode: .balancedFecRetransmission, fecPercentage: 5, // Lower FEC for max quality
                        adaptiveQoSEnabled: false, qosCheckIntervalSeconds: 5
                    ),
                    latencyReductionConfig: LatencyReductionConfig(
                        enablePredictiveFrameInterpolation: true, interpolationMaxPredictedFrames: 1,
                        atwMode: .alvrEnhancedPrediction, cloudInputPredictionStrength: 0.2
                    )
                )
                
            case .balanced:
                settings.shadowPCOptimizationSettings = .defaultSettings // Use the defaults defined in ShadowPCOptimizationSettings
                
            case .custom:
                // When switching to custom, we don't change the detailed shadowPCOptimizationSettings.
                // The user will modify them directly via the UI.
                // The UI (ShadowPCSettingsView) should set this preset if any detailed setting is changed.
                break
            }
        }
        
        // Persist changes after applying a preset
        do {
            try save(settings: settings)
        } catch {
            print("Error saving settings after applying preset: \(error)")
        }
    }
}
