import AppKit
import SwiftUI
import QuartzCore
import FarFlowCore

@MainActor final class RecordingPanel {
    private let panel:NSPanel
    private weak var model:AppModel?
    private var dragAnchor:NSPoint?
    init(model:AppModel) {
        self.model=model
        panel=NSPanel(contentRect:NSRect(origin:.zero,size:RecordingBarGeometry.idleSize),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isFloatingPanel=true;panel.level = .floating;panel.backgroundColor = .clear;panel.isOpaque=false;panel.hasShadow=true
        panel.hidesOnDeactivate=false;panel.isMovableByWindowBackground=false;panel.isReleasedWhenClosed=false
        panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary]
        panel.title="Far Flow recording controls";panel.contentView=RecordingHostingView(rootView:RecordingBar(model:model));panel.setAccessibilityLabel("Far Flow recording controls")
    }
    private var expanded:Bool {model?.state.busy == true}
    func show() {
        if !panel.isVisible,let model {
            let mouse=NSEvent.mouseLocation
            if let screen=NSScreen.screens.first(where:{$0.frame.contains(mouse)}) ?? NSScreen.main {
                let prefs=model.data.preferences, bounds=screen.visibleFrame
                let center=CGFloat(prefs.barCenterX ?? prefs.overlayX.map{$0+72} ?? bounds.midX)
                let bottom=CGFloat(prefs.barBottomY ?? prefs.overlayY ?? bounds.minY+14)
                let targetScreen=NSScreen.screens.first(where:{$0.visibleFrame.contains(CGPoint(x:center,y:bottom+15))}) ?? screen
                panel.setFrame(RecordingBarGeometry.frame(centerX:center,bottomY:bottom,expanded:expanded,bounds:targetScreen.visibleFrame),display:false)
            }
        }
        updateLayout(animated:false);panel.orderFrontRegardless()
    }
    func updateLayout(animated:Bool=true) {
        guard dragAnchor==nil,let screen=NSScreen.screens.first(where:{$0.frame.intersects(panel.frame)}) ?? NSScreen.main else{return}
        let target=RecordingBarGeometry.frame(centerX:panel.frame.midX,bottomY:panel.frame.minY,expanded:expanded,bounds:screen.visibleFrame)
        guard target != panel.frame else{return}
        if animated && panel.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {NSAnimationContext.runAnimationGroup{context in context.duration=0.2;context.timingFunction=CAMediaTimingFunction(name:.easeOut);panel.animator().setFrame(target,display:true)}}else{panel.setFrame(target,display:true)}
    }
    func hideUnlessPersistent(){if model?.data.preferences.alwaysShowBar != true{panel.orderOut(nil)}}
    func hideAfterDelay(){Task{try? await Task.sleep(for:.seconds(1.5));if self.model?.state == .idle && self.dragAnchor==nil{self.hideUnlessPersistent()}}}
    func dragToMouse(){let mouse=NSEvent.mouseLocation;if dragAnchor==nil{dragAnchor=NSPoint(x:mouse.x-panel.frame.minX,y:mouse.y-panel.frame.minY)};if let anchor=dragAnchor{panel.setFrameOrigin(NSPoint(x:mouse.x-anchor.x,y:mouse.y-anchor.y))}}
    func finishDragging(){
        dragAnchor=nil
        if let screen=NSScreen.screens.first(where:{$0.frame.contains(NSEvent.mouseLocation)}) ?? NSScreen.main {
            let frame=RecordingBarGeometry.frame(centerX:panel.frame.midX,bottomY:panel.frame.minY,expanded:expanded,bounds:screen.visibleFrame)
            panel.setFrame(frame,display:true);model?.data.preferences.barCenterX=frame.midX;model?.data.preferences.barBottomY=frame.minY
        }
    }
    func resetPosition(){if let screen=NSScreen.main{panel.setFrame(RecordingBarGeometry.frame(centerX:screen.visibleFrame.midX,bottomY:screen.visibleFrame.minY+14,expanded:expanded,bounds:screen.visibleFrame),display:true)}}
    func close(){panel.orderOut(nil);panel.close()}
}
private final class RecordingHostingView<Content:View>:NSHostingView<Content>{override func acceptsFirstMouse(for event:NSEvent?)->Bool{true}}

struct RecordingBar:View {
    @Bindable var model:AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var expanded:Bool {model.state.busy}
    var body:some View {
        HStack(spacing:11){
            if expanded {FlowMark().fill(Color(white:0.94)).frame(width:17,height:20)}
            else {Button{model.toggleRecording()}label:{FlowMark().fill(Color(white:0.94)).frame(width:16,height:19).frame(width:25,height:28)}.buttonStyle(.plain).help(model.canRecord ? "Start hands-free dictation":"Loading local speech model").disabled(!model.canRecord).accessibilityLabel("Start hands-free dictation")}
            if model.state == .recording {
                Rectangle().fill(.white.opacity(0.15)).frame(width:0.5,height:19)
                TimelineView(.animation(minimumInterval:0.08,paused:reduceMotion)){context in
                    let phase=context.date.timeIntervalSinceReferenceDate
                    HStack(spacing:2){ForEach(0..<29){i in
                        let envelope=max(0.12,1-abs(Double(i)-14)/15)
                        RoundedRectangle(cornerRadius:1).fill(FlowTheme.signal).frame(width:2,height:2+CGFloat(model.meter)*25*envelope*CGFloat(0.35+0.65*abs(sin(phase*5+Double(i)*0.55))))
                    }}.frame(width:114,height:26)
                }.accessibilityLabel("Microphone waveform")
                Button{model.stopRecording()}label:{Image(systemName:"stop.fill").font(.system(size:9)).frame(width:26,height:26).overlay(Circle().stroke(.white.opacity(0.3),lineWidth:0.7))}.buttonStyle(.plain).help("Stop dictation").accessibilityLabel("Stop dictation")
            }else if expanded {
                Spacer(minLength:0);ProgressView().controlSize(.small).colorScheme(.dark).accessibilityLabel(model.state.title);Spacer(minLength:0)
                if model.state != .inserting {Button{model.cancelRecording()}label:{Image(systemName:"xmark").font(.system(size:10)).frame(width:26,height:26)}.buttonStyle(.plain).help("Cancel dictation")}
            }else {Circle().fill(model.canRecord ? FlowTheme.signal:.orange).frame(width:5,height:5).accessibilityLabel(model.canRecord ? "Far Flow ready. Microphone off.":"Loading speech model")}
        }.padding(.horizontal,13).frame(width:expanded ? RecordingBarGeometry.expandedSize.width:RecordingBarGeometry.idleSize.width,height:expanded ? RecordingBarGeometry.expandedSize.height:RecordingBarGeometry.idleSize.height)
        .foregroundStyle(.white).background(Color(red:0.055,green:0.055,blue:0.045),in:Capsule()).overlay(Capsule().strokeBorder(.white.opacity(0.13),lineWidth:0.6))
        .contentShape(Capsule()).gesture(DragGesture(minimumDistance:3).onChanged{_ in model.dragRecordingBar()}.onEnded{_ in model.finishDraggingRecordingBar()})
        .animation(reduceMotion ? nil:.easeOut(duration:0.2),value:expanded)
        .onChange(of:model.state){_,_ in model.resizeRecordingBar()}
        .help("Far Flow · Drag to move · Hold Fn to dictate")
        .contextMenu{Button("Open Far Flow"){model.openHub()};if !model.lastText.isEmpty{Button("Copy last dictation"){InsertionService.copy(model.lastText)}};Button("Reset position"){model.resetRecordingBarPosition()};Divider();Button("Quit Far Flow"){NSApp.terminate(nil)}}
    }
}
