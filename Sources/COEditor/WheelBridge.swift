import AppKit
import CryptoKit

struct WheelReaderPresentation: Equatable {
    enum State { case notInstalled, warning, healthy }
    var state:State
    var text:String
    var isHealthy:Bool { state == .healthy }
    var symbol:String { isHealthy ? "checkmark.circle.fill":"exclamationmark.triangle.fill" }
    static let notInstalled=Self(state:.notInstalled,text:"滚轮组件未安装；当前使用原生滚动")
}
struct WheelReaderStatus: Decodable {
    var `protocol`:Int
    var pid:Int32
    var state:String
    var devices:Int
    var reports:UInt64
    var clients:Int?
    var updated:Double
    var openError:Int64?
    static func presentation(_ data:Data?,installed:Bool,installationIssue:String?=nil,configured:Bool=false,runningPID:Int32?=nil,now:Double=Date().timeIntervalSince1970)->WheelReaderPresentation {
        func warning(_ text:String)->WheelReaderPresentation { .init(state:.warning,text:text) }
        guard installed else {return .notInstalled}
        if let issue=installationIssue {return warning(issue)}
        guard configured else {return warning("滚轮组件已安装，但按需启动入口未注册；请重新设置组件")}
        guard let runningPID else {return .init(state:.healthy,text:"滚轮组件已安装，读取器待命；游戏启动时自动唤起")}
        guard let data,let s=try? JSONDecoder().decode(Self.self,from:data),s.protocol==2,s.pid==runningPID,
              now>=s.updated,now-s.updated<3 else {
            return warning("滚轮读取器正在启动或状态未更新；请稍后检查")
        }
        switch s.state {
        case "ready" where s.devices>0:return .init(state:.healthy,text:"滚轮读取器就绪 · \(s.clients ?? 0) 个程序 · \(s.devices) 个设备 · \(s.reports) 次物理报告")
        case "permission-required":return warning("滚轮读取器缺少输入监控授权；当前使用原生滚动")
        case "no-device","ready":return warning("滚轮读取器已授权，未检测到实体滚轮；当前使用原生滚动")
        case "setup":return warning("正在设置滚轮读取器，等待系统授权")
        case "idle":return .init(state:.healthy,text:"滚轮组件已安装，读取器待命；游戏启动时自动唤起")
        case "open-error":return warning("滚轮设备打开失败\(s.openError.map {"（错误码 0x"+String(UInt32(truncatingIfNeeded:$0),radix:16)+"）"} ?? "")；当前使用原生滚动")
        default:return warning("滚轮读取器状态异常；请重新检查组件")
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
    static let requiredRevision=3
    struct Receipt:Codable {
        var version:Int
        var revision:Int?
        var hash:String
        var needsUpgrade:Bool {version != 2 || (revision ?? 2)<WheelReader.requiredRevision}
    }
    static func status(driverSupported:Bool=true)->WheelReaderPresentation {
        guard Storage.fm.fileExists(atPath:installed.path) else {return .notInstalled}
        let executable=installed.appendingPathComponent("Contents/MacOS/COEditorWheel")
        var issue:String?
        if !Storage.fm.isExecutableFile(atPath:executable.path) {issue="滚轮组件安装不完整，缺少可执行文件；请重新安装"}
        else if let receipt=try? JSONDecoder().decode(Receipt.self,from:Data(contentsOf:record)) {
            if receipt.needsUpgrade {issue="滚轮组件版本需要更新；请重新设置组件"}
            else if (try? Storage.hash(executable)) != receipt.hash {issue="滚轮组件文件校验失败；请检查安装"}
        } else {issue="滚轮组件安装记录缺失或损坏；请重新设置组件"}
        if issue==nil && !driverSupported {issue="滚轮驱动需要更新，尚未接入按需读取器"}
        let data=try? Data(contentsOf:directory.appendingPathComponent("status.json"))
        let job=Process();job.executableURL=URL(fileURLWithPath:"/bin/launchctl");job.arguments=["print","gui/\(getuid())/"+label]
        let pipe=Pipe();job.standardOutput=pipe;job.standardError=FileHandle.nullDevice
        var loaded=false,pid:Int32?
        do {
            try job.run();let output=String(decoding:pipe.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self);job.waitUntilExit();loaded=job.terminationStatus==0
            for line in output.components(separatedBy:.newlines) {
                let parts=line.trimmingCharacters(in:.whitespaces).components(separatedBy:" = ")
                if parts.count==2 && parts[0]=="pid" {pid=Int32(parts[1])}
            }
        } catch {issue=issue ?? "无法检查滚轮组件的按需启动入口"}
        return WheelReaderStatus.presentation(data,installed:true,installationIssue:issue,configured:loaded,runningPID:pid)
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
    // Retain a validated current reader across editor/Sevoflurane updates.
    // Revision 3 fixes false client expiry caused by CrossOver's hard links.
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
            replace=receipt.needsUpgrade
        }
        if replace {
            guard let resource=Bundle.main.resourceURL else {throw TunerError.message("应用缺少滚轮组件")}
            let source=resource.appendingPathComponent("COEditor Wheel.app")
            try run("/usr/bin/codesign",["--verify","--strict",source.path])
            let stage=directory.appendingPathComponent(".install-"+UUID().uuidString+".app")
            defer{try? fm.removeItem(at:stage)}
            try fm.copyItem(at:source,to:stage)
            try run("/usr/bin/codesign",["--verify","--strict",stage.path])
            let helperInfo=try PropertyListSerialization.propertyList(from:Data(contentsOf:stage.appendingPathComponent("Contents/Info.plist")),format:nil) as? [String:Any]
            guard helperInfo?["CFBundleVersion"] as? String == String(requiredRevision) else {throw TunerError.message("应用附带的滚轮组件版本不匹配")}
            try run("/bin/launchctl",["bootout",domain+"/"+label],allowFailure:true)
            if fm.fileExists(atPath:installed.path){try fm.removeItem(at:installed)}
            try fm.moveItem(at:stage,to:installed)
            try JSONEncoder().encode(Receipt(version:2,revision:requiredRevision,hash:try Storage.hash(executable))).write(to:record,options:.atomic)
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
