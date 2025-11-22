import Foundation
import DiiaMVPModule
import DiiaCommonTypes
import UIKit
import DiiaUIComponents
import AVFoundation

struct PublicServiceCategoriesListModuleFactory {
    static func create() -> BaseModule {
        PublicServiceCategoriesListModule(context: .init(
            network: .create(),
            publicServiceRouteManager: .init(routeCreateHandlers: .publicServiceRouteCreateHandlers),
            storage: PublicServicesStorageImpl.init(storage: StoreHelper.instance),
            imageNameProvider: DSImageNameResolver.instance
        ))
    }
}

struct PublicServiceOpenerFactory {
    static func create() -> PublicServiceOpener {
        PublicServiceOpener(apiClient: PublicServicesAPIClient(),
                            routeManager: .init(routeCreateHandlers: .publicServiceRouteCreateHandlers))
    }
}

private extension Dictionary {
    static var publicServiceRouteCreateHandlers: [ServiceTypeCode: PublicServiceRouteCreateHandler] {[
        PublicServiceType.criminalRecordCertificate.rawValue: { items in
            return PSCriminalRecordExtractRoute(contextMenuItems: items)
        },
        PublicServiceType.photoVerification.rawValue: { items in
            return PhotoVerificationRoute(contextMenuItems: items)
        }
    ]}
}

class PublicServicesStorageImpl: PublicServicesStorage {
    private let storage: StoreHelperProtocol

    init(storage: StoreHelperProtocol) {
        self.storage = storage
    }

    func savePublicServicesResponse(response: PublicServiceResponse) {
        storage.save(response, type: PublicServiceResponse.self, forKey: .publicServiceListCache)
    }

    func getPublicServicesResponse() -> PublicServiceResponse? {
        storage.getValue(forKey: .publicServiceListCache)
    }
}

struct PhotoVerificationRoute: RouterProtocol {
    private let contextMenuItems: [ContextMenuItem]
    
    init(contextMenuItems: [ContextMenuItem]) {
        self.contextMenuItems = contextMenuItems
    }
    
    func route(in view: BaseView) {
        view.open(module: PhotoVerificationModule())
    }
}

// MARK: - Photo Verification Module Integration
// Merged here to resolve Xcode project linking issues.

final class PhotoVerificationModule: BaseModule {
    private let view: PhotoVerificationViewController
    private let presenter: PhotoVerificationPresenter
    
    init() {
        view = PhotoVerificationViewController()
        presenter = PhotoVerificationPresenter(view: view)
        view.presenter = presenter
    }

    func viewController() -> UIViewController {
        return view
    }
}

protocol PhotoVerificationAction: BasePresenter {
    func openCamera()
    func uploadFromGallery()
    func validatePhoto(_ image: UIImage)
}

final class PhotoVerificationPresenter: PhotoVerificationAction {
    
    unowned var view: PhotoVerificationView
    private let apiClient: PhotoValidationAPIClient
    
    init(view: PhotoVerificationView) {
        self.view = view
        self.apiClient = PhotoValidationAPIClient()
    }
    
    func viewDidLoad() {
        // Initial setup if needed
    }
    
    func openCamera() {
        // Logic to open camera for photo capture
        let cameraModule = PhotoCameraModule(delegate: self)
        view.open(module: cameraModule)
    }
    
    func uploadFromGallery() {
        // Logic to open photo gallery
        view.openImagePicker()
    }
    
    func validatePhoto(_ image: UIImage) {
        view.showLoading()
        
        // IMPORTANT: Crop image to 2:3 aspect ratio BEFORE sending to server
        // This ensures ONLY 2:3 photos are sent, regardless of source (camera or gallery)
        guard let croppedImage = ImageCropUtility.cropToAspectRatio(image: image, aspectRatio: 2.0/3.0) else {
            view.hideLoading()
            view.showError("Failed to process image")
            return
        }
        
        // Verify aspect ratio
        let aspectRatio = croppedImage.size.width / croppedImage.size.height
        let targetRatio: CGFloat = 2.0 / 3.0
        let tolerance: CGFloat = 0.01
        
        if abs(aspectRatio - targetRatio) > tolerance {
            view.hideLoading()
            view.showError("Image aspect ratio validation failed. Expected 2:3, got \(aspectRatio)")
            return
        }
        
        print("📸 Sending image to server - Size: \(croppedImage.size.width)x\(croppedImage.size.height), Aspect Ratio: \(aspectRatio) (2:3 = \(targetRatio))")
        
        // Compress for livestream (0.65 quality)
        guard let imageData = croppedImage.jpegData(compressionQuality: 0.65) else {
            view.hideLoading()
            view.showError("Failed to compress image")
            return
        }
        
        let base64String = imageData.base64EncodedString()
        
        // Send to server as stream validation (cropped 2:3 image only)
        apiClient.validatePhoto(base64Image: base64String, mode: "stream") { [weak self] result in
            self?.view.hideLoading()
            switch result {
            case .success(let response):
                if response.status == "success" {
                    self?.view.showSuccess("Photo meets all requirements!")
                } else {
                    let errors = response.errors.map { $0.message }.joined(separator: "\n")
                    self?.view.showValidationErrors(errors)
                }
            case .failure(let error):
                self?.view.showError("Validation failed: \(error.localizedDescription)")
            }
        }
    }
}

extension PhotoVerificationPresenter: PhotoCameraDelegate {
    func photoCameraDidCapture(_ image: UIImage) {
        validatePhoto(image)
    }
    
    func photoCameraDidCancel() {
        // Camera was cancelled
    }
}

protocol PhotoVerificationView: BaseView {
    func showLoading()
    func hideLoading()
    func showError(_ message: String)
    func showSuccess(_ message: String)
    func showValidationErrors(_ errors: String)
    func openImagePicker()
}

final class PhotoVerificationViewController: UIViewController {
    
    // MARK: - UI Components
    private let navigationView = TopNavigationView()
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        label.textColor = .black
        label.text = "Перевірка фото на документи"
        label.numberOfLines = 0
        return label
    }()
    
    private let descriptionCardView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = 16
        return view
    }()
    
    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = .black
        label.text = "Сервіс автоматично перевіряє фото на відповідність вимогам і підказує, що потрібно виправити перед поданням."
        label.numberOfLines = 0
        return label
    }()
    
    private let requirementsCardView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = 16
        return view
    }()
    
    private let requirementsTitleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        label.textColor = .black
        label.text = "Вимоги до фото"
        return label
    }()
    
    private let requirementsStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }()
    
    private let openCameraButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Відкрити камеру", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = .black
        button.layer.cornerRadius = 24
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        return button
    }()
    
    private let uploadFromGalleryButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Завантажити фото з галереї", for: .normal)
        button.setTitleColor(.black, for: .normal)
        button.backgroundColor = .clear
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        return button
    }()
    
    // MARK: - Properties
    var presenter: PhotoVerificationPresenter!
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        presenter.viewDidLoad()
    }
    
    // MARK: - Setup
    private func setupUI() {
        // Replaced UIColor(hexString:) with system gray as I couldn't verify the extension existence.
        // Using a close approximation to the light gray background.
        view.backgroundColor = UIColor(red: 243/255, green: 245/255, blue: 247/255, alpha: 1.0)
        
        view.addSubview(navigationView)
        view.addSubview(scrollView)
        view.addSubview(openCameraButton)
        view.addSubview(uploadFromGalleryButton)
        
        scrollView.addSubview(contentView)
        
        contentView.addSubview(titleLabel)
        contentView.addSubview(descriptionCardView)
        descriptionCardView.addSubview(descriptionLabel)
        
        contentView.addSubview(requirementsCardView)
        requirementsCardView.addSubview(requirementsTitleLabel)
        requirementsCardView.addSubview(requirementsStackView)
        
        setupConstraints()
        setupNavigation()
        setupRequirements()
        setupActions()
    }
    
    private func setupConstraints() {
        navigationView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        openCameraButton.translatesAutoresizingMaskIntoConstraints = false
        uploadFromGalleryButton.translatesAutoresizingMaskIntoConstraints = false
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionCardView.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        requirementsCardView.translatesAutoresizingMaskIntoConstraints = false
        requirementsTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        requirementsStackView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            navigationView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            navigationView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigationView.heightAnchor.constraint(equalToConstant: 44),
            
            uploadFromGalleryButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            uploadFromGalleryButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            uploadFromGalleryButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            uploadFromGalleryButton.heightAnchor.constraint(equalToConstant: 44),
            
            openCameraButton.bottomAnchor.constraint(equalTo: uploadFromGalleryButton.topAnchor, constant: -12),
            openCameraButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            openCameraButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            openCameraButton.heightAnchor.constraint(equalToConstant: 48),
            
            scrollView.topAnchor.constraint(equalTo: navigationView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: openCameraButton.topAnchor, constant: -16),
            
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            descriptionCardView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 24),
            descriptionCardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            descriptionCardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            descriptionLabel.topAnchor.constraint(equalTo: descriptionCardView.topAnchor, constant: 16),
            descriptionLabel.leadingAnchor.constraint(equalTo: descriptionCardView.leadingAnchor, constant: 16),
            descriptionLabel.trailingAnchor.constraint(equalTo: descriptionCardView.trailingAnchor, constant: -16),
            descriptionLabel.bottomAnchor.constraint(equalTo: descriptionCardView.bottomAnchor, constant: -16),
            
            requirementsCardView.topAnchor.constraint(equalTo: descriptionCardView.bottomAnchor, constant: 16),
            requirementsCardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            requirementsCardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            requirementsCardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24),
            
            requirementsTitleLabel.topAnchor.constraint(equalTo: requirementsCardView.topAnchor, constant: 16),
            requirementsTitleLabel.leadingAnchor.constraint(equalTo: requirementsCardView.leadingAnchor, constant: 16),
            requirementsTitleLabel.trailingAnchor.constraint(equalTo: requirementsCardView.trailingAnchor, constant: -16),
            
            requirementsStackView.topAnchor.constraint(equalTo: requirementsTitleLabel.bottomAnchor, constant: 16),
            requirementsStackView.leadingAnchor.constraint(equalTo: requirementsCardView.leadingAnchor, constant: 16),
            requirementsStackView.trailingAnchor.constraint(equalTo: requirementsCardView.trailingAnchor, constant: -16),
            requirementsStackView.bottomAnchor.constraint(equalTo: requirementsCardView.bottomAnchor, constant: -16)
        ])
    }
    
    private func setupNavigation() {
        navigationView.setupOnClose { [weak self] in
            self?.closeModule(animated: true)
        }
        navigationView.setupTitle(title: "") // Empty title in nav bar as per design
    }
    
    private func setupRequirements() {
        let requirements = [
            "Вертикальне фото 2:3, хороша якість (PNG/JPEG).",
            "Світлий однорідний фон, без людей і предметів.",
            "Рівне світло, без тіней.",
            "Обличчя в центрі, займає ~60% кадру.",
            "Голова прямо, погляд у камеру.",
            "Без фільтрів, окулярів, головних уборів.",
            "Волосся не закриває обличчя."
        ]
        
        requirements.forEach { text in
            let row = createRequirementRow(text: text)
            requirementsStackView.addArrangedSubview(row)
        }
    }
    
    private func createRequirementRow(text: String) -> UIView {
        let container = UIView()
        
        let dot = UIView()
        dot.backgroundColor = .black
        dot.layer.cornerRadius = 2
        dot.translatesAutoresizingMaskIntoConstraints = false
        
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = .black
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(dot)
        container.addSubview(label)
        
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 4),
            dot.heightAnchor.constraint(equalToConstant: 4),
            dot.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            dot.topAnchor.constraint(equalTo: label.topAnchor, constant: 8),
            
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            label.topAnchor.constraint(equalTo: container.topAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        
        return container
    }
    
    private func setupActions() {
        openCameraButton.addAction(UIAction { [weak self] _ in
            self?.presenter.openCamera()
        }, for: .primaryActionTriggered)
        
        uploadFromGalleryButton.addAction(UIAction { [weak self] _ in
            self?.presenter.uploadFromGallery()
        }, for: .primaryActionTriggered)
    }
}

extension PhotoVerificationViewController: PhotoVerificationView {
    func showLoading() {
        // Show loading indicator
        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.tag = 999
        activityIndicator.center = view.center
        activityIndicator.startAnimating()
        view.addSubview(activityIndicator)
    }
    
    func hideLoading() {
        view.subviews.first(where: { $0.tag == 999 })?.removeFromSuperview()
    }
    
    func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    func showSuccess(_ message: String) {
        let alert = UIAlertController(title: "Success", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    func showValidationErrors(_ errors: String) {
        let alert = UIAlertController(title: "Validation Issues", message: errors, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    func openImagePicker() {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .photoLibrary
        present(picker, animated: true)
    }
}

extension PhotoVerificationViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)
        if let image = info[.originalImage] as? UIImage {
            presenter.validatePhoto(image)
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

// MARK: - Photo Camera Module
protocol PhotoCameraDelegate: AnyObject {
    func photoCameraDidCapture(_ image: UIImage)
    func photoCameraDidCancel()
}

final class PhotoCameraModule: BaseModule {
    private let view: PhotoCameraViewController
    
    init(delegate: PhotoCameraDelegate) {
        view = PhotoCameraViewController(delegate: delegate)
    }
    
    func viewController() -> UIViewController {
        return view
    }
}

final class PhotoCameraViewController: UIViewController {
    private weak var delegate: PhotoCameraDelegate?
    private var captureSession: AVCaptureSession!
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var photoOutput: AVCapturePhotoOutput!
    
    private let overlayView = UIView()
    private let captureButton = UIButton(type: .custom)
    private let captureButtonInner = UIView()
    private let closeButton = UIButton(type: .system)
    private let guideView = UIView()
    private let instructionLabel = UILabel()
    
    init(delegate: PhotoCameraDelegate) {
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupUI()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        updateGuideFrame()
    }
    
    private func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .photo
        
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            showError("Camera not available")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
            
            photoOutput = AVCapturePhotoOutput()
            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
            }
            
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = view.bounds
            view.layer.addSublayer(previewLayer)
            
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.startRunning()
            }
        } catch {
            showError("Failed to setup camera: \(error.localizedDescription)")
        }
    }
    
    private func setupUI() {
        // Guide view for 2:3 aspect ratio
        guideView.layer.borderColor = UIColor.white.cgColor
        guideView.layer.borderWidth = 2
        guideView.layer.cornerRadius = 8
        guideView.backgroundColor = .clear
        view.addSubview(guideView)
        
        // Overlay to darken area outside guide
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        view.addSubview(overlayView)
        
        // Instruction label
        instructionLabel.text = "Position your face within the frame"
        instructionLabel.textColor = .white
        instructionLabel.font = .systemFont(ofSize: 16, weight: .medium)
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 0
        view.addSubview(instructionLabel)
        
        // Capture button with outer ring
        captureButton.backgroundColor = .white
        captureButton.layer.cornerRadius = 40
        captureButton.layer.borderWidth = 4
        captureButton.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
        captureButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        view.addSubview(captureButton)
        
        // Inner circle for capture button (classic camera button style)
        captureButtonInner.backgroundColor = .white
        captureButtonInner.layer.cornerRadius = 30
        captureButtonInner.isUserInteractionEnabled = false
        captureButton.addSubview(captureButtonInner)
        
        // Close button
        closeButton.setTitle("✕", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 30)
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        closeButton.layer.cornerRadius = 20
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButtonInner.translatesAutoresizingMaskIntoConstraints = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        guideView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // Capture button - large and prominent
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            captureButton.widthAnchor.constraint(equalToConstant: 80),
            captureButton.heightAnchor.constraint(equalToConstant: 80),
            
            // Inner circle of capture button
            captureButtonInner.centerXAnchor.constraint(equalTo: captureButton.centerXAnchor),
            captureButtonInner.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            captureButtonInner.widthAnchor.constraint(equalToConstant: 60),
            captureButtonInner.heightAnchor.constraint(equalToConstant: 60),
            
            // Close button
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 40),
            closeButton.heightAnchor.constraint(equalToConstant: 40),
            
            // Instruction label
            instructionLabel.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -30),
            instructionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            instructionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            
            // Overlay
            overlayView.topAnchor.constraint(equalTo: view.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func updateGuideFrame() {
        // Calculate 2:3 aspect ratio guide frame
        let padding: CGFloat = 40
        let availableWidth = view.bounds.width - (padding * 2)
        let guideHeight = availableWidth * 1.5 // 2:3 ratio (width:height)
        
        let frame = CGRect(
            x: padding,
            y: (view.bounds.height - guideHeight) / 2,
            width: availableWidth,
            height: guideHeight
        )
        
        guideView.frame = frame
        
        // Create mask for overlay
        let maskLayer = CAShapeLayer()
        let path = UIBezierPath(rect: view.bounds)
        path.append(UIBezierPath(roundedRect: frame, cornerRadius: 8).reversing())
        maskLayer.path = path.cgPath
        overlayView.layer.mask = maskLayer
    }
    
    @objc private func capturePhoto() {
        // Add visual feedback
        UIView.animate(withDuration: 0.1, animations: {
            self.captureButtonInner.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                self.captureButtonInner.transform = .identity
            }
        }
        
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    @objc private func closeTapped() {
        captureSession.stopRunning()
        delegate?.photoCameraDidCancel()
        dismiss(animated: true)
    }
    
    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.closeTapped()
        })
        present(alert, animated: true)
    }
}

extension PhotoCameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            showError("Failed to capture photo")
            return
        }
        
        captureSession.stopRunning()
        delegate?.photoCameraDidCapture(image)
        dismiss(animated: true)
    }
}

// MARK: - Image Crop Utility
/// Utility to ensure all photos sent to server are exactly 2:3 aspect ratio
/// This crops images by centering and maintaining the correct proportions
struct ImageCropUtility {
    /// Crops an image to the specified aspect ratio (width/height)
    /// - Parameters:
    ///   - image: The source image to crop
    ///   - aspectRatio: Target aspect ratio (e.g., 2.0/3.0 for 2:3)
    /// - Returns: Cropped UIImage with exact aspect ratio, or nil if cropping fails
    static func cropToAspectRatio(image: UIImage, aspectRatio: CGFloat) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        let originalWidth = CGFloat(cgImage.width)
        let originalHeight = CGFloat(cgImage.height)
        let currentRatio = originalWidth / originalHeight
        
        var cropRect: CGRect
        
        if currentRatio > aspectRatio {
            // Image is wider than target ratio, crop width (sides)
            let newWidth = originalHeight * aspectRatio
            let xOffset = (originalWidth - newWidth) / 2.0
            cropRect = CGRect(x: xOffset, y: 0, width: newWidth, height: originalHeight)
        } else {
            // Image is taller than target ratio, crop height (top/bottom)
            let newHeight = originalWidth / aspectRatio
            let yOffset = (originalHeight - newHeight) / 2.0
            cropRect = CGRect(x: 0, y: yOffset, width: originalWidth, height: newHeight)
        }
        
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
}

// MARK: - Photo Validation API Client
struct PhotoValidationResponse: Codable {
    let status: String
    let errors: [PhotoValidationError]
    let metadata: [String: DiiaCommonTypes.AnyCodable]?
}

struct PhotoValidationError: Codable {
    let code: String
    let message: String
}

class PhotoValidationAPIClient {
    private let baseURL = "http://localhost:8000/api/v1" // Change to your server URL
    
    func validatePhoto(base64Image: String, mode: String, completion: @escaping (Result<PhotoValidationResponse, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/validate/photo") else {
            completion(.failure(NSError(domain: "Invalid URL", code: -1)))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "image": base64Image,
            "mode": mode
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let data = data else {
                    completion(.failure(NSError(domain: "No data", code: -1)))
                    return
                }
                
                do {
                    let response = try JSONDecoder().decode(PhotoValidationResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
}
