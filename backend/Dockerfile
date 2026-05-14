# syntax=docker/dockerfile:1.7

# ---------- builder ----------
FROM node:20-alpine AS builder
WORKDIR /app

# Native build deps for argon2
RUN apk add --no-cache python3 make g++

COPY package.json package-lock.json* ./
RUN npm install --no-audit --no-fund

COPY tsconfig.json ./
COPY src ./src
RUN npm run build

# Prune dev dependencies so we can copy node_modules straight into the runner
RUN npm prune --omit=dev

# ---------- runner ----------
FROM node:20-alpine AS runner
WORKDIR /app

# argon2 native runtime
RUN apk add --no-cache libstdc++

ENV NODE_ENV=production

COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY drizzle ./drizzle

EXPOSE 3000
USER node

CMD ["node", "dist/index.js"]
