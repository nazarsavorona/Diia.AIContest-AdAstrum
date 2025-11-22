import UIKit
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

final class DocumentPhotoOnboardingViewController: UIViewController, BaseView {
    private let topView = TopNavigationView()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let contextMenuProvider: ContextMenuProviderProtocol
    
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
        view.addBackgroundImage(R.image.light_background.image)
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
        topView.setupOnContext { [weak self] in
            guard let self else { return }
            self.contextMenuProvider.openContextMenu(in: self)
        }
    }
    
    func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        
        scrollView.alwaysBounceVertical = true
        contentStack.axis = .vertical
        contentStack.spacing = Constants.verticalSpacing
        
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topView.bottomAnchor, constant: Constants.topSpacing),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: Constants.topSpacing),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: Constants.horizontalPadding),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -Constants.horizontalPadding),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -Constants.bottomSpacing),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -Constants.horizontalPadding * 2)
        ])
    }
    
    func buildContent() {
        let titleLabel = UILabel()
        titleLabel.font = FontBook.grandTextFont
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0
        titleLabel.text = Constants.title
        
        let descriptionCard = makeCardView(text: Constants.description)
        
        let requirementsTitle = UILabel()
        requirementsTitle.font = FontBook.bigText
        requirementsTitle.textColor = .label
        requirementsTitle.numberOfLines = 0
        requirementsTitle.text = Constants.requirementsTitle
        
        let requirementsCard = makeRequirementsCard()
        let cameraButton = makeCameraButton()
        let galleryButton = makeGalleryButton()
        
        contentStack.addArrangedSubview(titleLabel)
        contentStack.addArrangedSubview(descriptionCard)
        contentStack.addArrangedSubview(requirementsTitle)
        contentStack.addArrangedSubview(requirementsCard)
        contentStack.setCustomSpacing(Constants.sectionSpacing, after: requirementsCard)
        contentStack.addArrangedSubview(cameraButton)
        contentStack.addArrangedSubview(galleryButton)
    }
    
    func makeCardView(text: String) -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor.white.withAlphaComponent(Constants.cardAlpha)
        container.layer.cornerRadius = Constants.cardCornerRadius
        container.layer.masksToBounds = true
        
        let label = UILabel()
        label.font = FontBook.usualFont
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
        
        Constants.requirements.forEach { text in
            let label = UILabel()
            label.font = FontBook.usualFont
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
        button.titleLabel?.font = FontBook.bigText
        button.layer.cornerRadius = Constants.buttonCornerRadius
        button.heightAnchor.constraint(equalToConstant: Constants.buttonHeight).isActive = true
        button.addTarget(self, action: #selector(openCameraTapped), for: .touchUpInside)
        return button
    }
    
    func makeGalleryButton() -> UIButton {
        let button = UIButton(type: .system)
        let attributedTitle = NSAttributedString(
            string: Constants.openGalleryTitle,
            attributes: [
                .font: FontBook.usualFont,
                .foregroundColor: UIColor.label,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
        )
        button.setAttributedTitle(attributedTitle, for: .normal)
        button.contentHorizontalAlignment = .center
        button.addTarget(self, action: #selector(openGalleryTapped), for: .touchUpInside)
        return button
    }
    
    @objc func openCameraTapped() {
        AppRouter.instance.open(module: LiveCameraModule(), needPincode: false)
    }
    
    @objc func openGalleryTapped() {
        let alert = UIAlertController(title: nil,
                                      message: Constants.galleryStubMessage,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: R.Strings.general_confirm.localized(), style: .default))
        present(alert, animated: true)
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
        static let galleryStubMessage = "Завантаження з галереї буде доступне згодом."
        static let horizontalPadding: CGFloat = 16
        static let verticalSpacing: CGFloat = 16
        static let sectionSpacing: CGFloat = 20
        static let topSpacing: CGFloat = 12
        static let bottomSpacing: CGFloat = 24
        static let cardPadding: CGFloat = 16
        static let cardAlpha: CGFloat = 0.92
        static let cardCornerRadius: CGFloat = 18
        static let bulletSpacing: CGFloat = 8
        static let buttonHeight: CGFloat = 52
        static let buttonCornerRadius: CGFloat = 18
    }
}
