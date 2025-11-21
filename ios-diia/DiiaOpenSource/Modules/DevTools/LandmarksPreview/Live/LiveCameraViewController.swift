import UIKit
import AVFoundation
import DiiaUIComponents

final class LiveCameraViewController: UIViewController {
    private let cameraService = CameraCaptureService()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = FontBook.usualFont
        return label
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func setupLayout() {
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            statusLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24)
        ])
        statusLabel.text = "Запит доступу до камери"
    }

    private func attachPreviewLayer() {
        guard let layer = cameraService.previewLayer else { return }
        previewLayer?.removeFromSuperlayer()
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
    }
}

extension LiveCameraViewController: CameraCaptureServiceDelegate {
    func cameraCaptureService(_ service: CameraCaptureService, didOutput sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation) {
        // Only showing preview; no processing yet.
    }

    func cameraCaptureService(_ service: CameraCaptureService, didChangeAuthorization authorized: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if authorized {
                self.statusLabel.text = ""
                self.attachPreviewLayer()
                service.start()
            } else {
                self.statusLabel.text = "Доступ до камери заборонено. Дозвольте камеру в Налаштуваннях."
            }
        }
    }

    func cameraCaptureService(_ service: CameraCaptureService, didFail error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel.text = error.localizedDescription
        }
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
