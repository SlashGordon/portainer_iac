FROM nginx:alpine

RUN apk update && apk upgrade --no-cache \
    && rm -rf /var/cache/apk/*

COPY web_data.conf /etc/nginx/conf.d/default.conf
