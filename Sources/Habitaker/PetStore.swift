import Combine
import ImageIO
import UIKit

@MainActor
final class PetStore: ObservableObject {
    @Published var chosen = UserDefaults.standard.bool(forKey: "petChosen")
    @Published var preview: UIImage?
    @Published var busy = false
    @Published var message = ""
    @Published var custom: UIImage?
    @Published private(set) var previewColumns = 4
    private let imageURL = URL.documentsDirectory.appendingPathComponent("my-pet.png")
    private var cachedSheet: UIImage?
    private var cachedColumns = 0
    private var frames: [Int: UIImage] = [:]
    private let defaultSheet = UIImage(named: "pip-animated")
    private let legacySheet = UIImage(named: "pip-states")
    private var customColumns: Int { UserDefaults.standard.integer(forKey: "customPetColumns") == 4 ? 4 : 2 }

    init() { custom = UIImage(contentsOfFile: imageURL.path) }

    func generate(_ description: String) async {
        guard !busy else { return }
        busy = true
        message = "Creating your pet. This can take a minute or two."
        defer { busy = false }
        do {
            let result = try await Backend.shared.request("pets", method: "POST", body: ["description": description])
            guard let encoded = result["image"] as? String, let data = Data(base64Encoded: encoded) else {
                throw AuthFailure.invalid("The pet image could not be opened. Try again.")
            }
            try importSheet(data: data, columns: result["columns"] as? Int ?? 2)
            message = "Your pet is ready. Use this pet to continue."
        } catch { message = error.localizedDescription }
    }

    func chooseDefault() {
        UserDefaults.standard.set(false, forKey: "useCustomPet")
        UserDefaults.standard.set(true, forKey: "petChosen")
        chosen = true
    }

    func chooseCustom() -> Bool {
        guard let preview, let data = preview.pngData() else { return false }
        do {
            try data.write(to: imageURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            custom = preview
            UserDefaults.standard.set(true, forKey: "useCustomPet")
            UserDefaults.standard.set(previewColumns, forKey: "customPetColumns")
            UserDefaults.standard.set(true, forKey: "petChosen")
            chosen = true
            return true
        } catch {
            message = "Your pet could not be saved. Please try again."
            return false
        }
    }

    func frame(expression: String, speaking: Bool, previewing: Bool = false) -> UIImage? {
        animatedFrame(mood: PetMood.resolve(expression: expression, mode: "Gentle"), mouth: speaking ? 1 : 0, blinking: false, expression: expression, previewing: previewing)
    }

    func importSheet(data: Data, columns: Int = 4) throws {
        guard [2, 4].contains(columns), data.count <= 20_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == "public.png",
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width == height, width >= 512, width <= 4096,
              let image = UIImage(data: data), image.cgImage != nil else {
            throw AuthFailure.invalid("Use a square PNG sprite sheet from 512 to 4096 pixels, with a 4 by 4 grid. Your current pet is unchanged.")
        }
        previewColumns = columns
        preview = image
        message = "Your pet is ready. Check the expressions, then use this pet."
    }

    func animatedFrame(mood: PetMood, mouth: Int, blinking: Bool, expression: String, previewing: Bool = false) -> UIImage? {
        let useCustom = UserDefaults.standard.bool(forKey: "useCustomPet") && custom != nil
        let sheet = previewing && preview != nil ? preview : useCustom ? custom : defaultSheet ?? legacySheet
        let columns = previewing && preview != nil ? previewColumns : useCustom ? customColumns : defaultSheet == nil ? 2 : 4
        guard let cg = sheet?.cgImage else { return UIImage(named: "pip") }
        let index = columns == 4 ? mood.rawValue * 4 + (blinking && mouth == 0 ? 3 : min(2, max(0, mouth))) : mouth > 0 ? 1 : mood == .happy ? 3 : expression == "thinking" ? 2 : 0
        if cachedSheet !== sheet || cachedColumns != columns {
            cachedSheet = sheet
            cachedColumns = columns
            frames.removeAll()
        }
        if let cached = frames[index] { return cached }
        let width = cg.width / columns
        let height = cg.height / columns
        let x = Int(Double(index % columns) * Double(cg.width) / Double(columns))
        let y = Int(Double(index / columns) * Double(cg.height) / Double(columns))
        guard let cropped = cg.cropping(to: CGRect(x: x, y: y, width: width, height: height)) else { return nil }
        let image: UIImage
        if sheet === defaultSheet, cg.width == 1024, cg.height == 1024, index / columns == PetMood.furious.rawValue {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            format.preferredRange = .standard
            image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
                // The next row's ears spill into this atlas row's bottom gutter.
                context.cgContext.clip(to: CGRect(x: 0, y: 0, width: width, height: height - 6))
                UIImage(cgImage: cropped).draw(at: .zero)
            }
        } else {
            image = UIImage(cgImage: cropped)
        }
        frames[index] = image
        return image
    }
}
