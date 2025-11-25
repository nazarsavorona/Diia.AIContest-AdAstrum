import UIKit
import CoreImage
import DiiaMVPModule
import DiiaCommonTypes
import DiiaUIComponents

final class DocumentPhotoOnboardingModule: BaseModule {
    private let view: DocumentPhotoOnboardingViewController
    
    init(contextMenuProvider: ContextMenuProviderProtocol) {
        view = DocumentPhotoOnboardingViewController(contextMenuProvider: contextMenuProvider)
    }
    
    func viewController() -> UIViewController {
        return view
    }
}

final class DocumentPhotoOnboardingViewController: UIViewController, BaseView, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let topView = TopNavigationView()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let bottomStack = UIStackView()
    private let pageContainer = UIStackView()
    private let contextMenuProvider: ContextMenuProviderProtocol
    private let ciContext = CIContext()
    private let encryptor = ImagePayloadEncryptor()
    private let frameScale: CGFloat = 1.0 / 1.5
    private let finalValidationURL = URL(string: "https://d28w3hxcjjqa9z.cloudfront.net/api/v1/validate/photo")!
    
    init(contextMenuProvider: ContextMenuProviderProtocol) {
        self.contextMenuProvider = contextMenuProvider
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
    }
}

private extension DocumentPhotoOnboardingViewController {
    func setupView() {
        view.backgroundColor = Constants.backgroundColor
        setupNavigation()
        setupScrollView()
        buildContent()
    }
    
    func setupNavigation() {
        topView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topView)
        
        NSLayoutConstraint.activate([
            topView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        topView.setupTitle(title: .empty)
        topView.setupOnClose { [weak self] in
            self?.closeModule(animated: true)
        }
        topView.setupOnContext(callback: nil)
    }
    
    func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        pageContainer.translatesAutoresizingMaskIntoConstraints = false
        
        scrollView.alwaysBounceVertical = true
        contentStack.axis = .vertical
        contentStack.spacing = Constants.verticalSpacing
        contentStack.alignment = .fill
        
        bottomStack.axis = .vertical
        bottomStack.alignment = .center
        bottomStack.spacing = Constants.bottomStackButtonsSpacing
        
        pageContainer.axis = .vertical
        pageContainer.spacing = Constants.bottomSpacing
        
        view.addSubview(scrollView)
        view.addSubview(bottomStack)
        scrollView.addSubview(pageContainer)
        pageContainer.addArrangedSubview(contentStack)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomStack.topAnchor, constant: -Constants.bottomAreaSpacing),
            
            pageContainer.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: Constants.topSpacing),
            pageContainer.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: Constants.horizontalPadding),
            pageContainer.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -Constants.horizontalPadding),
            pageContainer.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -Constants.bottomSpacing),
            pageContainer.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -Constants.horizontalPadding * 2),
            
            bottomStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: Constants.horizontalPadding),
            bottomStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -Constants.horizontalPadding),
            bottomStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bottomStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Constants.bottomStackBottomPadding)
        ])
    }
    
    func buildContent() {
        let titleLabel = UILabel()
        titleLabel.font = Constants.titleFont
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0
        titleLabel.text = Constants.title
        titleLabel.accessibilityIdentifier = "document_photo_title"
        
        let descriptionCard = makeCardView(text: Constants.description)
        
        let requirementsCard = makeRequirementsCard()
        let cameraButton = makeCameraButton()
        let galleryButton = makeGalleryButton()
        
        let views: [UIView] = [
            titleLabel,
            descriptionCard,
            requirementsCard
        ]
        
        views.enumerated().forEach { index, view in
            contentStack.addArrangedSubview(view)
            if view === requirementsCard {
                contentStack.setCustomSpacing(Constants.sectionSpacing, after: view)
            } else if view === descriptionCard {
                contentStack.setCustomSpacing(Constants.cardSpacing, after: view)
            }
            if view === titleLabel {
                contentStack.setCustomSpacing(Constants.titleBottomSpacing, after: view)
            }
        }
        
        bottomStack.addArrangedSubview(cameraButton)
        bottomStack.addArrangedSubview(galleryButton)
    }
    
    func makeCardView(text: String) -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor.white.withAlphaComponent(Constants.cardAlpha)
        container.layer.cornerRadius = Constants.cardCornerRadius
        container.layer.masksToBounds = true
        
        let label = UILabel()
        label.font = Constants.bodyFont
        label.textColor = .label
        label.numberOfLines = 0
        label.text = text
        label.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: Constants.cardPadding),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Constants.cardPadding),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Constants.cardPadding),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Constants.cardPadding)
        ])
        
        return container
    }
    
    func makeRequirementsCard() -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor.white.withAlphaComponent(Constants.cardAlpha)
        container.layer.cornerRadius = Constants.cardCornerRadius
        container.layer.masksToBounds = true
        
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Constants.bulletSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.font = Constants.requirementsTitleFont
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0
        titleLabel.text = Constants.requirementsTitle
        stack.addArrangedSubview(titleLabel)
        stack.setCustomSpacing(Constants.requirementsTitleSpacing, after: titleLabel)
        
        Constants.requirements.forEach { text in
            let label = UILabel()
            label.font = Constants.bodyFont
            label.textColor = .label
            label.numberOfLines = 0
            label.text = "• \(text)"
            stack.addArrangedSubview(label)
        }
        
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: Constants.cardPadding),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Constants.cardPadding),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Constants.cardPadding),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Constants.cardPadding)
        ])
        
        return container
    }
    
    func makeCameraButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(Constants.openCameraTitle, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = .black
        button.titleLabel?.font = Constants.buttonFont
        button.layer.cornerRadius = Constants.buttonCornerRadius
        button.heightAnchor.constraint(equalToConstant: Constants.buttonHeight).isActive = true
        button.widthAnchor.constraint(equalToConstant: UIScreen.main.bounds.width * Constants.buttonWidthMultiplier).isActive = true
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        button.addTarget(self, action: #selector(openCameraTapped), for: .touchUpInside)
        return button
    }
    
    func makeGalleryButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(Constants.openGalleryTitle, for: .normal)
        button.setTitleColor(.label, for: .normal)
        button.titleLabel?.font = Constants.bodyFont
        button.contentHorizontalAlignment = .center
        button.tintColor = .label
        button.addTarget(self, action: #selector(openGalleryTapped), for: .touchUpInside)
        return button
    }
    
    @objc func openCameraTapped() {
        AppRouter.instance.open(module: DocumentPhotoCheckStreamModule(), needPincode: false)
    }
    
    @objc func openGalleryTapped() {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .photoLibrary
        picker.modalPresentationStyle = .fullScreen
        present(picker, animated: true)
    }
}

// MARK: - UIImagePickerControllerDelegate
extension DocumentPhotoOnboardingViewController {
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage else { return }
        validateAndNavigate(image: image)
    }
    
    private func validateAndNavigate(image: UIImage) {
        showProgress()
        guard let payload = encodeForValidation(image: image) else {
            hideProgress()
            showSimpleAlert(message: "Не вдалося обробити фото. Спробуйте інше.")
            return
        }
        let encryptedPayload: String
        do {
            encryptedPayload = try encryptor.encrypt(base64Payload: payload.base64)
        } catch {
            hideProgress()
            showSimpleAlert(message: "Не вдалося зашифрувати фото.")
            return
        }
        var request = URLRequest(url: finalValidationURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "encrypted_image": encryptedPayload,
            "encryption": ImagePayloadEncryptor.algorithmName,
            "mode": "full"
        ], options: [])
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.hideProgress()
                if let error = error {
                    self?.showSimpleAlert(message: self?.localizedMessage(code: nil, fallback: error.localizedDescription) ?? error.localizedDescription)
                    return
                }
                guard let data,
                      let parsed = try? JSONDecoder().decode(FinalValidationResponse.self, from: data) else {
                    self?.showSimpleAlert(message: "Не вдалося завершити перевірку фото.")
                    return
                }
                if parsed.status.lowercased() == "success" && parsed.errors.isEmpty {
                    let successVC = PhotoSuccessViewController(photoImage: payload.image) { [weak self] in
                        self?.navigationController?.popViewController(animated: true)
                    }
                    self?.navigationController?.pushViewController(successVC, animated: true)
                } else {
                    let msg = parsed.errors.first.flatMap { self?.localizedMessage(code: $0.code, fallback: $0.message) } ?? "Фото не пройшло перевірку."
                    self?.showSimpleAlert(message: msg)
                }
            }
        }.resume()
    }
    
    private func encodeForValidation(image: UIImage) -> (image: UIImage, base64: String)? {
        guard let ciImage = CIImage(image: image) else { return nil }
        var cropped = centerCrop(image: ciImage, targetAspectRatio: 2.0 / 3.0)
        let insetX = (cropped.extent.width * (1 - frameScale)) / 2
        let insetY = (cropped.extent.height * (1 - frameScale)) / 2
        cropped = cropped.cropped(to: cropped.extent.insetBy(dx: insetX, dy: insetY))
        guard let cgImage = ciContext.createCGImage(cropped, from: cropped.extent.integral) else { return nil }
        let uiImage = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.8) else { return nil }
        return (uiImage, jpegData.base64EncodedString())
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
    
    private func showSimpleAlert(message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func localizedMessage(code: String?, fallback: String) -> String {
        if let code, let mapped = Constants.photoErrorMessages[code] {
            return mapped
        }
        let lower = fallback.lowercased()
        if lower.contains("underexposed") { return "Недостатнє освітлення." }
        if lower.contains("overexposed") { return "Занадто яскраво." }
        if lower.contains("blurry") { return "Фото розмите." }
        if lower.contains("shadow") { return "Тіні на обличчі." }
        return fallback
    }
}

private extension DocumentPhotoOnboardingViewController {
    enum Constants {
        static let title = "Перевірка фото на документи"
        static let description = "Сервіс автоматично перевіряє фото на відповідність вимогам і підказує, що потрібно виправити перед поданням."
        static let requirementsTitle = "Вимоги до фото"
        static let requirements = [
            "Вертикальне фото 2:3, хороша якість (PNG/JPEG).",
            "Світлий однорідний фон, без людей і предметів.",
            "Рівне світло, без тіней.",
            "Обличчя в центрі, займає ~60% кадру.",
            "Голова прямо, погляд у камеру.",
            "Без фільтрів, окулярів, головних уборів.",
            "Волосся не закриває обличчя."
        ]
        static let openCameraTitle = "Відкрити камеру"
        static let openGalleryTitle = "Завантажити фото з галереї"
        static let backgroundColor = UIColor(red: 0.89, green: 0.95, blue: 0.98, alpha: 1.0)
        static let horizontalPadding: CGFloat = 16
        static let verticalSpacing: CGFloat = 16
        static let cardSpacing: CGFloat = 12
        static let sectionSpacing: CGFloat = 24
        static let topSpacing: CGFloat = 16
        static let bottomSpacing: CGFloat = 40
        static let bottomStackButtonsSpacing: CGFloat = 20
        // Backward alias for any cached references
        static let bottomStackSpacing: CGFloat = bottomStackButtonsSpacing
        static let bottomAreaSpacing: CGFloat = 16
        static let bottomStackBottomPadding: CGFloat = 20
        static let cardPadding: CGFloat = 18
        static let cardAlpha: CGFloat = 0.92
        static let cardCornerRadius: CGFloat = 18
        static let bulletSpacing: CGFloat = 8
        static let buttonHeight: CGFloat = 52
        static let buttonCornerRadius: CGFloat = 18
        static let titleBottomSpacing: CGFloat = 12
        static let buttonWidthMultiplier: CGFloat = 0.75
        static let requirementsTitleSpacing: CGFloat = 8
        
        static let titleFont: UIFont = FontBook.grandTextFont
        static let bodyFont: UIFont = FontBook.usualFont
        static let buttonFont: UIFont = FontBook.bigText
        static let requirementsTitleFont: UIFont = FontBook.bigText
        
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
