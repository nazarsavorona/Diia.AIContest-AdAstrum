import AVFoundation
import UIKit

protocol CameraCaptureServiceDelegate: AnyObject {
    func cameraCaptureService(_ service: CameraCaptureService, didOutput sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation)
    func cameraCaptureService(_ service: CameraCaptureService, didChangeAuthorization authorized: Bool)
    func cameraCaptureService(_ service: CameraCaptureService, didFail error: Error)
}

final class CameraCaptureService: NSObject {
    weak var delegate: CameraCaptureServiceDelegate?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "ua.gov.diia.camera.session")
    private var videoOutput: AVCaptureVideoDataOutput?
    private var videoDeviceInput: AVCaptureDeviceInput?

    private(set) var previewLayer: AVCaptureVideoPreviewLayer?

    func configure() {
        checkAuthorization()
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    private func checkAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            delegate?.cameraCaptureService(self, didChangeAuthorization: true)
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.delegate?.cameraCaptureService(self, didChangeAuthorization: granted)
                    if granted {
                        self.setupSession()
                    }
                }
            }
        default:
            delegate?.cameraCaptureService(self, didChangeAuthorization: false)
        }
    }

    private func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            do {
                if let existingInput = self.videoDeviceInput {
                    self.session.removeInput(existingInput)
                }
                guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) ??
                        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified) else {
                    throw CaptureError.deviceUnavailable
                }
                let input = try AVCaptureDeviceInput(device: camera)
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.videoDeviceInput = input
                }
            } catch {
                DispatchQueue.main.async {
                    self.delegate?.cameraCaptureService(self, didFail: error)
                }
                self.session.commitConfiguration()
                return
            }

            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.setSampleBufferDelegate(self, queue: self.sessionQueue)
            if self.session.canAddOutput(output) {
                self.session.addOutput(output)
                self.videoOutput = output
            }
            self.session.commitConfiguration()

            let layer = AVCaptureVideoPreviewLayer(session: self.session)
            layer.videoGravity = .resizeAspect
            self.previewLayer = layer
            self.start()
        }
    }
}

extension CameraCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let orientation = CGImagePropertyOrientation.pixelBufferOrientation(pixelBuffer: pixelBuffer)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.cameraCaptureService(self, didOutput: sampleBuffer, orientation: orientation)
        }
    }
}

extension CGImagePropertyOrientation {
    static func pixelBufferOrientation(pixelBuffer: CVPixelBuffer) -> CGImagePropertyOrientation {
        // Default to up; AVCapture handles mirrored preview itself
        return .right
    }
}

enum CaptureError: Error {
    case deviceUnavailable
}
