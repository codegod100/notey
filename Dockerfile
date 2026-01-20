FROM scratch

WORKDIR /

COPY backend/main /main
COPY static /static

EXPOSE 8080

CMD ["/main"]