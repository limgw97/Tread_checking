#!/bin/bash
set -e
echo "Cleaning up Tread_checking repo..."

# remove duplicate background image (identical copy already exists under page_data/image/)
rm -f tire_background.png

cat > "crud.py" << 'PYEOF_MARKER'
import os
from dotenv import load_dotenv
from sqlalchemy import create_engine, MetaData, Table, Column, Integer, LargeBinary, Boolean, String
from sqlalchemy.sql import select, insert, update
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.future import select as async_select

# DB 접속 정보는 코드에 직접 넣지 않고 환경변수(.env)에서 읽어옵니다.
# DB接続情報はコードに直接書かず、環境変数(.env)から読み込みます。
# Database credentials are read from an environment variable (.env), never hardcoded.
load_dotenv()
DATABASE_URL = os.environ["DATABASE_URL"]

engine = create_async_engine(DATABASE_URL, echo=True)
async_session = sessionmaker(
    engine, expire_on_commit=False, class_=AsyncSession
)
metadata = MetaData()

input_data = Table(
    'input_data', metadata,
    Column('id', Integer, primary_key=True, autoincrement=True),
    Column('user_id', String(12), nullable=False),
    Column('image_data', LargeBinary, nullable=False),
    Column('state', Boolean, nullable=False)
)

async def get_async_session():
    async with async_session() as session:
        yield session

async def add_input_data(user_id: str, image_data: bytes, state: bool, session: AsyncSession):
    async with session.begin():
        stmt = insert(input_data).values(user_id=user_id, image_data=image_data, state=state)
        await session.execute(stmt)


async def get_input_data(user_id: int):
    async with async_session() as session:
        async with session.begin():
            stmt = async_select(input_data).where(input_data.c.user_id == user_id)
            result = await session.execute(stmt)
            return result.fetchall()

async def update_input_data_state(id: int, state: bool):
    async with async_session() as session:
        async with session.begin():
            stmt = update(input_data).where(input_data.c.id == id).values(state=state)
            await session.execute(stmt)



PYEOF_MARKER

cat > "main.py" << 'PYEOF_MARKER'
from fastapi import FastAPI, UploadFile, File, HTTPException,Request
from fastapi.responses import JSONResponse, HTMLResponse
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image
import numpy as np
import tensorflow as tf
import io
import traceback
import os
from fastapi.templating import Jinja2Templates

# 기본값 설정 / デフォルト値の設定 / default value
API_BASE_URL = os.getenv("API_BASE_URL", "http://127.0.0.1:8000")

app = FastAPI()



# Allow CORS from all origins for testing; restrict in production as needed
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 또는 ["http://127.0.0.1"]으로 설정 가능 / または["http://127.0.0.1"]に設定可能 / or set to ["http://127.0.0.1"]
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Load and compile the model
try:
    print("Loading and compiling the model...")
    model = tf.keras.models.load_model("tire_tread_model.keras")
    model.compile(optimizer='adam', loss='binary_crossentropy', metrics=['accuracy'])
    print("Model loaded and compiled successfully.")
except Exception as e:
    print("Failed to load or compile model:", e)

def crop_tread(image):
    """Crop the central region of the tire tread in the image."""
    width, height = image.size
    left = width * 0.25
    top = height * 0.4
    right = width * 0.75
    bottom = height * 0.6
    return image.crop((left, top, right, bottom))

templates = Jinja2Templates(directory="templates")

# 현재 파일의 경로를 기준으로 templates 폴더의 경로를 가져옵니다.
# 現在のファイルのパスを基準にtemplatesフォルダのパスを取得します。
# Resolve the templates folder path relative to this file's location.
current_dir = os.path.dirname(os.path.abspath(__file__))
templates_dir = os.path.join(current_dir, "templates")

@app.get("/", response_class=HTMLResponse)
async def root(request: Request):
    user_agent = request.headers.get('user-agent', '')
    try:
        # 모바일 기기 여부 확인
        # モバイル端末かどうかを確認
        # Check whether the request is from a mobile device
        if "Mobi" in user_agent or "Android" in user_agent:
            # 모바일용 HTML 파일 반환 / モバイル用HTMLファイルを返す / return the mobile HTML file
            file_path = os.path.join(templates_dir, "mobile.html")
        else:
            # 데스크톱용 HTML 파일 반환 / デスクトップ用HTMLファイルを返す / return the desktop HTML file
            file_path = os.path.join(templates_dir, "example.html")
        
        # 파일 읽기 / ファイル読み込み / read the file
        with open(file_path, "r", encoding="utf-8") as file:
            content = file.read()

        return HTMLResponse(content=content)
    except FileNotFoundError:
        return HTMLResponse(content="File not found.", status_code=404)


@app.get("/", response_class=HTMLResponse)
async def root(request: Request):
    return templates.TemplateResponse("example.html", {"request": request})

@app.post("/predict/")
async def predict_image(file: UploadFile = File(...)):
    try:
        # Open image file directly as a PIL image
        image = Image.open(file.file).convert("RGB")

        # Preprocess the image for prediction
        tread_image = crop_tread(image)  # Crop the image
        tread_image = tread_image.resize((150, 50))  # Resize to model input shape
        tread_image = np.array(tread_image) / 255.0  # Normalize
        tread_image = np.expand_dims(tread_image, axis=0)  # Add batch dimension

        # Predict using the model
        prediction = model.predict(tread_image)
        threshold = 0.5
        result = "적합한 타이어입니다." if prediction[0][0] >= threshold else "교체가 필요한 타이어입니다."
        
        return JSONResponse(content={"message": result, "prediction_score": float(prediction[0][0])})
    
    except Exception as e:
        error_message = f"An error occurred: {e}. Trace: {traceback.format_exc()}"
        print(error_message)
        raise HTTPException(status_code=500, detail=error_message)

PYEOF_MARKER

cat > "qr.py" << 'PYEOF_MARKER'
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

PYEOF_MARKER

cat > ".env.example" << 'PYEOF_MARKER'
# Copy this file to ".env" and fill in your own NeonDB (or other PostgreSQL) credentials.
# このファイルを ".env" にコピーし、ご自身のNeonDB(または他のPostgreSQL)の認証情報を入力してください。
# 이 파일을 ".env"로 복사한 뒤 본인의 NeonDB(또는 다른 PostgreSQL) 접속 정보를 입력하세요.
#
# Never commit the real ".env" file. It's already excluded via .gitignore.
# 実際の ".env" ファイルは絶対にコミットしないでください。.gitignore で除外済みです。
# 실제 ".env" 파일은 절대 커밋하지 마세요. .gitignore에 이미 제외 처리돼 있습니다.

DATABASE_URL=postgresql+asyncpg://USER:PASSWORD@HOST/DBNAME

PYEOF_MARKER

cat > ".gitignore" << 'PYEOF_MARKER'
# Secrets — never commit the real .env
.env

# Python
__pycache__/
*.pyc
.venv/
venv/

# OS
.DS_Store
Thumbs.db

# Generated at runtime
example_image_qr.png

PYEOF_MARKER

cat > "requirements.txt" << 'PYEOF_MARKER'
fastapi                  # FastAPI 프레임워크
uvicorn[standard]        # FastAPI 실행을 위한 ASGI 서버
tensorflow               # 머신러닝 모델 로드를 위한 TensorFlow
pillow                   # 이미지 처리를 위한 PIL (Pillow)
numpy                    # 이미지 배열 및 데이터 처리를 위한 NumPy
sqlalchemy               # SQLAlchemy ORM
asyncpg                  # 비동기 PostgreSQL 드라이버
python-dotenv             # .env 파일에서 환경변수(DB 접속정보 등) 로드
python-multipart
jinja2

PYEOF_MARKER

cat > "README.md" << 'PYEOF_MARKER'
# Tire Wear Determination System Using Machine Learning and IR Camera
# 機械学習とIRカメラを用いたタイヤ摩耗判定システム
# 머신러닝과 IR 카메라를 활용한 타이어 마모도 판별 시스템

A thermal-imaging camera photographs a tire's tread, a CNN classifies it as normal or
worn, and the result is served through a small FastAPI web app (with a PostgreSQL/Neon
database storing submitted images and results).

熱画像カメラでタイヤのトレッドを撮影し、CNNモデルが正常/摩耗を分類、結果は小さな
FastAPI製Webアプリを通じて提供されます(送信された画像と結果はPostgreSQL/Neonの
データベースに保存されます)。

열화상 카메라로 타이어 트레드를 촬영하고, CNN 모델이 정상/마모 여부를 분류해서
결과를 작은 FastAPI 웹 앱으로 보여줍니다(제출된 이미지와 결과는 PostgreSQL/Neon
데이터베이스에 저장됩니다).

## Background / 背景 / 배경

This was built for **기계공학 종합설계2 (Mechanical Engineering Capstone Design 2)**,
a graduation-project course offered in the 2024-2 semester at the **School of
Mechanical Engineering, Hanyang University**, advised by **Prof. Woo-Sung Park
(박우성)**. The team (전현서, 임규원, 이재룡) wrote up the work as a paper,
*"머신러닝과 IR 카메라를 활용한 타이어 마모도 판별 시스템" / "Development of Tire
Wear Determination System Using Machine Learning and IR Camera"* — included in this
repo under `paper/` for reference. The project received an **Encouragement Award
(장려상)** at the **2024-2 Hanyang University School of Mechanical Engineering
Capstone Design Presentation**, a presentation open to every team in the department's
Capstone Design course that semester, placing joint 3rd–4th.

本プロジェクトは、**漢陽大学機械工学部**で2024年度2学期に開講された卒業設計科目
**「機械工学総合設計2」**(指導教員:朴禹成(パク・ウソン)教授)の一環として制作
されました。チーム(チョン・ヒョンソ、イム・ギュウォン、イ・ジェリョン)は研究内容を
論文としてまとめ("Development of Tire Wear Determination System Using Machine
Learning and IR Camera"、本リポジトリの`paper/`に参考として同梱)、2024年2学期の
漢陽大学機械工学部総合設計発表会にて**奨励賞**を受賞しました。この発表会は当該学期の
総合設計科目を履修した全チームが参加するもので、共同3〜4位に相当する成績でした。

이 프로젝트는 **한양대학교 기계공학부** 2024-2학기에 개설된 졸업작품 과목
**"기계공학 종합설계2"**에서 진행됐으며, 지도교수는 **박우성 교수님**입니다. 팀원
(전현서, 임규원, 이재룡)은 연구 내용을 논문으로 정리했고("머신러닝과 IR 카메라를
활용한 타이어 마모도 판별 시스템", 본 레포의 `paper/` 폴더에 참고용으로 함께
포함), 2024-2학기 한양대학교 기계공학부 종합설계 발표회에서 **장려상**을
수상했습니다. 이 발표회는 그 학기 종합설계 과목을 수강한 모든 팀이 참가하는
자리였고, 공동 3~4위에 해당하는 성적이었습니다.

### Why this project — the social/safety background
### なぜこのプロジェクトを行ったか — 社会的・安全上の背景
### 왜 이 프로젝트를 했는가 — 사회적·안전 배경

From the paper's introduction: tires are the vehicle component most directly tied to
safety, since they're the only part in contact with the road. A 2010–2012 statistic
cited in the paper found that tire defects caused 35.9% of highway traffic accidents —
the single largest cause — and a separate roadside survey found 40% of tires on
highway-driving vehicles needed attention. Despite this, only 26% of drivers actually
keep to a proper tire-inspection interval. Tire pressure is easy to check via a
built-in TPMS, but tread wear has no equivalent built-in system — drivers typically
fall back on informal methods like the coin test, which only checks one spot on the
tread and depends on the driver doing it manually and regularly. Prior academic
approaches tried laser displacement sensors (accurate but needs a linear rail setup and
is thrown off by debris near the sensor) or bilateral-filtered ordinary-camera images
(sensitive to low light). This project aimed to get around both limitations using a
thermal-imaging camera + CNN classifier, which shouldn't need special positioning
hardware and should still work in low light.

논문 서론에서: 타이어는 차량 부품 중 유일하게 지면과 맞닿아 있어서 안전과 가장
직결되는 부품입니다. 논문에서 인용한 2010~2012년 통계에 따르면 고속도로 교통사고의
35.9%가 타이어 불량으로 인한 것이었고(가장 큰 단일 원인), 별도의 노상 조사에서는
고속도로 주행 차량 타이어의 40%가 관리가 필요한 상태였습니다. 그럼에도 불구하고
적정 점검 주기를 지키는 운전자는 26%에 불과합니다. 타이어 공기압은 TPMS로 쉽게
확인할 수 있지만, 트레드 마모도는 그런 내장 시스템이 없어서 운전자들은 동전 테스트
같은 비공식적인 방법에 의존하는데, 이건 트레드의 한 지점만 확인 가능하고 운전자가
직접, 주기적으로 해야 한다는 한계가 있습니다. 기존 연구들은 레이저 변위 센서(정확하지만
Linear 벨트 설치가 필요하고 센서 근처 이물질에 영향받음)나 일반 카메라 이미지에
바이레터럴 필터를 적용하는 방식(저조도에서 정확도 저하)을 시도했습니다. 이 프로젝트는
열화상 카메라 + CNN 분류기로 이 두 한계를 모두 우회하고자 했습니다 — 특수한 위치
고정 장비가 필요 없고, 저조도에서도 동작해야 한다는 목표였습니다.

論文の序論より:タイヤは車両部品の中で唯一路面と接する部品であり、安全に最も直結する
部品である。論文で引用された2010〜2012年の統計によれば、高速道路での交通事故の
35.9%がタイヤ不良によるものであり(単一原因としては最大)、別途の路上調査では
高速走行中の車両のタイヤの40%が管理を要する状態であった。それにもかかわらず、
適切な点検周期を守っている運転者はわずか26%にとどまる。タイヤ空気圧はTPMSで容易に
確認できるが、トレッド摩耗にはそれに相当する内蔵システムが存在せず、運転者は硬貨を
使った簡易チェックのような非公式な方法に頼っているのが実情で、これはトレッドの一点
しか確認できず、運転者が手動かつ定期的に行う必要があるという限界がある。既存研究では
レーザー変位センサー(高精度だがLinearベルトの設置が必要で、センサー付近の異物の
影響を受けやすい)や、一般カメラ画像にバイラテラルフィルタを適用する手法(低照度下で
精度が低下)が試みられてきた。本プロジェクトは、熱画像カメラ+CNN分類器によって
この両方の限界を回避することを目指した — 特殊な位置決め機器を必要とせず、低照度
環境でも動作することを目標とした。

## Method (from the paper) / 手法(論文より) / 방법 (논문 기준)

- **Camera**: FLIR E76 thermal-imaging camera.
- **Data collection**: images taken at underground/surface parking lots around Hanyang
  University and at an auto repair shop for worn tires. Worn/normal threshold was
  tread depth 0.4cm. Collected 151 normal + 173 worn tire images, 324 total — out of
  351 images originally captured, 27 were excluded for poor image quality (concern
  that they'd hurt training rather than help).
- **Database**: NeonDB (serverless PostgreSQL). A single `TIRE_DATABASES` table with an
  `Image_Data` column (image stored as binary) and a `State` column
  (`True`=normal, `False`=worn).
- **Preprocessing**: crop 40% off the top/bottom and 25% off the left/right of each
  image to isolate the tread region, then resize to 50×150.
- **Model**: a 5-layer CNN — Conv2D (32 filters, 3×3, ReLU) → MaxPooling → Flatten →
  Dense(64) → Dense(1, sigmoid) for binary classification. Trained with early stopping
  (stops if validation loss doesn't improve for 3 consecutive epochs, max 50 epochs) to
  reduce overfitting.
- **Web app** (this repo): FastAPI backend serving a mobile/desktop-responsive upload
  page; uploaded images are cropped/resized/normalized the same way, run through the
  trained model, and the result is returned as "적합한 타이어입니다" (tire is fine) or
  "교체가 필요한 타이어입니다" (tire needs replacing).

- **카메라**: FLIR E76 열화상 카메라.
- **데이터 수집**: 한양대학교 인근 지하/지상 주차장, 마모 타이어는 자동차 공업소에서
  촬영. 마모/정상 기준은 트레드 깊이 0.4cm. 정상 151장 + 마모 173장, 총 324장 수집
  — 원래 351장을 촬영했는데, 화질이 좋지 않은 27장은 학습에 방해가 될까 봐
  제외했습니다.
- **데이터베이스**: NeonDB(서버리스 PostgreSQL). `TIRE_DATABASES` 테이블 하나에
  `Image_Data`(이미지를 바이너리로 저장) 컬럼과 `State`(정상=True, 마모=False)
  컬럼.
- **전처리**: 각 이미지의 상하 40%, 좌우 25%를 잘라내서 트레드 영역만 남긴 뒤
  50×150으로 리사이즈.
- **모델**: 5개 레이어로 구성된 CNN — Conv2D(필터 32개, 3×3, ReLU) → MaxPooling →
  Flatten → Dense(64) → Dense(1, sigmoid)로 이진 분류. 과적합 방지를 위해 조기
  종료(검증 손실이 3 epoch 연속 개선 안 되면 중단, 최대 50 epoch) 적용.
- **웹 앱(이 레포)**: 모바일/데스크톱 반응형 업로드 페이지를 제공하는 FastAPI
  백엔드. 업로드된 이미지도 동일한 방식으로 crop/resize/normalize한 뒤 학습된
  모델에 통과시켜 "적합한 타이어입니다" 또는 "교체가 필요한 타이어입니다"로
  결과를 반환.

- **カメラ**:FLIR E76サーマルイメージングカメラ。
- **データ収集**:漢陽大学周辺の地下・地上駐車場、摩耗タイヤは自動車整備工場で撮影。
  摩耗/正常の基準はトレッド深さ0.4cm。正常151枚+摩耗173枚、計324枚を収集 —
  もともと351枚を撮影したが、画質が悪く学習の妨げになる懸念があった27枚を除外した。
- **データベース**:NeonDB(サーバーレスPostgreSQL)。`TIRE_DATABASES`テーブル1つに
  `Image_Data`(画像をバイナリとして保存)列と`State`(正常=True、摩耗=False)列。
- **前処理**:各画像の上下40%、左右25%を切り取ってトレッド領域のみを残し、
  50×150にリサイズ。
- **モデル**:5層構成のCNN — Conv2D(フィルタ32個、3×3、ReLU) → MaxPooling →
  Flatten → Dense(64) → Dense(1、sigmoid)で二値分類。過学習防止のため早期終了
  (検証損失が3エポック連続で改善しなければ停止、最大50エポック)を適用。
- **Webアプリ(本リポジトリ)**:モバイル/デスクトップ対応のアップロードページを
  提供するFastAPIバックエンド。アップロードされた画像も同様にcrop/resize/
  normalizeした後、学習済みモデルに通し、「適合한 타이어입니다」または
  「교체가 필요한 타이어입니다」として結果を返す。

## Results (from the paper) / 結果(論文より) / 결과 (논문 기준)

- CNN classifier: **91.04% training accuracy**, **79.35% validation accuracy**.
- Normal tires showed a much larger tread-vs-surrounding temperature gap (avg. ~15.7°C)
  than worn tires (avg. ~3.8°C) — this temperature contrast is the main signal the
  model is picking up on.
- On the earlier photo dataset used for the abstract's headline numbers, normal and
  abnormal tires were classified at 90% and 70% accuracy respectively, including
  images taken in low light.
- Noted limitations: ~12-point gap between train/validation accuracy suggests some
  overfitting; data was mostly collected in one city under normal road conditions
  (no snow/rain/unpaved-road tires); the system runs offline rather than in real time.
  Future-work directions in the paper: data augmentation and batch normalization,
  lighter models (e.g. MobileNet) on edge devices (Raspberry Pi, Jetson) for real-time
  use, a wider range of vehicle/tire types, and seasonal data collection.

- CNN 분류기: **훈련 정확도 91.04%**, **검증 정확도 79.35%**.
- 정상 타이어는 트레드-주변부 온도 차이가 평균 약 15.7°C로 넓게 나타난 반면, 마모
  타이어는 평균 약 3.8°C로 좁게 나타났습니다 — 이 온도 대비가 모델이 학습한 주요
  신호입니다.
- 초록에 언급된 대표 수치를 낸 초기 사진 데이터셋 기준으로는 정상/비정상 타이어가
  각각 90%, 70% 정확도로 분류됐고, 저조도 환경 이미지도 정상적으로 분류됐습니다.
- 논문에서 언급한 한계: 훈련/검증 정확도 차이가 약 12%p로 과적합 가능성 시사;
  데이터가 주로 한 도시의 일반 도로 조건에서만 수집됨(눈길/빗길/비포장 도로 없음);
  현재 시스템은 실시간이 아니라 오프라인으로 동작. 논문의 향후 연구 방향: 데이터
  증강 및 배치 정규화, 경량 모델(MobileNet 등)을 엣지 디바이스(Raspberry Pi,
  Jetson)에 올려 실시간화, 더 다양한 차량/타이어 유형, 계절별 데이터 수집.

- CNNモデル:**訓練精度91.04%**、**検証精度79.35%**。
- 正常タイヤはトレッドと周辺部の温度差が平均約15.7°Cと大きかったのに対し、摩耗
  タイヤは平均約3.8°Cと小さかった — この温度差がモデルが学習した主な手がかりで
  ある。
- アブストラクトに記載された代表的な数値の元となった初期の写真データセットでは、
  正常/異常タイヤがそれぞれ90%、70%の精度で分類され、低照度環境で撮影した画像も
  正常に分類された。
- 論文で言及された限界:訓練/検証精度の差が約12ポイントあり過学習の可能性を示唆;
  データが主に単一都市の通常の道路状況下でのみ収集されている(雪道・雨天・未舗装
  道路のタイヤは含まれない);現行システムはリアルタイムではなくオフラインで動作。
  論文中の今後の研究方向:データ拡張とバッチ正規化、軽量モデル(MobileNetなど)を
  エッジデバイス(Raspberry Pi、Jetsonなど)に搭載してリアルタイム化、より多様な
  車両・タイヤタイプ、季節ごとのデータ収集。

## My role in the project / このプロジェクトでの担当 / 이 프로젝트에서 내 역할

This was a 3-person team (전현서, 임규원, 이재룡), and I was the only team member with
an IT/software background. My part covered everything except proposing the initial
idea and collecting the tire image data (which was a joint effort — I helped with data
collection early on, going around parking lots with the team, but later split off:
while teammates visited parking lots and repair shops to photograph tires, I coded at
a nearby cafe). Specifically I owned: the CNN model design and training, image
preprocessing, the FastAPI backend, the NeonDB/SQLAlchemy database integration, the
web frontend integration, and wiring the whole system together end-to-end.

3인 팀 프로젝트였고(전현서, 임규원, 이재룡), IT/소프트웨어 배경이 있는 팀원은
저뿐이었습니다. 초기 아이디어 제안과 타이어 이미지 데이터 수집(팀 전체가 같이
함 — 저도 초반에는 주차장 돌면서 데이터 수집을 같이 했는데, 나중에는 역할이
갈려서 팀원들이 주차장/카센터를 돌며 타이어를 촬영하는 동안 저는 근처 카페에서
코딩) 을 뺀 나머지 전부를 담당했습니다. 구체적으로는: CNN 모델 설계 및 학습,
이미지 전처리, FastAPI 백엔드, NeonDB/SQLAlchemy 데이터베이스 연동, 웹 프론트엔드
통합, 그리고 전체 시스템을 엔드투엔드로 연결하는 작업까지 전부 맡았습니다.

3人チームのプロジェクトで(チョン・ヒョンソ、イム・ギュウォン、イ・ジェリョン)、
IT・ソフトウェアのバックグラウンドを持つメンバーは私だけでした。最初のアイデア
提案とタイヤ画像データの収集(チーム全体で行った作業 — 私も初期は駐車場を回って
データ収集を一緒に行っていたが、その後役割が分かれ、チームメイトが駐車場や
整備工場を回ってタイヤを撮影している間、私は近くのカフェでコーディングしていた)
を除く残り全てを担当しました。具体的には:CNNモデルの設計・学習、画像の前処理、
FastAPIバックエンド、NeonDB/SQLAlchemyによるデータベース連携、Webフロントエンド
統合、そしてシステム全体をエンドツーエンドでつなぐ作業までを担当しました。

## What this repo contains / このリポジトリの内容 / 이 레포 구성

```
paper/                                  Capstone paper (background above is based on this)
main.py                                 FastAPI app: serves the upload page and /predict/ endpoint
crud.py                                 NeonDB (PostgreSQL) access via SQLAlchemy (async)
qr.py                                   One-off script to generate a QR code linking to a demo video
templates/example.html, mobile.html     Desktop / mobile upload pages
tire_tread_model.keras                  Trained CNN weights
page_data/image/tire_background.png     Background image used by the templates
requirements.txt                        Python dependencies
.env.example                            Template for the required DATABASE_URL env var
```

```
paper/                                  졸업설계 논문(위 배경 설명의 출처)
main.py                                 FastAPI 앱: 업로드 페이지와 /predict/ 엔드포인트 제공
crud.py                                 SQLAlchemy(비동기)로 NeonDB(PostgreSQL) 접근
qr.py                                   시연 영상 링크로 연결되는 QR 코드 생성용 일회성 스크립트
templates/example.html, mobile.html     데스크톱 / 모바일 업로드 페이지
tire_tread_model.keras                  학습된 CNN 가중치
page_data/image/tire_background.png     템플릿에서 쓰는 배경 이미지
requirements.txt                        파이썬 의존성 목록
.env.example                            필수 환경변수 DATABASE_URL 템플릿
```

```
paper/                                  卒業設計論文(上記の背景説明の出典)
main.py                                 FastAPIアプリ:アップロードページと/predict/エンドポイントを提供
crud.py                                 SQLAlchemy(非同期)によるNeonDB(PostgreSQL)アクセス
qr.py                                   デモ動画へのリンクを含むQRコードを生成する単発スクリプト
templates/example.html, mobile.html     デスクトップ/モバイル用アップロードページ
tire_tread_model.keras                  学習済みCNN重み
page_data/image/tire_background.png     テンプレートで使用する背景画像
requirements.txt                        Python依存パッケージ一覧
.env.example                            必須の環境変数DATABASE_URLのテンプレート
```

## Setup / セットアップ / 설치

```bash
pip install -r requirements.txt
cp .env.example .env   # then fill in your own DATABASE_URL
uvicorn main:app --reload
```

## Security note — DB credential was previously exposed
## セキュリティに関する注意 — DB認証情報が過去に公開されていました
## 보안 관련 안내 — DB 크레덴셜이 이전에 노출돼 있었습니다

An earlier version of `crud.py` had the NeonDB connection string — including the
username and password — hardcoded directly in the file, and this was publicly visible
on GitHub from the initial commit (2024-11-04) up until this cleanup. The password has
already been rotated on the Neon side. This version reads the connection string from
an environment variable instead (`DATABASE_URL`, see `.env.example`), and `.env` is
excluded via `.gitignore` so a real credential never gets committed again.

이전 버전의 `crud.py`에는 사용자명·비밀번호가 포함된 NeonDB 접속 문자열이 파일에
직접 하드코딩돼 있었고, 첫 커밋(2024-11-04)부터 이번 정리 전까지 깃허브에
공개돼 있었습니다. 비밀번호는 Neon 쪽에서 이미 재발급(로테이션) 완료했습니다.
이 버전에서는 접속 문자열을 환경변수(`DATABASE_URL`, `.env.example` 참고)로
읽어오도록 바꿨고, `.env`는 `.gitignore`로 제외해서 실제 크레덴셜이 다시
커밋되는 일이 없도록 했습니다.

以前のバージョンの`crud.py`には、ユーザー名・パスワードを含むNeonDBの接続文字列が
ファイルに直接ハードコーディングされており、初回コミット(2024年11月4日)から
今回の整理まで公開リポジトリ上で閲覧可能な状態でした。パスワードはNeon側で既に
再発行(ローテーション)済みです。このバージョンでは接続文字列を環境変数
(`DATABASE_URL`、`.env.example`参照)から読み込むように変更し、`.env`は
`.gitignore`で除外することで、実際の認証情報が再びコミットされないようにしています。

## Known issue (not fixed, flagged only) / 既知の問題(未修正、報告のみ) / 알려진 이슈 (수정 안 하고 기록만)

`main.py` defines `@app.get("/")` twice — once returning `mobile.html` or
`example.html` directly based on the user-agent, and once returning `example.html` via
Jinja2Templates. FastAPI matches routes in registration order, so the **first**
definition wins and the second is effectively dead code — meaning the Jinja2 route
never actually runs. Left as-is since fixing it is a logic change, not a cleanup;
flagging here in case it's worth fixing later.

`main.py`에 `@app.get("/")`가 두 번 정의돼 있습니다 — 하나는 user-agent를 보고
`mobile.html` 또는 `example.html`을 직접 읽어서 반환하고, 다른 하나는
Jinja2Templates로 `example.html`을 반환합니다. FastAPI는 라우트를 등록된 순서대로
매칭하기 때문에 **먼저 등록된** 쪽이 실제로 동작하고, 두 번째 정의는 사실상 죽은
코드입니다 — 즉 Jinja2 라우트는 실제로는 한 번도 실행되지 않습니다. 이건 로직
수정이라 이번 정리에서는 건드리지 않고 그대로 뒀습니다. 나중에 고칠 가치가 있을까
싶어 기록만 남겨둡니다.

`main.py`には`@app.get("/")`が2回定義されています — 1つはuser-agentを見て
`mobile.html`または`example.html`を直接読み込んで返し、もう1つはJinja2Templatesで
`example.html`を返します。FastAPIはルートを登録順にマッチさせるため、**先に登録
された方**が実際に動作し、2つ目の定義は事実上デッドコードです — つまりJinja2
ルートは実際には一度も実行されません。これはロジックの修正にあたるため今回の整理
では変更せず、そのまま残しています。今後修正する価値があるかもしれないので記録
のみ残しておきます。

PYEOF_MARKER

echo "Done. Run: git add -A && git commit -m 'security fix + cleanup' && git push"