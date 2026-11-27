import CoreAudio
import Foundation

/// Bluetooth protection of the organisation build (Undertone), defaults key
/// `orgBluetoothProtectionEnabled` (default on).
///
/// When a Bluetooth headset (AirPods, Teams headset …) records, macOS switches it from the
/// high-quality music profile to the hands-free profile: in a Teams meeting the sound drops and
/// the meeting may even lose the headset for a moment. With the protection on, Undertone records
/// from the built-in microphone whenever the device it would use is a Bluetooth device
/// (transport type Bluetooth or Bluetooth LE). This also applies when the user picked the
/// Bluetooth device on the microphone page. Without a usable built-in microphone (Mac mini,
/// closed lid) the Bluetooth device is used as before. The system default input is never changed:
/// Undertone only chooses the device for its own audio unit.
extension AudioDeviceManager {
    static let orgBluetoothProtectionKey = "orgBluetoothProtectionEnabled"

    static var isOrgBluetoothProtectionEnabled: Bool {
        OrgEdition.isEnabled
            && (UserDefaults.standard.object(forKey: orgBluetoothProtectionKey) as? Bool ?? true)
    }

    func isBluetoothDevice(_ deviceID: AudioDeviceID) -> Bool {
        let transport = getUInt32DeviceProperty(deviceID: deviceID, selector: kAudioDevicePropertyTransportType)
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    /// Built-in microphone that can record right now: the internal microphone first, then any
    /// other built-in input (e.g. a wired headset on the headphone jack).
    func builtInRecordingDevice(excluding excludedDeviceID: AudioDeviceID? = nil) -> AudioDeviceID? {
        let usable = availableDevices.map(\.id).filter { deviceID in
            deviceID != excludedDeviceID && isDeviceUsableForRecording(deviceID)
        }
        if let internalMicrophone = usable.first(where: isInternalMicrophone) {
            return internalMicrophone
        }
        return usable.first { deviceID in
            getUInt32DeviceProperty(deviceID: deviceID, selector: kAudioDevicePropertyTransportType)
                == kAudioDeviceTransportTypeBuiltIn
        }
    }

    func orgBluetoothSafeDevice(
        for deviceID: AudioDeviceID?, excluding excludedDeviceID: AudioDeviceID? = nil
    ) -> AudioDeviceID? {
        guard Self.isOrgBluetoothProtectionEnabled,
            let deviceID,
            isBluetoothDevice(deviceID),
            let builtIn = builtInRecordingDevice(excluding: excludedDeviceID)
        else {
            return deviceID
        }
        return builtIn
    }
}
