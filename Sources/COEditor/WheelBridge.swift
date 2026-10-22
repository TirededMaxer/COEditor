import AppKit
import CryptoKit

struct WheelReaderStatus: Decodable {
    var `protocol`:Int
    var pid:Int32
    var state:String
    var devices:Int
    var reports:UInt64
    var clients:Int?
    var updated:Double
    static func description(_ data:Data?,configured:Bool=false,now:Double=Date().timeIntervalSince1970)->String {
        let idle="滚轮读取器待命，游戏启动时自动唤起"
        guard let data,let s=try? JSONDecoder().decode(Self.self,from:data),s.protocol==2,
              now>=s.updated,now-s.updated<3,kill(s.pid,0)==0 else {
            return configured ? idle:"滚轮读取器尚未配置；当前使用原生滚动"
        }
        switch s.state {
        case "ready":return "滚轮读取器就绪 · \(s.clients ?? 0) 个程序 · \(s.devices) 个设备 · \(s.reports) 次物理报告"
        case "permission-required":return "滚轮读取器缺少输入监控授权；当前使用原生滚动"
        case "no-device":return "滚轮读取器已授权，未检测到实体滚轮；当前使用原生滚动"
        case "setup":return "正在设置滚轮读取器，等待系统授权"
        case "idle":return idle
        default:return "滚轮设备打开失败；当前使用原生滚动"
        }
    }
}
struct WheelReader {
    static let directory=Storage.support.appendingPathComponent("Wheel")
    static let installed=directory.appendingPathComponent("COEditor Wheel.app")
    static let record=directory.appendingPathComponent("installed.json")
    static let label="local.coeditor.wheel.protocol2"
    static let socketDirectory=Storage.fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/COEditor")
    static let socketURL=socketDirectory.appendingPathComponent("wheel.sock")
    struct Receipt:Codable {var version:Int;var hash:String}
    static func status()->String {
        let receipt=try? JSONDecoder().decode(Receipt.self,from:Data(contentsOf:record))
        let data=try? Data(contentsOf:directory.appendingPathComponent("status.json"))
        let loaded = receipt?.version==2 && ((try? run("/bin/launchctl",["print","gui/\(getuid())/"+label],allowFailure:true))==0)
        return WheelReaderStatus.description(data,configured:loaded)
    }
    @discardableResult static func run(_ path:String,_ arguments:[String],allowFailure:Bool=false)throws->Int32 {
        let p=Process();p.executableURL=URL(fileURLWithPath:path);p.arguments=arguments
        p.standardOutput=FileHandle.nullDevice;p.standardError=FileHandle.nullDevice
        try p.run();p.waitUntilExit()
        if p.terminationStatus != 0 && !allowFailure {throw TunerError.message("滚轮组件操作失败：\(URL(fileURLWithPath:path).lastPathComponent) (\(p.terminationStatus))")}
        return p.terminationStatus
    }
    static func agentConfiguration(executable:String,socket:String)->[String:Any] {
        ["Label":label,"ProgramArguments":[executable],"RunAtLoad":false,"KeepAlive":false,"ThrottleInterval":1,
         "Sockets":["WheelRequests":["SockType":"dgram","SockPathName":socket,"SockPathMode":0o600]],
         "StandardOutPath":directory.appendingPathComponent("reader.log").path,"StandardErrorPath":directory.appendingPathComponent("reader-error.log").path]
    }
    static func requestPermission()throws {
        var address=sockaddr_un();address.sun_family=sa_family_t(AF_UNIX);address.sun_len=UInt8(MemoryLayout<sockaddr_un>.size)
        let path=Array(socketURL.path.utf8)+[0]
        guard path.count<=MemoryLayout.size(ofValue:address.sun_path) else {throw TunerError.message("用户目录路径过长，无法建立滚轮通信")}
        withUnsafeMutableBytes(of:&address.sun_path){buffer in buffer.initializeMemory(as:UInt8.self,repeating:0);buffer.copyBytes(from:path)}
        let fd=socket(AF_UNIX,SOCK_DGRAM,0);guard fd>=0 else {throw TunerError.message("无法打开滚轮通信")};defer{close(fd)}
        // Four fixed-width little-endian words = protocol-2 C request (32 bytes).
        let words:[UInt64]=[0x4358575245513032,UInt64(3)<<32|2,0,0]
        let sent=words.withUnsafeBytes{bytes in withUnsafePointer(to:&address){pointer in
            pointer.withMemoryRebound(to:sockaddr.self,capacity:1){sendto(fd,bytes.baseAddress,bytes.count,0,$0,socklen_t(MemoryLayout<sockaddr_un>.size))}
        }}
        guard sent==32 else {throw TunerError.message("无法唤起滚轮读取器，请重新检查环境")}
    }
    // Retain a validated protocol-2 reader across editor/Sevoflurane updates.
    // Protocol 1 is upgraded once because it cannot exit with its last game.
    static func install(requestAccess:Bool)throws {
        let fm=FileManager.default
        for folder in [directory,socketDirectory] {
            try fm.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            let attrs=try fm.attributesOfItem(atPath:folder.path)
            guard attrs[.type] as? FileAttributeType == .typeDirectory,(attrs[.ownerAccountID] as? NSNumber)?.uint32Value==getuid() else {throw TunerError.message("滚轮目录的类型或所有者不正确")}
            try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:folder.path)
        }
        guard socketURL.path.utf8.count<104 else {throw TunerError.message("用户目录路径过长，无法建立滚轮通信")}
        let domain="gui/\(getuid())"
        let agents=fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        try fm.createDirectory(at:agents,withIntermediateDirectories:true)
        let legacy="local.coeditor.wheel.protocol1"
        try run("/bin/launchctl",["bootout",domain+"/"+legacy],allowFailure:true)
        let legacyPlist=agents.appendingPathComponent(legacy+".plist")
        if fm.fileExists(atPath:legacyPlist.path){try fm.removeItem(at:legacyPlist)}
        let executable=installed.appendingPathComponent("Contents/MacOS/COEditorWheel")
        var replace = !fm.fileExists(atPath:installed.path)
        if !replace {
            let receipt=try JSONDecoder().decode(Receipt.self,from:Data(contentsOf:record))
            guard [1,2].contains(receipt.version),try Storage.hash(executable)==receipt.hash else {throw TunerError.message("已安装滚轮组件发生变化，未覆盖现有文件")}
            try run("/usr/bin/codesign",["--verify","--strict",installed.path])
            replace=receipt.version==1
        }
        if replace {
            guard let resource=Bundle.main.resourceURL else {throw TunerError.message("应用缺少滚轮组件")}
            let source=resource.appendingPathComponent("COEditor Wheel.app")
            try run("/usr/bin/codesign",["--verify","--strict",source.path])
            let stage=directory.appendingPathComponent(".install-"+UUID().uuidString+".app")
            defer{try? fm.removeItem(at:stage)}
            try fm.copyItem(at:source,to:stage)
            try run("/usr/bin/codesign",["--verify","--strict",stage.path])
            if fm.fileExists(atPath:installed.path){try fm.removeItem(at:installed)}
            try fm.moveItem(at:stage,to:installed)
            try JSONEncoder().encode(Receipt(version:2,hash:try Storage.hash(executable))).write(to:record,options:.atomic)
        }
        try run("/usr/bin/codesign",["--verify","--strict",installed.path])
        let plist=agents.appendingPathComponent(label+".plist")
        let bytes=try PropertyListSerialization.data(fromPropertyList:agentConfiguration(executable:executable.path,socket:socketURL.path),format:.xml,options:0)
        let changed=(try? Data(contentsOf:plist)) != bytes
        if changed {try bytes.write(to:plist,options:.atomic);try run("/bin/launchctl",["bootout",domain+"/"+label],allowFailure:true)}
        if try run("/bin/launchctl",["print",domain+"/"+label],allowFailure:true) != 0 {
            try run("/bin/launchctl",["bootstrap",domain,plist.path])
        }
        if requestAccess {
            try Data("1\n".utf8).write(to:directory.appendingPathComponent("request-access"),options:.atomic)
            try requestPermission()
        }
    }
    static func promptSetup()throws {
        let alert=NSAlert();alert.messageText="设置按需滚轮读取器"
        alert.informativeText="组件路径：\n\(installed.path)\n\n它由启用滚轮优化的游戏唤起，最后一个程序退出后自动结束，不在登录后常驻。输入监控权限可读取全局键鼠输入；本组件只处理物理滚轮，发送给已登记的前台 Wine 程序。是否安装并申请授权？"
        alert.addButton(withTitle:"安装并请求授权");alert.addButton(withTitle:"取消")
        if alert.runModal() == .alertFirstButtonReturn {try install(requestAccess:true)}
    }
}
