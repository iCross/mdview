// FileHandler.swift
// macOS Markdown Viewer - File handling component

import Foundation

// MARK: - FileHandlerDelegate

protocol FileHandlerDelegate: AnyObject {
    func fileDidChange(at path: String)
}

// MARK: - FileHandler

class FileHandler {
    
    // MARK: - Properties
    
    weak var delegate: FileHandlerDelegate?
    private var fileDescriptor: Int32 = -1
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var watchingPath: String?
    
    // MARK: - Initialization
    
    deinit {
        stopWatching()
    }
    
    // MARK: - File Reading
    
    func readFile(at path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            return content
        } catch {
            print("Failed to read file: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - File Watching
    
    func startWatching(path: String) {
        // Stop any previous watch
        stopWatching()
        
        watchingPath = path
        fileDescriptor = open(path, O_EVTONLY)
        
        guard fileDescriptor != -1 else {
            print("Unable to open file for watching: \(path)")
            return
        }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )
        
        source.setEventHandler { [weak self] in
            guard let self = self, let path = self.watchingPath else { return }
            
            let flags = source.data
            
            if flags.contains(.delete) || flags.contains(.rename) {
                // File deleted or renamed; try to re-establish the watch.
                self.stopWatching()
                
                // Retry later (some editors rewrite files atomically).
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    if FileManager.default.fileExists(atPath: path) {
                        self?.startWatching(path: path)
                        self?.delegate?.fileDidChange(at: path)
                    }
                }
            } else if flags.contains(.write) {
                self.delegate?.fileDidChange(at: path)
            }
        }
        
        source.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd != -1 {
                close(fd)
            }
            self?.fileDescriptor = -1
        }
        
        dispatchSource = source
        source.resume()

        if CommandLine.arguments.contains("--debug") {
            fputs("Started watching file: \(path)\n", stderr)
        }
    }
    
    func stopWatching() {
        dispatchSource?.cancel()
        dispatchSource = nil
        watchingPath = nil
        
        if fileDescriptor != -1 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }
    
    // MARK: - Path Utilities
    
    func resolveAbsolutePath(_ path: String) -> String {
        if path.hasPrefix("/") {
            return path
        }
        
        if path.hasPrefix("~") {
            return NSString(string: path).expandingTildeInPath
        }
        
        let currentDirectory = FileManager.default.currentDirectoryPath
        return (currentDirectory as NSString).appendingPathComponent(path)
    }
}
