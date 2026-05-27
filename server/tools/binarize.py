import os
import argparse
import sys
from PIL import Image, ImageDraw

def binarize_and_transparent(img: Image.Image, threshold: int = 128) -> Image.Image:
    """
    画像をグレースケール化し、しきい値に基づいて二値化した上で
    背景を透明、線を黒にしたRGBA画像を返します。
    """
    # もし画像がRGBA（透過あり）の場合、白背景の上に重ねてから処理する
    # これにより、アルファチャンネル部分が白背景になり、グレースケール化が正しく機能します
    if img.mode in ("RGBA", "LA") or (img.mode == "P" and "transparency" in img.info):
        background = Image.new("RGBA", img.size, (255, 255, 255, 255))
        img_temp = Image.alpha_composite(background, img.convert("RGBA"))
        gray_img = img_temp.convert("L")
    else:
        gray_img = img.convert("L")
    
    # しきい値処理: 閾値未満は 0 (黒)、閾値以上は 255 (白)
    # point()関数は非常に高速です
    binary_img = gray_img.point(lambda p: 0 if p < threshold else 255, mode="1")
    
    # マスク画像の作成 (Lモード)
    # 元の二値画像は「黒が線、白が背景」。
    # マスクとして使うために、黒(線)の部分を 255 (不透明)、白(背景)の部分を 0 (透明) に反転します。
    mask = binary_img.convert("L").point(lambda p: 255 if p == 0 else 0)
    
    # 完全に透明なRGBA背景画像を作成
    rgba_img = Image.new("RGBA", img.size, (0, 0, 0, 0))
    
    # 線の描画用レイヤー（完全な黒線）
    black_line = Image.new("RGBA", img.size, (0, 0, 0, 255))
    
    # マスクを使用して黒線レイヤーを透明背景に貼り付け
    rgba_img.paste(black_line, (0, 0), mask=mask)
    
    return rgba_img

def process_image(input_path: str, output_dir: str, thumb_dir: str, filename: str, threshold: int = 128):
    """
    指定された入力画像を読み込み、二値化・透過処理とサイズ調整を行って保存します。
    """
    try:
        with Image.open(input_path) as img:
            print(f"Processing {input_path} (original size: {img.size})...")
            
            # 1. まず元の解像度で二値化・透過処理を実施
            rgba_img = binarize_and_transparent(img, threshold)
            
            # 2. 1024x1024 にリサイズ (アンチエイリアスを防ぐため、リサイズ後に再度二値化をかける)
            raw_fish = rgba_img.resize((1024, 1024), Image.Resampling.LANCZOS)
            final_fish = binarize_and_transparent(raw_fish, 128) # リサイズ後はアルファ値がボケるので再二値化
            
            # 3. 256x256 のサムネイル作成
            raw_thumb = rgba_img.resize((256, 256), Image.Resampling.LANCZOS)
            final_thumb = binarize_and_transparent(raw_thumb, 128)
            
            # 4. 出力先ディレクトリの確保
            os.makedirs(output_dir, exist_ok=True)
            os.makedirs(thumb_dir, exist_ok=True)
            
            # 5. 保存
            fish_path = os.path.join(output_dir, filename)
            thumb_path = os.path.join(thumb_dir, filename)
            
            final_fish.save(fish_path, "PNG")
            final_thumb.save(thumb_path, "PNG")
            
            print(f" -> Saved high-res to: {fish_path}")
            print(f" -> Saved thumbnail to: {thumb_path}")
            
            # 6. アサーション（二値化品質の検証）
            verify_binary_quality(fish_path)
            verify_binary_quality(thumb_path)
            
    except Exception as e:
        print(f"Error processing image {input_path}: {e}", file=sys.stderr)

def verify_binary_quality(img_path: str):
    """
    出力されたPNGの各ピクセルが「完全な黒 (0,0,0,255)」または「完全な透明 (0,0,0,0)」
    だけになっているかを走査し、品質をアサートします。
    """
    with Image.open(img_path) as img:
        # RGBAであることを保証
        if img.mode != "RGBA":
            raise AssertionError(f"Image {img_path} is not in RGBA mode.")
            
        data = img.getdata()
        for i, pixel in enumerate(data):
            r, g, b, a = pixel
            # 黒線 (0,0,0,255) か 透明背景 (0,0,0,0) のいずれかであるべき
            # ※RGB値が 0 であること、アルファ値が 0 または 255 であることを確認します。
            is_valid = (r == 0 and g == 0 and b == 0 and (a == 0 or a == 255))
            if not is_valid:
                raise AssertionError(
                    f"Quality check failed in {img_path} at pixel {i}: color={pixel}. "
                    f"Pixel must be exactly (0,0,0,255) or (0,0,0,0) with no anti-aliasing."
                )
    print(f" -> Quality check passed: {img_path} is perfectly binary.")

def generate_mock_drawings(temp_dir: str):
    """
    Pillowのドローイング機能を用いて、テスト用に
    魚・イカ・タコの3種類のシンプルな線画を生成します。
    """
    os.makedirs(temp_dir, exist_ok=True)
    print("Generating mock drawings...")

    # 1. 魚 (fish_01.png)
    img_fish = Image.new("RGB", (1024, 1024), "white")
    draw = ImageDraw.Draw(img_fish)
    # 胴体 (楕円)
    draw.ellipse([200, 350, 800, 670], fill=None, outline="black", width=20)
    # 尾びれ (三角形)
    draw.polygon([(200, 510), (80, 400), (80, 620)], fill=None, outline="black", width=20)
    # 目 (円)
    draw.ellipse([650, 460, 690, 500], fill="black")
    # 胸びれ
    draw.polygon([(450, 580), (410, 650), (490, 630)], fill=None, outline="black", width=20)
    img_fish.save(os.path.join(temp_dir, "raw_fish.png"))

    # 2. イカ (fish_02.png)
    img_squid = Image.new("RGB", (1024, 1024), "white")
    draw = ImageDraw.Draw(img_squid)
    # 頭部 (エンペラ)
    draw.polygon([(512, 150), (350, 350), (674, 350)], fill=None, outline="black", width=20)
    # 胴体 (長方形)
    draw.rectangle([350, 350, 674, 650], fill=None, outline="black", width=20)
    # 目
    draw.ellipse([430, 550, 460, 580], fill="black")
    draw.ellipse([564, 550, 594, 580], fill="black")
    # 足 (10本)
    for x in range(370, 670, 30):
        draw.line([(x, 650), (x - 20, 850), (x, 900)], fill="black", width=15, joint="round")
    img_squid.save(os.path.join(temp_dir, "raw_squid.png"))

    # 3. タコ (fish_03.png)
    img_octopus = Image.new("RGB", (1024, 1024), "white")
    draw = ImageDraw.Draw(img_octopus)
    # 頭部 (円)
    draw.ellipse([312, 200, 712, 600], fill=None, outline="black", width=20)
    # 目
    draw.ellipse([430, 400, 470, 440], fill="black")
    draw.ellipse([554, 400, 594, 440], fill="black")
    # 口
    draw.ellipse([487, 470, 537, 520], fill=None, outline="black", width=15)
    # 足 (8本)
    feet_x = [250, 300, 370, 450, 570, 650, 720, 770]
    for i, x in enumerate(feet_x):
        # 左右に広がるように曲線を引く
        offset = (i - 3.5) * 50
        draw.line([(x, 570), (x + offset, 750), (x + offset * 1.5, 880)], fill="black", width=15, joint="round")
    img_octopus.save(os.path.join(temp_dir, "raw_octopus.png"))

    print("Mock drawings generated successfully.")

def main():
    parser = argparse.ArgumentParser(description="Image Binarization Tool for Digital Aquarium")
    parser.add_argument("input", nargs="?", help="Input image file path. If omitted, generates mock drawings.")
    parser.add_argument("--threshold", type=int, default=128, help="Threshold value (0-255) for binarization (default: 128)")
    parser.add_argument("--output-name", help="Custom output filename. Used only when an input file is provided.")
    
    args = parser.parse_args()
    
    # パスの定義
    current_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.abspath(os.path.join(current_dir, "..", ".."))
    
    output_dir = os.path.join(project_root, "server", "static", "template_fish")
    thumb_dir = os.path.join(project_root, "server", "static", "thumbnails")
    
    if args.input:
        # 指定された入力ファイルの処理
        filename = args.output_name or os.path.basename(args.input)
        # 拡張子をpngに統一
        if not filename.lower().endswith(".png"):
            filename = os.path.splitext(filename)[0] + ".png"
        
        process_image(args.input, output_dir, thumb_dir, filename, args.threshold)
    else:
        # 引数がない場合はダミー画像を作成し自動処理
        temp_dir = os.path.join(project_root, "server", "static", ".temp_raw")
        generate_mock_drawings(temp_dir)
        
        process_image(os.path.join(temp_dir, "raw_fish.png"), output_dir, thumb_dir, "fish_01.png", args.threshold)
        process_image(os.path.join(temp_dir, "raw_squid.png"), output_dir, thumb_dir, "fish_02.png", args.threshold)
        process_image(os.path.join(temp_dir, "raw_octopus.png"), output_dir, thumb_dir, "fish_03.png", args.threshold)
        
        # 最後に一時ファイルの整理
        try:
            for f in os.listdir(temp_dir):
                os.remove(os.path.join(temp_dir, f))
            os.rmdir(temp_dir)
        except Exception as e:
            print(f"Notice: Failed to clean up temp files: {e}")

if __name__ == "__main__":
    main()
