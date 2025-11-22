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
    private let bottomStack = UIStackView()
    private let pageContainer = UIStackView()
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
    }
}
