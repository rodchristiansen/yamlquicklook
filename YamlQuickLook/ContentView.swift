import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.viewfinder")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .foregroundColor(.blue)
            
            Text("YAML Quick Look")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("A modern Quick Look extension for YAML files")
                .font(.title2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Features:")
                    .font(.headline)
                
                Label("Native plain-text Quick Look preview", systemImage: "eye.fill")
                Label("Support for .yaml and .yml extensions", systemImage: "doc.fill")
                Label("Scrollable content for large files", systemImage: "scroll.fill")
                Label("Thumbnail generation in Finder", systemImage: "photo.fill")
                Label("Dark mode support", systemImage: "circle.lefthalf.filled")
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            
            Text("To use: Select any YAML file in Finder and press Space for Quick Look preview")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        }
        .padding(40)
        .frame(maxWidth: 500, maxHeight: 600)
    }
}

#Preview {
    ContentView()
}