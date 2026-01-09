FROM scratch

WORKDIR /

COPY main /main
COPY static /static
COPY index.html /static/index.html
COPY elm.js /static/elm.js

EXPOSE 8080

CMD ["/main"]
