// ALVRClient/ShadowPCOptimizations.swift

import Foundation
import CoreGraphics // For CGFloat, CGSize etc. if needed for foveation regions

// MARK: - ALVR Server Setting Structures (for JSON generation)
// These structures mirror the relevant parts of ALVR server's session settings (settings.rs)
// for configuring video encoding and foveation.

private enum AlvrCodecTypeServer: String, Codable {
    case H264
    case Hevc
    case AV1
}

private enum AlvrRateControlModeServer: String, Codable {
    case Cbr
    case Vbr
}

private enum AlvrEncoderQualityPresetNvidiaServer: String, Codable {
    case P1, P2, P3, P4, P5, P6, P7
}

private enum AlvrNvencTuningPresetServer: String, Codable {
    case HighQuality
    case LowLatency
    case UltraLowLatency
    case Lossless
}

private enum AlvrNvencMultiPassServer: String, Codable {
    case Disabled
    case QuarterResolution
    case FullResolution
}

private enum AlvrNvencAdaptiveQuantizationModeServer: String, Codable {
    case Disabled
    case Spatial
    case Temporal
}

private struct AlvrNvencConfigServer: Codable {
    var quality_preset: AlvrEncoderQualityPresetNvidiaServer
    var tuning_preset: AlvrNvencTuningPresetServer
    var multi_pass: AlvrNvencMultiPassServer
    var adaptive_quantization_mode: AlvrNvencAdaptiveQuantizationModeServer
    // The following are i64 in Rust, defaulting to -1. We'll only set if explicitly configured.
    // For simplicity, we'll omit most of these unless directly mapped from our optimizer settings.
    // Add more fields here if direct control from ShadowPCOptimizationSettings is desired.
    // var low_delay_key_frame_scale: Int64?
    // var enable_intra_refresh: Bool?
    // var gop_length: Int64?
}

private struct AlvrEncoderConfigServer: Codable {
    var rate_control_mode: AlvrRateControlModeServer
    var use_10bit: Bool
    var encoding_gamma: Float
    var enable_hdr: Bool
    var nvenc: AlvrNvencConfigServer
    // amf and software encoders are omitted as we target NVIDIA RTX A4500
}

private struct AlvrFoveatedEncodingConfigServer: Codable { // Content of Switch<FoveatedEncodingConfig>
    var force_enable: Bool // This will be true if our foveation is enabled
    var center_size_x: Float
    var center_size_y: Float
    var center_shift_x: Float
    var center_shift_y: Float
    var edge_ratio_x: Float
    var edge_ratio_y: Float
}

private struct AlvrSwitchableConfig<T: Codable>: Codable {
    var enabled: Bool
    var content: T
}

private enum AlvrBitrateModeServer: Codable {
    case ConstantMbps(UInt64)
    case Adaptive(AlvrAdaptiveBitrateConfigServer)

    // Manual Codable implementation to match Rust's enum structure
    enum CodingKeys: String, CodingKey {
        case ConstantMbps
        case Adaptive
    }
    enum AdaptiveKeys: String, CodingKey { // For the nested Adaptive struct
        case saturation_multiplier, max_throughput_mbps, min_throughput_mbps // Add other adaptive params if needed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let val = try container.decodeIfPresent(UInt64.self, forKey: .ConstantMbps) {
            self = .ConstantMbps(val)
        } else if let val = try container.decodeIfPresent(AlvrAdaptiveBitrateConfigServer.self, forKey: .Adaptive) {
            self = .Adaptive(val)
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid BitrateModeServer"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ConstantMbps(let value):
            try container.encode(value, forKey: .ConstantMbps)
        case .Adaptive(let config):
            try container.encode(config, forKey: .Adaptive)
        }
    }
}

private struct AlvrAdaptiveBitrateConfigServer: Codable {
    var saturation_multiplier: Float
    var max_throughput_mbps: AlvrSwitchableConfig<UInt64> // Example, map other params if needed
    var min_throughput_mbps: AlvrSwitchableConfig<UInt64>
    // encoder_latency_limiter, decoder_latency_limiter etc. can be added if controlled
}

private struct AlvrBitrateConfigServer: Codable {
    var mode: AlvrBitrateModeServer
    // adapt_to_framerate, history_size, image_corruption_fix can be added if controlled
}

private enum AlvrFrameSizeServer: Codable {
    case Scale(Float)
    case Absolute(AlvrAbsoluteFrameSizeServer)

    enum CodingKeys: String, CodingKey {
        case Scale
        case Absolute
    }
     enum AbsoluteKeys: String, CodingKey {
        case width, height
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let val = try container.decodeIfPresent(Float.self, forKey: .Scale) {
            self = .Scale(val)
        } else if let val = try container.decodeIfPresent(AlvrAbsoluteFrameSizeServer.self, forKey: .Absolute) {
            self = .Absolute(val)
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid FrameSizeServer"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .Scale(let value):
            try container.encode(value, forKey: .Scale)
        case .Absolute(let config):
            try container.encode(config, forKey: .Absolute)
        }
    }
}

private struct AlvrAbsoluteFrameSizeServer: Codable {
    var width: UInt32
    var height: UInt32? // In ALVR, height is Option<u32>
}


private struct AlvrVideoSettingsServer: Codable { // Maps to VideoConfig in Rust
    var preferred_codec: AlvrCodecTypeServer
    var foveated_encoding: AlvrSwitchableConfig<AlvrFoveatedEncodingConfigServer>
    var encoder_config: AlvrEncoderConfigServer
    var bitrate: AlvrBitrateConfigServer
    var transcoding_view_resolution: AlvrFrameSizeServer
    var preferred_fps: Float
    var use_10bit_decoder: Bool? // Client preference, can be hinted
    var enable_hdr_decoder: Bool? // Client preference
    var encoding_gamma_decoder: Float? // Client preference
    // Add other VideoConfig fields as needed: color_correction, max_buffering_frames, etc.
}

private struct AlvrSessionSettingsServer: Codable { // Root structure
    var video: AlvrVideoSettingsServer
    // Other main categories like audio, headset, connection, extra can be added if needed.
    // For this optimization, focusing on video.
}


// MARK: - Main Optimizer Configuration
public struct ShadowPCOptimizationSettings: Codable, Equatable {
    public var videoConfig: VideoOptimizationConfig
    public var networkConfig: NetworkOptimizationConfig
    public var foveationConfig: EyeTrackedFoveationConfig
    public var halfLifeAlyxConfig: HalfLifeAlyxProfile
    public var latencyReductionConfig: LatencyReductionConfig

    public init(
        videoConfig: VideoOptimizationConfig = .defaultOptimized,
        networkConfig: NetworkOptimizationConfig = .defaultOptimized,
        foveationConfig: EyeTrackedFoveationConfig = .defaultOptimized,
        halfLifeAlyxConfig: HalfLifeAlyxProfile = .defaultOptimized,
        latencyReductionConfig: LatencyReductionConfig = .defaultOptimized
    ) {
        self.videoConfig = videoConfig
        self.networkConfig = networkConfig
        self.foveationConfig = foveationConfig
        self.halfLifeAlyxConfig = halfLifeAlyxConfig
        self.latencyReductionConfig = latencyReductionConfig
    }

    public static var defaultSettings: ShadowPCOptimizationSettings {
        ShadowPCOptimizationSettings()
    }
}

// MARK: - 1. Video Encoding Optimizations
public struct VideoOptimizationConfig: Codable, Equatable {
    public var codec: VideoCodec
    public var use10BitEncodingServer: Bool // Server-side preference
    public var targetMaxBitrateMbps: Int
    public var nvencPreset: NvencPreset
    public var nvencTuningPreset: NvencTuning
    public var nvencMultiPass: NvencMultiPassMode
    public var rateControlMode: RateControlMode
    public var adaptiveQuantizationMode: AdaptiveQuantizationMode
    public var dynamicBitrate: DynamicBitrateConfig
    public var sharpeningStrength: Float // Client-side post-processing or server if supported
    public var encodingGamma: Float
    public var enableHDRServer: Bool // Server-side preference
    public var targetEyeWidth: UInt32
    public var targetEyeHeight: UInt32
    public var targetRefreshRate: Float


    public enum VideoCodec: String, Codable, CaseIterable, Equatable {
        case h265 = "H.265 (HEVC)"
        case av1 = "AV1 (Experimental)"
    }

    public enum NvencPreset: String, Codable, CaseIterable, Equatable {
        case p1_fastest = "P1"
        case p2_faster = "P2"
        case p3_fast = "P3"
        case p4_medium = "P4"
        case p5_slow = "P5"
        case p6_slower = "P6"
        case p7_slowest = "P7"
    }
    
    public enum NvencTuning: String, Codable, CaseIterable, Equatable {
        case highQuality = "High Quality"
        case lowLatency = "Low Latency"
        case ultraLowLatency = "Ultra Low Latency"
        // case lossless = "Lossless" // Usually not practical for streaming
    }

    public enum NvencMultiPassMode: String, Codable, CaseIterable, Equatable {
        case disabled = "Disabled"
        case quarterRes = "1/4 Resolution"
        case fullRes = "Full Resolution"
    }

    public enum RateControlMode: String, Codable, CaseIterable, Equatable {
        case cbr = "CBR"
        case vbr = "VBR"
        // case constqp = "ConstQP" // Less common for dynamic streaming
    }
    
    public enum AdaptiveQuantizationMode: String, Codable, CaseIterable, Equatable {
        case disabled = "Disabled"
        case spatial = "Spatial AQ"
        case temporal = "Temporal AQ (Experimental)"
    }

    public struct DynamicBitrateConfig: Codable, Equatable {
        public var enabled: Bool
        public var baseBitrateMbps: Int
        public var maxBoostBitrateMbps: Int
        public var sceneComplexityMinThreshold: Float
        public var sceneComplexityMaxThreshold: Float
        public var bitrateAdjustmentSpeedFactor: Float

        public static let defaultHLAlyxOptimized = DynamicBitrateConfig(
            enabled: true, baseBitrateMbps: 45, maxBoostBitrateMbps: 68,
            sceneComplexityMinThreshold: 0.3, sceneComplexityMaxThreshold: 0.8,
            bitrateAdjustmentSpeedFactor: 0.5
        )
    }

    public static let defaultOptimized = VideoOptimizationConfig(
        codec: .h265,
        use10BitEncodingServer: true,
        targetMaxBitrateMbps: 70,
        nvencPreset: .p5_slow,
        nvencTuningPreset: .ultraLowLatency,
        nvencMultiPass: .quarterRes,
        rateControlMode: .vbr,
        adaptiveQuantizationMode: .spatial,
        dynamicBitrate: .defaultHLAlyxOptimized,
        sharpeningStrength: 0.20,
        encodingGamma: 2.2, // sRGB like gamma often preferred for game content
        enableHDRServer: true,
        targetEyeWidth: 2880, // Common high-res target, AVP is higher but SteamVR scales
        targetEyeHeight: 2880,
        targetRefreshRate: 90.0
    )
}

// MARK: - 2. Network Protocol Enhancements
public struct NetworkOptimizationConfig: Codable, Equatable {
    public var cloudStreamingExtraLatencyMs: Int
    public var prioritizeVideoData: Bool
    public var packetLossRecoveryMode: CloudPacketLossRecoveryMode
    public var fecPercentage: Int
    public var adaptiveQoSEnabled: Bool
    public var qosCheckIntervalSeconds: Int

    public enum CloudPacketLossRecoveryMode: String, Codable, CaseIterable, Equatable {
        case aggressiveRetransmission = "Aggressive Retransmission"
        case balancedFecRetransmission = "Balanced FEC + Retransmission"
        case robustFec = "Robust FEC"
    }

    public static let defaultOptimized = NetworkOptimizationConfig(
        cloudStreamingExtraLatencyMs: 25, // Adjusted estimate
        prioritizeVideoData: true,
        packetLossRecoveryMode: .balancedFecRetransmission,
        fecPercentage: 8,
        adaptiveQoSEnabled: false, // Client-side QoS is complex, disable by default
        qosCheckIntervalSeconds: 5
    )
}

// MARK: - 3. Eye Tracking Foveated Rendering
public struct EyeTrackedFoveationConfig: Codable, Equatable {
    public var enabled: Bool
    public var foveationLayers: [FoveationLayer]
    public var dynamicAdjustmentEnabled: Bool
    public var gazeMovementSensitivity: Float
    public var performanceTargetFps: Int
    public var edgeSmoothingLevel: FoveationEdgeSmoothing // This is often a client-side shader effect

    public struct FoveationLayer: Codable, Equatable {
        public var qualityFactor: Float // Maps to 1.0 / edge_ratio for server
        public var radiusDegrees: Float // Used to calculate center_size for server
        public var transitionDegrees: Float // Influences perception, not direct server param
    }
    
    public enum FoveationEdgeSmoothing: String, Codable, CaseIterable, Equatable {
        case none = "None"
        case low = "Low"
        case medium = "Medium"
        case high = "High"
    }

    public static let defaultOptimized = EyeTrackedFoveationConfig(
        enabled: true,
        foveationLayers: [
            FoveationLayer(qualityFactor: 1.0, radiusDegrees: 22.0, transitionDegrees: 7.0),
            FoveationLayer(qualityFactor: 0.55, radiusDegrees: 42.0, transitionDegrees: 10.0),
            FoveationLayer(qualityFactor: 0.20, radiusDegrees: 0.0, transitionDegrees: 0.0)
        ],
        dynamicAdjustmentEnabled: true,
        gazeMovementSensitivity: 0.75,
        performanceTargetFps: 87,
        edgeSmoothingLevel: .medium
    )
}

// MARK: - 4. Half-Life Alyx Specific Optimizations
public struct HalfLifeAlyxProfile: Codable, Equatable {
    public var enabled: Bool
    public var adaptToDarkScenes: Bool
    public var darkSceneLuminanceThreshold: Float
    public var darkSceneBitrateBoostFactor: Float
    public var darkSceneContrastEnhancement: Float // Client-side or server if supported
    public var motionAdaptiveQualityEnabled: Bool
    public var highMotionSpeedThreshold: Float
    public var qualityReductionFactorHighMotion: Float
    public var qualityIncreaseFactorLowMotion: Float
    public var optimizeHdrTonemapping: Bool
    public var hdrPeakLuminanceNits: Float
    public var hdrPaperWhiteNits: Float

    public static let defaultOptimized = HalfLifeAlyxProfile(
        enabled: true, adaptToDarkScenes: true, darkSceneLuminanceThreshold: 0.12,
        darkSceneBitrateBoostFactor: 1.30, darkSceneContrastEnhancement: 0.05,
        motionAdaptiveQualityEnabled: true, highMotionSpeedThreshold: 2.5,
        qualityReductionFactorHighMotion: 0.80, qualityIncreaseFactorLowMotion: 1.0, // Less aggressive increase
        optimizeHdrTonemapping: true, hdrPeakLuminanceNits: 1200.0, hdrPaperWhiteNits: 220.0
    )
}

// MARK: - 5. Latency Reduction Techniques
public struct LatencyReductionConfig: Codable, Equatable {
    public var enablePredictiveFrameInterpolation: Bool
    public var interpolationMaxPredictedFrames: Int
    public var atwMode: AsynchronousTimewarpMode
    public var cloudInputPredictionStrength: Float

    public enum AsynchronousTimewarpMode: String, Codable, CaseIterable, Equatable {
        case visionOSNative = "VisionOS Native"
        case alvrEnhancedPrediction = "ALVR Enhanced Prediction"
    }

    public static let defaultOptimized = LatencyReductionConfig(
        enablePredictiveFrameInterpolation: true,
        interpolationMaxPredictedFrames: 1, // Less aggressive interpolation
        atwMode: .alvrEnhancedPrediction,
        cloudInputPredictionStrength: 0.25
    )
}

// MARK: - ShadowPCOptimizer Class
public class ShadowPCOptimizer {
    public var settings: ShadowPCOptimizationSettings

    // Performance metrics (updated by ALVRShadowPCIntegration)
    public var currentFPS: Float = 0.0
    public var currentRoundTripLatencyMs: Float = 0.0 // Combined client-server-client
    public var currentEncodeLatencyMs: Float = 0.0
    public var currentDecodeLatencyMs: Float = 0.0
    public var currentNetworkLatencyMs: Float = 0.0 // Server to Client (one way)
    public var currentBitrateMbps: Float = 0.0
    
    // Dynamic adjustment state
    private var lastDynamicAdjustmentTime: Date = Date()
    private let dynamicAdjustmentInterval: TimeInterval = 1.0 // seconds

    public init(settings: ShadowPCOptimizationSettings = .defaultSettings) {
        self.settings = settings
    }

    // Called periodically by ALVRShadowPCIntegration
    public func performDynamicAdjustments() {
        guard Date().timeIntervalSince(lastDynamicAdjustmentTime) >= dynamicAdjustmentInterval else {
            return
        }
        lastDynamicAdjustmentTime = Date()

        var finalTargetBitrateMbps = Float(settings.videoConfig.targetMaxBitrateMbps)

        // Apply Half-Life Alyx dynamic bitrate adjustments
        if settings.halfLifeAlyxConfig.enabled && settings.halfLifeAlyxConfig.adaptToDarkScenes {
            let sceneLuminance = getCurrentSceneLuminance() // Assume this is provided
            if sceneLuminance < settings.halfLifeAlyxConfig.darkSceneLuminanceThreshold {
                finalTargetBitrateMbps *= settings.halfLifeAlyxConfig.darkSceneBitrateBoostFactor
            }
        }
        
        // Apply general dynamic bitrate scaling
        if settings.videoConfig.dynamicBitrate.enabled {
            let sceneComplexity = getCurrentSceneComplexity() // Assume this is provided
            let complexityFactor = min(1.0, max(0.0, (sceneComplexity - settings.videoConfig.dynamicBitrate.sceneComplexityMinThreshold) / (settings.videoConfig.dynamicBitrate.sceneComplexityMaxThreshold - settings.videoConfig.dynamicBitrate.sceneComplexityMinThreshold)))
            
            let base = Float(settings.videoConfig.dynamicBitrate.baseBitrateMbps)
            let boost = Float(settings.videoConfig.dynamicBitrate.maxBoostBitrateMbps) - base
            let dynamicTarget = base + (boost * complexityFactor)
            
            // Blend with HL:A adjustments or choose one. For now, let HL:A override if darker.
            if !(settings.halfLifeAlyxConfig.enabled && settings.halfLifeAlyxConfig.adaptToDarkScenes && getCurrentSceneLuminance() < settings.halfLifeAlyxConfig.darkSceneLuminanceThreshold) {
                 finalTargetBitrateMbps = dynamicTarget
            }
        }
        
        // Ensure final bitrate doesn't exceed overall max
        finalTargetBitrateMbps = min(finalTargetBitrateMbps, Float(settings.videoConfig.targetMaxBitrateMbps))
        
        // Update effective bitrate for JSON generation (internal state, not a direct setting)
        // This is a conceptual update; the JSON will use the calculated bitrate.
        // The `BitrateConfigServer` will be constructed with this.
        // For simplicity, we'll assume `ALVRShadowPCIntegration` reads this effective target
        // when calling `getServerSessionParametersAsJson`.
        // Let's add a property for this:
        self.effectiveTargetBitrateMbps = finalTargetBitrateMbps

        // Dynamic Foveation Adjustments (example)
        if settings.foveationConfig.enabled && settings.foveationConfig.dynamicAdjustmentEnabled {
            if currentFPS < Float(settings.foveationConfig.performanceTargetFps) && currentFPS > 0 {
                // If FPS is low, make foveation more aggressive (e.g., reduce quality factors or increase radii effects)
                // This is a simplified example. A real implementation would adjust layer parameters.
                // For now, this logic would inform how foveationLayers are translated in getServerSessionParametersAsJson.
                // We can add an internal `currentFoveationStrengthMultiplier` property.
                self.currentFoveationStrengthMultiplier = max(0.5, self.currentFoveationStrengthMultiplier - 0.05) // More aggressive
            } else {
                self.currentFoveationStrengthMultiplier = min(1.0, self.currentFoveationStrengthMultiplier + 0.02) // Less aggressive
            }
        } else {
            self.currentFoveationStrengthMultiplier = 1.0
        }
    }
    
    private var effectiveTargetBitrateMbps: Float = 0.0
    private var currentFoveationStrengthMultiplier: Float = 1.0


    // Function to generate server-side session parameters as a JSON string
    // This JSON should be applicable to ALVR server's session.json or equivalent C API for settings.
    public func getServerSessionParametersAsJson() -> String? {
        let videoSettings = settings.videoConfig
        let foveationSettings = settings.foveationConfig

        // Map VideoOptimizationConfig.VideoCodec to AlvrCodecTypeServer
        let serverCodec: AlvrCodecTypeServer
        switch videoSettings.codec {
        case .h265: serverCodec = .Hevc // HEVC for H.265
        case .av1: serverCodec = .AV1
        }

        // Map NvencPreset
        let serverNvencPreset: AlvrEncoderQualityPresetNvidiaServer = AlvrEncoderQualityPresetNvidiaServer(rawValue: videoSettings.nvencPreset.rawValue) ?? .P5
        
        // Map NvencTuning
        let serverNvencTuning: AlvrNvencTuningPresetServer
        switch videoSettings.nvencTuningPreset {
            case .highQuality: serverNvencTuning = .HighQuality
            case .lowLatency: serverNvencTuning = .LowLatency
            case .ultraLowLatency: serverNvencTuning = .UltraLowLatency
        }
        
        // Map NvencMultiPass
        let serverNvencMultipass: AlvrNvencMultiPassServer
        switch videoSettings.nvencMultiPass {
            case .disabled: serverNvencMultipass = .Disabled
            case .quarterRes: serverNvencMultipass = .QuarterResolution
            case .fullRes: serverNvencMultipass = .FullResolution
        }

        // Map RateControlMode
        let serverRcMode: AlvrRateControlModeServer
        switch videoSettings.rateControlMode {
        case .cbr: serverRcMode = .Cbr
        case .vbr: serverRcMode = .Vbr
        }
        
        // Map AdaptiveQuantizationMode
        let serverAqMode: AlvrNvencAdaptiveQuantizationModeServer
        switch videoSettings.adaptiveQuantizationMode {
            case .disabled: serverAqMode = .Disabled
            case .spatial: serverAqMode = .Spatial
            case .temporal: serverAqMode = .Temporal
        }

        let nvencConfig = AlvrNvencConfigServer(
            quality_preset: serverNvencPreset,
            tuning_preset: serverNvencTuning,
            multi_pass: serverNvencMultipass,
            adaptive_quantization_mode: serverAqMode
        )

        let encoderConfig = AlvrEncoderConfigServer(
            rate_control_mode: serverRcMode,
            use_10bit: videoSettings.use10BitEncodingServer,
            encoding_gamma: videoSettings.encodingGamma,
            enable_hdr: videoSettings.enableHDRServer,
            nvenc: nvencConfig
        )
        
        // Foveation: Convert UI layers to server's expected FoveatedEncodingConfig
        // ALVR foveation: center_size is normalized (0-1), edge_ratio is multiplier (1-inf)
        // Our config: qualityFactor (0-1), radiusDegrees (angle)
        // This mapping needs to be carefully calibrated.
        // For simplicity, assume first layer defines center, second periphery start.
        // Vision Pro FoV is roughly 100-110 degrees H/V.
        let totalFovDegreesHorizontal: Float = 100.0 // Approximate
        let totalFovDegreesVertical: Float = 100.0   // Approximate

        let centerLayer = foveationSettings.foveationLayers.first ?? EyeTrackedFoveationConfig.FoveationLayer(qualityFactor: 1.0, radiusDegrees: 20.0, transitionDegrees: 5.0)
        let midLayer = foveationSettings.foveationLayers.count > 1 ? foveationSettings.foveationLayers[1] : EyeTrackedFoveationConfig.FoveationLayer(qualityFactor: 0.5, radiusDegrees: 40.0, transitionDegrees: 10.0)
        // Peripheral layer quality factor is used for edge_ratio
        let peripheralLayer = foveationSettings.foveationLayers.last ?? EyeTrackedFoveationConfig.FoveationLayer(qualityFactor: 0.25, radiusDegrees: 0.0, transitionDegrees: 0.0)

        // Apply dynamic foveation strength multiplier
        let dynamicCenterQuality = centerLayer.qualityFactor * currentFoveationStrengthMultiplier
        let dynamicMidQuality = midLayer.qualityFactor * currentFoveationStrengthMultiplier
        let dynamicPeripheralQuality = peripheralLayer.qualityFactor * currentFoveationStrengthMultiplier


        // Convert radius from degrees to normalized screen space (approximate)
        // center_size_x/y are fractions of the total FoV that are *not* foveated (i.e. full res)
        // A larger radiusDegrees means a larger center_size.
        let serverCenterSizeX = min(1.0, (2.0 * centerLayer.radiusDegrees) / totalFovDegreesHorizontal)
        let serverCenterSizeY = min(1.0, (2.0 * centerLayer.radiusDegrees) / totalFovDegreesVertical)

        // edge_ratio_x/y: Multiplier for resolution drop-off. Higher means sharper drop.
        // qualityFactor 1.0 -> edge_ratio 1.0 (no drop)
        // qualityFactor 0.5 -> edge_ratio 2.0 (half res)
        // qualityFactor 0.25 -> edge_ratio 4.0 (quarter res)
        // Use the quality of the peripheral region to determine the edge ratios.
        let serverEdgeRatioX = 1.0 / max(0.1, dynamicPeripheralQuality) // Ensure not zero
        let serverEdgeRatioY = 1.0 / max(0.1, dynamicPeripheralQuality)

        let serverFoveationContent = AlvrFoveatedEncodingConfigServer(
            force_enable: foveationSettings.enabled,
            center_size_x: serverCenterSizeX,
            center_size_y: serverCenterSizeY,
            center_shift_x: 0.0, // Assuming centered gaze for now, dynamic shift is complex
            center_shift_y: 0.0,
            edge_ratio_x: serverEdgeRatioX,
            edge_ratio_y: serverEdgeRatioY
        )
        
        let serverFoveation = AlvrSwitchableConfig(enabled: foveationSettings.enabled, content: serverFoveationContent)

        // Bitrate configuration
        let actualTargetBitrate = UInt64(effectiveTargetBitrateMbps > 0 ? effectiveTargetBitrateMbps : Float(videoSettings.targetMaxBitrateMbps))
        
        let bitrateModeServer: AlvrBitrateModeServer
        if videoSettings.dynamicBitrate.enabled {
            // For simplicity, if dynamic bitrate is on in our settings, we'll still use ConstantMbps
            // for the server, but ALVRShadowPCIntegration will dynamically update this constant value.
            // A true adaptive mode on the server side is more complex to map.
            // Or, we map to ALVR's adaptive mode if the parameters align well.
            // Let's use ConstantMbps and have the integration layer adjust it.
            bitrateModeServer = .ConstantMbps(actualTargetBitrate)
        } else {
            bitrateModeServer = .ConstantMbps(actualTargetBitrate)
        }

        let bitrateConfig = AlvrBitrateConfigServer(mode: bitrateModeServer)
        
        let frameSize = AlvrFrameSizeServer.Absolute(AlvrAbsoluteFrameSizeServer(width: videoSettings.targetEyeWidth, height: videoSettings.targetEyeHeight))

        let videoSettingsServer = AlvrVideoSettingsServer(
            preferred_codec: serverCodec,
            foveated_encoding: serverFoveation,
            encoder_config: encoderConfig,
            bitrate: bitrateConfig,
            transcoding_view_resolution: frameSize,
            preferred_fps: videoSettings.targetRefreshRate,
            use_10bit_decoder: videoSettings.use10BitEncodingServer, // Client hints preference
            enable_hdr_decoder: videoSettings.enableHDRServer,       // Client hints preference
            encoding_gamma_decoder: videoSettings.encodingGamma     // Client hints preference
        )
        
        let sessionSettingsServer = AlvrSessionSettingsServer(video: videoSettingsServer)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.keyEncodingStrategy = .convertToSnakeCase // Crucial for ALVR server
        
        do {
            let jsonData = try encoder.encode(sessionSettingsServer)
            return String(data: jsonData, encoding: .utf8)
        } catch {
            // In a real app, ALVRShadowPCIntegration.shared.logError("Failed to generate server JSON: \(error)")
            print("[ShadowPCOptimizer] Error encoding server settings to JSON: \(error)")
            return nil
        }
    }

    // This function remains conceptual as client-side rendering is complex and handled elsewhere.
    // It's a hook for ALVRShadowPCIntegration if optimizer settings need to trigger client-side logic.
    public func applyClientSideOptimizations() {
        // Example: If sharpening is purely client-side, this might trigger an update in a client renderer.
        // Or update parameters for client-side frame interpolation.
        // For now, this is mostly managed by ALVRShadowPCIntegration observing settings changes.
        print("[ShadowPCOptimizer] Applying client-side optimization triggers (if any).")
    }
    
    // Stubs for external data providers (values would be fed by ALVRShadowPCIntegration)
    private func getCurrentSceneLuminance() -> Float {
        // This would be calculated by ALVRShadowPCIntegration based on frame analysis or game telemetry
        return 0.5 // Placeholder: normalized 0-1
    }
    
    private func getCurrentSceneComplexity() -> Float {
        // This would be calculated by ALVRShadowPCIntegration
        return 0.5 // Placeholder: normalized 0-1
    }
}

// MARK: - CaseIterable for Pickers (ensure these are defined if not already)
// These were in ShadowPCSettingsView.swift, moved here or ensure they are global.
// For simplicity, assuming they are accessible or redefined if this file is standalone.
// If these enums are defined in this file, they need to be outside any class/struct.
// Example:
// public enum VideoCodec: String, Codable, CaseIterable, Equatable { ... }
// (already defined within VideoOptimizationConfig, which is fine)

// MARK: - Equatable Conformance for top-level settings struct
// Already defined in ShadowPCSettingsView.swift, if this file is used standalone,
// ensure ShadowPCOptimizationSettings and its sub-structs conform to Equatable
// if needed for .onChange or other comparison logic.
// For this file's purpose, the Codable conformance is primary.
