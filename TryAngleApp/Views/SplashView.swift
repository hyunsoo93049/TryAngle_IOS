import SwiftUI

struct SplashView: View {
    @State private var opacity = 0.0
    @Binding var isActive: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 200)
                .opacity(opacity)
                .onAppear {
                    withAnimation(.easeIn(duration: 1.0)) {
                        opacity = 1.0
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation {
                            isActive = false
                        }
                    }
                }
        }
    }
}
