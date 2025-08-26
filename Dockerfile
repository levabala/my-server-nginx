FROM nginx:alpine
COPY dist/ /usr/share/nginx/html/
COPY other/ /usr/share/nginx/html/
COPY nginx/nginx.conf /etc/nginx/nginx.conf
EXPOSE 80 443
