import Foundation
import CoreFoundation

class IPC {
    static let portName: String = {
        return "com.gemini.mdview.port.\(getuid())"
    }()
    
    // MARK: - Client
    
    static func sendToRunningInstance(filePaths: [String]) -> Bool {
        guard let remotePort = CFMessagePortCreateRemote(nil, portName as CFString) else {
            return false
        }
        
        guard let data = try? JSONEncoder().encode(filePaths) else {
            return false
        }
        
        let cfData = data as CFData
        var responseData: Unmanaged<CFData>?
        
        let status = CFMessagePortSendRequest(
            remotePort,
            0, // MessageID (not used)
            cfData,
            3.0, // Timeout
            1.0, // Reply timeout
            nil, // RunLoop mode
            &responseData
        )
        
        if let response = responseData?.takeRetainedValue() {
             // We could check response if we wanted to
             _ = response
        }

        return status == kCFMessagePortSuccess
    }
    
    // MARK: - Server
    
    private static var onMessage: (([String]) -> Void)?
    
    static func startServer(onMessage: @escaping ([String]) -> Void) {
        self.onMessage = onMessage
        
        var context = CFMessagePortContext(
            version: 0,
            info: nil,
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        
        // Ensure any previous port with the same name is invalidated if possible
        // (though local ports usually die with the process).
        
        let localPort = CFMessagePortCreateLocal(
            nil,
            portName as CFString,
            callback,
            &context,
            nil
        )
        
        guard let port = localPort else {
            // If we fail to create the port, it might already exist or be restricted.
            // On macOS, CFMessagePortCreateLocal can fail if the name is taken.
            fputs("WARN: Failed to create local IPC port '\(portName)'. Single instance mode may not work.\n", stderr)
            return
        }
        
        guard let source = CFMessagePortCreateRunLoopSource(nil, port, 0) else {
            fputs("WARN: Failed to create RunLoop source for IPC port.\n", stderr)
            return
        }
        
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }
    
    private static let callback: CFMessagePortCallBack = { (local, msgid, data, info) -> Unmanaged<CFData>? in
        guard let data = data else { return nil }
        let nsData = data as Data
        
        if let paths = try? JSONDecoder().decode([String].self, from: nsData) {
            DispatchQueue.main.async {
                IPC.onMessage?(paths)
            }
        }
        
        return nil
    }
}
