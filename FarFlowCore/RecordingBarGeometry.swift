import CoreGraphics

public enum RecordingBarGeometry {
    public static let idleSize=CGSize(width:76,height:30)
    public static let expandedSize=CGSize(width:224,height:38)
    public static func frame(centerX:CGFloat,bottomY:CGFloat,expanded:Bool,bounds:CGRect)->CGRect {
        let size=expanded ? expandedSize:idleSize
        let x=min(max(centerX-size.width/2,bounds.minX+5),bounds.maxX-size.width-5)
        let y=min(max(bottomY,bounds.minY+5),bounds.maxY-size.height-5)
        return CGRect(origin:CGPoint(x:x,y:y),size:size)
    }
}
