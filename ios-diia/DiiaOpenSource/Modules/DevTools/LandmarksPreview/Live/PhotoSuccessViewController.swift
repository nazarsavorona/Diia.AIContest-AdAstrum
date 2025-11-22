import UIKit
import DiiaUIComponents

final class PhotoSuccessViewController: UIViewController {
    
    private let photoImage: UIImage
    private let onDismiss: () -> Void
    
    // MARK: - UI Components
    private let backgroundGradientView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let checkmarkIconView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.layer.cornerRadius = 20
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let checkmarkImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        // Create checkmark image programmatically
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        imageView.image = UIImage(systemName: "checkmark", withConfiguration: config)
        
        return imageView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Фото завантажено"
        label.font = FontBook.bigText
        label.textAlignment = .center
        label.textColor = .black
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Фото пройшло перевірку — можна використовувати для подання"
        label.font = FontBook.usualFont
        label.textAlignment = .center
        label.textColor = UIColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let photoContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = 16
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.08
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
        view.layer.shadowRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let photoImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        imageView.backgroundColor = .white
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let dismissButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Зрозуміло", for: .normal)
        button.titleLabel?.font = FontBook.bigText
        button.backgroundColor = .black
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 24
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Initialization
    init(photoImage: UIImage, onDismiss: @escaping () -> Void) {
        self.photoImage = photoImage
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNavigationBar()
        photoImageView.image = photoImage
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Ensure gradient is properly laid out
        backgroundGradientView.layer.sublayers?.forEach { layer in
            if layer is CAGradientLayer {
                layer.frame = backgroundGradientView.bounds
            }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
    
    // MARK: - Setup
    private func setupNavigationBar() {
        title = "Фото для перевірки"
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationController?.navigationBar.tintColor = .black
        
        // Back button with app's standard icon
        let backButton = UIBarButtonItem(
            image: R.image.menu_back.image,
            style: .plain,
            target: self,
            action: #selector(backButtonTapped)
        )
        backButton.tintColor = .black
        navigationItem.leftBarButtonItem = backButton
    }
    
    private func setupUI() {
        view.backgroundColor = .white
        
        // Add subviews
        view.addSubview(backgroundGradientView)
        view.addSubview(checkmarkIconView)
        checkmarkIconView.addSubview(checkmarkImageView)
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(photoContainerView)
        photoContainerView.addSubview(photoImageView)
        view.addSubview(dismissButton)
        
        dismissButton.addTarget(self, action: #selector(dismissButtonTapped), for: .touchUpInside)
        
        // Setup gradient background
        backgroundGradientView.setRadialGradient()
        
        // Layout constraints
        NSLayoutConstraint.activate([
            // Background gradient
            backgroundGradientView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundGradientView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundGradientView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundGradientView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Checkmark icon
            checkmarkIconView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            checkmarkIconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            checkmarkIconView.widthAnchor.constraint(equalToConstant: 56),
            checkmarkIconView.heightAnchor.constraint(equalToConstant: 56),
            
            checkmarkImageView.centerXAnchor.constraint(equalTo: checkmarkIconView.centerXAnchor),
            checkmarkImageView.centerYAnchor.constraint(equalTo: checkmarkIconView.centerYAnchor),
            checkmarkImageView.widthAnchor.constraint(equalToConstant: 28),
            checkmarkImageView.heightAnchor.constraint(equalToConstant: 28),
            
            // Title
            titleLabel.topAnchor.constraint(equalTo: checkmarkIconView.bottomAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            
            // Subtitle
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            
            // Photo container (2:3 aspect ratio - width:height)
            photoContainerView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 28),
            photoContainerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            photoContainerView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.56),
            photoContainerView.heightAnchor.constraint(equalTo: photoContainerView.widthAnchor, multiplier: 1.5),
            
            photoImageView.topAnchor.constraint(equalTo: photoContainerView.topAnchor, constant: 10),
            photoImageView.leadingAnchor.constraint(equalTo: photoContainerView.leadingAnchor, constant: 10),
            photoImageView.trailingAnchor.constraint(equalTo: photoContainerView.trailingAnchor, constant: -10),
            photoImageView.bottomAnchor.constraint(equalTo: photoContainerView.bottomAnchor, constant: -10),
            
            // Dismiss button
            dismissButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 48),
            dismissButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -48),
            dismissButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
            dismissButton.heightAnchor.constraint(equalToConstant: 48)
        ])
    }
    
    // MARK: - Actions
    @objc private func dismissButtonTapped() {
        onDismiss()
    }
    
    @objc private func backButtonTapped() {
        navigationController?.popViewController(animated: true)
    }
}

