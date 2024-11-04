from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import JSONResponse, HTMLResponse
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image
import numpy as np
import tensorflow as tf
import io
import traceback
import os
from fastapi.templating import Jinja2Templates

API_BASE_URL = os.getenv("API_BASE_URL", "http://127.0.0.1:8000")  # 기본값 설정

app = FastAPI()

# Allow CORS from all origins for testing; restrict in production as needed
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 또는 ["http://127.0.0.1"]으로 설정 가능
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
