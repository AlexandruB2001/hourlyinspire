import CoreGraphics
import Foundation
import PixelArt
import WalkscapeDomain

/// The walker (and companion) on today's zone, drawn with the app's
/// pixel-art renderer like the iPhone widget.
enum WatchArt {
    /// What the frames depend on, so they're only redrawn when it changes.
    struct Key: Hashable {
        let biome: Biome
        let avatarID: String
        let outfit: [String]
        let companionSpeciesID: String?
        let companionKilometres: Int
        let companionAccessories: [String]
        let companionSkinID: String?
        let walking: Bool

        init(_ glance: WatchGlance) {
            let snapshot = glance.snapshot
            biome = glance.zone.currentZone.biome
            avatarID = snapshot?.avatarID ?? "fern"
            outfit = snapshot?.outfit ?? []
            companionSpeciesID = snapshot?.companionSpeciesID
            companionKilometres = snapshot?.companionKilometres ?? 0
            companionAccessories = snapshot?.companionAccessories ?? []
            companionSkinID = snapshot?.companionSkinID
            walking = glance.todayMeters > 0
        }
    }

    /// Four walking frames once today's walk has started, else one standing frame.
    static func frames(for key: Key, width: Int = 64, height: Int = 48) -> [CGImage] {
        let layers = SceneRenderer.render(key.biome, width: width, height: height)
        let walkerX = Int((Double(width) * 0.55).rounded())
        let poses = key.walking
            ? (0..<CharacterSprites.walkFrameCount).map { CharacterSprites.walkFrame($0, avatarID: key.avatarID, outfit: key.outfit) }
            : [CharacterSprites.idleFrame(avatarID: key.avatarID, outfit: key.outfit)]
        let companion = key.companionSpeciesID.map {
            CompanionSprites.render(speciesID: $0, growth: CompanionGrowth(kilometres: key.companionKilometres),
                                    accessories: key.companionAccessories,
                                    skin: CompanionSkinCatalog.skin(withID: key.companionSkinID))
        }
        let background = layers.composite(cloudOffset: 9, farOffset: 4, midOffset: 7, groundOffset: 3)
        return poses.enumerated().compactMap { index, pose in
            var canvas = background
            if let companion {
                // Just behind the walker, trotting along on every other step.
                let bob = key.walking && index % 2 == 0 ? 1 : 0
                canvas.draw(companion, x: walkerX - CompanionSprites.canvasSize + 2,
                            y: layers.footY - CompanionSprites.canvasSize + 1 - bob)
            }
            canvas.draw(pose, x: walkerX, y: layers.footY - pose.height + 1)
            return canvas.cgImage()
        }
    }
}

extension PixelCanvas {
    /// A non-interpolated sRGB image of the canvas (straight alpha).
    func cgImage() -> CGImage? {
        let data = Data(rgbaBytes) as CFData
        guard let provider = CGDataProvider(data: data), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
