// PDFKit is the macOS import boundary for spec 0019; no Flutter runner plugin is required.
// API reference: https://developer.apple.com/documentation/pdfkit
import Foundation
import PDFKit
import AppKit

struct TextBox: Codable { let start: Int; let end: Int; let x: Double; let y: Double; let w: Double; let h: Double }
struct PageInfo: Codable { let file: String; let width: Int; let height: Int; let text: String; let count: Int; let boxes: [TextBox] }
func fail(_ message: String) -> Never { FileHandle.standardError.write(Data(message.utf8)); exit(1) }
guard CommandLine.arguments.count == 3 || CommandLine.arguments.count == 4 else { fail("缺少 PDF 文件或输出目录") }
guard let document = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1])), !document.isLocked else { fail("PDF 无法打开，或需要密码") }
guard document.pageCount > 0, document.pageCount <= (CommandLine.arguments.count == 4 ? 5000 : 100) else { fail("PDF 须为 1–100 页，请拆分后导入") }
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
var pages: [PageInfo] = []
let selected = CommandLine.arguments.count == 4 ? (Int(CommandLine.arguments[3]) ?? 0) : nil
if let selected = selected { guard selected >= 1, selected <= document.pageCount else { fail("页码无效") } }
let indices = selected.map { [ $0 - 1 ] } ?? Array(0..<document.pageCount)
do {
    for index in indices {
        try autoreleasepool {
            guard let page = document.page(at: index) else { fail("PDF 页面无法读取") }
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else { fail("PDF 页面尺寸无效") }
            let scale = min(2, sqrt(2_000_000 / (bounds.width * bounds.height)))
            let size = NSSize(width: max(1, floor(bounds.width * scale)), height: max(1, floor(bounds.height * scale)))
            let image = page.thumbnail(of: size, for: .mediaBox)
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { fail("PDF 页面渲染失败") }
            guard bitmap.pixelsWide * bitmap.pixelsHigh <= 2_100_000 else { fail("PDF 页面超过像素限制") }
            let file = "page-\(index + 1).png"
            try png.write(to: output.appendingPathComponent(file), options: .atomic)
            let text = String((page.string ?? "").prefix(100_000))
            var boxes: [TextBox] = []
            text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { _, range, _, stop in
                if boxes.count >= 20000 { stop = true; return }
                let offsets = NSRange(range, in: text)
                guard let selection = page.selection(for: offsets) else { return }
                let r = selection.bounds(for: page).intersection(bounds)
                if r.isNull || r.isEmpty { return }
                boxes.append(TextBox(start: offsets.location, end: offsets.location + offsets.length,
                    x: (r.minX-bounds.minX)/bounds.width, y: (bounds.maxY-r.maxY)/bounds.height,
                    w: r.width/bounds.width, h: r.height/bounds.height))
            }
            pages.append(PageInfo(file: file, width: bitmap.pixelsWide, height: bitmap.pixelsHigh, text: text, count: document.pageCount, boxes: boxes))
        }
    }
    if selected != nil { try JSONEncoder().encode(pages[0]).write(to: output.appendingPathComponent("page.json"), options: .atomic) }
    try JSONEncoder().encode(pages).write(to: output.appendingPathComponent("pages.json"), options: .atomic)
} catch { fail("PDF 导入失败：\(error.localizedDescription)") }
