import UIKit
import DiiaMVPModule

protocol LandmarksPreviewAction: BasePresenter {
    func reloadSample()
    func showSamplePicker()
}

protocol LandmarksPreviewView: BaseView {
    func display(viewModel: LandmarksPreviewViewModel)
    func displayError(message: String)
    func showSamplePicker(options: [LandmarkSampleDescriptor], selectedId: String?, onSelect: @escaping (LandmarkSampleDescriptor) -> Void)
}

struct LandmarksPreviewViewModel {
    let sampleId: String
    let title: String
    let subtitle: String
    let details: String?
    let image: UIImage
    let originalImageSize: CGSize
    let landmarks: [LandmarkPoint]
    let connections: [(Int, Int)]
}

struct LandmarkPoint {
    let index: Int
    let position: CGPoint
}

struct LandmarkSampleDescriptor: Equatable {
    let id: String
    let title: String
    let imageExtension: String
    let directory: String?
    let resourceName: String
}

final class LandmarksPreviewPresenter: LandmarksPreviewAction {
    private weak var view: LandmarksPreviewView?
    private let loader: LandmarkSampleLoader
    private var availableSamples: [LandmarkSampleDescriptor] = []
    private var currentSample: LandmarkSampleDescriptor?

    init(view: LandmarksPreviewView, loader: LandmarkSampleLoader) {
        self.view = view
        self.loader = loader
    }

    func configureView() {
        refreshSamples()
        guard let sample = currentSample else {
            view?.displayError(message: "No landmark fixtures found. Add image/txt pairs to Resources/Landmarks and rebuild the app.")
            return
        }
        openSample(sample)
    }

    func reloadSample() {
        if currentSample == nil {
            configureView()
            return
        }
        guard let sample = currentSample else { return }
        openSample(sample)
    }

    func showSamplePicker() {
        refreshSamples()
        guard !availableSamples.isEmpty else {
            view?.displayError(message: "No landmark fixtures found to choose from.")
            return
        }
        view?.showSamplePicker(options: availableSamples,
                               selectedId: currentSample?.id,
                               onSelect: { [weak self] descriptor in
                                   self?.currentSample = descriptor
                                   self?.openSample(descriptor)
                               })
    }

    private func refreshSamples() {
        let samples = loader.availableSamples()
        availableSamples = samples
        guard !samples.isEmpty else {
            currentSample = nil
            return
        }
        if let current = currentSample,
           samples.contains(where: { $0.id == current.id }) {
            return
        }
        currentSample = samples.first
    }

    private func openSample(_ descriptor: LandmarkSampleDescriptor) {
        do {
            let snapshot = try loader.loadSample(descriptor: descriptor)
            let subtitle = makeSubtitle(from: snapshot)
            let details = makeDetails(from: snapshot)
            let viewModel = LandmarksPreviewViewModel(sampleId: descriptor.id,
                                                      title: descriptor.title,
                                                      subtitle: subtitle,
                                                      details: details,
                                                      image: snapshot.image,
                                                      originalImageSize: snapshot.originalImageSize,
                                                      landmarks: snapshot.landmarks,
                                                      connections: mediaPipeFullMeshConnections)
            view?.display(viewModel: viewModel)
        } catch {
            view?.displayError(message: "Unable to load mock landmarks: \(error.localizedDescription)")
        }
    }

    private func makeSubtitle(from snapshot: LandmarkSnapshot) -> String {
        var parts: [String] = []
        if let mode = snapshot.metadata.mode {
            parts.append("Mode: \(mode)")
        }
        if let status = snapshot.metadata.status {
            parts.append("Status: \(status)")
        }
        parts.append("Points: \(snapshot.landmarks.count)")
        return parts.joined(separator: " • ")
    }

    private func makeDetails(from snapshot: LandmarkSnapshot) -> String? {
        var details: [String] = []
        if let imagePath = snapshot.metadata.imagePath {
            details.append("Source: \(imagePath)")
        }
        if let errors = snapshot.metadata.errors, !errors.isEmpty {
            details.append("Errors: \(errors)")
        }
        guard !details.isEmpty else { return nil }
        return details.joined(separator: "\n\n")
    }
}

// MARK: - Asset Loading
final class LandmarkSampleLoader {
    private let bundle: Bundle
    private let imageExtensions = ["jpg", "jpeg", "png"]
    private let assetsFolderName = "Landmarks"

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func availableSamples() -> [LandmarkSampleDescriptor] {
        guard let rootURL = landmarksRootURL(),
              let enumerator = FileManager.default.enumerator(at: rootURL,
                                                              includingPropertiesForKeys: nil,
                                                              options: [.skipsHiddenFiles]) else {
            return []
        }
        var descriptors: [LandmarkSampleDescriptor] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "txt" else { continue }
            let relativePath = fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
            let relativeDirectory = (relativePath as NSString).deletingLastPathComponent
            let directory = relativeDirectory.isEmpty ? nil : relativeDirectory
            let resourceName = fileURL.deletingPathExtension().lastPathComponent
            guard let imageExtension = findImageExtension(for: resourceName, directory: directory) else { continue }
            let descriptorId: String
            if let directory = directory {
                descriptorId = "\(directory)/\(resourceName)"
            } else {
                descriptorId = resourceName
            }
            let title = prettifiedTitle(from: descriptorId)
            descriptors.append(LandmarkSampleDescriptor(id: descriptorId,
                                                        title: title,
                                                        imageExtension: imageExtension,
                                                        directory: directory,
                                                        resourceName: resourceName))
        }
        return descriptors.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func loadSample(descriptor: LandmarkSampleDescriptor) throws -> LandmarkSnapshot {
        let imageResourceName = descriptor.resourceName
        let subdirectory = directoryPath(for: descriptor.directory)
        guard let imageURL = bundle.url(forResource: imageResourceName,
                                        withExtension: descriptor.imageExtension,
                                        subdirectory: subdirectory),
              let image = UIImage(contentsOfFile: imageURL.path) else {
            let displayPath = descriptor.directory.map { "\($0)/\(imageResourceName)" } ?? imageResourceName
            throw LandmarkLoaderError.imageNotFound(resourceName: "\(displayPath).\(descriptor.imageExtension)")
        }

        guard let landmarkURL = bundle.url(forResource: imageResourceName,
                                           withExtension: "txt",
                                           subdirectory: subdirectory) else {
            let displayPath = descriptor.directory.map { "\($0)/\(imageResourceName)" } ?? imageResourceName
            throw LandmarkLoaderError.landmarkFileMissing(resourceName: "\(displayPath).txt")
        }

        let rawContent: String
        do {
            rawContent = try String(contentsOf: landmarkURL, encoding: .utf8)
        } catch {
            throw LandmarkLoaderError.landmarkFileUnreadable(resourceName: "\(imageResourceName).txt")
        }

        let parser = LandmarksFileParser()
        let parsed = parser.parse(rawContent: rawContent)
        guard !parsed.landmarks.isEmpty else {
            throw LandmarkLoaderError.noLandmarksFound
        }

        return LandmarkSnapshot(image: image,
                                fileName: descriptor.title,
                                originalImageSize: image.size,
                                metadata: parsed.metadata,
                                landmarks: parsed.landmarks)
    }

    private func directoryPath(for directory: String?) -> String {
        if let directory = directory {
            return "\(assetsFolderName)/\(directory)"
        }
        return assetsFolderName
    }

    private func findImageExtension(for baseName: String, directory: String?) -> String? {
        let subdirectory = directoryPath(for: directory)
        for ext in imageExtensions {
            if bundle.url(forResource: baseName, withExtension: ext, subdirectory: subdirectory) != nil {
                return ext
            }
        }
        return nil
    }

    private func prettifiedTitle(from identifier: String) -> String {
        return identifier
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "/", with: " / ")
    }

    private func landmarksRootURL() -> URL? {
        return bundle.resourceURL?.appendingPathComponent(assetsFolderName, isDirectory: true)
    }
}

struct LandmarkSnapshot {
    struct Metadata {
        var imagePath: String?
        var mode: String?
        var status: String?
        var errors: String?
    }

    let image: UIImage
    let fileName: String
    let originalImageSize: CGSize
    let metadata: Metadata
    let landmarks: [LandmarkPoint]
}

struct LandmarksFileParserOutput {
    let metadata: LandmarkSnapshot.Metadata
    let landmarks: [LandmarkPoint]
}

struct LandmarksFileParser {
    func parse(rawContent: String) -> LandmarksFileParserOutput {
        var metadata = LandmarkSnapshot.Metadata()
        var points: [LandmarkPoint] = []
        let lines = rawContent.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("#") {
                processMetadataLine(trimmed, metadata: &metadata)
                continue
            }
            if let point = parsePoint(from: trimmed) {
                points.append(point)
            }
        }
        return LandmarksFileParserOutput(metadata: metadata, landmarks: points)
    }

    private func processMetadataLine(_ line: String, metadata: inout LandmarkSnapshot.Metadata) {
        let body = line.dropFirst().trimmingCharacters(in: .whitespaces)
        guard let separatorIndex = body.firstIndex(of: ":") else { return }
        let key = body[..<separatorIndex].trimmingCharacters(in: .whitespaces).lowercased()
        let value = body[body.index(after: separatorIndex)...].trimmingCharacters(in: .whitespaces)
        switch key {
        case "image":
            metadata.imagePath = value
        case "mode":
            metadata.mode = value
        case "status":
            metadata.status = value
        case "errors":
            metadata.errors = value
        default:
            break
        }
    }

    private func parsePoint(from line: String) -> LandmarkPoint? {
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count >= 3,
              let index = Int(parts[0]),
              let x = Double(parts[1]),
              let y = Double(parts[2]) else { return nil }
        return LandmarkPoint(index: index, position: CGPoint(x: x, y: y))
    }
}

enum LandmarkLoaderError: LocalizedError {
    case imageNotFound(resourceName: String)
    case landmarkFileMissing(resourceName: String)
    case landmarkFileUnreadable(resourceName: String)
    case noLandmarksFound

    var errorDescription: String? {
        switch self {
        case .imageNotFound(let resourceName):
            return "Image resource not found: \(resourceName)"
        case .landmarkFileMissing(let resourceName):
            return "Landmark file not found: \(resourceName)"
        case .landmarkFileUnreadable(let resourceName):
            return "Unable to read landmark file: \(resourceName)"
        case .noLandmarksFound:
            return "Landmark file does not contain any points"
        }
    }
}
