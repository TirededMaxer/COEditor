import AppKit
import CryptoKit

struct WheelReaderStatus: Decodable {
    var `protocol`:Int
    var pid:Int32
    var state:String
    var devices:Int
    var reports:UInt64
    var updated:Double
    static func description(_ data:Data?,now:Double=Date().timeIntervalSince1970)->String {
        guard let data,let s=try? JSONDecoder().decode(Self.self,from:data),s.protocol==1,
              now>=s.updated,now-s.updated<3,kill(s.pid,0)==0 else {return "滚轮读取器未运行；当前使用原生滚动"}
        switch s.state {
        case "ready":return "滚轮读取器就绪 · \(s.devices) 个设备 · \(s.reports) 次物理报告"
        case "permission-required":return "滚轮读取器缺少输入监控授权；当前使用原生滚动"
        case "no-device":return "滚轮读取器已授权，未检测到实体滚轮；当前使用原生滚动"
        default:return "滚轮设备打开失败；当前使用原生滚动"
        }
    }
}
struct WheelReader {
    static let directory=Storage.support.appendingPathComponent("Wheel")
    static let installed=directory.appendingPathComponent("COEditor Wheel.app")
    static let record=directory.appendingPathComponent("installed.json")
    static let label="local.coeditor.wheel.protocol1"
    struct Receipt:Codable {var version:Int;var hash:String}
    static func status()->String {WheelReaderStatus.description(try? Data(contentsOf:directory.appendingPathComponent("status.json")))}
    @discardableResult static func run(_ path:String,_ arguments:[String],allowFailure:Bool=false)throws->Int32 {
        let p=Process();p.executableURL=URL(fileURLWithPath:path);p.arguments=arguments
        p.standardOutput=FileHandle.nullDevice;p.standardError=FileHandle.nullDevice
        try p.run();p.waitUntilExit()
        if p.terminationStatus != 0 && !allowFailure {throw TunerError.message("滚轮组件操作失败：\(URL(fileURLWithPath:path).lastPathComponent) (\(p.terminationStatus))")}
        return p.terminationStatus
    }
    // Never replace an authorized protocol-1 reader on Sevoflurane or editor updates.
    // A modified or missing receipt requires explicit repair, not silent re-signing.
    static func install(requestAccess:Bool)throws {
        let fm=FileManager.default
        try fm.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:directory.path)
        let executable=installed.appendingPathComponent("Contents/MacOS/COEditorWheel")
        if fm.fileExists(atPath:installed.path) {
            let receipt=try JSONDecoder().decode(Receipt.self,from:Data(contentsOf:record))
            guard receipt.version==1,try Storage.hash(executable)==receipt.hash else {throw TunerError.message("已安装滚轮组件发生变化，请先检查；未覆盖现有授权身份")}
        } else {
            guard let resource=Bundle.main.resourceURL else {throw TunerError.message("应用缺少滚轮组件")}
            let source=resource.appendingPathComponent("COEditor Wheel.app")
            try run("/usr/bin/codesign",["--verify","--strict",source.path])
            try fm.copyItem(at:source,to:installed)
            try JSONEncoder().encode(Receipt(version:1,hash:try Storage.hash(executable))).write(to:record,options:.atomic)
        }
        try run("/usr/bin/codesign",["--verify","--strict",installed.path])
        let agents=fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        try fm.createDirectory(at:agents,withIntermediateDirectories:true)
        let plist=agents.appendingPathComponent(label+".plist")
        let config:[String:Any] = ["Label":label,"ProgramArguments":[executable.path],"RunAtLoad":true,"KeepAlive":true,"ThrottleInterval":5,
            "StandardOutPath":directory.appendingPathComponent("reader.log").path,"StandardErrorPath":directory.appendingPathComponent("reader-error.log").path]
        let bytes=try PropertyListSerialization.data(fromPropertyList:config,format:.xml,options:0)
        let changed=(try? Data(contentsOf:plist)) != bytes
        if changed {try bytes.write(to:plist,options:.atomic)}
        if requestAccess {try Data("1\n".utf8).write(to:directory.appendingPathComponent("request-access"),options:.atomic)}
        let domain="gui/\(getuid())"
        if changed {try run("/bin/launchctl",["bootout",domain+"/"+label],allowFailure:true)}
        if try run("/bin/launchctl",["print",domain+"/"+label],allowFailure:true) != 0 {
            try run("/bin/launchctl",["bootstrap",domain,plist.path])
        }
    }
    static func promptSetup()throws {
        let alert=NSAlert();alert.messageText="设置 COEditor 滚轮读取器"
        alert.informativeText="将独立组件安装到：\n\(installed.path)\n\n它需要 macOS 输入监控权限，可读取全局键鼠输入；本组件只处理实体鼠标滚轮，并发送给前台游戏。Sevoflurane 更新时保留此组件及授权。是否安装并请求授权？"
        alert.addButton(withTitle:"安装并请求授权");alert.addButton(withTitle:"取消")
        if alert.runModal() == .alertFirstButtonReturn {try install(requestAccess:true)}
    }
}
