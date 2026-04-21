# Use an official lightweight Python image
FROM python:3.10-slim

# Set working directory
WORKDIR /app

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of your code
COPY . .

# Cloud providers inject their own PORT, but we set a fallback
ENV PORT=8080

# Run the FastAPI server
CMD uvicorn api:app --host 0.0.0.0 --port ${PORT}