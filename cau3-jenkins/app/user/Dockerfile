# Lab 2 - Câu 3: Dockerfile cho service "user" (dựa trên bản gốc của upstream)
# Thay đổi so với upstream:
#   - Ghim base image (thay cho node:lts-alpine "trôi" phiên bản)
#   - Không cài devDependencies, chạy bằng user không phải root (node)
FROM node:20-alpine

ENV NODE_ENV=production
WORKDIR /app

COPY package.json ./
RUN npm install --omit=dev --no-audit --no-fund && npm cache clean --force

COPY --chown=node:node . .

USER node
EXPOSE 3000
CMD ["npm", "run", "prod"]
