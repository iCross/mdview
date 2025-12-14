// FileHandler.swift
// macOS Markdown Viewer - 檔案處理元件

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
            print("讀取檔案錯誤: \(error.localizedDescription)")
            return nil
        }
    }
    
    func fileExists(at path: String) -> Bool {
        return FileManager.default.fileExists(atPath: path)
    }
    
    func isMarkdownFile(at path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }
    
    // MARK: - File Watching
    
    func startWatching(path: String) {
        // 停止之前的監控
        stopWatching()
        
        watchingPath = path
        fileDescriptor = open(path, O_EVTONLY)
        
        guard fileDescriptor != -1 else {
            print("無法開啟檔案進行監控: \(path)")
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
                // 檔案被刪除或重新命名，嘗試重新建立監控
                self.stopWatching()
                
                // 稍後重試（檔案可能正在被編輯器重新寫入）
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
        
        print("開始監控檔案: \(path)")
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
    
    func getFileName(from path: String) -> String {
        return (path as NSString).lastPathComponent
    }
    
    func getFileDirectory(from path: String) -> String {
        return (path as NSString).deletingLastPathComponent
    }
}
