# Multi-stage build for the Codec marketing site (Astro -> static -> nginx)

# ---- build ----
FROM node:22-alpine AS build
WORKDIR /src

# Install deps with cache-friendly layering
COPY package.json package-lock.json* ./
RUN npm ci --no-audit --no-fund

# Build the static site
COPY . .
RUN npm run build

# ---- serve ----
FROM nginx:1.27-alpine
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
