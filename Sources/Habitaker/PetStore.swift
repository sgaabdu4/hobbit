import Combine
import UIKit

@MainActor
final class PetStore: ObservableObject {
    @Published var chosen = UserDefaults.standard.bool(forKey: "petChosen")
    @Published var preview: UIImage?
    @Published var busy = false
    @Published var message = ""
    @Published var custom: UIImage?
    private let imageURL = URL.documentsDirectory.appendingPathComponent("my-pet.png")

    init() { custom = UIImage(contentsOfFile: imageURL.path) }

    func generate(_ description: String) async {
        guard !busy else { return }
        busy = true
        message = "Creating your pet. This can take a minute or two."
        defer { busy = false }
        do {
            let result = try await Backend.shared.request("pets", method: "POST", body: ["description": description])
            guard let encoded = result["image"] as? String, let data = Data(base64Encoded: encoded),
                  let image = UIImage(data: data), image.size.width == image.size.height else {
                throw AuthFailure.invalid("The pet image could not be opened. Try again.")
            }
            preview = image
            message = "Your pet is ready. Use this pet to continue."
        } catch { message = error.localizedDescription }
    }

    func chooseDefault() {
        UserDefaults.standard.set(false, forKey: "useCustomPet")
        UserDefaults.standard.set(true, forKey: "petChosen")
        chosen = true
    }

    func chooseCustom() {
        guard let preview, let data = preview.pngData() else { return }
        do {
            try data.write(to: imageURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            custom = preview
            UserDefaults.standard.set(true, forKey: "useCustomPet")
            UserDefaults.standard.set(true, forKey: "petChosen")
            chosen = true
        } catch { message = "Your pet could not be saved. Please try again." }
    }

    func frame(expression: String, speaking: Bool, previewing: Bool = false) -> UIImage? {
        let sheet = previewing ? preview : UserDefaults.standard.bool(forKey: "useCustomPet") ? custom : UIImage(named: "pip-states")
        guard let cg = sheet?.cgImage else { return UIImage(named: "pip") }
        let index = speaking ? 1 : expression == "happy" ? 3 : expression == "thinking" ? 2 : 0
        let width = cg.width / 2
        let height = cg.height / 2
        guard let cropped = cg.cropping(to: CGRect(x: (index % 2) * width, y: (index / 2) * height, width: width, height: height)) else { return nil }
        return UIImage(cgImage: cropped)
    }
}
