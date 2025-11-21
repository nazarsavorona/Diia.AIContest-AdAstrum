import AVFoundation
import UIKit

protocol FaceLandmarksSource {
    func process(sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation, completion: @escaping (Result<[LandmarkPoint], Error>) -> Void)
    func stop()
}

final class ApiForwardingLandmarksSource: FaceLandmarksSource {
    func process(sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation, completion: @escaping (Result<[LandmarkPoint], Error>) -> Void) {
        // Placeholder: integrate API call using serialized frames.
        completion(.failure(LandmarksSourceError.notImplemented))
    }

    func stop() {}
}

final class MediapipeLandmarksSource: FaceLandmarksSource {
    #if canImport(MediaPipeTasksVision)
    // Implementation should wrap MediaPipe Tasks Vision FaceLandmarker.
    #endif

    func process(sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation, completion: @escaping (Result<[LandmarkPoint], Error>) -> Void) {
        #if canImport(MediaPipeTasksVision)
        // TODO: plug MediaPipe FaceLandmarker here once framework is added.
        completion(.failure(LandmarksSourceError.notImplemented))
        #else
        completion(.failure(LandmarksSourceError.mediapipeUnavailable))
        #endif
    }

    func stop() {}
}

enum LandmarksSourceError: LocalizedError {
    case mediapipeUnavailable
    case notImplemented

    var errorDescription: String? {
        switch self {
        case .mediapipeUnavailable:
            return "MediaPipe framework not linked. Add MediaPipeTasksVision per the official guide."
        case .notImplemented:
            return "Landmark provider is not implemented yet."
        }
    }
}
