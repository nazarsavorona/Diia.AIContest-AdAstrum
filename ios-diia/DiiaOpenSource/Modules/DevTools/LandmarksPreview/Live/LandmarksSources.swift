import AVFoundation
import CryptoKit
import QuartzCore
import UIKit

struct StreamValidationError {
    let code: String
    let message: String
}

struct LandmarksDetection {
    let landmarks: [LandmarkPoint]
    let originalImageSize: CGSize
    let status: String
    let errors: [StreamValidationError]
    let faceBoundingBox: CGRect?
    let latencyMs: Double?
}

protocol FaceLandmarksSource {
    func process(sampleBuffer: CMSampleBuffer,
                 orientation: CGImagePropertyOrientation,
                 completion: @escaping (Result<LandmarksDetection, Error>) -> Void)
    func stop()
}

final class ApiForwardingLandmarksSource: FaceLandmarksSource {
    private struct StreamRequest: Encodable {
        let encrypted_image: String
        let encryption: String = ImagePayloadEncryptor.algorithmName
        let mode: String = "stream"
    }

    private struct StreamResponse: Decodable {
        let status: String
        let errors: [ApiError]
        let landmarks: [ApiLandmark]?
        let guidance: ApiGuidance?
    }

    private struct ApiError: Decodable {
        let code: String
        let message: String
    }

    private struct ApiLandmark: Decodable {
        let x: Double
        let y: Double
    }

    private struct ApiGuidance: Decodable {
        let faceBBox: [Double]?

        enum CodingKeys: String, CodingKey {
            case faceBBox = "face_bbox"
        }
    }

    private let endpoint: URL
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let encryptor = ImagePayloadEncryptor()
    private let processingQueue = DispatchQueue(label: "ua.gov.diia.landmarks.api", qos: .userInitiated)
    private let ciContext = CIContext()
    private let debugSaveFrames = false
    private let debugSaveLimit = 0
    private var debugSavedCount = 0

    private var inFlight = false
    private var lastRequestTime: TimeInterval = 0
    private var throttleInterval: TimeInterval = 0.2
    private var currentTask: URLSessionDataTask?

    init(baseURL: URL = URL(string: "https://d28w3hxcjjqa9z.cloudfront.net/api/v1")!,
         session: URLSession = .shared) {
        self.session = session
        self.endpoint = baseURL.appendingPathComponent("validate/stream")
    }

    func process(sampleBuffer: CMSampleBuffer,
                 orientation: CGImagePropertyOrientation,
                 completion: @escaping (Result<LandmarksDetection, Error>) -> Void) {
        processingQueue.async { [weak self] in
            guard let self else { return }
            let startTime = CACurrentMediaTime()
            let now = CACurrentMediaTime()
            guard !self.inFlight, now - self.lastRequestTime >= self.throttleInterval else { return }
            guard let encodedFrame = self.encode(sampleBuffer: sampleBuffer, orientation: orientation) else {
                DispatchQueue.main.async {
                    completion(.failure(LandmarksSourceError.encodingFailed))
                }
                return
            }
            let encryptedPayload: String
            do {
                encryptedPayload = try self.encryptor.encrypt(base64Payload: encodedFrame.base64)
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            self.inFlight = true
            self.lastRequestTime = now
            var request = URLRequest(url: self.endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            do {
                let body = StreamRequest(encrypted_image: encryptedPayload)
                request.httpBody = try self.encoder.encode(body)
            } catch {
                self.markFinished()
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            let task = self.session.dataTask(with: request) { data, response, error in
                self.markFinished()
                if let error = error {
                    print("Stream request failed with error: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                    return
                }
                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    print("Stream request failed with HTTP \(httpResponse.statusCode)")
                    DispatchQueue.main.async {
                        completion(.failure(LandmarksSourceError.http(statusCode: httpResponse.statusCode)))
                    }
                    return
                }
                guard let data = data else {
                    print("Stream request failed: empty response data")
                    DispatchQueue.main.async {
                        completion(.failure(LandmarksSourceError.invalidResponse))
                    }
                    return
                }
                do {
                    let parsed = try self.decoder.decode(StreamResponse.self, from: data)
                    let points = parsed.landmarks?.enumerated().map { idx, point in
                        LandmarkPoint(index: idx,
                                      position: CGPoint(x: point.x, y: point.y))
                    } ?? []
                    let errors = parsed.errors.map { StreamValidationError(code: $0.code, message: $0.message) }
                    let bboxRect = Self.rect(from: parsed.guidance?.faceBBox)
                    let detection = LandmarksDetection(landmarks: points,
                                                       originalImageSize: encodedFrame.size,
                                                       status: parsed.status,
                                                       errors: errors,
                                                       faceBoundingBox: bboxRect,
                                                       latencyMs: (CACurrentMediaTime() - startTime) * 1000.0)
                    self.logResponse(detection: detection)
                    DispatchQueue.main.async {
                        completion(.success(detection))
                    }
                } catch {
                    print("Stream response decode failed: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                }
            }
            self.currentTask = task
            task.resume()
        }
    }

    func stop() {
        processingQueue.async { [weak self] in
            self?.currentTask?.cancel()
            self?.currentTask = nil
            self?.inFlight = false
        }
    }

    func updateThrottleInterval(_ interval: TimeInterval) {
        processingQueue.async { [weak self] in
            self?.throttleInterval = max(0.01, interval)
        }
    }

    private func encode(sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation) -> (base64: String, size: CGSize)? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        // Respect camera orientation passed from capture
        let oriented = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        
        let cropTarget = centerCrop(image: oriented, targetAspectRatio: 2.0 / 3.0)

        // Mirror horizontally to match front camera user expectation
        let mirrored = cropTarget
            .transformed(by: CGAffineTransform(scaleX: -1, y: 1))
            .transformed(by: CGAffineTransform(translationX: cropTarget.extent.width, y: 0))

        guard let cgImage = ciContext.createCGImage(mirrored, from: mirrored.extent.integral) else { return nil }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let uiImage = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.65) else { return nil }

        if debugSaveFrames && debugSavedCount < debugSaveLimit {
            debugSavedCount += 1
            saveDebugImage(data: jpegData, name: "stream_frame_\(debugSavedCount).jpg")
        }

        let base64 = jpegData.base64EncodedString()
        return (base64, imageSize)
    }

    private func markFinished() {
        processingQueue.async { [weak self] in
            self?.inFlight = false
            self?.currentTask = nil
        }
    }

    private static func rect(from bbox: [Double]?) -> CGRect? {
        guard let bbox, bbox.count == 4 else { return nil }
        return CGRect(x: bbox[0], y: bbox[1], width: bbox[2], height: bbox[3])
    }

    private func saveDebugImage(data: Data, name: String) {
        let fm = FileManager.default
        let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("LandmarksDebug", isDirectory: true)
        guard let dir else { return }
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            print("Saved debug image to \(url.path)")
        } catch {
            print("Failed to save debug image: \(error.localizedDescription)")
        }
    }

    private func logResponse(detection: LandmarksDetection) {
        let errorSummary = detection.errors.map { "[\($0.code)] \($0.message)" }.joined(separator: "; ")
        let bboxText: String
        if let bbox = detection.faceBoundingBox {
            bboxText = "bbox=\(Int(bbox.origin.x)),\(Int(bbox.origin.y)),\(Int(bbox.width))x\(Int(bbox.height))"
        } else {
            bboxText = "bbox=none"
        }
        let latencyText = detection.latencyMs.map { String(format: "%.0fms", $0) } ?? "n/a"
        print("Stream response -> status=\(detection.status.uppercased()) landmarks=\(detection.landmarks.count) \(bboxText) latency=\(latencyText) errors=\(errorSummary)")
    }

    private func centerCrop(image: CIImage, targetAspectRatio: CGFloat) -> CIImage {
        var rect = image.extent
        let currentRatio = rect.width / rect.height
        if currentRatio > targetAspectRatio {
            let newWidth = rect.height * targetAspectRatio
            rect.origin.x += (rect.width - newWidth) / 2.0
            rect.size.width = newWidth
        } else {
            let newHeight = rect.width / targetAspectRatio
            rect.origin.y += (rect.height - newHeight) / 2.0
            rect.size.height = newHeight
        }
        rect = rect.integral
        return image.cropped(to: rect)
    }
}

enum LandmarksSourceError: LocalizedError {
    case mediapipeUnavailable
    case notImplemented
    case encodingFailed
    case invalidResponse
    case http(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .mediapipeUnavailable:
            return "MediaPipe framework not linked. Add MediaPipeTasksVision per the official guide."
        case .notImplemented:
            return "Landmark provider is not implemented yet."
        case .encodingFailed:
            return "Не вдалося підготувати кадр для відправки на сервер."
        case .invalidResponse:
            return "Отримано некоректну відповідь від сервера."
        case .http(let statusCode):
            return "Сервер повернув помилку \(statusCode)."
        }
    }
}

struct ImagePayloadEncryptor {
    enum Error: Swift.Error {
        case combinedDataUnavailable
    }

    static let algorithmName = "aes_gcm"
    static let defaultSecret = "diia-stream-shared-secret"

    private let key: SymmetricKey

    init(secret: String = ImagePayloadEncryptor.defaultSecret) {
        let hashed = SHA256.hash(data: Data(secret.utf8))
        self.key = SymmetricKey(data: hashed)
    }

    func encrypt(base64Payload: String) throws -> String {
        let data = Data(base64Payload.utf8)
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw Error.combinedDataUnavailable
        }
        return Data(combined).base64EncodedString()
    }
}
