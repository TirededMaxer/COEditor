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
    override func sendEvent(_ event:NSEvent) {
        if event.type == .leftMouseDown,let content=contentView,
           let editor=firstResponder as? NSTextView,editor.isFieldEditor {
            var hit=content.hitTest(content.convert(event.locationInWindow,from:nil))
            var textInput=false
            while let node=hit {
                if let field=node as? NSTextField,field.isEditable {textInput=true;break}
                if let text=node as? NSTextView,text.isEditable {textInput=true;break}
                hit=node.superview
            }
            if !textInput {clearInputFocus()}
        }
        super.sendEvent(event)
    }
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
    // The form has 22 pt padding, so this point lies in its actual blank area.
    let blank=view.convert(NSPoint(x:5,y:5),to:nil)
    for type in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
        guard let event=NSEvent.mouseEvent(with:type,location:blank,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1) else {throw TunerError.message("无法创建空白点击事件")}
        window.sendEvent(event)
    }
    RunLoop.current.run(until:Date().addingTimeInterval(0.05))
    try expect(field.currentEditor()==nil,"点击空白处必须结束数字编辑")
    strayKey()
    try expect(model.file==saved && !model.hasUnsavedChanges,"空白处取消焦点后误触键盘不得修改参数")
    field.selectText(nil)
    try expect(field.currentEditor() != nil,"取消编辑后必须能再次主动编辑输入框")
    window.resignKey();window.makeKey()
    RunLoop.current.run(until:Date().addingTimeInterval(0.05))
    try expect(window.firstResponder === view && field.currentEditor()==nil,"返回窗口时不得保留数字输入焦点")
    strayKey()
    try expect(model.file==saved && !model.hasUnsavedChanges,"切回窗口后误触按键不得修改参数")
    print("PASS: actual FPS field has no startup focus, blank click ends editing, editing can resume, returning clears focus, stray keys preserve settings")
}
