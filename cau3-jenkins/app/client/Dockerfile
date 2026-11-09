# Lab 2 - Câu 3: Dockerfile production cho client (Next.js 12)
# Giữ node:16 vì Next.js 12.0 không build được trên Node >= 17 (OpenSSL 3).
# Trivy sẽ cảnh báo image này (Node 16 đã EOL) -> được ghi nhận trong báo cáo.

FROM node:16-alpine AS dependencies
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

FROM node:16-alpine AS builder
WORKDIR /app
COPY . .
COPY --from=dependencies /app/node_modules ./node_modules
RUN npm run build && npm prune --omit=dev

FROM node:16-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production

COPY --from=builder --chown=node:node /app/next.config.js ./
COPY --from=builder --chown=node:node /app/public ./public
COPY --from=builder --chown=node:node /app/.next ./.next
COPY --from=builder --chown=node:node /app/node_modules ./node_modules
COPY --from=builder --chown=node:node /app/package.json ./package.json

USER node
EXPOSE 3000
CMD ["npm", "run", "start"]
