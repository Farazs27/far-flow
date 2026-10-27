import SwiftUI
import CoreText

enum FlowTheme {
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor:NSColor(name:nil) { appearance in
            let n=appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? dark:light
            return NSColor(red:Double((n>>16)&255)/255,green:Double((n>>8)&255)/255,blue:Double(n&255)/255,alpha:1)
        })
    }
    static let background=adaptive(0xF6F3EB,0x24231F)
    static let surface=adaptive(0xF3F0E8,0x2B2A25)
    static let ink=adaptive(0x181815,0xF1EDE3)
    static let secondary=adaptive(0x625F57,0xBDB7AA)
    static let line=adaptive(0xD8D3C8,0x4C4941)
    static let sidebar=Color(red:0.105,green:0.10,blue:0.085)
    static let sidebarInk=Color(red:0.94,green:0.925,blue:0.89)
    static let green=adaptive(0x596D43,0xBBC88A)
    static let accent=green
    static let signal=Color(red:0.65,green:0.76,blue:0.41)
    static func body(_ size:CGFloat=13,weight:Font.Weight = .regular)->Font { .custom("ZalandoSans-Regular",size:size).weight(weight) }
    static func registerFonts() {
        for name in ["ZalandoSans","Archivo","Marcellus-Regular"] {
            if let url=Bundle.main.url(forResource:name,withExtension:"ttf") ?? Bundle.main.url(forResource:name,withExtension:"ttf",subdirectory:"Fonts") { CTFontManagerRegisterFontsForURL(url as CFURL,.process,nil) }
        }
    }
}

/// The first approved concept's flowing F, preserved as scalable native geometry.
struct FlowMark: Shape {
    func path(in rect:CGRect)->Path {
        var p=Path()
        p.move(to:CGPoint(x:10,y:2));p.addLine(to:CGPoint(x:32,y:2));p.addLine(to:CGPoint(x:28,y:7));p.addLine(to:CGPoint(x:2,y:7));p.addCurve(to:CGPoint(x:10,y:2),control1:CGPoint(x:3,y:4),control2:CGPoint(x:6,y:2));p.closeSubpath()
        p.move(to:CGPoint(x:2,y:36));p.addLine(to:CGPoint(x:2,y:23));p.addCurve(to:CGPoint(x:13,y:12),control1:CGPoint(x:2,y:16),control2:CGPoint(x:6,y:12));p.addLine(to:CGPoint(x:29,y:12));p.addCurve(to:CGPoint(x:23,y:18),control1:CGPoint(x:28,y:16),control2:CGPoint(x:26,y:18));p.addLine(to:CGPoint(x:15,y:18));p.addCurve(to:CGPoint(x:8,y:25),control1:CGPoint(x:10,y:18),control2:CGPoint(x:8,y:20));p.addLine(to:CGPoint(x:8,y:31));p.closeSubpath()
        return p.applying(CGAffineTransform(scaleX:rect.width/34,y:rect.height/38)).offsetBy(dx:rect.minX,dy:rect.minY)
    }
}

struct FlowActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(FlowTheme.body(13,weight:.medium)).foregroundStyle(FlowTheme.background)
            .padding(.horizontal,22).frame(minHeight:40).background(FlowTheme.ink.opacity(configuration.isPressed ? 0.8:1),in:RoundedRectangle(cornerRadius:8)).opacity(enabled ? 1:0.4)
    }
}
struct FlowUtilityStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(FlowTheme.body(12)).foregroundStyle(configuration.role == .destructive ? Color.red:FlowTheme.ink)
            .padding(.horizontal,10).frame(minHeight:30).background(configuration.isPressed ? FlowTheme.line.opacity(0.45):Color.clear,in:RoundedRectangle(cornerRadius:7)).overlay(RoundedRectangle(cornerRadius:7).strokeBorder(FlowTheme.line,lineWidth:0.7)).opacity(enabled ? 1:0.4)
    }
}
struct PageHeading<Actions:View>:View {
    let title:String;let subtitle:String;@ViewBuilder var actions:()->Actions
    var body:some View { HStack(alignment:.center) {VStack(alignment:.leading,spacing:8){Text(title).font(FlowTheme.body(37,weight:.medium));Text(subtitle).font(FlowTheme.body(14)).foregroundStyle(FlowTheme.secondary)};Spacer();actions()}.padding(.bottom,28) }
}
struct EmptyFlow:View {
    let symbol:String;let title:String;let detail:String
    var body:some View { VStack(spacing:14){Image(systemName:symbol).font(.system(size:27,weight:.light)).foregroundStyle(FlowTheme.green);Text(title).font(FlowTheme.body(20,weight:.medium));Text(detail).font(FlowTheme.body(14)).foregroundStyle(FlowTheme.secondary).multilineTextAlignment(.center).frame(maxWidth:380)}.frame(maxWidth:.infinity).padding(.vertical,50) }
}
struct StatusDot:View {var ready=true;var body:some View {Circle().fill(ready ? FlowTheme.green:Color.orange).frame(width:7,height:7).accessibilityHidden(true)}}
struct SectionLabel:View {let title:String;var body:some View {Text(title).font(FlowTheme.body(11,weight:.medium)).foregroundStyle(FlowTheme.secondary)}}

/// Standard switch interaction with a stable app-green on state, including inactive windows.
struct FlowSwitchStyle:ToggleStyle {
    func makeBody(configuration:Configuration)->some View {
        Button{configuration.isOn.toggle()}label:{
            Capsule().fill(configuration.isOn ? FlowTheme.green:FlowTheme.line)
                .overlay(alignment:configuration.isOn ? .trailing:.leading){Circle().fill(.white).padding(2)}
                .frame(width:32,height:18).frame(width:36,height:26)
        }.buttonStyle(.plain)
        .accessibilityRepresentation{Toggle(isOn:configuration.$isOn){configuration.label}.toggleStyle(.switch)}
    }
}
