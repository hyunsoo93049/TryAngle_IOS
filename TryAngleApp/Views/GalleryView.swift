import SwiftUI
import Photos
import PhotosUI

struct GalleryView: View {
    @Binding var selectedTab: Int
    @State private var showPhotoPicker = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack {
                // 상단 헤더 (로고 + 닫기 버튼)
                ZStack {
                    Image("Logo")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(height: 24)
                        .foregroundColor(.white)
                    
                    HStack {
                        Button(action: {
                            // 카메라 탭(1)으로 복귀
                            selectedTab = 1
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .padding()
                        }
                        Spacer()
                    }
                }
                .padding(.top, 50)

                Spacer()

                Button(action: {
                    showPhotoPicker = true
                }) {
                    VStack(spacing: 20) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 60))
                            .foregroundColor(.white)

                        Text("사진 보기")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                    }
                }

                Spacer()
            }
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerView()
        }
    }
}

// MARK: - 포토피커 뷰
struct PhotoPickerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 0  // 무제한 선택
        config.filter = .images

        let picker = PHPickerViewController(configuration: config)
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
}

// MARK: - 갤러리 사진 아이템
struct GalleryPhotoItem: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
        }
        .onAppear {
            loadImage()
        }
    }

    private func loadImage() {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isSynchronous = false

        manager.requestImage(
            for: asset,
            targetSize: CGSize(width: 200, height: 200),
            contentMode: .aspectFill,
            options: options
        ) { img, _ in
            if let img = img {
                DispatchQueue.main.async {
                    self.image = img
                }
            }
        }
    }
}

struct GalleryView_Previews: PreviewProvider {
    static var previews: some View {
        GalleryView(selectedTab: .constant(0))
    }
}
