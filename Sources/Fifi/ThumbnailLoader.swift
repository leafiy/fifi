import AppKit
import FifiCore
import SwiftUI

final class ThumbnailLoader {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 200
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    private let blobStore: BlobStore

    init(blobStore: BlobStore) {
        self.blobStore = blobStore
    }

    func thumbnail(for item: ClipboardItem, completion: @escaping (NSImage?) -> Void) {
        guard let path = item.thumbnailPath else {
            completion(nil)
            return
        }

        let key = path as NSString
        if let cached = Self.cache.object(forKey: key) {
            completion(cached)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [blobStore] in
            let data = try? blobStore.data(atRelativePath: path)
            let image = data.flatMap(NSImage.init(data:))
            if let image, let data {
                Self.cache.setObject(image, forKey: key, cost: data.count)
            }
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }
}

struct ThumbnailView: View {
    let item: ClipboardItem
    let loader: ThumbnailLoader
    let size: CGFloat

    @State private var image: NSImage?
    @State private var loadedPath: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(.quaternary)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .onAppear(perform: load)
        .onChange(of: item.thumbnailPath) {
            image = nil
            loadedPath = nil
            load()
        }
    }

    private func load() {
        guard loadedPath != item.thumbnailPath else { return }
        loadedPath = item.thumbnailPath
        let requestedPath = item.thumbnailPath
        loader.thumbnail(for: item) { loadedImage in
            guard requestedPath == item.thumbnailPath else { return }
            image = loadedImage
        }
    }
}
