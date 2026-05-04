FROM node:24-alpine

WORKDIR /app
ENV NODE_ENV=production
ENV PORT=8080

COPY lib ./lib
COPY frontend ./frontend

USER 10001
EXPOSE 8080
CMD ["node", "/app/frontend/server.js"]

