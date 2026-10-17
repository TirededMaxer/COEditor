import AppKit
import SwiftUI
import CryptoKit
import UniformTypeIdentifiers

struct TuningFile: Equatable {
    var sections: [String: [String: Int]] = [:]
    init(_ text: String = "") {
        var section = "global"
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") && line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast()).lowercased()
                if sections[section] == nil { sections[section] = [:] }
            } else if !line.hasPrefix("#") && !line.hasPrefix(";"), let eq = line.firstIndex(of: "="), let value = Int(line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)) {
                let key = line[..<eq].trimmingCharacters(in: .whitespaces)
                if key == "preset" || key == "preset_fps" { continue }
                sections[section, default: [:]][key] = value
            }
        }
    }
    static var initial: TuningFile {
        TuningFile("[global]\nmouse=1\nwheel=1\nsync=-1\ndrawables=0\nqueue=0\nfps=0\npacing=0\nstats=0\n")
    }
    func value(_ key: String, in section: String) -> Int {
        sections[section.lowercased()]?[key] ?? sections["global"]?[key] ?? (["mouse": 1, "wheel": 1, "sync": -1, "drawables": 0, "queue": 0, "fps": 0, "stats": 0, "pacing": 0][key] ?? 0)
    }
    func validate() throws {
        for (section, values) in sections {
            guard !section.isEmpty && !section.contains("\n") && !section.contains("]") && !section.contains("/") && !section.contains("\\") else { throw TunerError.message("游戏名称无效") }
            for (key, value) in values {
                let valid: Bool
                switch key {
                case "mouse", "wheel", "stats": valid = (0...1).contains(value)
                case "sync": valid = (-1...1).contains(value)
                case "drawables": valid = [0, 2, 3].contains(value)
                case "queue": valid = (0...16).contains(value)
                case "fps": valid = (0...1000).contains(value)
                case "pacing": valid = (0...2).contains(value)
                default: valid = true
                }
                guard valid else { throw TunerError.message("\(section) 的 \(key) 数值无效") }
            }
        }
    }
    func serialized() -> String {
        let names = sections.keys.sorted { a,b in a == b ? false : a == "global" ? true : b == "global" ? false : a < b }
        return "# COEditor；保存后重启对应游戏生效。\n" + names.map { section in
            "[\(section)]\n" + (sections[section] ?? [:]).keys.sorted().map { "\($0)=\(sections[section]![$0]!)" }.joined(separator: "\n")
        }.joined(separator: "\n\n") + "\n"
    }
}
enum TunerError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}
struct Component: Codable {
    var target: String
    var payload: String
    var sha256: String
    var allowedBefore: [String]
    var optional: Bool?
}
struct InstallManifest: Codable { var runtime: String; var baseVersion: String; var components: [Component]; var frameControlVersion:Int? }
struct MaintenanceResult: Codable {
    var ok: Bool
    var runtime: String
    var installedCrossOver: String
    var notes: [String]
}
struct Storage {
    static let fm = FileManager.default
    static let root = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CrossOver")
    static let custom = root.appendingPathComponent("CustomRuntimes")
    static let support = custom.appendingPathComponent(".tuner-support")
    static let bottle = root.appendingPathComponent("Bottles/Steam")
    static let ini = bottle.appendingPathComponent("drive_c/.cx-tuner.ini")
    static let conf = bottle.appendingPathComponent("cxbottle.conf")
    static let bindingsURL = support.appendingPathComponent("games.json")
    static func bindings()->[String:GameBinding] { (try? JSONDecoder().decode([String:GameBinding].self,from:Data(contentsOf:bindingsURL))) ?? [:] }
    static func bind(_ game:InstalledSteamGame,exe:GameExecutable)throws {
        var entries=bindings()
        if let old=entries[exe.profile],old.executable != exe.path {throw TunerError.message("另一个配置使用同名启动程序，暂时无法分别设置：\(exe.profile)")}
        entries[exe.profile]=GameBinding(appID:game.id,name:game.name,executable:exe.path)
        try JSONEncoder().encode(entries).write(to:bindingsURL,options:.atomic)
    }
    static func queueInstalled(_ exe:GameExecutable)->Bool {
        let target=URL(fileURLWithPath:exe.path).deletingLastPathComponent().appendingPathComponent("d3d11.dll")
        guard let actual=try? hash(target),let expected=try? hash(support.appendingPathComponent("Payload/d3d11-cs2.dll")),actual==expected,let info=try? manifest() else{return false}
        return info.components.contains {component in
            let path=component.target.hasPrefix("/") ? component.target:root.appendingPathComponent(component.target).path
            return path==target.path && component.sha256==actual
        }
    }
    static func hash(_ url: URL) throws -> String { SHA256.hash(data: try Data(contentsOf: url)).map { String(format:"%02x",$0) }.joined() }
    static func manifest() throws -> InstallManifest { try JSONDecoder().decode(InstallManifest.self, from: Data(contentsOf: support.appendingPathComponent("manifest.json"))) }
    static func version() -> String {
        let url = URL(fileURLWithPath:"/Applications/CrossOver.app/Contents/Info.plist")
        guard let data = try? Data(contentsOf:url), let p = try? PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any] else { return "未安装" }
        return p["CFBundleShortVersionString"] as? String ?? "未知"
    }
    static func quote(_ value: String) -> String { let encoder=JSONEncoder();encoder.outputFormatting=[.withoutEscapingSlashes];return String(data:try! encoder.encode(value),encoding:.utf8)! }
    static func repairedConfig(_ text: String, runtime: String) throws -> String {
        var lines = text.components(separatedBy:"\n")
        guard let start = lines.firstIndex(of:"[EnvironmentVariables]") else { throw TunerError.message("容器缺少环境变量节，未自动改写") }
        let end = ((start+1)..<lines.count).first { lines[$0].hasPrefix("[") } ?? lines.count
        let required=["CX_ROOT":runtime,"CX_D3D11_REAL_DLL":"Z:"+runtime.replacingOccurrences(of:"/",with:"\\")+"\\lib64\\apple_gptk\\wine\\x86_64-windows\\d3d11.dll","CX_HIDE_STEAM_DOCK":"1"]
        var found=Set<String>()
        for i in (start+1)..<end {
            for (key,value) in required where lines[i].hasPrefix("\"\(key)\"") {
                lines[i] = "\"\(key)\" = " + quote(value);found.insert(key)
            }
            for key in ["DXMT_CONFIG", "DXVK_CONFIG"] {
                let prefix = "\"\(key)\" = "
                if lines[i].hasPrefix(prefix) {
                    let raw = String(lines[i].dropFirst(prefix.count))
                    if raw.hasPrefix("\"") && raw.hasSuffix("\""), (try? JSONDecoder().decode(String.self,from:Data(raw.utf8))) == nil {
                        lines[i] = prefix + quote(String(raw.dropFirst().dropLast()))
                    }
                }
            }
        }
        for key in required.keys.sorted().reversed() where !found.contains(key) {lines.insert("\"\(key)\" = " + quote(required[key]!),at:start+1)}
        return lines.joined(separator:"\n")
    }
    static func backupConfig(_ url: URL) throws {
        guard fm.fileExists(atPath:url.path) else { return }
        let dir = support.appendingPathComponent("Backups/settings")
        try fm.createDirectory(at:dir,withIntermediateDirectories:true)
        let name = "\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8))-\(url.lastPathComponent)"
        try fm.copyItem(at:url,to:dir.appendingPathComponent(name))
        let files = try fm.contentsOfDirectory(at:dir,includingPropertiesForKeys:nil).sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in files.dropFirst(30) { try? fm.removeItem(at:old) }
    }
    static func save(_ file: TuningFile) throws {
        try file.validate()
        let bytes = Data(file.serialized().utf8)
        if (try? Data(contentsOf:ini)) == bytes { return }
        try backupConfig(ini)
        try bytes.write(to:ini,options:.atomic)
    }
    static func registerGame(_ exe: URL) throws {
        let data=try Data(contentsOf:exe,options:.mappedIfSafe)
        func u16(_ p:Int)->Int { Int(data[p]) | (Int(data[p+1])<<8) }
        guard data.count>64, data[0]==77, data[1]==90 else {throw TunerError.message("请选择 Windows 游戏主程序")}
        let pe=(0..<4).reduce(0){$0 | (Int(data[60+$1]) << (8*$1))}
        guard pe>0,pe+26<data.count,u16(pe)==0x4550,u16(pe+4)==0x8664 else {throw TunerError.message("D3D11 队列适配目前支持 64 位 x86 游戏")}
        let target=exe.deletingLastPathComponent().appendingPathComponent("d3d11.dll")
        let payload=support.appendingPathComponent("Payload/d3d11-cs2.dll")
        let expected=try hash(payload)
        if fm.fileExists(atPath:target.path),try hash(target) != expected {throw TunerError.message("该游戏已有其他 d3d11.dll，已保留。可在通用设置中调整输入和 Metal 画面。")}
        let info=try manifest();let wine=custom.appendingPathComponent(info.runtime+"/bin/wine")
        let process=Process();process.executableURL=wine
        process.arguments=["--bottle","Steam","--no-update","--wait","--cx-app","C:\\windows\\system32\\reg.exe","add","HKCU\\Software\\Wine\\AppDefaults\\"+exe.lastPathComponent+"\\DllOverrides","/v","d3d11","/t","REG_SZ","/d","native,builtin","/f"]
        let log=support.appendingPathComponent("game-registration.log")
        _=fm.createFile(atPath:log.path,contents:nil);let handle=try FileHandle(forWritingTo:log);defer {try? handle.close()}
        let query=Process();query.executableURL=wine
        query.arguments=["--bottle","Steam","--no-update","--wait","--cx-app","C:\\windows\\system32\\reg.exe","query","HKCU\\Software\\Wine\\AppDefaults\\"+exe.lastPathComponent+"\\DllOverrides","/v","d3d11"]
        let pipe=Pipe();query.standardOutput=pipe;query.standardError=handle
        try query.run();let existing=pipe.fileHandleForReading.readDataToEndOfFile();query.waitUntilExit()
        if query.terminationStatus==0 && !(String(data:existing,encoding:.utf8) ?? "").contains("native,builtin") {throw TunerError.message("该游戏已有专用 D3D11 加载设置，已保留；暂不自动安装队列补丁")}
        process.standardOutput=handle;process.standardError=handle
        try process.run();process.waitUntilExit()
        guard process.terminationStatus==0 else {throw TunerError.message("游戏队列注册失败，请检查 game-registration.log")}
        try Data(contentsOf:payload).write(to:target,options:.atomic)
        var updated=try manifest();let relative=target.path.hasPrefix(root.path+"/") ? String(target.path.dropFirst(root.path.count+1)) : target.path
        updated.components.removeAll{$0.target==relative}
        updated.components.append(Component(target:relative,payload:"Payload/d3d11-cs2.dll",sha256:expected,allowedBefore:[],optional:true))
        try JSONEncoder().encode(updated).write(to:support.appendingPathComponent("manifest.json"),options:.atomic)
    }
    static func maintain(repair: Bool) -> MaintenanceResult {
        var result = MaintenanceResult(ok:true,runtime:"26.3",installedCrossOver:version(),notes:[])
        do {
            let info = try manifest(); result.runtime = info.baseVersion
            for c in info.components {
                let target = c.target.hasPrefix("/") ? URL(fileURLWithPath:c.target) : root.appendingPathComponent(c.target)
                if c.optional == true && !fm.fileExists(atPath:target.deletingLastPathComponent().path) { continue }
                let actual = try? hash(target)
                if actual == c.sha256 { continue }
                if repair && (actual == nil || c.allowedBefore.contains(actual!)) {
                    let payload = support.appendingPathComponent(c.payload)
                    guard try hash(payload) == c.sha256 else { throw TunerError.message("备份组件校验失败：\(c.payload)") }
                    try fm.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
                    try Data(contentsOf:payload).write(to:target,options:.atomic)
                    try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:target.path)
                    result.notes.append("已恢复：\(target.lastPathComponent)")
                } else {
                    result.ok = false;result.notes.append("组件发生未知变化，需要适配：\(target.lastPathComponent)")
                }
            }
            if result.ok {
                let runtime = custom.appendingPathComponent(info.runtime).path
                let original = try String(contentsOf:conf,encoding:.utf8)
                let fixed = try repairedConfig(original,runtime:runtime)
                if fixed != original {
                    if repair { try backupConfig(conf);try Data(fixed.utf8).write(to:conf,options:.atomic);result.notes.append("已保持补丁引擎路径及配置格式") }
                    else { result.ok = false;result.notes.append("容器运行路径需要恢复") }
                }
                if !fm.fileExists(atPath:ini.path) {
                    if repair { try save(.initial);result.notes.append("已恢复默认调整配置") }
                    else { result.ok = false;result.notes.append("调整配置缺失") }
                } else { try TuningFile(String(contentsOf:ini,encoding:.utf8)).validate() }
            }
            if result.installedCrossOver != info.baseVersion { result.notes.append("已安装 CrossOver \(result.installedCrossOver)；继续使用已验证的 \(info.baseVersion) 补丁引擎。切换新版引擎需重新适配。") }
            if result.notes.isEmpty { result.notes = ["补丁环境与配置完整"] }
        } catch { result.ok = false;result.notes.append(error.localizedDescription) }
        if repair, let data = try? JSONEncoder().encode(result) {
            let url = support.appendingPathComponent("maintenance-status.json")
            if (try? Data(contentsOf:url)) != data { try? data.write(to:url,options:.atomic) }
        }
        return result
    }
}
final class TunerModel: ObservableObject {
    @Published var file = TuningFile.initial
    @Published var selected = "cs2.exe"
    @Published var message = ""
    @Published var healthy = true
    @Published var environment = ""
    @Published var busy = false
    @Published var games:[InstalledSteamGame] = []
    @Published var bindings:[String:GameBinding] = [:]
    @Published var queueProfiles:Set<String> = []
    @Published var showGamePicker = false
    @Published var showFrameStats = false
    @Published var supportsFrameControl = false
    private var savedFile = TuningFile.initial
    init(loadEnvironment:Bool = true) { if loadEnvironment { reload();check();refreshGames() } }
    var hasUnsavedChanges:Bool { file != savedFile }
    var inheritsInput:Bool { file.sections[selected]?["mouse"] == nil && file.sections[selected]?["wheel"] == nil }
    private func edited() { message = hasUnsavedChanges ? "有未保存的修改" : "" }
    func acceptSaved(_ saved:TuningFile) { file=saved;savedFile=saved;message="" }
    func setInputInheritance(_ inherit:Bool) {
        guard !isGlobal,inherit != inheritsInput else { return }
        if inherit {
            file.sections[selected]?.removeValue(forKey:"mouse")
            file.sections[selected]?.removeValue(forKey:"wheel")
        } else {
            let mouse=get("mouse"),wheel=get("wheel")
            file.sections[selected,default:[:]]["mouse"]=mouse
            file.sections[selected,default:[:]]["wheel"]=wheel
        }
        edited()
    }
    var scopes: [String] { ["global"] + file.sections.keys.filter{$0 != "global"}.sorted() }
    var isGlobal: Bool { selected == "global" }
    func label(_ section: String) -> String {
        if section=="global" {return "通用"}
        guard let game=bindings[section] else{return section}
        let count=bindings.values.filter{$0.appID==game.appID}.count
        return count>1 ? "\(game.name) · \(section)":game.name
    }
    var selectedProgram:String {
        guard let entry=bindings[selected] else{return ""}
        if let game=games.first(where:{$0.id==entry.appID}),entry.executable.hasPrefix(game.directory+"/") {return String(entry.executable.dropFirst(game.directory.count+1))}
        return entry.executable
    }
    var supportsQueue:Bool {isGlobal || queueProfiles.contains(selected)}
    func refreshGames(openPicker:Bool=false) {
        if openPicker {busy=true;message="正在检索已安装的游戏…"}
        DispatchQueue.global(qos:.userInitiated).async {
            do {let games=try SteamLibrary.scan();DispatchQueue.main.async {
                self.games=games;self.bindings=Storage.bindings();self.queueProfiles=[]
                for game in games {for exe in game.executables {
                    if self.file.sections[exe.profile] != nil && self.bindings[exe.profile]==nil {self.bindings[exe.profile]=GameBinding(appID:game.id,name:game.name,executable:exe.path)}
                    if Storage.queueInstalled(exe) {self.queueProfiles.insert(exe.profile)}
                }}
                if openPicker {self.busy=false;self.showGamePicker=true;self.message="请选择游戏及其启动程序"}
            }}catch {DispatchQueue.main.async {self.busy=false;self.message=error.localizedDescription}}
        }
    }
    func get(_ key: String) -> Int { file.value(key,in:selected) }
    func set(_ key: String,_ value: Int) {
        guard get(key) != value else { return }
        // Restore an inherited field's original absence when an edit is undone.
        if key != "mouse" && key != "wheel" && savedFile.sections[selected]?[key] == nil && savedFile.value(key,in:selected) == value {
            file.sections[selected]?.removeValue(forKey:key)
        } else { file.sections[selected,default:[:]][key] = value }
        edited()
    }
    func setFollowingGame(_ key:String,_ follows:Bool,manualValue:Int) {
        guard follows != (get(key)==0) else { return }
        set(key,follows ? 0:manualValue)
    }
    func setFrameLimitEnabled(_ enabled:Bool) {
        guard enabled != (get("fps") != 0) else { return }
        set("fps",enabled ? 120:0)
    }
    func binding(_ key: String) -> Binding<Bool> { Binding(get:{self.get(key) != 0},set:{self.set(key,$0 ? 1 : 0)}) }
    func reload() {
        do { let loaded = Storage.fm.fileExists(atPath:Storage.ini.path) ? TuningFile(try String(contentsOf:Storage.ini,encoding:.utf8)) : .initial;try loaded.validate();acceptSaved(loaded);message="已读取保存的设置" }
        catch { message=error.localizedDescription }
        if file.sections[selected] == nil { selected="global" }
    }
    @discardableResult func save() -> Bool { do { try Storage.save(file);savedFile=file;message="已保存，重启对应游戏后生效";return true } catch {message="保存失败："+error.localizedDescription;return false} }
    func check() { supportsFrameControl = (try? Storage.manifest().frameControlVersion) == 1;let r=Storage.maintain(repair:true);healthy=r.ok;environment="补丁引擎 \(r.runtime) · CrossOver \(r.installedCrossOver)\n"+r.notes.joined(separator:"\n") }
    func addGame(_ game:InstalledSteamGame,exe:GameExecutable) {
        let name=exe.profile
        if let old=bindings[name],old.executable != exe.path {message="另一个配置使用同名启动程序，暂时无法分别设置：\(name)";return}
        busy=true;message="正在添加游戏…"
        DispatchQueue.global(qos:.userInitiated).async {
            do {
                var queue=Storage.queueInstalled(exe),note=""
                if exe.is64Bit && !queue {do {try Storage.registerGame(URL(fileURLWithPath:exe.path));queue=true}catch {note=error.localizedDescription}}
                try Storage.bind(game,exe:exe)
                let installed=queue,detail=note
                DispatchQueue.main.async {
                    if self.file.sections[name] == nil {self.file.sections[name]=[:]}
                    if installed {self.queueProfiles.insert(name)}else {self.file.sections[name]?["queue"]=0}
                    self.bindings[name]=GameBinding(appID:game.id,name:game.name,executable:exe.path)
                    self.selected=name;self.showGamePicker=false;self.message=detail.isEmpty ? "已选择游戏，设置后保存":"已添加画面与输入配置；"+detail;self.busy=false
                }
            }
            catch {DispatchQueue.main.async {self.message=error.localizedDescription;self.busy=false}}
        }
    }
}
struct GamePickerView:View {
    @ObservedObject var model:TunerModel
    @State private var selection:String?
    @State private var executablePath=""
    var game:InstalledSteamGame? {model.games.first{$0.id==selection}}
    var selectedExecutable:GameExecutable? {game?.executables.first{$0.path==executablePath}}
    func select(_ id:String?) {selection=id;executablePath=game?.executables.first?.path ?? ""}
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Text("选择已安装的游戏").font(.title3.bold())
            List(selection:Binding(get:{selection},set:{select($0)})) {ForEach(model.games){game in
                HStack {Text(game.name);Spacer();if model.bindings.values.contains(where:{$0.appID==game.id}) {Text("已添加").foregroundStyle(.secondary)}}.tag(game.id)
            }}.frame(height:min(220,max(85,CGFloat(model.games.count)*38)))
            if let game=game {
                Text(game.name).font(.headline)
                if game.executables.isEmpty {Text("未找到可用的 Windows 启动程序").foregroundStyle(.secondary)}
                else {
                    Picker("启动程序",selection:$executablePath){ForEach(game.executables){exe in Text(exe.launchName.isEmpty ? exe.relativePath:"\(exe.launchName) · \(exe.relativePath)").tag(exe.path)}}
                    if let exe=selectedExecutable {Text(exe.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)}
                }
            } else {Text(model.games.isEmpty ? "Steam 容器中没有找到已安装的游戏":"请选择一个游戏").foregroundStyle(.secondary)}
            HStack {Button("刷新列表"){model.showGamePicker=false;model.refreshGames(openPicker:true)};Spacer();Button("取消"){model.showGamePicker=false};Button("使用所选游戏"){if let game=game,let exe=selectedExecutable {model.addGame(game,exe:exe)}}.disabled(selectedExecutable==nil).buttonStyle(.borderedProminent)}
        }.padding(20).frame(width:560).disabled(model.busy)
        .onAppear {select(model.bindings[model.selected]?.appID ?? model.games.first?.id)}
    }
}
extension NumberFormatter {
    static var coeditorInteger:NumberFormatter {let f=NumberFormatter();f.numberStyle = .none;f.minimum=1;f.maximum=1000;f.allowsFloats=false;return f}
}
struct ContentHeightKey:PreferenceKey {static var defaultValue:CGFloat=650;static func reduce(value:inout CGFloat,nextValue:()->CGFloat){value=nextValue()}}
struct NumberControl: View {
    var label:String;var value:Int;var bounds:ClosedRange<Double>;var enabled:Bool;var placeholder:String="默认";var change:(Int)->Void
    var body:some View {HStack {Text(label).frame(width:135,alignment:.leading);Slider(value:Binding(get:{Double(min(Int(bounds.upperBound),max(Int(bounds.lowerBound),value)))},set:{if enabled {change(Int($0.rounded()))}}),in:bounds,step:1).disabled(!enabled);Text(enabled ? "\(value)" : placeholder).monospacedDigit().frame(width:42,alignment:.trailing)}}
}
struct TunerView:View {
    @ObservedObject var model:TunerModel
    var resize:(CGFloat)->Void
    @State private var contentHeight:CGFloat=650
    var body:some View {
        ScrollView { VStack(alignment:.leading,spacing:12) {
            HStack { Image(systemName:"slider.horizontal.3").font(.system(size:30)).foregroundStyle(.blue);VStack(alignment:.leading){Text("COEditor").font(.title2.bold());Text("Steam 容器").foregroundStyle(.secondary)};Spacer() }
            HStack {Text("配置范围");Picker("配置范围",selection:$model.selected){ForEach(model.scopes,id:\.self){Text(model.label($0)).tag($0)}}.labelsHidden();Button("添加游戏…"){model.refreshGames(openPicker:true)} }
            if !model.selectedProgram.isEmpty {Text("启动程序："+model.selectedProgram).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)}
            GroupBox("画面") {
                VStack(alignment:.leading,spacing:10) {
                    VStack(alignment:.leading,spacing:10) {
                    HStack {Text("显示同步").frame(width:135,alignment:.leading);Picker("显示同步",selection:Binding(get:{model.get("sync")},set:{model.set("sync",$0)})){Text("跟随游戏").tag(-1);Text("强制开启").tag(1);Text("强制关闭").tag(0)}.labelsHidden()}
                    Toggle("缓冲数量跟随游戏",isOn:Binding(get:{model.get("drawables")==0},set:{model.setFollowingGame("drawables",$0,manualValue:3)}))
                    HStack {Text("Metal 缓冲数量").frame(width:135,alignment:.leading);Picker("Metal 缓冲数量",selection:Binding(get:{max(2,model.get("drawables"))},set:{if model.get("drawables") != 0 {model.set("drawables",$0)}})){Text("2").tag(2);Text("3").tag(3)}.pickerStyle(.segmented).labelsHidden().disabled(model.get("drawables")==0)}
                    Toggle("队列长度跟随游戏",isOn:Binding(get:{model.get("queue")==0},set:{model.setFollowingGame("queue",$0,manualValue:2)})).disabled(!model.supportsQueue)
                    NumberControl(label:"D3D11 队列上限",value:model.get("queue"),bounds:1...16,enabled:model.get("queue") != 0 && model.supportsQueue,placeholder:model.supportsQueue ? "默认":"未适配"){model.set("queue",$0)}
                    }
                    Text("Metal 选项适用于 D3DMetal；队列上限适用于已适配的 64 位 D3D11 游戏。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                }.padding(9)
            }
            GroupBox("帧率与提交") {
                VStack(alignment:.leading,spacing:10) {
                    VStack(alignment:.leading,spacing:10) {
                    Toggle("按游戏限帧",isOn:Binding(get:{model.get("fps") != 0},set:{model.setFrameLimitEnabled($0)}))
                    HStack {
                        Text("帧率上限").frame(width:135,alignment:.leading)
                        TextField("FPS",value:Binding(get:{max(1,model.get("fps"))},set:{if model.get("fps") != 0 {model.set("fps",min(1000,max(1,$0)))}}),formatter:NumberFormatter.coeditorInteger).frame(width:75)
                        Stepper("",value:Binding(get:{max(1,model.get("fps"))},set:{if model.get("fps") != 0 {model.set("fps",$0)}}),in:1...1000).labelsHidden()
                        Text("FPS").foregroundStyle(.secondary);Spacer()
                    }.disabled(model.get("fps")==0)
                    HStack {Text("提交节奏").frame(width:135,alignment:.leading);Picker("提交节奏",selection:Binding(get:{model.get("pacing")},set:{model.set("pacing",$0)})){Text("关闭").tag(0);Text("均衡").tag(1);Text("低延迟").tag(2)}.labelsHidden()}
                    Text("在领取下一帧缓冲前等待呈现进度；低延迟档限制更紧，可能降低帧率。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    }.disabled(!model.supportsFrameControl)
                    HStack {Toggle("实际呈现帧时间统计",isOn:model.binding("stats")).disabled(!model.supportsFrameControl);Spacer();Button("查看统计…"){model.showFrameStats=true}}
                    if !model.supportsFrameControl {Text("未检测到帧控制补丁，请先更新运行时组件。").font(.caption).foregroundStyle(.orange)}
                    Text("适用于 D3DMetal。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                }.padding(9)
            }
            GroupBox("输入") {
                VStack(alignment:.leading,spacing:10) {
                    if !model.isGlobal {
                        Toggle("沿用通用输入设置",isOn:Binding(get:{model.inheritsInput},set:{model.setInputInheritance($0)}))
                    }
                    Toggle("鼠标移动优化",isOn:model.binding("mouse")).disabled(!model.isGlobal && model.file.sections[model.selected]?["mouse"] == nil)
                    Text("保留已验收的 macOS 原生处理手感；关闭后使用原引擎输入。").font(.caption).foregroundStyle(.secondary)
                    Toggle("滚轮刻度优化",isOn:model.binding("wheel")).disabled(!model.isGlobal && model.file.sections[model.selected]?["wheel"] == nil)
                    Text("实体鼠标按 Windows 刻度处理，触控板保留原生滚动。").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,alignment:.leading).padding(9)
            }
            HStack(alignment:.top) {Image(systemName:model.healthy ? "checkmark.circle.fill":"exclamationmark.triangle.fill").foregroundStyle(model.healthy ? .green:.orange);Text(model.environment).font(.caption).textSelection(.enabled);Spacer();Button("检查环境"){model.check()} }
            Text(model.message).font(.caption).foregroundStyle(.secondary).frame(minHeight:18)
            HStack {Button("重新读取"){model.reload()};Spacer();Button("打开 Steam"){if model.save() && model.healthy {NSWorkspace.shared.open(URL(fileURLWithPath:"/Applications/Sevoflurane.app"))}};Button("保存设置"){model.save()}.keyboardShortcut("s",modifiers:.command).buttonStyle(.borderedProminent)}
        }.padding(22).frame(width:600).fixedSize(horizontal:false,vertical:true).disabled(model.busy)
        .background(GeometryReader{geometry in Color.clear.preference(key:ContentHeightKey.self,value:geometry.size.height)})
        }.frame(width:620,height:min(contentHeight,(NSScreen.main?.visibleFrame.height ?? 900)-70))
        .onPreferenceChange(ContentHeightKey.self){height in if abs(contentHeight-height)>1 {contentHeight=height;resize(height)}}
        .sheet(isPresented:$model.showFrameStats){FrameStatsView(profile:model.selected,name:model.label(model.selected))}
        .sheet(isPresented:$model.showGamePicker){GamePickerView(model:model)}
    }
}
final class AppDelegate:NSObject,NSApplicationDelegate {
    var window:NSWindow!
    func applicationDidFinishLaunching(_ notification:Notification) {
        let model=TunerModel();let view=NSHostingView(rootView:TunerView(model:model,resize:{[weak self] height in DispatchQueue.main.async {guard let window=self?.window else{return};let top=window.frame.maxY;window.setContentSize(NSSize(width:620,height:min(height,(window.screen?.visibleFrame.height ?? 900)-70)));window.setFrameOrigin(NSPoint(x:window.frame.minX,y:top-window.frame.height));let metrics:[String:Double]=["contentHeight":height,"windowContentHeight":window.contentRect(forFrameRect:window.frame).height];if let data=try? JSONEncoder().encode(metrics){try? data.write(to:Storage.support.appendingPathComponent("Tests/window-layout.json"),options:.atomic)}}}))
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:644,height:760),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.title="COEditor";window.contentView=view;window.setContentSize(view.fittingSize);window.center();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        let menu=NSMenu();let item=NSMenuItem();menu.addItem(item);let appMenu=NSMenu();appMenu.addItem(withTitle:"退出 COEditor",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q");item.submenu=appMenu;NSApp.mainMenu=menu
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {true}
}
func runTests() throws {
    let t=TuningFile("[cs2.exe]\nqueue=1\n[global]\nmouse=1\nwheel=0\nqueue=3\nsync=-1\ndrawables=0\n[other.exe]\nqueue=2\n")
    try t.validate();assert(t.value("queue",in:"CS2.EXE")==1);assert(t.value("wheel",in:"cs2.exe")==0)
    assert(TuningFile(t.serialized()).sections==t.sections)
    let broken=TuningFile("[global]\ndrawables=1\n");do {try broken.validate();throw TunerError.message("invalid buffer accepted")}catch TunerError.message(let s) {assert(s != "invalid buffer accepted")}
    let source="[Bottle]\n\"Version\" = \"26.3\"\n[EnvironmentVariables]\n\"CX_ROOT\" = \"old\"\n\"KEEP\" = \"unchanged\"\n\"DXMT_CONFIG\" = \"dxgi.customDeviceDesc = \"A B\"\"\n"
    let fixed=try Storage.repairedConfig(source,runtime:"/a path/runtime")
    assert(fixed.contains("\"KEEP\" = \"unchanged\""));assert(fixed.contains("\\\"A B\\\""));assert(!fixed.contains("\\/"));let twice=try Storage.repairedConfig(fixed,runtime:"/a path/runtime");assert(twice==fixed)
    func expect(_ condition:Bool,_ detail:String)throws {if !condition {throw TunerError.message(detail)}}
    let legacy=TuningFile("[global]\npreset=3\npreset_fps=144\nmouse=1\nwheel=1\nqueue=2\n[CS2.EXE]\npreset=4\npreset_fps=120\nsync=1\ndrawables=3\nqueue=16\nfps=120\npacing=2\nstats=1\nfuture_key=7\n")
    try legacy.validate()
    try expect(legacy.sections["cs2.exe"] == ["sync":1,"drawables":3,"queue":16,"fps":120,"pacing":2,"stats":1,"future_key":7],"移除旧预设标记不得改变实际参数")
    try expect(legacy.value("mouse",in:"cs2.exe")==1 && legacy.value("wheel",in:"cs2.exe")==1,"旧配置的通用输入继承应保留")
    try expect(!legacy.serialized().contains("preset"),"保存时不得继续写入旧预设标记")
    try expect(TuningFile(legacy.serialized()).sections==legacy.sections,"旧配置清理后应能完整往返")
    var manual=legacy
    manual.sections["cs2.exe"]?["queue"]=5
    manual.sections["cs2.exe"]?["fps"]=0
    manual.sections["cs2.exe"]?["pacing"]=0
    try manual.validate()
    let restored=TuningFile(manual.serialized())
    try expect(restored.value("queue",in:"cs2.exe")==5 && restored.value("fps",in:"cs2.exe")==0 && restored.value("pacing",in:"cs2.exe")==0 && restored.value("stats",in:"cs2.exe")==1,"独立调整不得联动改写其他参数")
    try expect(TuningFile.initial.value("sync",in:"cs2.exe")==(-1) && TuningFile.initial.value("drawables",in:"cs2.exe")==0 && TuningFile.initial.value("queue",in:"cs2.exe")==0,"新配置画面应跟随游戏")
    try runFrameStatsTests()
    let controls=TuningFile("[global]\nqueue=16\nfps=120\nstats=1\npacing=2\n[cs2.exe]\nfps=90\n")
    try controls.validate()
    try expect(controls.value("fps",in:"cs2.exe")==90 && controls.value("pacing",in:"cs2.exe")==2,"新参数继承失败")
    try expect(TuningFile().value("fps",in:"global")==0 && TuningFile().value("pacing",in:"global")==0,"旧配置必须默认关闭新功能")
    // No disk access or maintenance in model regressions: the fixture is the saved baseline.
    let draft=TunerModel(loadEnvironment:false)
    draft.acceptSaved(legacy);draft.selected="cs2.exe"
    try expect(!draft.hasUnsavedChanges && draft.message.isEmpty,"打开应用不得显示未保存")
    for key in ["mouse","wheel","sync","drawables","queue","fps","pacing","stats"] {draft.set(key,draft.get(key))}
    draft.setFollowingGame("drawables",false,manualValue:3)
    draft.setFollowingGame("queue",false,manualValue:2)
    draft.setFrameLimitEnabled(true)
    try expect(!draft.hasUnsavedChanges && draft.message.isEmpty && draft.file==legacy,"控件回写相同数值不得创建覆盖或显示未保存")
    draft.selected="global";draft.selected="cs2.exe"
    try expect(!draft.hasUnsavedChanges,"切换游戏不应修改配置")
    draft.set("queue",5)
    try expect(draft.hasUnsavedChanges && draft.message=="有未保存的修改","实际编辑必须显示未保存")
    draft.set("queue",16)
    try expect(!draft.hasUnsavedChanges && draft.message.isEmpty,"改回保存值应清除未保存提示")
    draft.set("sync",0);draft.set("sync",1)
    try expect(!draft.hasUnsavedChanges && draft.inheritsInput,"撤销编辑应保留输入继承")
    draft.setInputInheritance(false)
    try expect(draft.hasUnsavedChanges && !draft.inheritsInput && draft.file.sections["cs2.exe"]?["wheel"]==1,"关闭继承必须写入明确的输入覆盖")
    draft.set("wheel",0);draft.set("wheel",1)
    try expect(!draft.inheritsInput && draft.file.sections["cs2.exe"]?["wheel"]==1,"独立输入编辑改回原值不得意外恢复单个键的继承")
    draft.setInputInheritance(true)
    try expect(!draft.hasUnsavedChanges && draft.message.isEmpty,"恢复原有继承应清除未保存提示")
    draft.set("fps",144);let saved=draft.file;draft.acceptSaved(saved)
    try expect(!draft.hasUnsavedChanges,"保存成功应更新比较基线")
    draft.set("fps",120);draft.acceptSaved(saved)
    try expect(!draft.hasUnsavedChanges && draft.get("fps")==144,"重新读取应丢弃草稿并更新基线")
    draft.acceptSaved(.initial);draft.selected="global"
    draft.setFollowingGame("drawables",true,manualValue:3);draft.setFollowingGame("queue",true,manualValue:2);draft.setFrameLimitEnabled(false)
    try expect(!draft.hasUnsavedChanges,"跟随游戏和关闭限帧的同状态回写不得写入默认数值")
    draft.setFollowingGame("drawables",false,manualValue:3);draft.setFrameLimitEnabled(true)
    try expect(draft.hasUnsavedChanges && draft.get("drawables")==3 && draft.get("fps")==120,"实际切换开关应写入数值")
    print("PASS: clean startup, no-op control callbacks, scope switching, edit/revert, input inheritance and saved baselines")
    print("PASS: legacy preset metadata removal, unchanged runtime values, independent manual edits and neutral defaults")
    print("PASS: inheritance, case-insensitive profiles, round-trip, invalid values, config preservation and idempotent repair")
}
@main struct TunerMain {static func main() {
if CommandLine.arguments.contains("--list-games") {
    do {let games=try SteamLibrary.scan();let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes];print(String(data:try encoder.encode(games),encoding:.utf8)!);exit(0)}catch {fputs("\(error)\n",stderr);exit(1)}
} else if CommandLine.arguments.contains("--library-test") {
    do {try runLibraryTests();exit(0)}catch {fputs("\(error)\n",stderr);exit(1)}
} else if CommandLine.arguments.contains("--self-test") {
    do {try runTests();exit(0)}catch {fputs("\(error)\n",stderr);exit(1)}
} else if let i=CommandLine.arguments.firstIndex(of:"--register-game"), i+1<CommandLine.arguments.count {
    do {try Storage.registerGame(URL(fileURLWithPath:CommandLine.arguments[i+1]));print("Game registered");exit(0)}catch {fputs("\(error.localizedDescription)\n",stderr);exit(1)}
} else if CommandLine.arguments.contains("--maintain") || CommandLine.arguments.contains("--verify") {
    let r=Storage.maintain(repair:CommandLine.arguments.contains("--maintain"));if let data=try? JSONEncoder().encode(r),let s=String(data:data,encoding:.utf8){print(s)};exit(r.ok ? 0:1)
} else {
    let app=NSApplication.shared;let delegate=AppDelegate();app.delegate=delegate;app.setActivationPolicy(.regular);withExtendedLifetime(delegate){app.run()}
}
}}
