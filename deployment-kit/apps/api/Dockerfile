FROM node:24-alpine

WORKDIR /app
ENV NODE_ENV=production
ENV PORT=8081

COPY lib ./lib
COPY api ./api

USER 10001
EXPOSE 8081
CMD ["node", "/app/api/server.js"]

