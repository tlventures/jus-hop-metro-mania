FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --production --no-audit --no-fund
COPY . .
EXPOSE 8080
CMD ["node", "server.js"]
