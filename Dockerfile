FROM node:26.12.0-bookworm-slim
WORKDIR /app
COPY package.json ./
COPY server ./server
ENV NODE_ENV=production
ENV HOBBIT_HOSTED=true
ENV HOBBIT_DATA_DIR=/var/data/hobbit
ENV PORT=8787
RUN mkdir -p /var/data/hobbit && chown node:node /var/data/hobbit
USER node
EXPOSE 8787
CMD ["node", "server/server.mjs"]
