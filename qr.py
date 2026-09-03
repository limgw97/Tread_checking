import qrcode

# QR 코드에 포함할 URL
# QRコードに埋め込むURL
# URL to encode into the QR code
url = "https://drive.google.com/file/d/1dQg-MbtUPz8Ymbwnx57KrNk26uw2v-wL/view?usp=sharing"

# QR 코드 생성
# QRコード生成
# Generate the QR code
qr = qrcode.make(url)

# QR 코드 이미지를 파일로 저장
# QRコード画像をファイルに保存
# Save the QR code image to a file
qr.save("example_image_qr.png")

# QR 코드 출력 (시각적으로 확인)
# QRコードを表示(目視確認用)
# Display the QR code (visual check)
qr.show()

