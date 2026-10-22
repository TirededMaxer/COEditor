import Foundation

func runWheelStatusTests() throws {
    func expect(_ condition:Bool,_ message:String)throws {if !condition {throw TunerError.message(message)}}
    let now=Date().timeIntervalSince1970,pid:Int32=1234
    func data(_ state:String,devices:Int=1,version:Int=2,readerPID:Int32=1234,updated:Double?=nil)->Data {
        Data("{\"protocol\":\(version),\"pid\":\(readerPID),\"state\":\"\(state)\",\"devices\":\(devices),\"reports\":3,\"clients\":1,\"openError\":5,\"updated\":\(updated ?? now)}".utf8)
    }
    func active(_ bytes:Data?)->WheelReaderPresentation {WheelReaderStatus.presentation(bytes,installed:true,configured:true,runningPID:pid,now:now)}
    let missing=WheelReaderStatus.presentation(data("ready"),installed:false,configured:true,runningPID:pid,now:now)
    try expect(missing.state == .notInstalled && missing.text.contains("未安装") && !missing.isHealthy,"缺少组件不能被旧状态标记为就绪")
    let idle=WheelReaderStatus.presentation(nil,installed:true,configured:true,now:now)
    try expect(idle.isHealthy && idle.text.contains("待命") && idle.symbol=="checkmark.circle.fill","已安装且正常待命应显示绿色对勾")
    let ready=active(data("ready"))
    try expect(ready.isHealthy && ready.text.contains("1 个程序") && ready.text.contains("1 个设备"),"活动读取器应显示实际设备和程序数")
    for (state,text) in [("permission-required","缺少输入监控"),("no-device","未检测到实体滚轮"),("open-error","错误码 0x5"),("setup","等待系统授权"),("unknown","状态异常")] {
        let status=active(data(state))
        try expect(status.state == .warning && status.text.contains(text) && status.symbol=="exclamationmark.triangle.fill","异常状态应显示对应原因："+state)
    }
    for error in ["-536870174","3758097122"] {
        let bytes=Data(String(decoding:data("open-error"),as:UTF8.self).replacingOccurrences(of:"\"openError\":5",with:"\"openError\":"+error).utf8)
        try expect(active(bytes).text.contains("设备打开失败") && active(bytes).text.contains("0xe00002e2"),"有符号或无符号 IOReturn 都应显示设备打开错误")
    }
    for bytes in [nil,Data("broken".utf8),data("ready",version:1),data("ready",readerPID:999),data("ready",updated:now-4),data("ready",updated:now+10)] as [Data?] {
        try expect(!active(bytes).isHealthy,"运行中缺失、过期或错误进程的状态不能显示绿色对勾")
    }
    try expect(!active(data("ready",devices:0)).isHealthy,"没有实体设备不能报告活动读取正常")
    let unregistered=WheelReaderStatus.presentation(nil,installed:true,now:now)
    try expect(unregistered.text.contains("未注册") && !unregistered.isHealthy,"安装与注册必须分别检查")
    let damaged=WheelReaderStatus.presentation(data("ready"),installed:true,installationIssue:"文件校验失败",configured:true,runningPID:pid,now:now)
    try expect(damaged.text=="文件校验失败" && !damaged.isHealthy,"安装异常必须优先于旧就绪状态")
    print("PASS: wheel missing/installed/idle/ready states, specific failures, icon semantics, stale status and process identity")
}
