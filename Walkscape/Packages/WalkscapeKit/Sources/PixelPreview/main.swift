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

// Items.
var items = PixelCanvas(width: ItemSprites.allIDs.count * 12, height: 12)
for (i, id) in ItemSprites.allIDs.enumerated() { items.draw(ItemSprites.render(id), x: i * 12 + 1, y: 1) }
write(items, "items", scale: 6)
