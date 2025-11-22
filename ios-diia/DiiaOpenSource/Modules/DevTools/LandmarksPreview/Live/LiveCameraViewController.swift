import UIKit
import AVFoundation
import DiiaUIComponents

final class LiveCameraViewController: UIViewController {
    private let cameraService = CameraCaptureService()
    private let landmarksSource: FaceLandmarksSource = ApiForwardingLandmarksSource()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let overlayView = LandmarksOverlayView()
    private var lastFrameSize: CGSize = CGSize(width: 2, height: 3)
    private var responseTimestamps: [CFTimeInterval] = []
    private let fpsWindow: CFTimeInterval = 2.0

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = FontBook.usualFont
        return label
    }()
    private let responseLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .left
        label.textColor = .label
        label.font = FontBook.usualFont
        return label
    }()
    private let infoContainer: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        view.layer.cornerRadius = 12
        view.clipsToBounds = true
        return view
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Камера (Live)"
        view.backgroundColor = .black
        cameraService.delegate = self
        loadRocketSimConnect()
        setupLayout()
        cameraService.configure()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cameraService.stop()
        landmarksSource.stop()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        overlayView.frame = view.bounds
    }

    private func setupLayout() {
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.backgroundColor = .clear
        view.addSubview(overlayView)

        infoContainer.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        responseLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(infoContainer)
        infoContainer.addSubview(statusLabel)
        infoContainer.addSubview(responseLabel)

        NSLayoutConstraint.activate([
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: view.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            infoContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            infoContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            infoContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            statusLabel.leadingAnchor.constraint(equalTo: infoContainer.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: infoContainer.trailingAnchor, constant: -12),
            statusLabel.topAnchor.constraint(equalTo: infoContainer.topAnchor, constant: 10),

            responseLabel.leadingAnchor.constraint(equalTo: infoContainer.leadingAnchor, constant: 12),
            responseLabel.trailingAnchor.constraint(equalTo: infoContainer.trailingAnchor, constant: -12),
            responseLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            responseLabel.bottomAnchor.constraint(equalTo: infoContainer.bottomAnchor, constant: -12)
        ])
        statusLabel.text = "Запит доступу до камери"
        responseLabel.textColor = .systemYellow
        responseLabel.text = "Надішліть кадр, щоб побачити відповіді сервера."
        overlayView.configure(landmarks: [],
                              imageSize: lastFrameSize,
                              connections: mediaPipeFullMeshConnections,
                              faceBoundingBox: nil)
    }

    private func attachPreviewLayer() {
        guard let layer = cameraService.previewLayer else { return }
        previewLayer?.removeFromSuperlayer()
        layer.videoGravity = .resizeAspect
        if let connection = layer.connection {
            connection.videoOrientation = .portrait
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
    }

    private func updateResponse(status: String, errors: [StreamValidationError], latencyMs: Double?) {
        let upperStatus = status.uppercased()
        let fpsValue = calculateFPS()
        let latencyText: String
        if let latencyMs {
            latencyText = String(format: "%.0f ms", latencyMs)
        } else {
            latencyText = "—"
        }
        var lines: [String] = [
            "Статус: \(upperStatus)",
            String(format: "FPS (server): %.1f • Затримка: %@", fpsValue, latencyText)
        ]
        if !errors.isEmpty {
            let errorLines = errors.prefix(3).map { "• [\($0.code)] \($0.message)" }
            lines.append(contentsOf: errorLines)
            if errors.count > 3 {
                lines.append("• ...ще \(errors.count - 3)")
            }
        } else {
            lines.append("Повідомлень про помилки немає")
        }
        responseLabel.text = lines.joined(separator: "\n")
        responseLabel.textColor = upperStatus == "SUCCESS" ? .systemGreen : .systemYellow
    }
}

extension LiveCameraViewController: CameraCaptureServiceDelegate {
    func cameraCaptureService(_ service: CameraCaptureService, didOutput sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation) {
        landmarksSource.process(sampleBuffer: sampleBuffer, orientation: orientation) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let detection):
                self.lastFrameSize = detection.originalImageSize
                self.recordResponseTick()
                self.overlayView.configure(landmarks: detection.landmarks,
                                           imageSize: detection.originalImageSize,
                                           connections: mediaPipeFullMeshConnections,
                                           faceBoundingBox: detection.faceBoundingBox)
                self.updateResponse(status: detection.status, errors: detection.errors, latencyMs: detection.latencyMs)
            case .failure(let error):
                self.recordResponseTick()
                self.overlayView.configure(landmarks: [],
                                           imageSize: self.lastFrameSize,
                                           connections: mediaPipeFullMeshConnections,
                                           faceBoundingBox: nil)
                let inlineError = StreamValidationError(code: "client_error", message: error.localizedDescription)
                self.updateResponse(status: "fail", errors: [inlineError], latencyMs: nil)
            }
        }
    }

    func cameraCaptureService(_ service: CameraCaptureService, didChangeAuthorization authorized: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if authorized {
                self.statusLabel.text = "Камера активна. Надсилаємо кадри на сервер..."
                self.attachPreviewLayer()
                service.start()
            } else {
                self.statusLabel.text = "Доступ до камери заборонено. Дозвольте камеру в Налаштуваннях."
                self.responseLabel.text = nil
            }
        }
    }

    func cameraCaptureService(_ service: CameraCaptureService, didFail error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel.text = error.localizedDescription
            self?.responseLabel.text = nil
        }
    }
}

private extension LiveCameraViewController {
    func recordResponseTick() {
        let now = CACurrentMediaTime()
        responseTimestamps.append(now)
        responseTimestamps.removeAll { now - $0 > fpsWindow }
    }

    func calculateFPS() -> Double {
        guard let latest = responseTimestamps.last else { return 0 }
        let windowStart = latest - fpsWindow
        let framesInWindow = responseTimestamps.filter { $0 >= windowStart }.count
        return Double(framesInWindow) / fpsWindow
    }
}

private extension LiveCameraViewController {
    func loadRocketSimConnect() {
        #if DEBUG
        let path = "/Applications/RocketSim.app/Contents/Frameworks/RocketSimConnectLinker.nocache.framework"
        guard let bundle = Bundle(path: path) else {
            print("RocketSim Connect linker bundle not found at \(path)")
            return
        }
        do {
            try bundle.loadAndReturnError()
            print("RocketSim Connect successfully linked")
        } catch {
            print("Failed to load RocketSim Connect linker: \(error)")
        }
        #endif
    }
}
