import Foundation
import PixelArt
import WalkscapeDomain

// Developer tool: renders the procedural art to PPM files so it can be
// reviewed without a simulator. Usage: swift run pixel-preview <output-dir>

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "preview-output"
try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

func write(_ canvas: PixelCanvas, _ name: String, scale: Int = 4, background: PixelColor = PixelColor(0xF4EBD0)) {
    var flat = PixelCanvas(width: canvas.width, height: canvas.height, fill: background)
    flat.draw(canvas, x: 0, y: 0)
    let big = flat.scaled(by: scale)
    var data = Data("P6\n\(big.width) \(big.height)\n255\n".utf8)
    for p in big.pixels { data.append(contentsOf: [p.r, p.g, p.b]) }
    FileManager.default.createFile(atPath: "\(output)/\(name).ppm", contents: data)
}

// Character sheet: every avatar x (4 walk frames + idle + portrait).
var sheet = PixelCanvas(width: 6 * 18, height: AvatarCatalog.starters.count * 22)
for (row, avatar) in AvatarCatalog.starters.enumerated() {
    for frame in 0..<4 {
        sheet.draw(CharacterSprites.walkFrame(frame, avatarID: avatar.id), x: frame * 18 + 1, y: row * 22 + 1)
    }
    sheet.draw(CharacterSprites.idleFrame(avatarID: avatar.id), x: 4 * 18 + 1, y: row * 22 + 1)
    sheet.draw(CharacterSprites.portrait(avatarID: avatar.id), x: 5 * 18 + 1, y: row * 22 + 1)
}
write(sheet, "characters", scale: 6)
print("wrote previews to \(output)")

// Every biome at phone-like proportions, with the walker on the path.
for biome in Biome.allCases {
    let layers = SceneRenderer.render(biome, width: 130, height: 96)
    var frame = layers.composite()
    frame.draw(CharacterSprites.walkFrame(0, avatarID: "fern"), x: 40, y: layers.footY - CharacterSprites.height + 1)
    write(frame, "scene-\(biome.rawValue)", scale: 3)
}

// Looks: every hairstyle in each outfit shape, then the skin tones.
var looks = PixelCanvas(width: (HairStyle.allCases.count + 1) * 18, height: (BodyStyle.allCases.count + 1) * 26)
for (row, body) in BodyStyle.allCases.enumerated() {
    for (column, hair) in HairStyle.allCases.enumerated() {
        looks.draw(CharacterSprites.walkFrame(0, avatarID: CharacterLook(colors: "plum", hair: hair, body: body).avatarID),
                   x: column * 18 + 1, y: row * 26 + 1)
    }
}
for (column, tone) in SkinTone.allCases.enumerated() {
    looks.draw(CharacterSprites.idleFrame(avatarID: CharacterLook(hair: .pigtails, skin: tone).avatarID,
                                          outfit: ["flower-crown", "yellow-wellies"]),
               x: column * 18 + 1, y: BodyStyle.allCases.count * 26 + 1)
}
write(looks, "looks", scale: 6, background: PixelColor(0x9CC2D8))

// Items.
var items = PixelCanvas(width: ItemSprites.allIDs.count * 12, height: 12)
for (i, id) in ItemSprites.allIDs.enumerated() { items.draw(ItemSprites.render(id), x: i * 12 + 1, y: 1) }
write(items, "items", scale: 6)

// Team world wildlife and treasures.
let worldSprites = TeamWorldContent.allCreatures.map(\.spriteID) + TeamWorldCatalog.worlds.compactMap(\.treasure?.spriteID)
var worldItems = PixelCanvas(width: worldSprites.count * 12, height: 12)
for (i, id) in worldSprites.enumerated() { worldItems.draw(ItemSprites.render(id), x: i * 12 + 1, y: 1) }
write(worldItems, "team-world-items", scale: 6)

// Every shop item on the walker.
var outfits = PixelCanvas(width: 10 * 18, height: ((ShopCatalog.items.count + 9) / 10) * 26)
for (i, item) in ShopCatalog.items.enumerated() {
    outfits.draw(CharacterSprites.idleFrame(avatarID: "fern", outfit: [item.id]), x: (i % 10) * 18 + 1, y: (i / 10) * 26 + 1)
}
write(outfits, "outfits", scale: 6, background: PixelColor(0x9CC2D8))

// Companions at 0, 3, 5, 12, 20, 35, 50, 80 and 100 km.
let companionKilometres = [0, 3, 5, 12, 20, 35, 50, 80, 100]
var companions = PixelCanvas(width: companionKilometres.count * 22, height: CompanionCatalog.starters.count * 22)
for (row, species) in CompanionCatalog.starters.enumerated() {
    for (column, km) in companionKilometres.enumerated() {
        companions.draw(CompanionSprites.render(speciesID: species.id, growth: CompanionGrowth(kilometres: km)),
                        x: column * 22 + 1, y: row * 22 + 1)
    }
}
write(companions, "companions", scale: 6, background: PixelColor(0x9CC2D8))

// Thumbnails at the sizes the app uses.
var thumbs = PixelCanvas(width: Biome.allCases.count * 64, height: 48)
for (i, biome) in Biome.allCases.enumerated() {
    thumbs.draw(SceneRenderer.thumbnail(biome, width: 60, height: 44), x: i * 64, y: 0)
}
write(thumbs, "thumbnails", scale: 3)

// Promo art for social videos: unscaled layers with transparency, each as a
// PPM (colour) plus a PGM (alpha). Usage: pixel-preview <dir> promo
if CommandLine.arguments.contains("promo") {
    let promo = "\(output)/promo"
    try? FileManager.default.createDirectory(atPath: promo, withIntermediateDirectories: true)
    func writeRGBA(_ canvas: PixelCanvas, _ name: String) {
        var rgb = Data("P6\n\(canvas.width) \(canvas.height)\n255\n".utf8)
        var alpha = Data("P5\n\(canvas.width) \(canvas.height)\n255\n".utf8)
        for p in canvas.pixels {
            rgb.append(contentsOf: [p.r, p.g, p.b])
            alpha.append(p.a)
        }
        FileManager.default.createFile(atPath: "\(promo)/\(name).ppm", contents: rgb)
        FileManager.default.createFile(atPath: "\(promo)/\(name).pgm", contents: alpha)
    }
    // Scenes as separate parallax layers, a 9:8 band for 1080-wide video at 8x.
    for biome in Biome.allCases {
        let layers = SceneRenderer.render(biome, width: 135, height: 120)
        for (name, layer) in [("sky", layers.sky), ("clouds", layers.clouds), ("far", layers.far), ("mid", layers.mid),
                              ("ground", layers.ground)] {
            writeRGBA(layer, "scene-\(biome.rawValue)-\(name)")
        }
        FileManager.default.createFile(atPath: "\(promo)/scene-\(biome.rawValue)-footY.txt", contents: Data("\(layers.footY)".utf8))
    }
    // The walker in a few outfits: 4 walk frames and the idle frame each.
    let outfits: [(String, [String])] = [
        ("plain", []), ("crown", ["golden-crown", "aurora-scarf", "red-sneakers"]), ("hoodie", ["grey-hoodie", "white-sneakers"]),
        ("wizard", ["wizard-hat", "rainbow-scarf", "hero-cape"]), ("starry", ["starry-hoodie", "flower-crown", "golden-boots"]),
        ("halo", ["halo", "phoenix-wings", "white-tee"]),
    ]
    for (name, outfit) in outfits {
        for frame in 0..<CharacterSprites.walkFrameCount {
            writeRGBA(CharacterSprites.walkFrame(frame, avatarID: "fern", outfit: outfit), "walker-\(name)-walk\(frame)")
        }
        writeRGBA(CharacterSprites.idleFrame(avatarID: "fern", outfit: outfit), "walker-\(name)-idle")
    }
    // Companions at each growth stage.
    for species in CompanionCatalog.starters {
        for km in [0, 5, 20, 50, 100] {
            writeRGBA(CompanionSprites.render(speciesID: species.id, growth: CompanionGrowth(kilometres: km)),
                      "companion-\(species.id)-\(km)km")
        }
    }
    for id in ["chest", "coin", "mystery-box", "star"] { writeRGBA(ItemSprites.render(id), "item-\(id)") }
    print("wrote promo art to \(promo)")
}

// App icon source: 128x128 art scaled 8x to 1024. Usage: pixel-preview <dir> icon
if CommandLine.arguments.contains("icon") {
    let layers = SceneRenderer.render(.meadow, width: 64, height: 64)
    var icon = layers.composite(cloudOffset: 20, midOffset: 6, groundOffset: 10)
    let character = CharacterSprites.walkFrame(0, avatarID: "fern").scaled(by: 2)
    icon.draw(character, x: 16, y: layers.footY - character.height + 2)
    var data = Data("P6\n\(icon.width * 16) \(icon.height * 16)\n255\n".utf8)
    for p in icon.scaled(by: 16).pixels { data.append(contentsOf: [p.r, p.g, p.b]) }
    FileManager.default.createFile(atPath: "\(output)/AppIcon.ppm", contents: data)
}
