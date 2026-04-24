import CoreBluetooth
import Foundation

enum BLEConnectionState: Equatable {
    case idle
    case bluetoothUnavailable(String)
    case unauthorized
    case scanning
    case connecting(String)
    case connected(String)

    var title: String {
        switch self {
        case .idle:
            return "Not Connected"
        case .bluetoothUnavailable(let reason):
            return "Bluetooth Unavailable: \(reason)"
        case .unauthorized:
            return "Bluetooth Permission Needed"
        case .scanning:
            return "Scanning for JingQiBMP..."
        case .connecting(let name):
            return "Connecting to \(name)..."
        case .connected(let name):
            return "Connected to \(name)"
        }
    }
}

final class BLEManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var onStateChange: ((BLEConnectionState) -> Void)?
    var onPayload: ((Data) -> Void)?
    var onLog: ((String) -> Void)?

    private var centralManager: CBCentralManager?
    private var discoveredPeripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?
    private var txCharacteristic: CBCharacteristic?

    private var isScanning = false

    func start() {
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        } else {
            handleCentralState()
        }
    }

    func connectOrScan() {
        start()
        handleCentralState()
    }

    func disconnect() {
        guard let centralManager, let peripheral = discoveredPeripheral else {
            updateState(.idle)
            return
        }

        centralManager.cancelPeripheralConnection(peripheral)
    }

    func sendCommand(_ command: String) {
        guard
            let peripheral = discoveredPeripheral,
            let rxCharacteristic,
            let data = command.data(using: .utf8)
        else {
            onLog?("Tx failed: BLE link is not ready.")
            return
        }

        let writeType: CBCharacteristicWriteType = rxCharacteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: rxCharacteristic, type: writeType)
        onLog?("Tx: \(command)")
    }

    private func handleCentralState() {
        guard let centralManager else { return }

        switch centralManager.state {
        case .poweredOn:
            scanForPeripheral()
        case .unauthorized:
            updateState(.unauthorized)
        case .unsupported:
            updateState(.bluetoothUnavailable("This iPhone does not support BLE."))
        case .poweredOff:
            updateState(.bluetoothUnavailable("Bluetooth is turned off."))
        case .resetting:
            updateState(.bluetoothUnavailable("Bluetooth is resetting."))
        case .unknown:
            updateState(.bluetoothUnavailable("Bluetooth state is unknown."))
        @unknown default:
            updateState(.bluetoothUnavailable("Bluetooth entered an unexpected state."))
        }
    }

    private func scanForPeripheral() {
        guard let centralManager else { return }
        guard centralManager.state == .poweredOn else {
            handleCentralState()
            return
        }

        if isScanning {
            centralManager.stopScan()
        }

        discoveredPeripheral = nil
        rxCharacteristic = nil
        txCharacteristic = nil
        isScanning = true

        updateState(.scanning)
        onLog?("Scanning for BLE peripheral named \(NUSConstants.targetName)...")
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func updateState(_ state: BLEConnectionState) {
        DispatchQueue.main.async { [onStateChange] in
            onStateChange?(state)
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        handleCentralState()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let advertisedName = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unknown"

        guard advertisedName.localizedCaseInsensitiveContains(NUSConstants.targetName) else {
            return
        }

        isScanning = false
        central.stopScan()

        discoveredPeripheral = peripheral
        peripheral.delegate = self
        updateState(.connecting(advertisedName))
        onLog?("Found \(advertisedName) (RSSI \(RSSI)). Connecting...")
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let name = peripheral.name ?? NUSConstants.targetName
        updateState(.connected(name))
        onLog?("Connected to \(name). Discovering services...")
        peripheral.discoverServices([NUSConstants.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let message = error?.localizedDescription ?? "Unknown error"
        onLog?("Failed to connect: \(message)")
        updateState(.idle)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let message = error?.localizedDescription ?? "Connection closed."
        onLog?("Disconnected: \(message)")
        discoveredPeripheral = nil
        rxCharacteristic = nil
        txCharacteristic = nil
        updateState(.idle)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            onLog?("Service discovery failed: \(error.localizedDescription)")
            return
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == NUSConstants.serviceUUID }) else {
            onLog?("NUS service was not found on the peripheral.")
            return
        }

        peripheral.discoverCharacteristics([NUSConstants.rxCharacteristicUUID, NUSConstants.txCharacteristicUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            onLog?("Characteristic discovery failed: \(error.localizedDescription)")
            return
        }

        guard let characteristics = service.characteristics else {
            onLog?("No characteristics were returned for the NUS service.")
            return
        }

        for characteristic in characteristics {
            switch characteristic.uuid {
            case NUSConstants.rxCharacteristicUUID:
                rxCharacteristic = characteristic
            case NUSConstants.txCharacteristicUUID:
                txCharacteristic = characteristic
            default:
                break
            }
        }

        guard let txCharacteristic else {
            onLog?("NUS TX characteristic was not found.")
            return
        }

        peripheral.setNotifyValue(true, for: txCharacteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            onLog?("Enabling notifications failed: \(error.localizedDescription)")
            return
        }

        guard characteristic.uuid == NUSConstants.txCharacteristicUUID else { return }
        onLog?("BLE link is ready. You can start streaming pressure data.")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            onLog?("Receive error: \(error.localizedDescription)")
            return
        }

        guard characteristic.uuid == NUSConstants.txCharacteristicUUID, let data = characteristic.value else {
            return
        }

        DispatchQueue.main.async { [onPayload] in
            onPayload?(data)
        }
    }
}
