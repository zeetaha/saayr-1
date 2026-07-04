import Foundation

/// Static checks for device-level integrity signals used in the anti-cheat proof bundle.
struct DeviceIntegrity {

    // MARK: - Jailbreak Detection

    /// Returns `true` if any known jailbreak indicator is found.
    static func isJailbroken() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        let jbPaths = [
            "/Applications/Cydia.app",
            "/Applications/Sileo.app",
            "/Applications/Zebra.app",
            "/Applications/Installer.app",
            "/Applications/Saily.app",
            "/Applications/Sileo.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/private/var/lib/apt",
            "/private/var/lib/cydia",
            "/private/var/tmp/cydia.log",
            "/usr/libexec/cydia/cydo",
            "/usr/sbin/frida-server",
            "/bin/bash",
            "/bin/sh",
            "/etc/apt"
        ]

        for path in jbPaths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }

        // Sandbox write test — a non-jailbroken device can't write to /
        do {
            try "jailbreak_test".write(
                toFile: "/private/jailbreak_test.txt",
                atomically: true,
                encoding: .utf8
            )
            // If we got here, the write succeeded → jailbroken
            try FileManager.default.removeItem(atPath: "/private/jailbreak_test.txt")
            return true
        } catch {
            // Expected on non-jailbroken devices
        }

        return false
        #endif
    }

    // MARK: - Debugger Detection

    /// Returns `true` if a debugger is attached to the current process.
    static func isDebuggerAttached() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)

        guard result == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
        #endif
    }

    // MARK: - Simulator Detection

    static func isSimulator() -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Mock Location Detection

    /// Returns `true` only if the device explicitly reports software-simulated location.
    /// This is a compile-time stub; the runtime check lives in `FilteredLocationManager`
    /// via `CLLocation.sourceInformation.isSimulatedBySoftware`.
    ///
    /// We keep this here for consistency in the proof bundle, but the actual detection
    /// happens at the individual `CLLocation` level.
    static func isMockLocation(_ isSimulatedByCoreLocation: Bool) -> Bool {
        return isSimulatedByCoreLocation
    }
}
