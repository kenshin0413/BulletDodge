from pathlib import Path

from PIL import Image


ROOT = Path("/Users/kenshin/Desktop/BulletDodge/BulletDodge/BulletDodge/Assets.xcassets/arena_floor_v1.imageset")
SOURCE_PATH = Path("/Users/kenshin/Desktop/BulletDodge/backups/arena_floor_v1.pre_regen_backup.png")
TARGET_PATH = ROOT / "arena_floor_v1.png"
TEMP_PATH = ROOT / "arena_floor_v1.tmp.png"


def make_vertical_fade_mask(width: int, height: int, fade: int) -> Image.Image:
    fade = max(1, min(fade, height // 2))
    mask = Image.new("L", (width, height), 255)
    px = mask.load()
    for y in range(height):
        if y < fade:
            alpha = int(255 * y / fade)
        elif y >= height - fade:
            alpha = int(255 * (height - 1 - y) / fade)
        else:
            alpha = 255
        for x in range(width):
            px[x, y] = max(0, min(255, alpha))
    return mask


def blend_patch(base: Image.Image, patch: Image.Image, xy: tuple[int, int], fade: int) -> None:
    overlay = patch.copy()
    overlay.putalpha(make_vertical_fade_mask(overlay.width, overlay.height, fade))
    base.alpha_composite(overlay, xy)


def main() -> None:
    source = Image.open(SOURCE_PATH).convert("RGBA")
    canvas = source.copy()

    new_left = 145
    new_right = 858
    old_left = 160
    old_right = 843
    border_width = 25
    floor_top = 154
    floor_bottom = 1416

    # Move the side blue borders outward so the front-side movement boundary is the visual reference.
    left_fill = source.crop((177, floor_top, 208, floor_bottom)).resize((old_left - new_left, floor_bottom - floor_top), Image.Resampling.BICUBIC)
    right_fill = source.crop((795, floor_top, 826, floor_bottom)).resize((new_right - old_right, floor_bottom - floor_top), Image.Resampling.BICUBIC)
    canvas.alpha_composite(left_fill, (new_left, floor_top))
    canvas.alpha_composite(right_fill, (old_right, floor_top))

    left_border = source.crop((old_left, floor_top, old_left + border_width, floor_bottom))
    right_border = source.crop((old_right - border_width, floor_top, old_right, floor_bottom))
    canvas.alpha_composite(left_border, (new_left, floor_top))
    canvas.alpha_composite(right_border, (new_right - border_width, floor_top))

    # Stretch top and bottom border runs to meet the shifted side borders.
    top_border = source.crop((old_left, floor_top, old_right, floor_top + 24)).resize((new_right - new_left, 24), Image.Resampling.BICUBIC)
    bottom_border = source.crop((old_left, 1391, old_right, 1416)).resize((new_right - new_left, 25), Image.Resampling.BICUBIC)
    canvas.alpha_composite(top_border, (new_left, floor_top))
    canvas.alpha_composite(bottom_border, (new_left, 1391))

    # Replace the visible horizontal seam bands near the fences with clean floor samples blended in.
    top_clean = source.crop((177, 448, 827, 618)).resize((new_right - new_left - border_width * 2, 176), Image.Resampling.BICUBIC)
    bottom_clean = source.crop((177, 962, 827, 1132)).resize((new_right - new_left - border_width * 2, 182), Image.Resampling.BICUBIC)
    blend_patch(canvas, top_clean, (new_left + border_width, 188), 52)
    blend_patch(canvas, bottom_clean, (new_left + border_width, 1216), 56)

    # Restore the border strips over the refreshed floor so the blue boundary remains crisp.
    for box in [
        (160, 154, 242, 236),
        (758, 154, 843, 236),
        (160, 1330, 242, 1416),
        (758, 1330, 843, 1416),
    ]:
        dx = box[0]
        if box[0] == 160:
            dx = box[0] - (old_left - new_left)
        elif box[0] == 758:
            dx = box[0] + (new_right - old_right)
        canvas.alpha_composite(source.crop(box), (dx, box[1]))

    # Keep the top and bottom fence bands intact.
    for box in [
        (0, 90, 1003, 184),
        (0, 1365, 1003, 1472),
    ]:
        canvas.alpha_composite(source.crop(box), (box[0], box[1]))

    canvas.save(TEMP_PATH)
    TEMP_PATH.replace(TARGET_PATH)


if __name__ == "__main__":
    main()
