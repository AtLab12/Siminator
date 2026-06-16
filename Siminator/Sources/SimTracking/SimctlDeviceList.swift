import Foundation

struct SimctlDeviceList: Decodable {
    let devices: [String: [SimctlDevice]]

    var bootedDevices: [SimctlDevice] {
        devices.values.flatMap { $0 }.filter { $0.state == "Booted" }
    }
}

struct SimctlDevice: Decodable, Identifiable {
    var id: String { udid }
    let name: String
    let udid: String
    let state: String
}
