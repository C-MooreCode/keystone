import Foundation

struct ServiceContainer {
    let designSystem = DesignSystem()
    let testing = TestingUtilities()
    let persistence: PersistenceController
    let events: EventDispatcher
    let vision: any VisionOCRServicing
    let barcode: any BarcodeServicing
    let location: any LocationServicing
    let csvImporter: any CSVImportServicing

    init(
        persistence: PersistenceController,
        eventDispatcher: EventDispatcher,
        vision: any VisionOCRServicing = VisionOCRService(),
        barcode: any BarcodeServicing = BarcodeService(),
        location: any LocationServicing = LocationService(),
        csvImporter: any CSVImportServicing = CSVImportService()
    ) {
        self.persistence = persistence
        self.events = eventDispatcher
        self.vision = vision
        self.barcode = barcode
        self.location = location
        self.csvImporter = csvImporter
    }
}
