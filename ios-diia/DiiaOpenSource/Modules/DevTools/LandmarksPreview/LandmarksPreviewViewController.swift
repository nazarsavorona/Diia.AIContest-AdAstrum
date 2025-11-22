import UIKit
import AVFoundation
import DiiaMVPModule
import DiiaUIComponents

final class LandmarksPreviewViewController: UIViewController {
    var presenter: LandmarksPreviewAction!

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let detailLabel = UILabel()
    private let errorLabel = UILabel()
    private let imageContainer = UIView()
    private let imageView = UIImageView()
    private let overlayView = LandmarksOverlayView()
    private var aspectConstraint: NSLayoutConstraint?
    private lazy var chooseSampleButton: UIBarButtonItem = {
        UIBarButtonItem(title: "Choose", style: .plain, target: self, action: #selector(chooseSampleTapped))
    }()
    private let sampleButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Вибрати фікстуру", for: .normal)
        button.titleLabel?.font = FontBook.bigText
        button.contentHorizontalAlignment = .leading
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        presenter.configureView()
    }

    private func configureView() {
        title = "Landmarks demo"
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = chooseSampleButton
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh,
                                                            target: self,
                                                            action: #selector(reloadTapped))

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.backgroundColor = .clear
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.layoutMargins = UIEdgeInsets(top: 24, left: 16, bottom: 24, right: 16)

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        titleLabel.font = FontBook.grandTextFont
        titleLabel.numberOfLines = 0
        subtitleLabel.font = FontBook.bigText
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0
        detailLabel.font = FontBook.usualFont
        detailLabel.numberOfLines = 0
        detailLabel.textColor = .secondaryLabel
        errorLabel.font = FontBook.bigText
        errorLabel.textColor = .systemRed
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true

        imageContainer.translatesAutoresizingMaskIntoConstraints = false
        imageContainer.backgroundColor = UIColor.black
        imageContainer.layer.cornerRadius = 16
        imageContainer.clipsToBounds = true
        aspectConstraint = imageContainer.heightAnchor.constraint(equalToConstant: 320)
        aspectConstraint?.isActive = true

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        overlayView.translatesAutoresizingMaskIntoConstraints = false

        imageContainer.addSubview(imageView)
        imageContainer.addSubview(overlayView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor),

            overlayView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor)
        ])

        contentStack.addArrangedSubview(titleLabel)
        contentStack.addArrangedSubview(subtitleLabel)
        contentStack.addArrangedSubview(imageContainer)
        contentStack.addArrangedSubview(detailLabel)
        contentStack.addArrangedSubview(errorLabel)
        sampleButton.addTarget(self, action: #selector(chooseSampleTapped), for: .touchUpInside)
        contentStack.insertArrangedSubview(sampleButton, at: 0)
    }

    @objc private func reloadTapped() {
        presenter.reloadSample()
    }

    @objc private func chooseSampleTapped() {
        presenter.showSamplePicker()
    }

    private func updateAspectRatio(for imageSize: CGSize) {
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        aspectConstraint?.isActive = false
        let ratio = imageSize.height / imageSize.width
        let newConstraint = imageContainer.heightAnchor.constraint(equalTo: imageContainer.widthAnchor, multiplier: ratio)
        newConstraint.priority = .defaultHigh
        newConstraint.isActive = true
        aspectConstraint = newConstraint
        view.setNeedsLayout()
    }
}

extension LandmarksPreviewViewController: LandmarksPreviewView {
    func display(viewModel: LandmarksPreviewViewModel) {
        errorLabel.isHidden = true
        imageContainer.isHidden = false
        titleLabel.text = viewModel.title
        subtitleLabel.text = viewModel.subtitle
        detailLabel.text = viewModel.details
        detailLabel.isHidden = viewModel.details?.isEmpty ?? true
        imageView.image = viewModel.image
        overlayView.configure(landmarks: viewModel.landmarks,
                              imageSize: viewModel.originalImageSize,
                              connections: viewModel.connections)
        updateAspectRatio(for: viewModel.image.size)
        sampleButton.setTitle("Фікстура: \(viewModel.title)", for: .normal)
    }

    func displayError(message: String) {
        imageView.image = nil
        imageContainer.isHidden = true
        errorLabel.isHidden = false
        errorLabel.text = message
        titleLabel.text = nil
        subtitleLabel.text = nil
        detailLabel.text = nil
        sampleButton.setTitle("Вибрати фікстуру", for: .normal)
    }

    func showSamplePicker(options: [LandmarkSampleDescriptor], selectedId: String?, onSelect: @escaping (LandmarkSampleDescriptor) -> Void) {
        guard !options.isEmpty else { return }
        let alert = UIAlertController(title: "Select fixture", message: nil, preferredStyle: .actionSheet)
        for option in options {
            let marker = option.id == selectedId ? "✓ " : ""
            let actionTitle = "\(marker)\(option.title)"
            alert.addAction(UIAlertAction(title: actionTitle, style: .default, handler: { _ in
                onSelect(option)
            }))
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = chooseSampleButton
            popover.sourceView = sampleButton
            popover.sourceRect = sampleButton.bounds
        }
        present(alert, animated: true)
    }

    func startLiveMode(sourceType: LandmarksPreviewMode) {
        imageContainer.isHidden = false
        errorLabel.isHidden = false
        switch sourceType {
        case .mediapipe:
            errorLabel.text = "MediaPipe live mode requires linking the MediaPipeTasksVision framework per the official guide."
        case .api:
            errorLabel.text = "API live mode placeholder. Connect your API client to stream frames."
        case .fixtures:
            errorLabel.text = nil
        }
    }

    func stopLiveMode() {
        errorLabel.isHidden = true
    }
}

final class LandmarksOverlayView: UIView {
    private var landmarks: [LandmarkPoint] = []
    private var connections: [(Int, Int)] = []
    private var originalImageSize: CGSize = .zero
    private var faceBoundingBox: CGRect?
    private let dotRadius: CGFloat = 2.5
    private let targetAspectRatio: CGFloat = 2.0 / 3.0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    func configure(landmarks: [LandmarkPoint], imageSize: CGSize, connections: [(Int, Int)], faceBoundingBox: CGRect? = nil) {
        self.landmarks = landmarks
        self.originalImageSize = imageSize
        self.connections = connections
        self.faceBoundingBox = faceBoundingBox
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard originalImageSize.width > 0,
              originalImageSize.height > 0,
              let context = UIGraphicsGetCurrentContext() else { return }

        context.setLineWidth(0)

        let widthRatio = bounds.width / originalImageSize.width
        let heightRatio = bounds.height / originalImageSize.height
        let scale = min(widthRatio, heightRatio)
        let drawWidth = originalImageSize.width * scale
        let drawHeight = originalImageSize.height * scale
        let originX = (bounds.width - drawWidth) / 2.0
        let originY = (bounds.height - drawHeight) / 2.0

        var convertedPoints: [Int: CGPoint] = [:]
        for landmark in landmarks {
            let x = originX + landmark.position.x * scale
            let y = originY + landmark.position.y * scale
            convertedPoints[landmark.index] = CGPoint(x: x, y: y)
        }

        // Draw target aspect frame (matches crop)
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(2.0)
        context.stroke(CGRect(x: originX, y: originY, width: drawWidth, height: drawHeight))

        if let box = faceBoundingBox {
            context.setStrokeColor(UIColor.systemOrange.withAlphaComponent(0.8).cgColor)
            context.setLineWidth(2)
            let rect = CGRect(x: originX + box.origin.x * scale,
                              y: originY + box.origin.y * scale,
                              width: box.width * scale,
                              height: box.height * scale)
            context.stroke(rect)
        }

        if !connections.isEmpty {
            context.setStrokeColor(UIColor.systemGreen.withAlphaComponent(0.85).cgColor)
            context.setLineWidth(0.7)
            context.setLineCap(.round)
            context.beginPath()
            for (start, end) in connections {
                guard let startPoint = convertedPoints[start],
                      let endPoint = convertedPoints[end] else { continue }
                context.move(to: startPoint)
                context.addLine(to: endPoint)
            }
            context.strokePath()
        }

        context.setFillColor(UIColor.systemYellow.cgColor)
        for point in convertedPoints.values {
            let rect = CGRect(x: point.x - dotRadius,
                              y: point.y - dotRadius,
                              width: dotRadius * 2,
                              height: dotRadius * 2)
            context.fillEllipse(in: rect)
        }
    }
}
