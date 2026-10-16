import AppKit
let destination=CommandLine.arguments[1]
let iconset=URL(fileURLWithPath:destination)
try FileManager.default.createDirectory(at:iconset,withIntermediateDirectories:true)
for size in [16,32,128,256,512] { for scale in [1,2] {
 let px=size*scale;let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:px,pixelsHigh:px,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!;NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
 let r=NSRect(x:Double(px)*0.06,y:Double(px)*0.06,width:Double(px)*0.88,height:Double(px)*0.88)
 let path=NSBezierPath(roundedRect:r,xRadius:Double(px)*0.19,yRadius:Double(px)*0.19)
 NSColor(calibratedRed:0.12,green:0.38,blue:0.88,alpha:1).setFill();path.fill()
 if let symbol=NSImage(systemSymbolName:"slider.horizontal.3",accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:Double(px)*0.52,weight:.medium)) {
  let data=symbol.tiffRepresentation!;let tint=NSImage(data:data)!;tint.lockFocus();NSColor.white.set();NSRect(origin:.zero,size:tint.size).fill(using:.sourceIn);tint.unlockFocus()
  tint.draw(in:NSRect(x:Double(px)*0.21,y:Double(px)*0.24,width:Double(px)*0.58,height:Double(px)*0.52))
 }
 NSGraphicsContext.restoreGraphicsState()
 let filename="icon_\(size)x\(size)"+(scale==2 ? "@2x" : "")+".png"
 try bitmap.representation(using:.png,properties:[:])!.write(to:iconset.appendingPathComponent(filename))
}}
