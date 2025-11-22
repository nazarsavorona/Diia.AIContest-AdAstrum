import UIKit
import AVFoundation
import DiiaUIComponents
import DiiaMVPModule

final class DocumentPhotoCheckStreamViewController: UIViewController, BaseView {
    private let cameraService = CameraCaptureService()
    private let validationSource: FaceLandmarksSource = ApiForwardingLandmarksSource()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var lastFrameSize: CGSize = CGSize(width: 2, height: 3)
    
    private let topView = TopNavigationView()
    private let previewContainer = UIView()
    private let placeholderImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.isHidden = true
        iv.backgroundColor = UIColor(white: 0.15, alpha: 1)
        iv.image = R.image.light_background.image
        return iv
    }()
    private let landmarksOverlay = LandmarksOverlayView()
    private let overlayView = PhotoCheckFrameView()
    private let messageLabel: UILabel = {
        let label = PaddingLabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = FontBook.bigText
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        label.layer.cornerRadius = 6
        label.clipsToBounds = true
        label.isHidden = true
        return label
    }()
    private let continueButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Продовжити", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = FontBook.bigText
        button.backgroundColor = UIColor.black.withAlphaComponent(0.2)
        button.layer.cornerRadius = 22
        button.isEnabled = false
        return button
    }()
    private let landmarksToggleStack: UIStackView = {
        let label = UILabel()
        label.font = FontBook.usualFont
        label.textColor = .label
        label.text = "Landmarks"
        let sw = UISwitch()
        sw.isOn = false
        let stack = UIStackView(arrangedSubviews: [label, sw])
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    private var showLandmarks = false {
        didSet { updateLandmarksVisibility() }
    }
    
    private var isFrameValid: Bool = false {
        didSet {
            updateButtonState()
            overlayView.state = isFrameValid ? .success : .idle
        }
    }
    
    private var isValidating = false
    private var lastValidationAt: CFTimeInterval = 0
    private let validationThrottle: CFTimeInterval = 0.6
    private let frameScale: CGFloat = 1.0 / 1.5
    private var lastSampleBuffer: CMSampleBuffer?
    private var lastValidImage: UIImage?
    private var needsRetake = false
    private var isFinalValidating = false
    private var lastOrientation: CGImagePropertyOrientation = .right
    private let finalValidationURL = URL(string: "https://d28w3hxcjjqa9z.cloudfront.net/api/v1/validate/photo")!
    private let ciContext = CIContext()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.backgroundColor
        setupLayout()
        cameraService.delegate = self
        cameraService.configure()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cameraService.stop()
        validationSource.stop()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = previewContainer.bounds
        overlayView.frame = previewContainer.bounds
        landmarksOverlay.frame = previewContainer.bounds
        let frameRect = calculateFrameRect(in: previewContainer.bounds)
        overlayView.frameRect = frameRect
        landmarksOverlay.cropRect = frameRect
    }
    
    private func setupLayout() {
        topView.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        placeholderImageView.translatesAutoresizingMaskIntoConstraints = false
        landmarksOverlay.translatesAutoresizingMaskIntoConstraints = false
        continueButton.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(topView)
        view.addSubview(previewContainer)
        
        previewContainer.addSubview(placeholderImageView)
        previewContainer.addSubview(landmarksOverlay)
        previewContainer.addSubview(messageLabel)
        previewContainer.addSubview(overlayView)
        previewContainer.addSubview(landmarksToggleStack)
        previewContainer.addSubview(continueButton)
        if let toggle = landmarksToggleStack.arrangedSubviews.last as? UISwitch {
            toggle.addTarget(self, action: #selector(toggleLandmarks(_:)), for: .valueChanged)
        }
        landmarksOverlay.showsReferenceFrame = false
        landmarksOverlay.showsBoundingBox = false
        
        topView.setupTitle(title: "Фото для перевірки")
        topView.setupOnClose { [weak self] in
            self?.closeModule(animated: true)
        }
        topView.setupOnContext(callback: nil)
        
        continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
        updateButtonState()
        
        NSLayoutConstraint.activate([
            topView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            previewContainer.topAnchor.constraint(equalTo: topView.bottomAnchor, constant: 4),
            previewContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            
            placeholderImageView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            placeholderImageView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            placeholderImageView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            placeholderImageView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),
            
            landmarksOverlay.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            landmarksOverlay.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            landmarksOverlay.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            landmarksOverlay.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),
            
            messageLabel.centerXAnchor.constraint(equalTo: previewContainer.centerXAnchor),
            messageLabel.topAnchor.constraint(equalTo: previewContainer.topAnchor, constant: 12),
            
            overlayView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),
            
            landmarksToggleStack.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: -12),
            landmarksToggleStack.topAnchor.constraint(equalTo: previewContainer.topAnchor, constant: 12),
            
            continueButton.centerXAnchor.constraint(equalTo: previewContainer.centerXAnchor),
            continueButton.widthAnchor.constraint(equalTo: previewContainer.widthAnchor, multiplier: 0.7),
            continueButton.bottomAnchor.constraint(equalTo: previewContainer.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            continueButton.heightAnchor.constraint(equalToConstant: 56)
        ])
    }
    
    private func attachPreviewLayer() {
        guard let layer = cameraService.previewLayer else { return }
        previewLayer?.removeFromSuperlayer()
        layer.videoGravity = .resizeAspectFill
        if let connection = layer.connection {
            connection.videoOrientation = .portrait
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        layer.frame = previewContainer.bounds
        previewContainer.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
    }
    
    private func updateButtonState() {
        switch (isFinalValidating, needsRetake, isFrameValid) {
        case (true, _, _):
            continueButton.isEnabled = false
            continueButton.backgroundColor = UIColor.black.withAlphaComponent(0.2)
            continueButton.setTitleColor(.white.withAlphaComponent(0.6), for: .disabled)
            continueButton.setTitle("Перевіряємо...", for: .disabled)
        case (false, true, _):
            continueButton.isEnabled = true
            continueButton.backgroundColor = .black
            continueButton.setTitleColor(.white, for: .normal)
            continueButton.setTitle("Завантажити нове фото", for: .normal)
        case (false, false, true):
            continueButton.isEnabled = true
            continueButton.backgroundColor = .black
            continueButton.setTitleColor(.white, for: .normal)
            continueButton.setTitle("Продовжити", for: .normal)
        default:
            continueButton.isEnabled = false
            continueButton.backgroundColor = UIColor.black.withAlphaComponent(0.2)
            continueButton.setTitleColor(UIColor.white.withAlphaComponent(0.6), for: .disabled)
            continueButton.setTitle("Продовжити", for: .disabled)
        }
    }
    
    private func showErrors(_ errors: [StreamValidationError]) {
        guard let first = errors.first else {
            messageLabel.isHidden = true
            overlayView.state = .idle
            return
        }
        let mapped = Constants.photoErrorMessages[first.code] ?? first.message
        messageLabel.text = mapped
        messageLabel.isHidden = false
        overlayView.state = .idle
        isFrameValid = false
        if showLandmarks {
            landmarksOverlay.isHidden = false
        }
    }
    
    @objc private func continueTapped() {
        if isFinalValidating { return }
        if needsRetake {
            needsRetake = false
            isFrameValid = false
            messageLabel.isHidden = true
            lastValidImage = nil
            lastSampleBuffer = nil
            overlayView.state = .idle
            cameraService.start()
            updateButtonState()
            return
        }
        guard let payload = encodeForFinalValidation() else { return }
        // freeze stream
        cameraService.stop()
        validationSource.stop()
        isFinalValidating = true
        updateButtonState()
        performFinalValidation(with: payload.image, base64: payload.base64)
    }
    
    private func showPlaceholder(reason: String) {
        placeholderImageView.isHidden = false
        messageLabel.text = reason
        messageLabel.isHidden = false
        overlayView.state = .idle
        isFrameValid = false
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
        updateLandmarksVisibility()
    }

    private func performFinalValidation(with image: UIImage, base64: String) {
        isFinalValidating = true
        continueButton.setTitle("Перевіряємо...", for: .normal)
        continueButton.isEnabled = false
        let requestBody: [String: Any] = ["image": base64, "mode": "full"]
        var request = URLRequest(url: finalValidationURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody, options: [])
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isFinalValidating = false
                if let error = error {
                    self?.handleFinalValidationFailure(message: error.localizedDescription)
                    return
                }
                guard let data,
                      let parsed = try? JSONDecoder().decode(FinalValidationResponse.self, from: data) else {
                    self?.handleFinalValidationFailure(message: "Помилка валідації.")
                    return
                }
                if parsed.status.lowercased() == "success" && parsed.errors.isEmpty {
                    self?.handleFinalValidationSuccess(image: image)
                } else {
                    let msg = parsed.errors.first.flatMap { Constants.photoErrorMessages[$0.code] ?? $0.message } ?? "Фото не пройшло перевірку."
                    self?.handleFinalValidationFailure(message: msg)
                }
            }
        }.resume()
    }
    
    private func handleFinalValidationSuccess(image: UIImage) {
        needsRetake = false
        let successVC = PhotoSuccessViewController(photoImage: image) { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
        navigationController?.pushViewController(successVC, animated: true)
        updateButtonState()
    }
    
    private func handleFinalValidationFailure(message: String) {
        needsRetake = true
        isFrameValid = false
        messageLabel.text = message
        messageLabel.isHidden = false
        updateButtonState()
        cameraService.start()
    }
    
    @objc private func toggleLandmarks(_ sender: UISwitch) {
        showLandmarks = sender.isOn
        updateLandmarksVisibility()
    }
    
    private func updateLandmarksVisibility() {
        landmarksOverlay.isHidden = !showLandmarks
        if !showLandmarks {
            landmarksOverlay.configure(landmarks: [], imageSize: lastFrameSize, connections: [])
        }
    }
    
    private func calculateFrameRect(in bounds: CGRect) -> CGRect {
        var target = bounds.insetBy(dx: 16, dy: 16)
        let targetAspect: CGFloat = 2.0 / 3.0
        let currentAspect = target.width / target.height
        if currentAspect > targetAspect {
            let newWidth = target.height * targetAspect
            target.origin.x += (target.width - newWidth) / 2
            target.size.width = newWidth
        } else {
            let newHeight = target.width / targetAspect
            target.origin.y += (target.height - newHeight) / 2
            target.size.height = newHeight
        }
        let newWidth = target.width * frameScale
        let newHeight = target.height * frameScale
        target.origin.x += (target.width - newWidth) / 2
        target.origin.y += (target.height - newHeight) / 2
        target.size = CGSize(width: newWidth, height: newHeight)
        return target
    }

    private func encodeForFinalValidation() -> (image: UIImage, base64: String)? {
        guard let sampleBuffer = lastSampleBuffer,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let oriented = CIImage(cvPixelBuffer: pixelBuffer).oriented(lastOrientation)
        var cropped = centerCrop(image: oriented, targetAspectRatio: 2.0 / 3.0)
        let scale = frameScale
        let insetX = (cropped.extent.width * (1 - scale)) / 2
        let insetY = (cropped.extent.height * (1 - scale)) / 2
        cropped = cropped.cropped(to: cropped.extent.insetBy(dx: insetX, dy: insetY))
        guard let cgImage = ciContext.createCGImage(cropped, from: cropped.extent.integral) else { return nil }
        let uiImage = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.8) else { return nil }
        let base64 = jpegData.base64EncodedString()
        return (uiImage, base64)
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

extension DocumentPhotoCheckStreamViewController: CameraCaptureServiceDelegate {
    func cameraCaptureService(_ service: CameraCaptureService, didOutput sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation) {
        let now = CACurrentMediaTime()
        lastSampleBuffer = sampleBuffer
        lastOrientation = orientation
        guard !isValidating, now - lastValidationAt > validationThrottle else { return }
        isValidating = true
        lastValidationAt = now
        
        validationSource.process(sampleBuffer: sampleBuffer, orientation: orientation) { [weak self] result in
            guard let self else { return }
            self.isValidating = false
            switch result {
            case .success(let detection):
                self.lastFrameSize = detection.originalImageSize
                if detection.errors.isEmpty && detection.status.lowercased() == "success" {
                    self.messageLabel.isHidden = true
                    self.isFrameValid = true
                    self.overlayView.state = .success
                    if let payload = self.encodeForFinalValidation() {
                        self.lastValidImage = payload.image
                    }
                    if self.showLandmarks {
                        self.landmarksOverlay.isHidden = false
                        self.landmarksOverlay.configure(landmarks: detection.landmarks,
                                                        imageSize: detection.originalImageSize,
                                                        connections: mediaPipeFullMeshConnections,
                                                        faceBoundingBox: detection.faceBoundingBox)
                    }
                } else {
                    self.showErrors(detection.errors)
                    if self.showLandmarks {
                        self.landmarksOverlay.isHidden = false
                        self.landmarksOverlay.configure(landmarks: detection.landmarks,
                                                        imageSize: detection.originalImageSize,
                                                        connections: mediaPipeFullMeshConnections,
                                                        faceBoundingBox: detection.faceBoundingBox)
                    }
                }
            case .failure(let error):
                self.isFrameValid = false
                self.messageLabel.text = error.localizedDescription
                self.messageLabel.isHidden = false
                self.overlayView.state = .idle
                self.landmarksOverlay.isHidden = true
                self.needsRetake = true
            }
        }
    }
    
    func cameraCaptureService(_ service: CameraCaptureService, didChangeAuthorization authorized: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if authorized {
                self.attachPreviewLayer()
                service.start()
            } else {
                self.messageLabel.text = "Доступ до камери заборонено."
                self.messageLabel.isHidden = false
            }
        }
    }
    
    func cameraCaptureService(_ service: CameraCaptureService, didFail error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.messageLabel.text = error.localizedDescription
            self?.messageLabel.isHidden = false
        }
    }
}

private extension DocumentPhotoCheckStreamViewController {
    enum Constants {
        static let backgroundColor = UIColor(red: 0.89, green: 0.95, blue: 0.98, alpha: 1.0)
        static let buttonWidthMultiplier: CGFloat = 0.8
        static let photoErrorMessages: [String: String] = [
            "overexposed_or_too_bright": "Занадто яскраво.",
            "strong_shadows_on_face": "Тіні на обличчі.",
            "image_blurry_or_out_of_focus": "Фото розмите.",
            "no_face_detected": "Обличчя не видно.",
            "more_than_one_person_in_photo": "У кадрі має бути одна людина.",
            "head_is_tilted": "Тримайте голову рівно.",
            "face_not_looking_straight_at_camera": "Дивіться в камеру.",
            "face_too_small_in_frame": "Підійдіть ближче.",
            "face_too_close_or_cropped": "Відійдіть далі.",
            "face_not_centered": "Вирівняйте обличчя по центру.",
            "hair_covers_part_of_face": "Відкрийте обличчя.",
            "background_not_uniform": "Фон має бути рівним.",
            "extraneous_people_in_background": "Приберіть людей з фону."
        ]
    }
}

private struct FinalValidationResponse: Decodable {
    struct ValidationError: Decodable {
        let code: String
        let message: String
    }
    let status: String
    let errors: [ValidationError]
}

private final class PaddingLabel: UILabel {
    var insets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right,
                      height: size.height + insets.top + insets.bottom)
    }
}

private final class PhotoCheckFrameView: UIView {
    enum State {
        case idle
        case success
    }
    
    var frameRect: CGRect?
    var state: State = .idle {
        didSet { setNeedsDisplay() }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }
    
    override func draw(_ rect: CGRect) {
        let path = UIBezierPath()
        path.lineWidth = 4
        guard let target = frameRect ?? defaultFrame(in: rect) else { return }
        
        let corner: CGFloat = 24
        let color: UIColor = state == .success ? UIColor(red: 0.21, green: 0.73, blue: 0.36, alpha: 1) : UIColor(white: 0.9, alpha: 1)
        color.setStroke()
        
        func addCorner(_ x: CGFloat, _ y: CGFloat, _ dx: CGFloat, _ dy: CGFloat) {
            let start = CGPoint(x: x, y: y)
            path.move(to: start)
            path.addLine(to: CGPoint(x: x + dx * corner, y: y))
            path.move(to: start)
            path.addLine(to: CGPoint(x: x, y: y + dy * corner))
        }
        
        addCorner(target.minX, target.minY, 1, 1)
        addCorner(target.maxX, target.minY, -1, 1)
        addCorner(target.minX, target.maxY, 1, -1)
        addCorner(target.maxX, target.maxY, -1, -1)
        
        path.stroke()
    }
    
    private func defaultFrame(in rect: CGRect) -> CGRect? {
        var target = rect.insetBy(dx: 16, dy: 16)
        let targetAspect: CGFloat = 2.0 / 3.0
        let currentAspect = target.width / target.height
        if currentAspect > targetAspect {
            let newWidth = target.height * targetAspect
            target.origin.x += (target.width - newWidth) / 2
            target.size.width = newWidth
        } else {
            let newHeight = target.width / targetAspect
            target.origin.y += (target.height - newHeight) / 2
            target.size.height = newHeight
        }
        let scale: CGFloat = 1.0 / 1.5
        let newWidth = target.width * scale
        let newHeight = target.height * scale
        target.origin.x += (target.width - newWidth) / 2
        target.origin.y += (target.height - newHeight) / 2
        target.size = CGSize(width: newWidth, height: newHeight)
        return target
    }
}
