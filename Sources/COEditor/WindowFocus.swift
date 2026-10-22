import AppKit
import SwiftUI

// Give the window a neutral first responder instead of its first text field.
final class TunerHostingView<Content:View>:NSHostingView<Content> {
    override var acceptsFirstResponder:Bool {true}
}
final class TunerWindow:NSWindow {
    func installContent(_ view:NSView) {
        contentView=view;initialFirstResponder=view;clearInputFocus()
    }
    func clearInputFocus() {if let view=contentView {makeFirstResponder(view)}}
    override func resignKey() {clearInputFocus();super.resignKey()}
}

func runWindowFocusTests() throws {
    func expect(_ condition:Bool,_ message:String)throws {if !condition {throw TunerError.message(message)}}
    let app=NSApplication.shared;app.setActivationPolicy(.regular)
    let model=TunerModel(loadEnvironment:false)
    model.acceptSaved(TuningFile("[global]\nfps=120\n"));model.selected="global";model.supportsFrameControl=true
    let view=TunerHostingView(rootView:TunerView(model:model,resize:{_ in}))
    let window=TunerWindow(contentRect:NSRect(x:0,y:0,width:620,height:800),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.installContent(view);window.makeKeyAndOrderFront(nil)
    defer {window.orderOut(nil)}
    view.layoutSubtreeIfNeeded()
    RunLoop.current.run(until:Date().addingTimeInterval(0.1))
    try expect(window.initialFirstResponder === view && window.firstResponder === view,"启动时不得聚焦数字输入框")
    func fields(_ node:NSView)->[NSTextField] {
        (node as? NSTextField).map {[$0]} ?? node.subviews.flatMap(fields)
    }
    guard let field=fields(view).first(where:{$0.isEditable && $0.isEnabled}) else {throw TunerError.message("未找到实际帧率输入框")}
    let saved=model.file
    func strayKey() {
        if let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"9",charactersIgnoringModifiers:"9",isARepeat:false,keyCode:25) {window.sendEvent(event)}
    }
    strayKey()
    try expect(model.file==saved && field.currentEditor()==nil,"默认焦点下按键不得编辑帧率")
    field.selectText(nil)
    try expect(field.currentEditor() != nil,"用户主动选择后必须仍能编辑")
    window.resignKey();window.makeKey()
    RunLoop.current.run(until:Date().addingTimeInterval(0.05))
    try expect(window.firstResponder === view && field.currentEditor()==nil,"返回窗口时不得保留数字输入焦点")
    strayKey()
    try expect(model.file==saved && !model.hasUnsavedChanges,"切回窗口后误触按键不得修改参数")
    print("PASS: actual FPS field has no startup focus, explicit editing works, returning clears focus, stray keys preserve settings")
}
