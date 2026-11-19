// Run from the project root: swift tool/generate_app_icons.swift
// Native rendering of assets/brand/linkwallet.svg's vector geometry.
import AppKit
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor { CGColor(red:r/255, green:g/255, blue:b/255, alpha:1) }
func draw(_ size: Int) throws -> Data {
  let rep = NSBitmapImageRep(bitmapDataPlanes:nil, pixelsWide:size, pixelsHigh:size, bitsPerSample:8, samplesPerPixel:4, hasAlpha:true, isPlanar:false, colorSpaceName:.deviceRGB, bytesPerRow:0, bitsPerPixel:0)!
  let ctx = NSGraphicsContext(bitmapImageRep:rep)!.cgContext
  ctx.translateBy(x:0, y:CGFloat(size)); ctx.scaleBy(x:CGFloat(size)/1024, y: -CGFloat(size)/1024)
  ctx.saveGState()
  ctx.addPath(CGPath(roundedRect:CGRect(x:64,y:64,width:896,height:896),cornerWidth:200,cornerHeight:200,transform:nil)); ctx.clip()
  let gradient = CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[color(37,135,97),color(16,61,48)] as CFArray, locations:[0,1])!
  ctx.drawLinearGradient(gradient,start:CGPoint(x:144,y:100),end:CGPoint(x:850,y:940),options:[.drawsBeforeStartLocation,.drawsAfterEndLocation]); ctx.restoreGState()
  let outline = CGMutablePath(); outline.move(to:CGPoint(x:512,y:250))
  for p in [CGPoint(x:740,y:382),CGPoint(x:740,y:642),CGPoint(x:512,y:774),CGPoint(x:284,y:642),CGPoint(x:284,y:382)] { outline.addLine(to:p) }; outline.closeSubpath()
  ctx.addPath(outline); ctx.setStrokeColor(color(244,255,248)); ctx.setLineWidth(48); ctx.setLineJoin(.round); ctx.strokePath()
  ctx.setFillColor(color(188,233,206)); ctx.fillEllipse(in:CGRect(x:452,y:410,width:120,height:120))
  let stem = CGMutablePath(); stem.move(to:CGPoint(x:484,y:508)); for p in [CGPoint(x:540,y:508),CGPoint(x:558,y:616),CGPoint(x:466,y:616)] { stem.addLine(to:p) }; stem.closeSubpath(); ctx.addPath(stem); ctx.fillPath()
  ctx.setFillColor(color(229,199,127)); ctx.setStrokeColor(color(28,104,75)); ctx.setLineWidth(16); ctx.addEllipse(in:CGRect(x:697,y:339,width:86,height:86)); ctx.drawPath(using:.fillStroke)
  return rep.representation(using:.png,properties:[:])!
}
for size in [16,32,64,128,256,512,1024] {
  let png = try draw(size)
  try png.write(to:root.appendingPathComponent("macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_\(size).png"))
  if size == 1024 { try png.write(to:root.appendingPathComponent("assets/brand/linkwallet.png")) }
}
