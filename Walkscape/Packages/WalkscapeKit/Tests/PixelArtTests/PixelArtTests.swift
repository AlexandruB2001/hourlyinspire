import XCTest
@testable import PixelArt
import WalkscapeDomain

final class PixelArtTests: XCTestCase {
    func testEveryBiomeRendersAtManySizesWithoutCrashing() {
        for biome in Biome.allCases {
            for (w, h) in [(32, 40), (96, 56), (130, 96), (200, 120), (433, 99)] {
                let layers = SceneRenderer.render(biome, width: w, height: h)
                XCTAssertEqual(layers.sky.width, w)
                XCTAssertEqual(layers.ground.height, h)
                XCTAssertTrue((0..<h).contains(layers.footY))
            }
        }
    }

    func testRenderingIsDeterministic() {
        XCTAssertEqual(SceneRenderer.render(.village, width: 120, height: 90),
                       SceneRenderer.render(.village, width: 120, height: 90))
    }

    func testScrollingLayersTile() {
        let layers = SceneRenderer.render(.meadow, width: 100, height: 80)
        XCTAssertTrue(layers.ground.wrapsHorizontally)
        XCTAssertEqual(layers.ground[-1, 70], layers.ground[99, 70])
        XCTAssertEqual(layers.ground[100, 70], layers.ground[0, 70])
    }

    func testSkyIsOpaque() {
        for biome in Biome.allCases {
            let sky = SceneRenderer.render(biome, width: 64, height: 48).sky
            XCTAssertTrue(sky.pixels.allSatisfy { $0.a == 255 }, "\(biome) sky has holes")
        }
    }

    func testCharacterFramesForEveryAvatar() {
        for avatar in AvatarCatalog.starters {
            for frame in 0..<CharacterSprites.walkFrameCount {
                let canvas = CharacterSprites.walkFrame(frame, avatarID: avatar.id)
                XCTAssertEqual(canvas.width, CharacterSprites.width)
                XCTAssertEqual(canvas.height, CharacterSprites.height)
                XCTAssertTrue(canvas.pixels.contains { $0.a > 0 })
            }
        }
        // Unknown avatars fall back to the base palette instead of failing.
        XCTAssertEqual(CharacterSprites.walkFrame(0, avatarID: "unknown"), CharacterSprites.walkFrame(0, avatarID: "fern"))
    }

    func testEveryCollectibleAndAchievementHasASprite() {
        let ids = ZoneCatalog.standard.allCollectibles.map(\.spriteID) + AchievementCatalog.standard.map(\.spriteID)
        for id in ids { XCTAssertNotNil(ItemSprites.sprite(id), "missing sprite \(id)") }
    }

    func testSpritesUseOnlyPaletteKeys() {
        for id in ItemSprites.allIDs {
            let sprite = ItemSprites.sprite(id)!
            for key in sprite.rows.joined() where key != "." {
                XCTAssertNotNil(sprite.palette[key], "\(id) uses unknown key \(key)")
            }
        }
        let base = CharacterSprites.basePalette
        for key in (CharacterSprites.upperBody + CharacterSprites.legs.flatMap { $0 }).joined() where key != "." {
            XCTAssertNotNil(base[key], "character uses unknown key \(key)")
        }
    }

    func testAlphaBlending() {
        var canvas = PixelCanvas(width: 1, height: 1, fill: PixelColor(0x000000))
        canvas.plot(0, 0, PixelColor(0xFFFFFF, alpha: 128))
        XCTAssertEqual(canvas[0, 0].r, 128)
        XCTAssertEqual(canvas[0, 0].a, 255)
    }
}
