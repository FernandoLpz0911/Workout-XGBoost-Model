# Use an official lightweight Python image
FROM python:3.10-slim

# Set working directory
WORKDIR /app

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of your code (api.py, models, csv, etc.)
COPY . .

# Expose the port FastAPI will run on
ENV PORT 8080

# Run the web service using Uvicorn
CMD exec uvicorn api:app --host 0.0.0.0 --port $PORT