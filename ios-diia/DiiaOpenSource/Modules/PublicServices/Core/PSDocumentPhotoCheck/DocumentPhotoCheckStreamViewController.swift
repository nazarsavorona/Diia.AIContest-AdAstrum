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
    private let overlayView = PhotoCheckFrameView()
    private let messageLabel: UILabel = {
        let label = PaddingLabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = FontBook.usualFont
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
    
    private var isFrameValid: Bool = false {
        didSet {
            updateButtonState()
            overlayView.state = isFrameValid ? .success : .idle
        }
    }
    
    private var isValidating = false
    private var lastValidationAt: CFTimeInterval = 0
    private let validationThrottle: CFTimeInterval = 0.6
    
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
        overlayView.frame = previewContainer.bounds.insetBy(dx: 12, dy: 12)
    }
    
    private func setupLayout() {
        topView.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        continueButton.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(topView)
        view.addSubview(previewContainer)
        view.addSubview(continueButton)
        
        previewContainer.addSubview(messageLabel)
        previewContainer.addSubview(overlayView)
        
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
            
            previewContainer.topAnchor.constraint(equalTo: topView.bottomAnchor, constant: 8),
            previewContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewContainer.heightAnchor.constraint(equalTo: previewContainer.widthAnchor, multiplier: 4.0/3.0),
            
            messageLabel.centerXAnchor.constraint(equalTo: previewContainer.centerXAnchor),
            messageLabel.topAnchor.constraint(equalTo: previewContainer.topAnchor, constant: 12),
            
            overlayView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),
            
            continueButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            continueButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            continueButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            continueButton.heightAnchor.constraint(equalToConstant: 56)
        ])
    }
    
    private func attachPreviewLayer() {
        guard let layer = cameraService.previewLayer else { return }
        previewLayer?.removeFromSuperlayer()
        layer.videoGravity = .resizeAspectFill
        if let connection = layer.connection {
            connection.videoOrientation = .portrait
            connection.automaticallyAdjustsVideoMirroring = true
            connection.isVideoMirrored = true
        }
        layer.frame = previewContainer.bounds
        previewContainer.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
    }
    
    private func updateButtonState() {
        if isFrameValid {
            continueButton.isEnabled = true
            continueButton.backgroundColor = .black
            continueButton.setTitleColor(.white, for: .normal)
        } else {
            continueButton.isEnabled = false
            continueButton.backgroundColor = UIColor.black.withAlphaComponent(0.2)
            continueButton.setTitleColor(UIColor.white.withAlphaComponent(0.6), for: .disabled)
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
    }
    
    @objc private func continueTapped() {
        // TODO: hook real final validation endpoint and navigation to confirmation screen.
        let alert = UIAlertController(title: "Фото пройшло перевірку", message: "Далі відкриваємо фінальну сторінку заяви.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Ок", style: .default) { [weak self] _ in
            self?.closeModule(animated: true)
        })
        present(alert, animated: true)
    }
}

extension DocumentPhotoCheckStreamViewController: CameraCaptureServiceDelegate {
    func cameraCaptureService(_ service: CameraCaptureService, didOutput sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation) {
        let now = CACurrentMediaTime()
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
                } else {
                    self.showErrors(detection.errors)
                }
            case .failure(let error):
                self.isFrameValid = false
                self.messageLabel.text = error.localizedDescription
                self.messageLabel.isHidden = false
                self.overlayView.state = .idle
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
        let insetRect = rect.insetBy(dx: 12, dy: 12)
        let corner: CGFloat = 28
        let color: UIColor = state == .success ? UIColor(red: 0.21, green: 0.73, blue: 0.36, alpha: 1) : UIColor(white: 0.9, alpha: 1)
        color.setStroke()
        
        func addCorner(_ x: CGFloat, _ y: CGFloat, _ dx: CGFloat, _ dy: CGFloat) {
            let start = CGPoint(x: x, y: y)
            path.move(to: start)
            path.addLine(to: CGPoint(x: x + dx * corner, y: y))
            path.move(to: start)
            path.addLine(to: CGPoint(x: x, y: y + dy * corner))
        }
        
        addCorner(insetRect.minX, insetRect.minY, 1, 1)
        addCorner(insetRect.maxX, insetRect.minY, -1, 1)
        addCorner(insetRect.minX, insetRect.maxY, 1, -1)
        addCorner(insetRect.maxX, insetRect.maxY, -1, -1)
        
        path.stroke()
    }
}
