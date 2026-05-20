FROM node:20-alpine

WORKDIR /app
COPY package.json package.json
COPY server.js server.js

ENV NODE_ENV=production
ENV PORT=8787
CMD ["node", "server.js"]
