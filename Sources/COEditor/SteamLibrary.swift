import Foundation

struct SteamKV {
    var value = ""
    var children: [String:SteamKV] = [:]
    subscript(_ key:String)->SteamKV {children[key.lowercased()] ?? SteamKV()}
}
struct SteamTextVDF {
    var bytes:[UInt8];var offset=0
    init(_ text:String){bytes=Array(text.utf8)}
    mutating func token()->String? {
        while offset<bytes.count {
            if bytes[offset]<=32 {offset+=1;continue}
            if bytes[offset]==47 && offset+1<bytes.count && bytes[offset+1]==47 {while offset<bytes.count && bytes[offset] != 10 {offset+=1};continue}
            break
        }
        guard offset<bytes.count else{return nil}
        let first=bytes[offset];offset+=1
        if first==123 || first==125 {return String(UnicodeScalar(first))}
        var result:[UInt8]=[]
        if first==34 {
            while offset<bytes.count {
                let c=bytes[offset];offset+=1
                if c==34 {break}
                if c==92 && offset<bytes.count {
                    let next=bytes[offset];offset+=1
                    result.append(next==110 ? 10:next==114 ? 13:next==116 ? 9:next)
                } else {result.append(c)}
            }
        } else {
            result.append(first)
            while offset<bytes.count && bytes[offset]>32 && bytes[offset] != 123 && bytes[offset] != 125 {result.append(bytes[offset]);offset+=1}
        }
        return String(decoding:result,as:UTF8.self)
    }
    mutating func object(_ depth:Int=0)->SteamKV {
        guard depth<64 else{return SteamKV()}
        var result=SteamKV()
        while let key=token(),key != "}" {
            guard let value=token() else{break}
            result.children[key.lowercased()]=value=="{" ? object(depth+1):SteamKV(value:value)
        }
        return result
    }
    static func read(_ url:URL)->SteamKV {guard let text=try? String(contentsOf:url,encoding:.utf8) else{return SteamKV()};var parser=SteamTextVDF(text);return parser.object()}
}
struct SteamBinaryReader {
    var data:Data;var offset=0;var strings:[String]=[]
    mutating func number(_ size:Int)throws->UInt64 {
        guard offset>=0,size<=8,offset<=data.count-size else{throw TunerError.message("Steam 游戏信息不完整")}
        defer {offset+=size};return (0..<size).reduce(UInt64(0)){$0 | (UInt64(data[offset+$1]) << (8*$1))}
    }
    mutating func string()throws->String {
        let start=offset
        while offset<data.count && data[offset] != 0 {offset+=1}
        guard offset<data.count else{throw TunerError.message("Steam 游戏信息不完整")}
        defer {offset+=1};return String(decoding:data[start..<offset],as:UTF8.self)
    }
    mutating func object(_ depth:Int=0)throws->SteamKV {
        guard depth<64 else{throw TunerError.message("Steam 游戏信息嵌套过深")}
        var result=SteamKV()
        while offset<data.count {
            let type=try number(1);if type==8 || type==11 {return result}
            let name:String
            if strings.isEmpty {name=try string()}
            else {let index=Int(try number(4));guard index<strings.count else{throw TunerError.message("Steam 游戏信息索引无效")};name=strings[index]}
            let item:SteamKV
            switch type {
            case 0:item=try object(depth+1)
            case 1:item=SteamKV(value:try string())
            case 2,3,4,6:item=SteamKV(value:String(try number(4)))
            case 7,10:item=SteamKV(value:String(try number(8)))
            case 5:
                let count=Int(try number(2));guard offset<=data.count-count*2 else{throw TunerError.message("Steam 游戏信息不完整")};offset+=count*2;item=SteamKV()
            default:throw TunerError.message("Steam 游戏信息格式暂不支持")
            }
            result.children[name.lowercased()]=item
        }
        throw TunerError.message("Steam 游戏信息缺少结束标记")
    }
    static func appInfo(_ url:URL,ids:Set<String>)throws->[String:SteamKV] {
        var reader=SteamBinaryReader(data:try Data(contentsOf:url,options:.mappedIfSafe))
        let magic=try reader.number(4);guard [0x07564427,0x07564428,0x07564429].contains(magic) else {throw TunerError.message("Steam 游戏信息版本暂不支持")}
        _=try reader.number(4)
        if magic==0x07564429 {
            let table=Int(try reader.number(8)),resume=reader.offset;reader.offset=table
            let count=Int(try reader.number(4));guard count<1_000_000 else{throw TunerError.message("Steam 游戏信息索引无效")}
            for _ in 0..<count {reader.strings.append(try reader.string())};reader.offset=resume
        }
        var result:[String:SteamKV]=[:]
        while reader.offset+4<=reader.data.count {
            let id=String(try reader.number(4));if id=="0" {break}
            let length=Int(try reader.number(4)),start=reader.offset,end=start+length
            guard length>=40,end<=reader.data.count else{throw TunerError.message("Steam 游戏记录不完整")}
            if ids.contains(id) {
                reader.offset=start+40+(magic>=0x07564428 ? 20:0)
                let parsed=try reader.object();guard reader.offset<=end else{throw TunerError.message("Steam 游戏记录边界无效")}
                result[id]=parsed["appinfo"]
            }
            reader.offset=end
        }
        return result
    }
}
struct GameExecutable:Identifiable,Codable,Hashable {
    var path:String;var relativePath:String;var launchName:String;var is64Bit:Bool
    var id:String {path}
    var profile:String {URL(fileURLWithPath:path).lastPathComponent.lowercased()}
}
struct InstalledSteamGame:Identifiable,Codable {
    var id:String;var name:String;var directory:String;var executables:[GameExecutable]
}
struct GameBinding:Codable {
    var appID:String;var name:String;var executable:String
}
struct SteamLibrary {
    static let fm=FileManager.default
    static var steam:URL {Storage.bottle.appendingPathComponent("drive_c/Program Files (x86)/Steam")}
    static func windowsPath(_ input:String,bottle:URL=Storage.bottle)->URL? {
        let path=input.replacingOccurrences(of:"\\",with:"/")
        if path.hasPrefix("/"){return URL(fileURLWithPath:path).standardizedFileURL}
        guard path.count>=3 else{return nil};let chars=Array(path)
        guard chars[1]==":" else{return nil}
        let drive=String(chars[0]).lowercased();let tail=String(chars.dropFirst(2)).trimmingCharacters(in:CharacterSet(charactersIn:"/"))
        let base:URL
        if drive=="c" {base=bottle.appendingPathComponent("drive_c")}
        else if drive=="z" {base=URL(fileURLWithPath:"/")}
        else {
            let link=bottle.appendingPathComponent("dosdevices/"+drive+":")
            guard fm.fileExists(atPath:link.path) else{return nil};base=link.resolvingSymlinksInPath()
        }
        return base.appendingPathComponent(tail).standardizedFileURL
    }
    static func architecture(_ url:URL)->Int? {
        guard let file=try? FileHandle(forReadingFrom:url) else{return nil};defer {try? file.close()}
        guard let dos=try? file.read(upToCount:64),dos.count==64,dos[0]==77,dos[1]==90 else{return nil}
        let offset=(0..<4).reduce(0){$0 | (UInt64(dos[60+$1]) << (8*$1))}
        do {try file.seek(toOffset:offset);guard let pe=try file.read(upToCount:6),pe.count==6,pe[0]==80,pe[1]==69,pe[2]==0,pe[3]==0 else{return nil};return Int(pe[4]) | Int(pe[5])<<8}catch{return nil}
    }
    static func executable(_ path:String,directory:URL,name:String)->GameExecutable? {
        let relative=path.replacingOccurrences(of:"\\",with:"/")
        let full=directory.appendingPathComponent(relative).standardizedFileURL
        guard full.path.hasPrefix(directory.standardizedFileURL.path+"/"),fm.fileExists(atPath:full.path),full.pathExtension.lowercased()=="exe",let arch=architecture(full),[0x8664,0x14c].contains(arch) else{return nil}
        return GameExecutable(path:full.path,relativePath:relative,launchName:name,is64Bit:arch==0x8664)
    }
    static func candidates(_ info:SteamKV,directory:URL,branch:String="public")->[GameExecutable] {
        var results:[GameExecutable]=[];var seen=Set<String>()
        let launch=info["config"]["launch"]
        for key in launch.children.keys.sorted(by:{(Int($0) ?? 0)<(Int($1) ?? 0)}) {
            let entry=launch[key],os=entry["config"]["oslist"].value.lowercased(),type=entry["type"].value.lowercased(),beta=entry["config"]["betakey"].value
            if !os.isEmpty && !os.components(separatedBy:",").map({$0.trimmingCharacters(in:.whitespaces)}).contains("windows") {continue}
            if !beta.isEmpty && beta != branch {continue}
            if entry["arguments"].value.contains("+app_set_config") || entry["arguments"].value.contains("+app_install") {continue}
            if ["server","tool"].contains(type) {continue}
            if let exe=executable(entry["executable"].value,directory:directory,name:entry["description"].value),seen.insert(exe.path.lowercased()).inserted {results.append(exe)}
        }
        if !results.isEmpty {return results}
        // Offline metadata may be absent. Offer existing candidates for explicit selection.
        let excluded=["redist","redistributable","directx","vcredist","installer","uninstall","crash","steamworks shared","_commonredist","easyanticheat","battleye"]
        guard let files=fm.enumerator(atPath:directory.path) else{return []}
        for case let relative as String in files {
            let lower=relative.lowercased(),file=directory.appendingPathComponent(relative)
            if relative.split(separator:"/").contains(where:{$0.hasPrefix(".")}) {files.skipDescendants();continue}
            if excluded.contains(where:lower.contains) {files.skipDescendants();continue}
            if file.pathExtension.lowercased()=="exe",let exe=executable(relative,directory:directory,name:"") {results.append(exe)}
        }
        return results.sorted{$0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending}
    }
    static func scan(at steamURL:URL=steam,bottle:URL=Storage.bottle)throws->[InstalledSteamGame] {
        let steam=steamURL.resolvingSymlinksInPath()
        var libraries=[steam.standardizedFileURL]
        let folders=SteamTextVDF.read(steam.appendingPathComponent("steamapps/libraryfolders.vdf"))["libraryfolders"]
        for item in folders.children.values {
            let path=item["path"].value.isEmpty ? item.value:item["path"].value
            if let url=windowsPath(path,bottle:bottle),!libraries.contains(url){libraries.append(url)}
        }
        var installed:[(String,String,URL,String)]=[]
        for library in libraries {
            let dir=library.appendingPathComponent("steamapps")
            for file in (try? fm.contentsOfDirectory(at:dir,includingPropertiesForKeys:nil)) ?? [] where file.lastPathComponent.hasPrefix("appmanifest_") && file.pathExtension=="acf" {
                let app=SteamTextVDF.read(file)["appstate"],id=app["appid"].value,name=app["name"].value,folder=app["installdir"].value
                guard !id.isEmpty,!name.isEmpty,!folder.isEmpty,id != "228980" else{continue}
                let directory=dir.appendingPathComponent("common/"+folder).standardizedFileURL
                guard directory.path.hasPrefix(dir.appendingPathComponent("common").path+"/"),fm.fileExists(atPath:directory.path) else{continue}
                let beta=app["userconfig"]["betakey"].value
                installed.append((id,name,directory,beta.isEmpty ? "public":beta))
            }
        }
        let metadata=(try? SteamBinaryReader.appInfo(steam.appendingPathComponent("appcache/appinfo.vdf"),ids:Set(installed.map{$0.0}))) ?? [:]
        var seen=Set<String>();var games:[InstalledSteamGame]=[]
        for (id,name,directory,branch) in installed where seen.insert(id).inserted {
            let info=metadata[id] ?? SteamKV(),type=info["common"]["type"].value.lowercased()
            if ["tool","config","dlc","music","video","hardware"].contains(type) {continue}
            games.append(InstalledSteamGame(id:id,name:name,directory:directory.path,executables:candidates(info,directory:directory,branch:branch)))
        }
        return games.sorted{$0.name.localizedStandardCompare($1.name) == .orderedAscending}
    }
}

func runLibraryTests()throws {
    func expect(_ ok:Bool,_ name:String)throws {if !ok {throw TunerError.message("Steam library test failed: "+name)}}
    let fm=FileManager.default,base=URL(fileURLWithPath:NSTemporaryDirectory()).resolvingSymlinksInPath().appendingPathComponent("tuner-library-"+UUID().uuidString)
    defer {try? fm.removeItem(at:base)}
    let bottle=base.appendingPathComponent("Bottle"),steam=bottle.appendingPathComponent("drive_c/Steam"),extra=base.appendingPathComponent("OtherLibrary")
    for dir in [steam.appendingPathComponent("steamapps/common/Game A/bin"),steam.appendingPathComponent("appcache"),extra.appendingPathComponent("steamapps/common/Game B"),bottle.appendingPathComponent("dosdevices")] {try fm.createDirectory(at:dir,withIntermediateDirectories:true)}
    try fm.createSymbolicLink(at:bottle.appendingPathComponent("dosdevices/d:"),withDestinationURL:extra)
    func write(_ text:String,_ url:URL)throws {try Data(text.utf8).write(to:url)}
    func pe(_ arch:UInt16,_ url:URL)throws {
        var bytes=Data(repeating:0,count:256);bytes[0]=77;bytes[1]=90;bytes[60]=128;bytes[128]=80;bytes[129]=69;bytes[132]=UInt8(arch&255);bytes[133]=UInt8(arch>>8);try bytes.write(to:url)
    }
    let directory=steam.appendingPathComponent("steamapps/common/Game A")
    try pe(0x8664,directory.appendingPathComponent("bin/Game.exe"));try pe(0x8664,directory.appendingPathComponent("linux.exe"));try pe(0x8664,directory.appendingPathComponent("crashhandler.exe"))
    try pe(0x14c,extra.appendingPathComponent("steamapps/common/Game B/B.exe"))
    try write("// libraries\n\"libraryfolders\" {\"0\" {\"path\" \"C:\\\\Steam\"} \"1\" {\"path\" \"D:\\\\\"}}",steam.appendingPathComponent("steamapps/libraryfolders.vdf"))
    try write("\"AppState\" {\"appid\" \"100\" \"name\" \"Game A\" \"installdir\" \"Game A\"}",steam.appendingPathComponent("steamapps/appmanifest_100.acf"))
    try write("\"AppState\" {\"appid\" \"228980\" \"name\" \"Steamworks Shared\" \"installdir\" \"Game A\"}",steam.appendingPathComponent("steamapps/appmanifest_228980.acf"))
    try write("\"AppState\" {\"appid\" \"200\" \"name\" \"Game B\" \"installdir\" \"Game B\"}",extra.appendingPathComponent("steamapps/appmanifest_200.acf"))
    try expect(SteamLibrary.windowsPath("D:\\steamapps",bottle:bottle)?.path==extra.appendingPathComponent("steamapps").path,"DOS drive mapping")
    // Build a minimal v41 record with an indexed key string table and Windows/Linux launch choices.
    let keys=["appinfo","common","type","config","launch","0","executable","oslist","1"]
    func n(_ value:UInt64,_ count:Int)->Data {Data((0..<count).map{UInt8((value >> ($0*8))&255)})}
    func value(_ key:String,_ text:String)->Data {var b=Data([1]);b.append(n(UInt64(keys.firstIndex(of:key)!),4));b.append(Data(text.utf8));b.append(0);return b}
    func object(_ key:String,_ content:Data)->Data {var b=Data([0]);b.append(n(UInt64(keys.firstIndex(of:key)!),4));b.append(content);b.append(8);return b}
    let linux=object("0",value("executable","linux.exe")+object("config",value("oslist","linux")))
    let windows=object("1",value("executable","bin\\Game.exe")+object("config",value("oslist","windows")))
    var kv=object("appinfo",object("common",value("type","game"))+object("config",object("launch",linux+windows)));kv.append(8)
    var record=n(100,4)+n(UInt64(60+kv.count),4)+Data(repeating:0,count:60);record.append(kv)
    var binary=n(0x07564429,4)+n(1,4)+n(UInt64(16+record.count+4),8);binary.append(record);binary.append(n(0,4));binary.append(n(UInt64(keys.count),4))
    for key in keys {binary.append(Data(key.utf8));binary.append(0)}
    let appInfo=steam.appendingPathComponent("appcache/appinfo.vdf");try binary.write(to:appInfo)
    let metadata=try SteamBinaryReader.appInfo(appInfo,ids:["100"])
    try expect(metadata["100"]?["common"]["type"].value=="game","binary v41 metadata")
    let games=try SteamLibrary.scan(at:steam,bottle:bottle)
    try expect(Set(games.map{$0.id})==["100","200"],"installed games across libraries; redistributables excluded")
    let a=games.first{$0.id=="100"}!,b=games.first{$0.id=="200"}!
    try expect(a.executables.count==1 && a.executables[0].relativePath=="bin/Game.exe" && a.executables[0].is64Bit,"exact Windows launch entry")
    try expect(b.executables.count==1 && !b.executables[0].is64Bit,"offline fallback and 32-bit identification: \(b)")
    try expect(SteamLibrary.executable("../outside.exe",directory:directory,name:"")==nil,"launch path containment")
    var truncated=binary;truncated.removeLast(5)
    do {_=try SteamBinaryReader.appInfo({let p=base.appendingPathComponent("truncated.vdf");try! truncated.write(to:p);return p}(),ids:["100"]);throw TunerError.message("truncated metadata accepted")}catch TunerError.message(let text) {try expect(text != "truncated metadata accepted","truncated metadata rejected")}
    print("PASS: local Steam manifests, multiple libraries, DOS paths, v41 metadata, exact Windows launch, 32-bit detection, fallback and path checks")
}
