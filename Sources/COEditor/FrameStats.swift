import Foundation
import SwiftUI
import Combine

struct FrameSnapshot: Decodable {
    let version: Int
    let profile: String
    let pid: Int
    let lastPresented: Double
    let width, height: Double
    let samples: Int
    let fps, meanMs, p95Ms, p99Ms, low1Fps, maxMs: Double
    let intervalsMs: [Double]
    let limitFps, pacing, feedbackTimeouts: Int

    var age: Double { ProcessInfo.processInfo.systemUptime - lastPresented }
    var active: Bool { age >= 0 && age < 3 }
    static func read(directory: URL, profile: String) -> FrameSnapshot? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let snapshots = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []).compactMap { url -> FrameSnapshot? in
            guard url.pathExtension == "json", let data = try? Data(contentsOf: url),
                  let item = try? decoder.decode(Self.self, from: data), item.version == 1,
                  item.samples > 0, item.lastPresented.isFinite,
                  item.intervalsMs.allSatisfy({ $0.isFinite && $0 > 0 }),
                  profile == "global" || item.profile.lowercased() == profile.lowercased()
            else { return nil }
            return item
        }
        // Prefer the largest currently presenting surface, rather than a small
        // auxiliary layer. With no live surface, retain the latest sample.
        let live = snapshots.filter(\.active)
        return live.max { $0.width * $0.height < $1.width * $1.height }
            ?? snapshots.max { $0.lastPresented < $1.lastPresented }
    }
}

struct FrameStatsView: View {
    var profile: String
    var name: String
    @State private var snapshot: FrameSnapshot?
    @Environment(\.dismiss) private var dismiss
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private func refresh() {
        snapshot = FrameSnapshot.read(directory: Storage.bottle.appendingPathComponent("drive_c/.cx-frame-stats"), profile: profile)
    }
    private func metric(_ title: String, _ value: Double?, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value.map { String(format: "%.1f", $0) + unit } ?? "—").monospacedDigit().font(.title3)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("实际呈现帧时间").font(.title3.bold()); Spacer(); Button("完成") { dismiss() } }
            Text(name).font(.headline)
            if let s = snapshot {
                HStack { Text(s.active ? "正在采样" : "采样已暂停").foregroundStyle(s.active ? .green : .secondary); Spacer(); Text("\(s.profile) · \(Int(s.width)) × \(Int(s.height))").foregroundStyle(.secondary) }.font(.caption)
                HStack { metric("呈现帧率", s.fps, " FPS"); metric("平均帧时间", s.meanMs, " ms"); metric("1% Low（呈现）", s.samples >= 100 ? s.low1Fps : nil, " FPS") }
                HStack { metric("P95 帧时间", s.p95Ms, " ms"); metric("P99 帧时间", s.p99Ms, " ms"); metric("最长帧间隔", s.maxMs, " ms") }
                FrameGraph(intervals: Array(s.intervalsMs.suffix(180))).frame(height: 125)
                Text("最近 \(s.samples) 个呈现间隔 · 限帧：\(s.limitFps == 0 ? "跟随游戏" : String(s.limitFps)) · 提交节奏：\(["关闭", "均衡", "低延迟"][min(2,max(0,s.pacing))])").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("尚无采样。开启实际呈现统计，保存设置并重启对应游戏。").foregroundStyle(.secondary).frame(height: 150)
            }
            Text("按画面真正上屏的间隔统计，不代表输入到显示的总延迟。1% Low 至少需要 100 个间隔。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(22).frame(width: 570).onAppear(perform: refresh).onReceive(timer) { _ in refresh() }
    }
}

struct FrameGraph: View {
    let intervals: [Double]
    var body: some View {
        GeometryReader { geometry in
            let peak = max(16.67, intervals.max() ?? 0) * 1.1
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.07))
                Path { p in
                    guard intervals.count > 1 else { return }
                    for (i, time) in intervals.enumerated() {
                        let point = CGPoint(x: CGFloat(i) / CGFloat(intervals.count-1) * geometry.size.width, y: geometry.size.height * (1 - time / peak))
                        if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
                    }
                }.stroke(Color.blue, lineWidth: 1.4)
                Text(String(format: "%.1f ms", peak)).font(.caption2).foregroundStyle(.secondary).padding(5)
            }
        }.accessibilityLabel("最近的实际呈现帧间隔曲线")
    }
}

func runFrameStatsTests() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    func fixture(_ profile: String, _ size: Int, _ age: Double) -> [String: Any] {
        ["version":1,"profile":profile,"pid":123,"last_presented":ProcessInfo.processInfo.systemUptime-age,
         "width":size,"height":size,"samples":120,"fps":120.0,"mean_ms":8.33,"p95_ms":8.4,
         "p99_ms":16.6,"low1_fps":60,"max_ms":16.6,"intervals_ms":[8.3,8.4,16.6],
         "limit_fps":120,"pacing":1,"feedback_timeouts":0]
    }
    func save(_ json: [String: Any], _ file: String) throws {
        try JSONSerialization.data(withJSONObject: json).write(to: directory.appendingPathComponent(file))
    }
    try save(fixture("cs2.exe", 100, 0), "small.json")
    try save(fixture("cs2.exe", 1920, 0), "game.json")
    try save(fixture("other.exe", 3000, 0), "other.json")
    try Data("partial".utf8).write(to: directory.appendingPathComponent("partial.json"))
    guard let sample = FrameSnapshot.read(directory: directory, profile: "CS2.EXE"), sample.width == 1920,
          sample.low1Fps == 60, sample.active, sample.pacing == 1 else { throw TunerError.message("帧统计按游戏筛选或曲面选择失败") }
    try save(fixture("other.exe", 3000, 10), "other.json")
    guard FrameSnapshot.read(directory: directory, profile: "global")?.profile == "cs2.exe" else { throw TunerError.message("过期采样不应覆盖正在运行的游戏") }
    guard FrameSnapshot.read(directory: directory, profile: "missing.exe") == nil else { throw TunerError.message("不得显示其他游戏的采样") }
    print("PASS: frame JSON decoding, per-game filtering, largest live surface, stale samples and partial write tolerance")
}
