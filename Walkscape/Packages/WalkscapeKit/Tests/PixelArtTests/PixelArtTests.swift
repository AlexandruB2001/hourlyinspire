import XCTest
@testable import PixelArt
import WalkscapeDomain

final class PixelArtTests: XCTestCase {
    func testEveryBiomeRendersAtManySizesWithoutCrashing() {
        for biome in Biome.allCases {
            for (w, h) in [(24, 24), (40, 30), (48, 28), (32, 40), (96, 56), (130, 96), (200, 120), (433, 99)] {
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

    func testEveryBiomeLooksDifferent() {
        let thumbnails = Biome.allCases.map { SceneRenderer.thumbnail($0) }
        XCTAssertEqual(Set(thumbnails).count, Biome.allCases.count)
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

    func testEveryShopItemHasArtThatChangesTheWalker() {
        XCTAssertEqual(Set(EquipmentArt.allIDs), Set(ShopCatalog.items.map(\.id)))
        let plain = CharacterSprites.idleFrame(avatarID: "fern", outfit: [])
        for item in ShopCatalog.items {
            let dressed = CharacterSprites.idleFrame(avatarID: "fern", outfit: [item.id])
            XCTAssertEqual(dressed.height, CharacterSprites.outfittedHeight)
            XCTAssertNotEqual(dressed, plain, "\(item.id) is invisible")
        }
    }

    func testOutfitArtUsesOnlyPaletteKeys() {
        for id in EquipmentArt.allIDs {
            let art = EquipmentArt.art(for: id)!
            XCTAssertEqual(Set(art.overlay.map(\.count)).count <= 1, true, "\(id) has ragged rows")
            for key in art.overlay.joined() where key != "." {
                XCTAssertNotNil(EquipmentArt.palette[key], "\(id) uses unknown key \(key)")
            }
        }
    }

    func testAnEmptyOutfitIsThePlainWalkerWithHeadroom() {
        let headroom = CharacterSprites.outfitHeadroom
        for frame in 0..<CharacterSprites.walkFrameCount {
            let plain = CharacterSprites.walkFrame(frame, avatarID: "sky")
            let outfitted = CharacterSprites.walkFrame(frame, avatarID: "sky", outfit: [])
            for y in 0..<CharacterSprites.height {
                for x in 0..<CharacterSprites.width { XCTAssertEqual(outfitted[x, y + headroom], plain[x, y]) }
            }
        }
    }

    func testCompanionsGrowVisiblyAtEveryStage() {
        XCTAssertEqual(CompanionSprites.speciesIDs, CompanionCatalog.starters.map(\.id).sorted())
        for species in CompanionCatalog.starters {
            var previous: PixelCanvas?
            for km in [0, 3, 5, 12, 20, 35, 50, 80, 100] {
                let canvas = CompanionSprites.render(speciesID: species.id, growth: CompanionGrowth(kilometres: km))
                XCTAssertEqual(canvas.width, CompanionSprites.canvasSize)
                XCTAssertTrue(canvas.pixels.contains { $0.a > 0 }, "\(species.id) at \(km) km is blank")
                if let previous { XCTAssertNotEqual(canvas, previous, "\(species.id) didn't change by \(km) km") }
                previous = canvas
            }
        }
    }

    func testCompanionArtIsInBoundsAndUsesPaletteKeys() {
        let palette = ItemSprites.palette.overriding(["e": PixelColor(0xFF8A3D)])
        for (species, stages) in CompanionSprites.art {
            XCTAssertEqual(stages.count, 4, species)
            for stage in stages {
                XCTAssertEqual(Set(stage.rows.map(\.count)).count, 1, "\(species) has ragged rows")
                XCTAssertLessThanOrEqual(stage.rows.count, CompanionSprites.canvasSize)
                for key in stage.rows.joined() + stage.details.map(\.key) where key != "." {
                    XCTAssertNotNil(palette[key], "\(species) uses unknown key \(key)")
                }
                for detail in stage.details {
                    XCTAssertTrue(stage.rows.indices.contains(detail.y) && detail.x < stage.rows[detail.y].count,
                                  "\(species) detail out of bounds")
                }
            }
        }
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

    // MARK: Seasons

    func testSeasonsRecolourTheSceneButKeepItsShape() {
        let plain = SceneRenderer.render(.meadow, width: 96, height: 60)
        let seasons = Season.allCases.map { SceneRenderer.render(.meadow, width: 96, height: 60, season: $0) }
        XCTAssertEqual(Set(seasons.map(\.mid)).count, 4, "each season looks different")
        for layers in seasons {
            XCTAssertNotEqual(layers.mid, plain.mid)
            XCTAssertEqual(layers.footY, plain.footY)
            // Transparent pixels stay transparent, so parallax layering is unchanged.
            XCTAssertEqual(layers.mid.pixels.map { $0.a == 0 }, plain.mid.pixels.map { $0.a == 0 })
        }
        XCTAssertEqual(SceneRenderer.render(.meadow, width: 96, height: 60, season: .winter),
                       SceneRenderer.render(.meadow, width: 96, height: 60, season: .winter), "deterministic")
        XCTAssertEqual(SceneRenderer.render(.crystalCaves, width: 96, height: 60, season: .winter),
                       SceneRenderer.render(.crystalCaves, width: 96, height: 60), "caves ignore the seasons")
    }

    func testEveryWildlifeAndTreasureHasASprite() {
        for id in WildlifeCatalog.all.map(\.spriteID) + TreasureCatalog.all.map(\.spriteID) + WorldEventCatalog.all.map(\.spriteID) {
            XCTAssertNotNil(ItemSprites.sprite(id), "missing sprite \(id)")
        }
    }

    func testCompanionAccessoriesAreDrawnOnEveryStage() {
        for accessory in CompanionAccessoryCatalog.all {
            XCTAssertNotNil(CompanionAccessoryArt.sprite(accessory.id), "missing art for \(accessory.id)")
        }
        for species in CompanionSprites.speciesIDs {
            for km in [0, 5, 20, 50, 100] {
                let growth = CompanionGrowth(kilometres: km)
                let plain = CompanionSprites.render(speciesID: species, growth: growth)
                for accessory in CompanionAccessoryCatalog.all {
                    let dressed = CompanionSprites.render(speciesID: species, growth: growth, accessories: [accessory.id])
                    XCTAssertNotEqual(dressed, plain, "\(accessory.id) shows on \(species) at \(km) km")
                    XCTAssertEqual(dressed.width, CompanionSprites.canvasSize)
                }
            }
        }
    }

    func testCampsiteGrowsWithItsLevelAndShowsDecorations() {
        let levels = (1...5).map { CampfireRenderer.render(level: $0, decorations: []) }
        XCTAssertEqual(Set(levels).count, 5, "every level looks different")
        XCTAssertNotEqual(CampfireRenderer.render(level: 1, decorations: [], frame: 0),
                          CampfireRenderer.render(level: 1, decorations: [], frame: 1), "the fire flickers")
        for decoration in CampfireCatalog.decorations {
            XCTAssertNotEqual(CampfireRenderer.render(level: 5, decorations: [decoration.id]), levels[4], decoration.id)
        }
        XCTAssertEqual(levels[0].width, CampfireRenderer.width)
    }

    func testEveryTeamWorldHasItsOwnLook() {
        let plain = SceneRenderer.render(.pineForest, width: 80, height: 50)
        let tinted = WorldTint.allCases.map { SceneRenderer.render(.pineForest, width: 80, height: 50, tint: $0) }
        XCTAssertEqual(Set(tinted.map(\.mid)).count, WorldTint.allCases.count)
        for layers in tinted { XCTAssertNotEqual(layers.mid, plain.mid) }
    }
}
