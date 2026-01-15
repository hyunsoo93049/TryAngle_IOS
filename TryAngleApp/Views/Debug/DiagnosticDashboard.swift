import SwiftUI

// MARK: - Diagnostic Dashboard

public struct DiagnosticDashboard: View {
    @ObservedObject var pipeline: DetectionPipeline
    @ObservedObject var logger = PipelineLogger.shared
    
    // Toggle States
    @State private var showPose = true
    @State private var showDepth = false
    @State private var showSilhouette = false
    
    public init(pipeline: DetectionPipeline) {
        self.pipeline = pipeline
    }
    
    public var body: some View {
        VStack {
            Text("🔍 Diagnostic Dashboard")
                .font(.headline)
                .padding()
            
            // Toggles
            HStack {
                Toggle("Pose", isOn: $showPose)
                    .toggleStyle(.button)
                Toggle("Depth", isOn: $showDepth)
                    .toggleStyle(.button)
                Toggle("Mask", isOn: $showSilhouette)
                    .toggleStyle(.button)
            }
            .padding()
            
            Divider()
            
            // Logs
            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(logger.logs, id: \.self) { log in
                        Text(log)
                            .font(.caption) // .monospaced() is available in iOS 15+
                            .foregroundColor(.gray)
                    }
                }
                .padding()
            }
            .frame(maxHeight: 200)
            
            Spacer()
        }
        .background(Color.black.opacity(0.8))
        .foregroundColor(.white)
        .cornerRadius(12)
        .padding()
    }
}
