import AVFoundation
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
typealias UIViewController = NSViewController
#endif

protocol BarcodeScannerDelegate: AnyObject {
    func barcodeScanner(_ scanner: UIViewController, didScan code: String)
    func barcodeScannerDidCancel(_ scanner: UIViewController)
}

struct BarcodeProduct: Codable, Equatable {
    let code: String
    let name: String
    let unit: String?
}

protocol BarcodeServicing: AnyObject {
    func makeScanner(delegate: BarcodeScannerDelegate) -> UIViewController
    func lookupProduct(for code: String) async -> BarcodeProduct?
    func overrideProduct(_ product: BarcodeProduct) async
}

private actor BarcodeCatalogStore {
    private var catalog: [String: BarcodeProduct]
    private var overrides: [String: BarcodeProduct]
    private let userDefaults: UserDefaults
    private let overridesKey = "barcode_service_overrides"

    init(bundle: Bundle, userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
        if let overridesData = userDefaults.data(forKey: overridesKey),
           let stored = try? JSONDecoder().decode([String: BarcodeProduct].self, from: overridesData) {
            self.overrides = stored
        } else {
            self.overrides = [:]
        }

        if let url = bundle.url(forResource: "ean_catalog", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: BarcodeProduct].self, from: data) {
            self.catalog = decoded
        } else {
            self.catalog = [:]
        }
    }

    func lookup(code: String) -> BarcodeProduct? {
        if let override = overrides[code] {
            return override
        }
        return catalog[code]
    }

    func storeOverride(_ product: BarcodeProduct) {
        overrides[product.code] = product
        if let data = try? JSONEncoder().encode(overrides) {
            userDefaults.set(data, forKey: overridesKey)
        }
    }
}

final class BarcodeService: NSObject, BarcodeServicing {
    private let store: BarcodeCatalogStore

    init(bundle: Bundle = .main, userDefaults: UserDefaults = .standard) {
        self.store = BarcodeCatalogStore(bundle: bundle, userDefaults: userDefaults)
    }

    func makeScanner(delegate: BarcodeScannerDelegate) -> UIViewController {
        BarcodeScannerViewController(delegate: delegate)
    }

    func lookupProduct(for code: String) async -> BarcodeProduct? {
        let normalized = normalize(code: code)
        return await store.lookup(code: normalized)
    }

    func overrideProduct(_ product: BarcodeProduct) async {
        let normalized = normalize(code: product.code)
        let normalizedProduct = BarcodeProduct(code: normalized, name: product.name, unit: product.unit)
        await store.storeOverride(normalizedProduct)
    }

    private func normalize(code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#if canImport(UIKit)
private final class BarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private weak var delegate: BarcodeScannerDelegate?
    private var hasDeliveredResult = false

    init(delegate: BarcodeScannerDelegate) {
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hasDeliveredResult = false
        if !session.isRunning {
            session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            session.stopRunning()
        }
    }

    private func configureSession() {
        view.backgroundColor = .black

        guard let videoDevice = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: videoDevice) else {
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let metadataOutput = AVCaptureMetadataOutput()
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.ean8, .ean13, .upce]
        }

        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasDeliveredResult,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let stringValue = object.stringValue else { return }

        hasDeliveredResult = true
        session.stopRunning()
        delegate?.barcodeScanner(self, didScan: stringValue)
    }

    @objc
    private func cancel() {
        delegate?.barcodeScannerDidCancel(self)
    }
}
#else
private final class BarcodeScannerViewController: UIViewController {
    init(delegate: BarcodeScannerDelegate) {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#endif
