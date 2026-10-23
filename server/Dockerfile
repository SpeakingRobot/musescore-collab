# syntax=docker/dockerfile:1
FROM node:20-alpine

# Install build tools for better-sqlite3 native module
RUN apk add --no-cache python3 make g++

WORKDIR /app

# Install dependencies
COPY package*.json ./
RUN npm ci --omit=dev

# Copy source
COPY . .

# Create data directory for SQLite (will be mounted as volume)
RUN mkdir -p /data

# Set DB path to the persistent volume
ENV DB_PATH=/data/collab.db

EXPOSE 3001

CMD ["node", "index.js"]
