import Foundation
public enum FarFlowVersion {
    public static var value: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    }
}
