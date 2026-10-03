import Foundation
import IOBluetooth
import NeckReminderCore

/// Optional: watches one paired Bluetooth headset (AirPods etc.). When it disconnects after
/// its signal faded away — the wearer walked out of range — that's a hard "away" signal,
/// timed from when the signal started fading. Disconnects with a strong signal right
/// before (case closed, switched to the iPhone, disconnected by hand) are ignored.
///
/// Uses the Bluetooth permission (asked by macOS the first time this is switched on).
/// iPhone and Apple Watch can't be used: they advertise rotating private addresses
/// and expose no stable signal strength to Mac apps.
@MainActor
final class BluetoothProximity: ObservableObject {
    struct Device: Identifiable, Hashable {
        var id: String     // address
        var name: String
        var isAudio: Bool
    }

    @Published private(set) var pairedDevices: [Device] = []
    @Published private(set) var connected = false
    @Published private(set) var rssi: Int?
    @Published private(set) var lastEvent: String?
    /// Set when the headset walked out of range; cleared as soon as there is input again.
    @Published private(set) var walkedAwaySince: Date?

    var address: String? {
        didSet {
            if address != oldValue { readings.removeAll(); connected = false; rssi = nil; walkedAwaySince = nil }
        }
    }

    private var readings: [ProximityAnalyzer.Reading] = []

    func refreshPairedDevices() {
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        pairedDevices = devices.compactMap { d in
            guard let address = d.addressString else { return nil }
            let name = d.name ?? d.nameOrAddress ?? address
            // Major class 0x04 = audio/video.
            let isAudio = d.deviceClassMajor == 0x04 || name.lowercased().contains("airpods") || name.lowercased().contains("beats")
            return Device(id: address, name: name, isAudio: isAudio)
        }
        .sorted { ($0.isAudio ? 0 : 1, $0.name) < ($1.isAudio ? 0 : 1, $1.name) }
    }

    /// Called with every activity sample.
    func poll(now: Date) {
        guard let address, let device = IOBluetoothDevice(addressString: address) else { return }
        let isConnected = device.isConnected()
        if isConnected {
            let raw = Int(device.rawRSSI())
            if raw < 20 && raw > -128 { // 127 means "not available"
                readings.append(.init(date: now, rssi: raw))
                rssi = raw
            }
            readings.removeAll { now.timeIntervalSince($0.date) > 180 }
            if !connected { walkedAwaySince = nil }
        } else if connected {
            if let start = ProximityAnalyzer.walkAwayStart(readings, disconnectedAt: now) {
                walkedAwaySince = start
                lastEvent = tr("信号逐渐减弱后断开：判定为离开", "Faded out, then disconnected: you left")
            } else {
                lastEvent = tr("信号很强时断开：可能是放回耳机盒、切换设备或手动断开，不作为离开依据",
                               "Disconnected with a strong signal (case, other device or by hand): ignored")
            }
            readings.removeAll()
            rssi = nil
        }
        connected = isConnected
    }

    func userIsBack() {
        walkedAwaySince = nil
    }
}
