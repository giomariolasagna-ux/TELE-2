import Foundation

struct RectNorm: Codable, Equatable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double
}

struct CameraMetadata: Codable, Equatable {
    var iso: Double
    var shutterS: Double
    var ev: Double
    var wbKelvin: Double
    var focalMm: Double?
    var orientationUpright: Bool
}

struct CapturedFramePair: Codable, Equatable {
    var captureId: String
    var zoomFactor: Double
    var fullWidth: Int
    var fullHeight: Int
    var cropWidth: Int
    var cropHeight: Int
    var cropRectNorm: RectNorm
    var metadata: CameraMetadata
}

struct DualAnalysisPack: Codable, Equatable {
    var captureId: String?
    var sceneSummaryFull: String?
    var sceneSummaryCrop: String?
    var qualityFlagsCrop: String?
    var constraints: String?

    enum CodingKeys: String, CodingKey {
        case captureId = "capture_id"
        case sceneSummaryFull = "scene_summary_full"
        case sceneSummaryCrop = "scene_summary_crop"
        case qualityFlagsCrop = "quality_flags_crop"
        case constraints
    }
}

struct PromptBundle: Codable, Equatable {
    var captureId: String
    var nbPrompt: String
    var nbNegative: String
    var renderNotes: String?
}

