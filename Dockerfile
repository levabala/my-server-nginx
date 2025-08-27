FROM nginx:alpine
COPY nginx/nginx.conf /etc/nginx/nginx.conf
EXPOSE 80 443
