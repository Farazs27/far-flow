import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root=URL(fileURLWithPath:CommandLine.arguments[1])
let master=root.appendingPathComponent("brand/assets/far-flow-studio-icon.png")
func render(_ size:Int,to url:URL) {
    let color=CGColorSpaceCreateDeviceRGB()
    guard let ctx=CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:size*4,space:color,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)else{fatalError("Bitmap")}
    ctx.scaleBy(x:CGFloat(size)/1024,y:CGFloat(size)/1024)
    ctx.setFillColor(CGColor(red:0.09,green:0.09,blue:0.08,alpha:1))
    ctx.addPath(CGPath(roundedRect:CGRect(x:42,y:42,width:940,height:940),cornerWidth:210,cornerHeight:210,transform:nil));ctx.fillPath()
    ctx.translateBy(x:294,y:765);ctx.scaleBy(x:13,y:-13)
    let p=CGMutablePath();p.move(to:CGPoint(x:10,y:2));p.addLine(to:CGPoint(x:32,y:2));p.addLine(to:CGPoint(x:28,y:7));p.addLine(to:CGPoint(x:2,y:7));p.addCurve(to:CGPoint(x:10,y:2),control1:CGPoint(x:3,y:4),control2:CGPoint(x:6,y:2));p.closeSubpath()
    p.move(to:CGPoint(x:2,y:36));p.addLine(to:CGPoint(x:2,y:23));p.addCurve(to:CGPoint(x:13,y:12),control1:CGPoint(x:2,y:16),control2:CGPoint(x:6,y:12));p.addLine(to:CGPoint(x:29,y:12));p.addCurve(to:CGPoint(x:23,y:18),control1:CGPoint(x:28,y:16),control2:CGPoint(x:26,y:18));p.addLine(to:CGPoint(x:15,y:18));p.addCurve(to:CGPoint(x:8,y:25),control1:CGPoint(x:10,y:18),control2:CGPoint(x:8,y:20));p.addLine(to:CGPoint(x:8,y:31));p.closeSubpath()
    ctx.setFillColor(CGColor(red:0.96,green:0.945,blue:0.9,alpha:1));ctx.addPath(p);ctx.fillPath()
    guard let image=ctx.makeImage(),let dst=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil)else{fatalError("PNG")}
    CGImageDestinationAddImage(dst,image,nil);CGImageDestinationFinalize(dst)
}
render(1024,to:master)
let catalog=root.appendingPathComponent("FarFlow/Resources/Assets.xcassets/FarFlowAppIcon.appiconset")
let data=try Data(contentsOf:catalog.appendingPathComponent("Contents.json"))
let spec=try JSONSerialization.jsonObject(with:data) as! [String:Any]
for image in spec["images"] as! [[String:Any]] {
    guard let name=image["filename"] as? String,let size=image["size"] as? String,let scale=image["scale"] as? String else{continue}
    let pixels=Int(size.split(separator:"x")[0])! * Int(scale.prefix(1))!
    render(pixels,to:catalog.appendingPathComponent(name))
}
render(512,to:root.appendingPathComponent("FarFlow/Resources/Assets.xcassets/AppMark.imageset/mark.png"))
