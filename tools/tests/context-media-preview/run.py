import argparse
from pathlib import Path
import subprocess
import tempfile


root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument("--sanitize", action="store_true")
args = parser.parse_args()
row = (root / "packages/ChatUI/Sources/ChatUI/ContextMediaRowItem.swift").read_text()
preview = (root / "packages/TelegramMediaUtils/Sources/TelegramMediaUtils/StickerPreviewHandler.swift").read_text()
canvas = (root / "Telegram-Mac/packages-integration/hooks/PreviewSenderUIHooksInstall.swift").read_text()


def section(source, start, end):
    offset = source.index(start)
    return source[offset:source.index(end, offset)]


fixture = Path(__file__).with_name("ContextMediaPreviewTests.swift").read_text()
for marker, code in [
    ("__PREVIEW_ENTRY__", section(preview, "@discardableResult\npublic func startModalPreviewHandle", "@discardableResult\npublic func showModalPreview")),
    ("__PREVIEW__", section(row, "    private struct Press {", "    public override func interactionContentView")),
    ("__REBIND__", section(row, "    public override func set(item: TableRowItem", "        guard let item = item as? ContextMediaRowItem else { return }") + "    }"),
    ("__GESTURE__", section(row, "    public func index(at point:", "    public override func layout()")),
    ("__CANVAS_SHOW__", section(canvas, "        var dragImage: CGImage?", "\n    }\n\n    private func ownsPicker(")),
    ("__CANVAS_VISIBILITY__", section(canvas, "    private func updatePickerVisibility(", "    deinit")),
    ("__CANVAS_TEARDOWN__", section(canvas, "    private func ownsPicker(", "    private func pick(")),
]:
    fixture = fixture.replace(marker, code)

with tempfile.TemporaryDirectory(prefix="context-media-preview-") as directory:
    directory = Path(directory)
    source = directory / "main.swift"
    source.write_text(fixture)
    binary = directory / "tests"
    flags = ["-sanitize=address"] if args.sanitize else []
    developer = Path(subprocess.check_output(["xcode-select", "-p"], text=True).strip())
    testing = developer / "Platforms/MacOSX.platform/Developer"
    frameworks, libraries = str(testing / "Library/Frameworks"), str(testing / "usr/lib")
    subprocess.run(["xcrun", "swiftc", "-module-cache-path", str(directory / "cache"),
                    "-F", frameworks, "-I", libraries, "-L", libraries,
                    "-Xlinker", "-rpath", "-Xlinker", frameworks,
                    "-Xlinker", "-rpath", "-Xlinker", libraries,
                    *flags, str(source), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
