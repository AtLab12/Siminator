import Foundation
import SwiftUI

struct ToolsHomeView: View {
    var body: some View {
        VStack {
            Text("Siminator by Mikolaj Zawada")
            
            Text("Some tools will go here")
            
            Text("More will go here")
        }
        .padding(16)
        .frame(width: 260, height: 180)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.regularMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
