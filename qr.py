import qrcode

# QR 코드에 포함할 URL
url = "https://drive.google.com/file/d/1dQg-MbtUPz8Ymbwnx57KrNk26uw2v-wL/view?usp=sharing"

# QR 코드 생성
qr = qrcode.make(url)

# QR 코드 이미지를 파일로 저장
qr.save("example_image_qr.png")

# QR 코드 출력 (시각적으로 확인)
qr.show()  # 이미지 뷰어를 통해 QR 코드 열기py
